//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import AVFoundation
import Combine
import JellyfinAPI
import MediaPlayer
import UIKit

/// App-wide audio engine for music and audiobooks.
///
/// Streams from the server, keeps playing in the background, drives the lock
/// screen / Control Center, and reports position to the server so listening
/// resumes on any device.
@MainActor
final class KhyloAudioPlayer: ObservableObject {

    static let shared = KhyloAudioPlayer()

    enum Kind {
        case music
        case audiobook
    }

    enum RepeatMode {
        case off
        case all
        case one

        var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
    }

    @Published private(set) var queue: [BaseItemDto] = []
    @Published private(set) var index = 0
    @Published private(set) var kind: Kind = .music
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
        }
    }
    /// Source quality of the current track (codec, bitrate, bit depth, sample rate).
    @Published private(set) var quality: KhyloAudioQuality?

    /// Position and length live on their own object so that only progress views
    /// redraw while playing, not every screen that shows what's playing.
    let clock = KhyloPlaybackClock()

    private(set) var currentTime: Double {
        get { clock.currentTime }
        set { clock.currentTime = newValue }
    }

    private(set) var duration: Double {
        get { clock.duration }
        set { if clock.duration != newValue { clock.duration = newValue } }
    }
    @Published private(set) var sleepTimerEnd: Date?
    /// Title of the audiobook (its folder), shown instead of the part name.
    @Published private(set) var collectionTitle: String?
    @Published private(set) var artworkURL: URL?
    @Published var repeatMode: RepeatMode = .off {
        didSet {
            player.actionAtItemEnd = repeatMode == .one ? .none : .advance
            preloadNext()
        }
    }
    @Published private(set) var isShuffled = false
    /// The queue's order before shuffling, so shuffle can be turned back off.
    private var unshuffledQueue: [BaseItemDto] = []

    var current: BaseItemDto? { queue.indices.contains(index) ? queue[index] : nil }
    var isActive: Bool { current != nil }

    /// A queue player so the next track is already buffering when this one ends.
    private let player = AVQueuePlayer()
    /// The next track, loaded into the player ahead of time.
    private var preloaded: (item: AVPlayerItem, index: Int)?
    /// The item playing the current track (other players post end notifications too).
    private weak var activeItem: AVPlayerItem?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusCancellable: AnyCancellable?
    private var itemCancellable: AnyCancellable?
    private var videoObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    /// Another app took the audio while we were playing; pick back up when it's done.
    private var resumeAfterInterruption = false
    private var qualityTask: Task<Void, Never>?
    private var playSessionID = UUID().uuidString
    private var lastReport = Date.distantPast
    private var sleepTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.tick(time.seconds)
            }
        }
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                let buffering = status == .waitingToPlayAtSpecifiedRate
                if self?.isBuffering != buffering { self?.isBuffering = buffering }
            }
        itemCancellable = player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.currentItemChanged(item)
            }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let ended = notification.object as? AVPlayerItem
            MainActor.assumeIsolated { self?.itemDidEnd(ended) }
        }
        videoObserver = NotificationCenter.default.addObserver(
            forName: .khyloVideoWillPlay,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.isPlaying == true { self?.pause() }
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated { self?.handleInterruption(type) }
        }
        // Some apps never announce that they've finished with the audio; coming
        // back to Khylo picks up then.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeIfInterrupted() }
        }
        configureRemoteCommands()
    }

    // MARK: - Interruptions

    /// Another app (or a call) took the audio, or gave it back.
    private func handleInterruption(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            guard isPlaying else { return }
            resumeAfterInterruption = true
            isPlaying = false
            report(force: true)
            updateNowPlaying()
        case .ended:
            // Give the other app a moment to let go of the audio, then carry on.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.resumeIfInterrupted()
            }
        default:
            break
        }
    }

    private func resumeIfInterrupted() {
        guard resumeAfterInterruption, isActive else { return }
        resumeAfterInterruption = false
        resume()
    }

    // MARK: - Control

    /// Starts a queue. `startTicks` resumes inside the first item; nil uses the server's saved position.
    func play(
        _ items: [BaseItemDto],
        startAt startIndex: Int = 0,
        kind: Kind,
        collectionTitle: String? = nil,
        artworkURL: URL? = nil,
        startTicks: Int? = nil
    ) {
        guard items.indices.contains(startIndex) else { return }
        reportStopped()
        queue = items
        isShuffled = false
        unshuffledQueue = []
        self.kind = kind
        self.collectionTitle = collectionTitle
        self.artworkURL = artworkURL
        rate = kind == .audiobook ? rate : 1
        load(index: startIndex, startTicks: startTicks)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard isActive else { return }
        // The queue ran out: start the current track again.
        guard player.currentItem != nil else {
            load(index: index, startTicks: 0)
            return
        }
        activateSession()
        player.play()
        isPlaying = true
        report(force: true)
        updateNowPlaying()
    }

    func pause() {
        resumeAfterInterruption = false
        player.pause()
        isPlaying = false
        report(force: true)
        updateNowPlaying()
    }

    func next() {
        if index + 1 < queue.count {
            reportStopped()
            load(index: index + 1, startTicks: 0)
        } else if repeatMode == .all, !queue.isEmpty {
            reportStopped()
            load(index: 0, startTicks: 0)
        }
    }

    /// Shuffles everything after the current track, or restores the original order.
    func toggleShuffle() {
        guard let current else { return }
        if isShuffled {
            let original = unshuffledQueue
            queue = original
            index = original.firstIndex { $0.id == current.id } ?? 0
            unshuffledQueue = []
            isShuffled = false
        } else {
            unshuffledQueue = queue
            var rest = queue
            rest.remove(at: index)
            queue = [current] + rest.shuffled()
            index = 0
            isShuffled = true
        }
        preloadNext()
        updateNowPlaying()
    }

    /// Moves a queued track to play right after the current one.
    func playNext(_ item: BaseItemDto) {
        guard isActive else {
            play([item], kind: .music, startTicks: 0)
            return
        }
        let currentID = current?.id
        queue.removeAll { $0.id == item.id && $0.id != currentID }
        index = queue.firstIndex { $0.id == currentID } ?? index
        queue.insert(item, at: min(index + 1, queue.count))
        preloadNext()
    }

    func addToQueue(_ item: BaseItemDto) {
        guard isActive else {
            play([item], kind: .music, startTicks: 0)
            return
        }
        queue.append(item)
        preloadNext()
    }

    func previous() {
        // Restart the current item unless we're near its start.
        if currentTime > 4 || index == 0 {
            seek(to: 0)
        } else {
            reportStopped()
            load(index: index - 1, startTicks: 0)
        }
    }

    func jump(to newIndex: Int) {
        guard queue.indices.contains(newIndex) else { return }
        reportStopped()
        load(index: newIndex, startTicks: nil)
    }

    func skip(by seconds: Double) {
        seek(to: max(0, min(duration, currentTime + seconds)))
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        report(force: true)
        updateNowPlaying()
    }

    func stop() {
        reportStopped()
        preloaded = nil
        player.removeAllItems()
        isPlaying = false
        queue = []
        index = 0
        currentTime = 0
        duration = 0
        setSleepTimer(minutes: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// nil cancels; 0 means "end of current part".
    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes else {
            sleepTimerEnd = nil
            return
        }
        let seconds = minutes == 0 ? max(duration - currentTime, 1) / Double(rate) : Double(minutes * 60)
        sleepTimerEnd = Date().addingTimeInterval(seconds)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepTimerEnd = nil
        }
    }

    // MARK: - Loading

    private func load(index newIndex: Int, startTicks: Int?) {
        index = newIndex
        guard let item = current, let url = streamURL(for: item) else { return }

        let start = Double(startTicks ?? item.userData?.playbackPositionTicks ?? 0) / 10_000_000
        duration = Double(item.runTimeTicks ?? 0) / 10_000_000
        currentTime = start
        playSessionID = UUID().uuidString

        let playerItem = makePlayerItem(url)
        preloaded = nil
        player.removeAllItems()
        player.insert(playerItem, after: nil)
        activeItem = playerItem
        if start > 1 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        activateSession()
        player.defaultRate = rate
        // play() (not playImmediately) lets the player buffer enough to avoid stutter.
        player.play()
        isPlaying = true
        trackDidStart()
        preloadNext()
    }

    private func makePlayerItem(_ url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: [AVURLAssetAllowsCellularAccessKey: true]))
        item.audioTimePitchAlgorithm = kind == .audiobook ? .timeDomain : .spectral
        item.preferredForwardBufferDuration = 30
        return item
    }

    /// Bookkeeping when a track begins, whether picked or reached from the queue.
    private func trackDidStart() {
        reportStart()
        loadArtwork()
        loadQuality()
        updateNowPlaying()
    }

    /// Which queue position plays after the current one, if any.
    private var nextIndex: Int? {
        guard repeatMode != .one, !queue.isEmpty else { return nil }
        if index + 1 < queue.count { return index + 1 }
        return repeatMode == .all && queue.count > 1 ? 0 : nil
    }

    /// Puts the next track into the player so it starts without a gap.
    private func preloadNext() {
        if let preloaded {
            player.remove(preloaded.item)
            self.preloaded = nil
        }
        guard player.currentItem != nil,
              let next = nextIndex,
              let url = streamURL(for: queue[next])
        else { return }
        let item = makePlayerItem(url)
        player.insert(item, after: player.currentItem)
        preloaded = (item, next)
    }

    /// The queue player moved on to the preloaded track.
    private func currentItemChanged(_ item: AVPlayerItem?) {
        guard let item, let preloaded, item === preloaded.item else { return }
        reportStopped()
        self.preloaded = nil
        activeItem = item
        index = preloaded.index
        duration = Double(current?.runTimeTicks ?? 0) / 10_000_000
        currentTime = 0
        playSessionID = UUID().uuidString
        trackDidStart()
        preloadNext()
    }

    private func itemDidEnd(_ ended: AVPlayerItem?) {
        guard let ended, ended === activeItem else { return }
        if repeatMode == .one {
            report(force: true)
            player.seek(to: .zero)
            player.play()
            return
        }
        if preloaded == nil {
            // End of the queue.
            report(force: true)
            reportStopped()
            isPlaying = false
            currentTime = 0
            updateNowPlaying()
        }
        // Otherwise the queue player advances by itself; currentItemChanged picks it up.
    }

    private func streamURL(for item: BaseItemDto) -> URL? {
        guard let session = KhyloAPI.session, let id = item.id else { return nil }
        var parameters = Paths.GetUniversalAudioStreamParameters()
        parameters.container = ["mp3", "aac", "m4a|aac", "m4b|aac", "flac", "alac", "m4a|alac", "wav", "mp4"]
        parameters.userID = session.user.id
        parameters.deviceID = UIDevice.current.identifierForVendor?.uuidString
        parameters.maxStreamingBitrate = 320_000_000
        parameters.transcodingContainer = "mp4"
        parameters.transcodingProtocol = .hls
        parameters.audioCodec = "aac"
        guard let base = session.client.url(with: Paths.getUniversalAudioStream(itemID: id, parameters: parameters)),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "api_key", value: session.user.accessToken)]
        return components.url
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: kind == .audiobook ? .spokenAudio : .default)
        try? session.setActive(true)
    }

    // MARK: - Time

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, isActive else { return }
        currentTime = seconds
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        report(force: false)
    }

    // MARK: - Server reporting

    private func stateInfo() -> PlaybackStateInfo? {
        guard let item = current else { return nil }
        var info = PlaybackStateInfo()
        info.itemID = item.id
        info.canSeek = true
        info.isPaused = !isPlaying
        info.playMethod = .directStream
        info.playSessionID = playSessionID
        info.positionTicks = Int(currentTime * 10_000_000)
        return info
    }

    private func reportStart() {
        guard let info = stateInfo(), let client = KhyloAPI.session?.client else { return }
        lastReport = Date()
        Task { _ = try? await client.send(Paths.reportPlaybackStart(info)) }
    }

    private func report(force: Bool) {
        guard force || Date().timeIntervalSince(lastReport) > 10,
              let info = stateInfo(),
              let client = KhyloAPI.session?.client
        else { return }
        lastReport = Date()
        Task { _ = try? await client.send(Paths.reportPlaybackProgress(info)) }
    }

    private func reportStopped() {
        guard let item = current, let client = KhyloAPI.session?.client else { return }
        var info = PlaybackStopInfo()
        info.itemID = item.id
        info.playSessionID = playSessionID
        info.positionTicks = Int(currentTime * 10_000_000)
        Task { _ = try? await client.send(Paths.reportPlaybackStopped(info)) }
    }

    // MARK: - Lock screen

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: 30) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let isBook = kind == .audiobook
        center.skipForwardCommand.isEnabled = isBook
        center.skipBackwardCommand.isEnabled = isBook
        center.nextTrackCommand.isEnabled = !isBook || index + 1 < queue.count
        center.previousTrackCommand.isEnabled = !isBook
    }

    private var artworkImage: UIImage?

    /// Album cover for music (per track); the book's cover for audiobooks.
    func displayArtworkURL(width: CGFloat) -> URL? {
        guard let item = current else { return nil }
        if kind == .audiobook, let artworkURL { return artworkURL }
        return KhyloArtwork.url(for: item, style: .square, width: width) ?? artworkURL
    }

    private func loadQuality() {
        qualityTask?.cancel()
        quality = nil
        guard kind == .music, let id = current?.id else { return }
        qualityTask = Task { [weak self] in
            guard let item = try? await KhyloAPI.item(id), !Task.isCancelled else { return }
            self?.quality = KhyloAudioQuality(item)
        }
    }

    private func loadArtwork() {
        artworkTask?.cancel()
        artworkImage = nil
        let url = displayArtworkURL(width: 600)
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled
            else { return }
            self?.artworkImage = image
            self?.updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        updateCommandAvailability()
        guard let item = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: kind == .audiobook ? (item.name ?? "") : (item.name ?? ""),
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
        ]
        if kind == .audiobook {
            info[MPMediaItemPropertyAlbumTitle] = collectionTitle ?? item.album
            info[MPMediaItemPropertyArtist] = item.albumArtist ?? item.artists?.first
        } else {
            info[MPMediaItemPropertyArtist] = item.artists?.joined(separator: ", ") ?? item.albumArtist
            info[MPMediaItemPropertyAlbumTitle] = item.album
        }
        if let artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - Clock

