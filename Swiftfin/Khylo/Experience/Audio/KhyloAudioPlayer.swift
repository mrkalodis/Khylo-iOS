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

    @Published private(set) var queue: [BaseItemDto] = []
    @Published private(set) var index = 0
    @Published private(set) var kind: Kind = .music
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var rate: Float = 1 {
        didSet { if isPlaying { player.rate = rate } }
    }
    @Published private(set) var sleepTimerEnd: Date?
    /// Title of the audiobook (its folder), shown instead of the part name.
    @Published private(set) var collectionTitle: String?
    @Published private(set) var artworkURL: URL?

    var current: BaseItemDto? { queue.indices.contains(index) ? queue[index] : nil }
    var isActive: Bool { current != nil }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusCancellable: AnyCancellable?
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
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        configureRemoteCommands()
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
        activateSession()
        player.playImmediately(atRate: rate)
        isPlaying = true
        report(force: true)
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        report(force: true)
        updateNowPlaying()
    }

    func next() {
        guard index + 1 < queue.count else { return }
        reportStopped()
        load(index: index + 1, startTicks: 0)
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
        player.replaceCurrentItem(with: nil)
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

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let playerItem = AVPlayerItem(url: url)
        playerItem.audioTimePitchAlgorithm = .timeDomain
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemFinished() }
        }

        player.replaceCurrentItem(with: playerItem)
        if start > 1 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        activateSession()
        player.playImmediately(atRate: rate)
        isPlaying = true
        reportStart()
        loadArtwork()
        updateNowPlaying()
    }

    private func itemFinished() {
        report(force: true)
        reportStopped()
        if index + 1 < queue.count {
            load(index: index + 1, startTicks: 0)
        } else {
            isPlaying = false
            updateNowPlaying()
        }
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

    private func loadArtwork() {
        artworkTask?.cancel()
        artworkImage = nil
        let url = artworkURL ?? current.flatMap { KhyloArtwork.url(for: $0, style: .square, width: 600) }
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
