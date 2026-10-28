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
import Logging
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

    enum Kind: String, Codable {
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
            discardPreload()
        }
    }
    @Published private(set) var isShuffled = false
    /// The queue's order before shuffling, so shuffle can be turned back off.
    private var unshuffledQueue: [BaseItemDto] = []

    var current: BaseItemDto? { queue.indices.contains(index) ? queue[index] : nil }
    var isActive: Bool { current != nil }

    /// Set to open the full Now Playing screen. It lives above the tabs, so it
    /// opens from anywhere: tapping the mini player, or starting an audiobook.
    @Published var isNowPlayingRequested = false

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
    private var itemStatusCancellable: AnyCancellable?
    private var failureObserver: NSObjectProtocol?
    private var videoEndObserver: NSObjectProtocol?
    /// Fresh attempts at the current track after a network failure or an early end.
    private var retries = 0
    /// The item whose failure or end has already been handled (each is handled once).
    private weak var handledItem: AVPlayerItem?
    /// Songs in a row that wouldn't play at all; past a few, pause instead of skipping on.
    private var failedInARow = 0
    /// Autoplay: more songs are being fetched for when the queue runs out.
    private var isExtendingQueue = false
    /// The queue ran out while autoplay was still fetching; play on when it arrives.
    private var waitingForAutoplay = false
    private var playSessionID = UUID().uuidString
    /// The song whose stream the server has actually opened; only that one is
    /// reported as playing.
    private weak var startedItem: AVPlayerItem?
    /// Waiting for the sign-in token (the phone was locked) before starting a song.
    private var tokenWaitTask: Task<Void, Never>?
    /// Notices a song that loaded but never started.
    private var startWatchdog: Task<Void, Never>?
    /// The song that has actually made sound.
    private weak var playingItem: AVPlayerItem?
    /// After a stream stalls or fails, the song is retried as one plain MP3
    /// stream instead of HLS.
    private var usePlainStream = false
    /// Which load is current, so a slow lookup can't start an old song.
    private var loadGeneration: UUID?
    /// The latest jump, so an older one finishing late isn't taken as a failure.
    private var seekGeneration = 0
    private let logger = Logger.swiftfin()
    /// Signal was lost: the song waits here and picks up at the same spot.
    private var waitingForNetwork = false
    private var waitPosition: Double = 0
    private var networkWaitTask: Task<Void, Never>?
    /// When waiting for a connection began (gives up after a few minutes).
    private var networkWaitStarted: Date?
    private var networkCancellable: AnyCancellable?
    /// Keeps the app running while the next song loads, even in the background.
    private var transitionTask: UIBackgroundTaskIdentifier = .invalid
    private var lastSessionSave = Date.distantPast
    private var resignObserver: NSObjectProtocol?
    private var lastReport = Date.distantPast
    private var sleepTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        // The player never moves on by itself: when a song ends, Khylo checks it really
        // finished (and didn't just lose its connection) before starting the next one.
        player.actionAtItemEnd = .pause
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
                if status == .playing {
                    self?.playingItem = self?.player.currentItem
                    self?.releaseAppAwake()
                }
            }
        itemCancellable = player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.currentItemChanged(item)
            }
        itemStatusCancellable = player.publisher(for: \.currentItem?.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay: self.streamDidOpen(self.player.currentItem)
                case .failed: self.recoverFromFailure(self.player.currentItem)
                default: break
                }
            }
        // A dropped connection mid-song (common in the car) ends the item early.
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let failed = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                self?.recoverFromFailure(failed)
            }
        }
        // The video player takes over the lock screen controls while it plays and
        // clears them when it closes; take them back afterwards.
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .khyloPlaybackDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reclaimAfterVideo() }
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
        // Signal's back: carry on from where the song stopped.
        networkCancellable = KhyloNetwork.shared.$isOnline
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] online in
                if online { self?.resumeAfterNetwork() }
            }
        // Remember what's playing so it's there after the app is closed.
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSession(force: true) }
        }
        claimRemoteCommands()
    }

    /// Takes the lock screen controls back once the video player has let go of them.
    private func reclaimAfterVideo() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.isActive else { return }
            self.claimRemoteCommands()
            self.updateNowPlaying()
        }
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
        retries = 0
        failedInARow = 0
        isExtendingQueue = false
        waitingForAutoplay = false
        queue = items
        isShuffled = false
        unshuffledQueue = []
        self.kind = kind
        self.collectionTitle = collectionTitle
        self.artworkURL = artworkURL
        rate = kind == .audiobook ? rate : 1
        load(index: startIndex, startTicks: startTicks)
        // An audiobook opens its player as soon as you press play.
        if kind == .audiobook { isNowPlayingRequested = true }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard isActive else { return }
        // Nothing loaded (the queue ran out, the app was reopened, or the stream
        // broke): start the current track again from where it was.
        guard let item = player.currentItem, item === activeItem, item.status != .failed else {
            load(index: index, startTicks: Int(currentTime * 10_000_000))
            return
        }
        activateSession()
        claimRemoteCommands()
        player.play()
        isPlaying = true
        report(force: true)
        updateNowPlaying()
    }

    func pause() {
        resumeAfterInterruption = false
        stopWaitingForNetwork()
        player.pause()
        isPlaying = false
        isBuffering = false
        report(force: true)
        updateNowPlaying()
        saveSession(force: true)
        releaseAppAwake()
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
        discardPreload()
        prepareCache()
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
        discardPreload()
        prepareCache()
    }

    func addToQueue(_ item: BaseItemDto) {
        guard isActive else {
            play([item], kind: .music, startTicks: 0)
            return
        }
        queue.append(item)
        discardPreload()
        prepareCache()
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
        defer {
            report(force: true)
            updateNowPlaying()
        }
        // Nothing loaded yet (the app was just reopened): Play starts from here.
        guard let item = player.currentItem, item === activeItem else { return }

        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let isLocal = (item.asset as? AVURLAsset)?.url.isFileURL == true
        let canJump = isLocal || item.seekableTimeRanges.contains { $0.timeRangeValue.containsTime(target) }
        guard canJump else {
            // A stream the server converts on the fly can't jump: reopen the song there.
            reopen(at: seconds, from: item, reason: "stream can't jump")
            return
        }
        seekGeneration += 1
        let generation = seekGeneration
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                // A newer drag replacing this one isn't a failure.
                guard let self, !finished, generation == self.seekGeneration, self.activeItem === item else { return }
                self.reopen(at: seconds, from: item, reason: "jump didn't finish")
            }
        }
    }

    /// Opens the song again at a new spot: the copy on the phone if there is
    /// one, otherwise a fresh stream that can jump.
    private func reopen(at seconds: Double, from item: AVPlayerItem, reason: String) {
        logger.info("Music: reopening the song to jump to \(Int(seconds))s (\(reason))")
        if switchToCachedCopy(at: seconds, from: item) { return }
        usePlainStream = false
        reload(at: seconds)
    }

    func stop() {
        tokenWaitTask?.cancel()
        startWatchdog?.cancel()
        stopWaitingForNetwork()
        KhyloSongCache.shared.cancel()
        try? FileManager.default.removeItem(at: Self.sessionFile)
        releaseAppAwake()
        loadGeneration = nil
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
        // A different song starts fresh; reloading the same one keeps its retry count.
        if newIndex != index || current?.id != queue[safe: newIndex]?.id {
            retries = 0
            usePlainStream = false
        }
        index = newIndex
        tokenWaitTask?.cancel()
        stopWaitingForNetwork()
        guard let item = current else { return }
        holdAppAwake()
        // Never open a stream without the sign-in token: the server refuses it.
        guard let url = streamURL(for: item) else {
            waitForToken(index: newIndex, startTicks: startTicks)
            return
        }

        let start = Double(startTicks ?? KhyloDownloads.shared.resumeTicks(for: item) ?? 0) / 10_000_000
        duration = Double(item.runTimeTicks ?? 0) / 10_000_000
        currentTime = start
        playSessionID = UUID().uuidString

        preloaded = nil
        player.removeAllItems()
        activeItem = nil
        waitingForAutoplay = false
        activateSession()
        claimRemoteCommands()
        player.defaultRate = rate
        isPlaying = true
        isBuffering = true
        let generation = UUID()
        loadGeneration = generation
        let name = item.name ?? ""

        if url.isFileURL || usePlainStream {
            attach(url, start: start, name: name)
        } else {
            // Find out what the server will send before handing it to the player.
            Task { @MainActor [weak self] in
                let resolved = await Self.resolveStream(url)
                guard let self, self.loadGeneration == generation, self.isActive else { return }
                self.attach(resolved.url, start: start, name: name, note: resolved.note)
            }
        }
        trackDidStart()
        prepareCache()
        saveSession(force: true)
    }

    /// Puts a song's stream into the player and starts it.
    private func attach(_ url: URL, start: Double, name: String, note: String? = nil) {
        let playerItem = makePlayerItem(url)
        player.removeAllItems()
        player.insert(playerItem, after: nil)
        activeItem = playerItem
        handledItem = nil
        if start > 1 {
            // Exactly where it was, not the nearest earlier point.
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        // Paused while the stream was being looked up: stay paused.
        if isPlaying {
            // play() (not playImmediately) lets the player buffer enough to avoid stutter.
            player.play()
        }
        let source = url.isFileURL ? "download" : (usePlainStream ? "plain stream" : (note ?? "stream"))
        logger.info("Music: loading \(name) from \(source)")
        armStartWatchdog(for: playerItem)
    }

    /// When the server converts a song it answers with an HLS master playlist.
    /// Apple's player can sit on that master forever without asking for any
    /// audio, while the media playlist inside it starts at once. So: ask the
    /// server (headers only) what it will send, and for HLS hand the player the
    /// media playlist directly. Songs that stream as they are stay untouched.
    private static func resolveStream(_ url: URL) async -> (url: URL, note: String) {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 8
        for (name, value) in Self.streamHeaders() { head.setValue(value, forHTTPHeaderField: name) }
        let answer = try? await URLSession.shared.data(for: head)
        guard let http = answer?.1 as? HTTPURLResponse, http.statusCode == 200 else {
            // Say what the server answered, so a refused stream can be traced.
            let status = (answer?.1 as? HTTPURLResponse)?.statusCode
            Logger.swiftfin().warning("Music: stream check answered \(status.map(String.init) ?? "nothing")", metadata: ["path": "\(url.path)"])
            return (url, "stream (unchecked)")
        }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard type.contains("mpegurl") else { return (url, "direct stream") }

        var get = URLRequest(url: url)
        get.timeoutInterval = 8
        for (name, value) in Self.streamHeaders() { get.setValue(value, forHTTPHeaderField: name) }
        guard let (data, _) = try? await URLSession.shared.data(for: get),
              let text = String(data: data, encoding: .utf8)
        else { return (url, "hls master (unread)") }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let infIndex = lines.firstIndex(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }),
              let variant = lines[(infIndex + 1)...].first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
              let media = URL(string: variant, relativeTo: url)?.absoluteURL
        else {
            // Already a media playlist.
            return (url, "hls")
        }
        return (media, "hls media playlist")
    }

    /// A song that loads its playlist but never asks for any audio would spin
    /// forever. If it hasn't started after a while, treat it as failed: the
    /// retry opens a fresh, plain stream.
    private func armStartWatchdog(for item: AVPlayerItem) {
        startWatchdog?.cancel()
        startWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled, item === self.activeItem,
                  self.isPlaying, self.playingItem !== item
            else { return }
            self.logger.warning(
                "Music: song didn't start within 10s",
                metadata: [
                    "status": "\(item.status.rawValue)",
                    "waiting": "\(self.player.reasonForWaitingToPlay?.rawValue ?? "none")",
                    "details": "\(Self.describe(item))",
                ]
            )
            self.usePlainStream = true
            self.recoverFromFailure(item)
        }
    }

    /// What the player saw of a stream, for the log.
    private static func describe(_ item: AVPlayerItem) -> String {
        var parts: [String] = []
        if let error = item.error as NSError? {
            parts.append("error \(error.domain) \(error.code): \(error.localizedDescription)")
        }
        for event in item.errorLog()?.events.suffix(3) ?? [] {
            parts.append("errorLog \(event.errorStatusCode) \(event.errorDomain): \(event.errorComment ?? "")")
        }
        if let access = item.accessLog()?.events.last {
            parts.append("access requests=\(access.numberOfMediaRequests) bytes=\(access.numberOfBytesTransferred) uri=\(access.uri?.components(separatedBy: "?").first ?? "")")
        }
        return parts.isEmpty ? "nothing logged" : parts.joined(separator: " | ")
    }

    /// The sign-in token couldn't be read yet (e.g. right after a restart, before
    /// the first unlock). Hold the song and start it as soon as the token is there.
    private func waitForToken(index waitingIndex: Int, startTicks: Int?) {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        tokenWaitTask = Task { @MainActor [weak self] in
            for _ in 0 ..< 60 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.isActive, self.index == waitingIndex else { return }
                if KhyloAPI.accessToken != nil {
                    self.load(index: waitingIndex, startTicks: startTicks)
                    return
                }
            }
        }
    }

    /// The server opened the stream: now the song really is playing.
    private func streamDidOpen(_ item: AVPlayerItem?) {
        guard let item, item === activeItem, item !== startedItem else { return }
        startedItem = item
        reportStart()
    }

    /// Plays the track at `newIndex` again from `seconds`, with a fresh connection.
    private func reload(at seconds: Double) {
        let wasPlaying = isPlaying
        // Tell the server the broken stream is over before opening a new one.
        reportStopped()
        load(index: index, startTicks: Int(seconds * 10_000_000))
        if !wasPlaying { pause() }
    }

    /// The stream for the current track failed (lost connection, server hiccup).
    /// Pick it up again from where it stopped; only after several tries move on,
    /// and never race through the queue.
    private func recoverFromFailure(_ item: AVPlayerItem?) {
        guard isActive, let item, item === activeItem, item !== handledItem else { return }
        handledItem = item
        startWatchdog?.cancel()
        holdAppAwake()
        // Where it actually got to (the clock can lag a moment behind).
        let playhead = item.currentTime().seconds
        let position = max(currentTime, playhead.isFinite ? playhead : 0)
        let rejected = Self.wasRejected(item)
        logger.warning("Music: stream failed", metadata: ["details": "\(Self.describe(item))"])

        // The song's already on the phone: carry on from that copy at the same second.
        if switchToCachedCopy(at: position, from: item) { return }

        // No signal: wait for it and pick up at the same spot. Losing signal
        // never skips a song.
        if !KhyloNetwork.shared.isOnline || (Self.isNetworkFailure(item) && retries >= 3) {
            waitForNetwork(at: position)
            return
        }

        // Anything but a refused link: try the plain stream next time.
        if !rejected { usePlainStream = true }
        if retries < 3 {
            retries += 1
            // A refused link is rebuilt with the current token right away; a dropped
            // connection gets a moment to come back.
            let wait: Double = rejected && retries == 1 ? 0.5 : [2, 5, 10][min(retries - 1, 2)]
            isBuffering = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard let self, self.isActive, self.activeItem === item else { return }
                self.reload(at: position)
            }
            return
        }

        // Online, several fresh tries, and the file itself still won't play: move on.
        retries = 0
        failedInARow += 1
        if failedInARow < 3, let next = nextIndex {
            reportStopped()
            load(index: next, startTicks: 0)
        } else {
            // Several songs in a row won't play (the server or connection is down):
            // stop here rather than skipping through everything.
            failedInARow = 0
            player.pause()
            isPlaying = false
            isBuffering = false
            updateNowPlaying()
            releaseAppAwake()
        }
    }

    /// Swaps a broken stream for the copy kept on the phone, at the same second.
    private func switchToCachedCopy(at position: Double, from item: AVPlayerItem) -> Bool {
        guard kind == .music,
              let cached = KhyloSongCache.shared.file(for: current?.id),
              (item.asset as? AVURLAsset)?.url != cached
        else { return false }
        logger.info("Music: carrying on from the copy on the phone")
        retries = 0
        attach(cached, start: position, name: current?.name ?? "", note: "copy on the phone")
        return true
    }

    /// Holds the song until there's a connection again, then carries on from the same spot.
    private func waitForNetwork(at position: Double) {
        if networkWaitStarted == nil { networkWaitStarted = Date() }
        // After a few minutes without a connection, pause rather than spin forever.
        if let started = networkWaitStarted, Date().timeIntervalSince(started) > 5 * 60 {
            networkWaitStarted = nil
            stopWaitingForNetwork()
            player.pause()
            isPlaying = false
            isBuffering = false
            updateNowPlaying()
            releaseAppAwake()
            return
        }
        logger.info("Music: waiting for a connection")
        waitingForNetwork = true
        waitPosition = position
        isBuffering = true
        networkWaitTask?.cancel()
        networkWaitTask = Task { @MainActor [weak self] in
            for _ in 0 ..< 30 {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, self.waitingForNetwork else { return }
                // The copy on the phone may have finished meanwhile.
                if let item = self.activeItem, self.switchToCachedCopy(at: self.waitPosition, from: item) {
                    self.stopWaitingForNetwork()
                    return
                }
                if KhyloNetwork.shared.isOnline {
                    self.resumeAfterNetwork()
                    return
                }
            }
        }
    }

    private func resumeAfterNetwork() {
        guard waitingForNetwork, isActive else { return }
        stopWaitingForNetwork()
        retries = 0
        reload(at: waitPosition)
    }

    private func stopWaitingForNetwork() {
        waitingForNetwork = false
        networkWaitTask?.cancel()
        networkWaitTask = nil
    }

    /// The connection dropped, as opposed to the file or the server refusing.
    private static func isNetworkFailure(_ item: AVPlayerItem) -> Bool {
        let error = item.error as NSError?
        guard let error else { return true }
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        if [error, underlying].contains(where: { $0?.domain == NSURLErrorDomain }) { return true }
        return item.errorLog()?.events.contains { $0.errorDomain == NSURLErrorDomain } == true
    }

    // MARK: - Staying awake between songs

    /// iOS only keeps a music app running in the background while sound is
    /// playing. Between songs (or while a stream reconnects) nothing plays for
    /// a moment, so ask for a little time to get the next one going.
    private func holdAppAwake() {
        guard transitionTask == .invalid else { return }
        transitionTask = UIApplication.shared.beginBackgroundTask(withName: "org.khylo.music.next") { [weak self] in
            MainActor.assumeIsolated { self?.releaseAppAwake() }
        }
    }

    private func releaseAppAwake() {
        guard transitionTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(transitionTask)
        transitionTask = .invalid
    }

    /// The server turned the stream down (signed-out or missing token), as opposed
    /// to the connection dropping.
    private static func wasRejected(_ item: AVPlayerItem) -> Bool {
        if let events = item.errorLog()?.events,
           events.contains(where: { $0.errorStatusCode == 401 || $0.errorStatusCode == 403 }) {
            return true
        }
        let error = item.error as NSError?
        let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError
        return [error, underlying].contains {
            $0?.domain == NSURLErrorDomain && $0?.code == NSURLErrorUserAuthenticationRequired
        }
    }

    /// The sign-in token as a header too, besides the one in the link, so the
    /// server accepts the stream whichever way it reads it.
    private static func streamHeaders() -> [String: String] {
        guard let token = KhyloAPI.accessToken else { return [:] }
        return ["Authorization": "MediaBrowser Token=\"\(token)\"", "X-Emby-Token": token]
    }

    private func makePlayerItem(_ url: URL) -> AVPlayerItem {
        var options: [String: Any] = [AVURLAssetAllowsCellularAccessKey: true]
        if !url.isFileURL {
            options["AVURLAssetHTTPHeaderFieldsKey"] = Self.streamHeaders()
        }
        if url.isFileURL {
            // MP3s the server converted on the fly have no header giving their
            // length, so the player can't jump around in them unless it reads
            // the whole file first. Cheap for a file on the phone; a stream
            // would have to download completely, so streams don't do this.
            options[AVURLAssetPreferPreciseDurationAndTimingKey] = true
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        item.audioTimePitchAlgorithm = kind == .audiobook ? .timeDomain : .spectral
        // A long buffer rides out short dead spots.
        item.preferredForwardBufferDuration = 60
        if kind == .music { KhyloEqualizer.attach(to: item) }
        return item
    }

    /// Bookkeeping when a track begins, whether picked or reached from the queue.
    private func trackDidStart() {
        handledItem = nil
        extendQueueIfNeeded()
        // The server hears it started once the stream really opens (streamDidOpen).
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

    /// Forgets a loaded-ahead next track (the queue changed).
    private func discardPreload() {
        if let preloaded {
            player.remove(preloaded.item)
            self.preloaded = nil
        }
    }

    // The next song is not loaded ahead: the server only ever sees one stream
    // from this phone, so its stream limits never refuse the song that's next.

    /// Puts the next track into the player so it starts without a gap.
    private func preloadNext() {
        discardPreload()
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
        retries = 0
        trackDidStart()
    }

    /// A song reached its end. This is the only place the next song starts, so
    /// nothing can skip ahead on its own.
    private func itemDidEnd(_ ended: AVPlayerItem?) {
        guard let ended, ended === activeItem, ended !== handledItem else { return }
        handledItem = ended

        if repeatMode == .one {
            report(force: true)
            handledItem = nil
            player.seek(to: .zero)
            player.play()
            return
        }

        // Ended well before its real length: the stream was cut off, not finished.
        // Carry on from the same spot instead of moving to the next song.
        let expected = Double(current?.runTimeTicks ?? 0) / 10_000_000
        let reached = currentTime
        if expected > 30, reached < expected - 10 {
            holdAppAwake()
            if switchToCachedCopy(at: reached, from: ended) { return }
            if !KhyloNetwork.shared.isOnline {
                waitForNetwork(at: reached)
                return
            }
        }
        if expected > 30, reached < expected - 10, retries < 3 {
            retries += 1
            let wait: Double = [2, 5, 10][min(retries - 1, 2)]
            isBuffering = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard let self, self.isActive, self.activeItem === ended else { return }
                self.reload(at: reached)
            }
            return
        }

        failedInARow = 0
        holdAppAwake()
        report(force: true)
        reportStopped()

        if let preloaded, preloaded.item.status != .failed, let next = nextIndex, preloaded.index == next {
            // The next song is already loaded: hand over to it.
            player.advanceToNextItem()
            player.play()
            return
        }
        discardPreload()
        if let next = nextIndex {
            load(index: next, startTicks: 0)
        } else if isExtendingQueue {
            // Autoplay is still finding more music; carry on as soon as it arrives.
            waitingForAutoplay = true
            isBuffering = true
        } else {
            isPlaying = false
            currentTime = 0
            updateNowPlaying()
        }
    }

    // MARK: - Autoplay

    /// When the last song in the queue starts, line up more music like it, so
    /// playback carries on instead of stopping: a mix built from that song (and
    /// its artist), falling back to more by the same artist.
    private func extendQueueIfNeeded() {
        guard kind == .music, repeatMode == .off, !isExtendingQueue,
              index >= queue.count - 1, let seed = current,
              KhyloNetwork.shared.isOnline
        else { return }
        isExtendingQueue = true
        Task { @MainActor [weak self] in
            var more = (try? await KhyloAPI.instantMix(from: seed.id ?? "", limit: 60)) ?? []
            if more.isEmpty, let artistID = seed.khyloArtistLinks.first?.id {
                more = (try? await KhyloAPI.items(types: [.audio], sortBy: [.random], artistIDs: [artistID], limit: 60).items) ?? []
            }
            guard let self else { return }
            self.isExtendingQueue = false
            let known = Set(self.queue.suffix(200).compactMap(\.id))
            let fresh = more.filter { !known.contains($0.id ?? "") }
            guard !fresh.isEmpty, self.kind == .music else {
                if self.waitingForAutoplay {
                    self.waitingForAutoplay = false
                    self.isBuffering = false
                    self.isPlaying = false
                    self.updateNowPlaying()
                }
                return
            }
            self.queue.append(contentsOf: fresh)
            self.prepareCache()
            if self.waitingForAutoplay {
                self.waitingForAutoplay = false
                self.load(index: self.index + 1, startTicks: 0)
            } else {
                self.updateCommandAvailability()
            }
        }
    }

    private func streamURL(for item: BaseItemDto) -> URL? {
        // A downloaded copy plays first; streaming only when it isn't downloaded.
        if let id = item.id, let file = KhyloDownloads.shared.fileURL(for: id) {
            return file
        }
        // Then the copy kept ahead while listening.
        if kind == .music, let cached = KhyloSongCache.shared.file(for: item.id) {
            return cached
        }
        guard let session = KhyloAPI.session, let id = item.id,
              let token = KhyloAPI.accessToken
        else { return nil }
        var parameters = Paths.GetUniversalAudioStreamParameters()
        parameters.container = ["mp3", "aac", "m4a|aac", "m4b|aac", "flac", "alac", "m4a|alac", "wav", "mp4"]
        parameters.userID = session.user.id
        parameters.deviceID = UIDevice.current.identifierForVendor?.uuidString
        parameters.maxStreamingBitrate = 320_000_000
        if usePlainStream {
            // One continuous MP3 stream: plays anywhere, nothing to piece together.
            parameters.transcodingContainer = "mp3"
            parameters.transcodingProtocol = .http
            parameters.audioCodec = "mp3"
        } else {
            // HLS made of MPEG-TS segments, the kind iPhone has always played reliably.
            parameters.transcodingContainer = "ts"
            parameters.transcodingProtocol = .hls
            parameters.audioCodec = "aac"
        }
        guard let base = session.client.url(with: Paths.getUniversalAudioStream(itemID: id, parameters: parameters)),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "api_key", value: token)]
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
        // Time from a song that isn't the one playing (just skipped, or the next one
        // waiting) would make the bar jump; only the playing song moves it.
        if let item = player.currentItem, let active = activeItem, item !== active { return }
        currentTime = seconds
        // The song's real length comes from the library. A stream the server converts
        // on the fly only knows how much has arrived so far, which made the length
        // wrong and kept changing.
        let known = Double(current?.runTimeTicks ?? 0) / 10_000_000
        if known > 0 {
            duration = max(known, seconds)
        } else if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = max(itemDuration, seconds)
        }
        if player.timeControlStatus == .playing, seconds > 3 {
            retries = 0
            failedInARow = 0
            networkWaitStarted = nil
        }
        report(force: false)
        saveSession(force: false)
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

    /// Downloaded songs and audiobooks keep their progress on the phone too, so
    /// it's saved without a connection and sent to the server later.
    private func recordOffline(isFinal: Bool) {
        guard let id = current?.id, KhyloDownloads.shared.isDownloaded(id) else { return }
        KhyloDownloads.shared.record(itemID: id, ticks: Int(currentTime * 10_000_000), isFinal: isFinal)
    }

    private func reportStart() {
        guard let info = stateInfo(), let client = KhyloAPI.session?.client else { return }
        lastReport = Date()
        Task { _ = try? await client.send(Paths.reportPlaybackStart(info)) }
    }

    private func report(force: Bool) {
        guard startedItem != nil, startedItem === activeItem,
              force || Date().timeIntervalSince(lastReport) > 10,
              let info = stateInfo(),
              let client = KhyloAPI.session?.client
        else { return }
        lastReport = Date()
        recordOffline(isFinal: false)
        Task { _ = try? await client.send(Paths.reportPlaybackProgress(info)) }
    }

    private func reportStopped() {
        // A stream that never opened was never reported as playing.
        guard startedItem != nil, startedItem === activeItem else { return }
        startedItem = nil
        recordOffline(isFinal: true)
        guard let item = current, let client = KhyloAPI.session?.client else { return }
        var info = PlaybackStopInfo()
        info.itemID = item.id
        info.playSessionID = playSessionID
        info.positionTicks = Int(currentTime * 10_000_000)
        Task { _ = try? await client.send(Paths.reportPlaybackStopped(info)) }
    }

    // MARK: - Cache ahead

    /// The song that's streaming and the next two, kept on the phone as you listen.
    private func prepareCache() {
        guard kind == .music, let current else {
            KhyloSongCache.shared.cancel()
            return
        }
        var items: [BaseItemDto] = []
        if !KhyloDownloads.shared.isDownloaded(current.id), KhyloSongCache.shared.file(for: current.id) == nil {
            items.append(current)
        }
        var position = index
        for _ in 0 ..< 2 {
            position += 1
            if position >= queue.count {
                guard repeatMode == .all, !queue.isEmpty else { break }
                position = 0
            }
            items.append(queue[position])
        }
        KhyloSongCache.shared.prepare(items)
    }

    // MARK: - Remembering what was playing

    private struct SavedSession: Codable {
        var queue: [BaseItemDto]
        var index: Int
        var position: Double
        var kind: Kind
        var collectionTitle: String?
        var artworkURL: URL?
        /// The account it was playing on ("server|user").
        var owner: String?
    }

    private static var sessionFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("khylo-now-playing.json")
    }

    /// Saves the queue and position so the app opens on the same song.
    private func saveSession(force: Bool) {
        guard current != nil, force || Date().timeIntervalSince(lastSessionSave) > 5 else { return }
        lastSessionSave = Date()
        let first = max(0, index - 50)
        let last = min(queue.count, index + 150)
        let saved = SavedSession(
            queue: Array(queue[first ..< last]),
            index: index - first,
            position: currentTime,
            kind: kind,
            collectionTitle: collectionTitle,
            artworkURL: artworkURL,
            owner: KhyloAccount.currentKey
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(
            at: Self.sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: Self.sessionFile, options: .atomic)
    }

    /// Puts back what was playing when the app was last closed, paused, so
    /// Play carries on from the same spot.
    func restoreSession() {
        guard !isActive,
              let data = try? Data(contentsOf: Self.sessionFile),
              let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
              saved.queue.indices.contains(saved.index)
        else { return }
        // Only the account (and server) that was listening gets its song back.
        let belongs = if let owner = saved.owner {
            owner == KhyloAccount.currentKey
        } else {
            saved.queue[saved.index].serverID == KhyloAccount.currentServerID
        }
        guard belongs else {
            try? FileManager.default.removeItem(at: Self.sessionFile)
            return
        }
        queue = saved.queue
        index = saved.index
        kind = saved.kind
        collectionTitle = saved.collectionTitle
        artworkURL = saved.artworkURL
        duration = Double(saved.queue[saved.index].runTimeTicks ?? 0) / 10_000_000
        currentTime = saved.position
        isPlaying = false
        isBuffering = false
        loadArtwork()
        loadQuality()
        updateNowPlaying()
    }

    // MARK: - Lock screen

    /// Makes the lock screen, Control Center, headphone and car controls drive this
    /// player. Other players (the video player) replace these handlers while they
    /// run, so this is called again whenever music starts or resumes.
    private func claimRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let commands: [MPRemoteCommand] = [
            center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
            center.nextTrackCommand, center.previousTrackCommand,
            center.skipForwardCommand, center.skipBackwardCommand,
            center.changePlaybackPositionCommand,
        ]
        for command in commands {
            command.removeTarget(nil)
        }
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
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
        // Saved artwork works offline.
        if let local = KhyloDownloads.shared.artworkURL(for: item.id) { return local }
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
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