/// Playback position, published apart from the player so progress bars can
/// update twice a second without redrawing everything else.
@MainActor
final class KhyloPlaybackClock: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
}

// MARK: - Quality

/// A track's source quality, e.g. "FLAC · 24-bit / 96 kHz" or "MP3 · 320 kbps".
struct KhyloAudioQuality: Equatable {

    let codec: String
    let bitrate: Int?
    let bitDepth: Int?
    let sampleRate: Int?

    private static let losslessCodecs: Set<String> = ["flac", "alac", "wav", "pcm", "aiff", "ape", "wavpack", "dsd", "truehd"]

    init?(_ item: BaseItemDto) {
        let source = item.mediaSources?.first
        let stream = (source?.mediaStreams ?? item.mediaStreams)?.first { $0.type == .audio }
        guard let codec = stream?.codec ?? source?.container else { return nil }
        self.codec = codec.lowercased()
        self.bitrate = stream?.bitRate ?? source?.bitrate
        self.bitDepth = stream?.bitDepth
        self.sampleRate = stream?.sampleRate
    }

    var isLossless: Bool {
        Self.losslessCodecs.contains(codec) || codec.hasPrefix("pcm")
    }

    var isHiRes: Bool {
        isLossless && ((bitDepth ?? 16) > 16 || (sampleRate ?? 44100) > 48000)
    }

    /// "Hi-Res", "Lossless", or nil for lossy files.
    var badge: String? {
        isHiRes ? "Hi-Res" : (isLossless ? "Lossless" : nil)
    }

    var codecName: String {
        switch codec {
        case "flac": "FLAC"
        case "alac": "ALAC"
        case "aac": "AAC"
        case "mp3": "MP3"
        case "opus": "Opus"
        case "vorbis": "Vorbis"
        case "wav", "pcm": "WAV"
        default: codec.hasPrefix("pcm") ? "WAV" : codec.uppercased()
        }
    }

    /// Full description for Now Playing.
    var detail: String {
        if isLossless {
            var parts = [codecName]
            let depth = bitDepth.map { "\($0)-bit" }
            let rate = sampleRate.map { Self.formatRate($0) }
            let spec = [depth, rate].compactMap { $0 }.joined(separator: " / ")
            if !spec.isEmpty { parts.append(spec) }
            return parts.joined(separator: " · ")
        }
        guard let bitrate, bitrate > 0 else { return codecName }
        return "\(codecName) · \(Int((Double(bitrate) / 1000).rounded())) kbps"
    }

    /// Short form for album headers and rows: "24/96", "16/44.1" or "320".
    var short: String {
        if isLossless, let bitDepth, let sampleRate {
            return "\(bitDepth)/\(Self.formatRate(sampleRate, unit: false))"
        }
        if let bitrate, bitrate > 0 { return "\(Int((Double(bitrate) / 1000).rounded())) kbps" }
        return codecName
    }

    private static func formatRate(_ rate: Int, unit: Bool = true) -> String {
        let khz = Double(rate) / 1000
        let text = khz == khz.rounded() ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
        return unit ? "\(text) kHz" : text
    }
}
