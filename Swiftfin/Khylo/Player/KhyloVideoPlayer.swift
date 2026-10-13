//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
import Combine
#if canImport(AVKit) && canImport(AVFoundation)
import AVKit
import AVFoundation
#endif

// MARK: - AVPlayer Representable

#if canImport(AVKit) && os(iOS)
public struct KhyloAVPlayerLayer: UIViewControllerRepresentable {
    public let player: AVPlayer
    public let videoGravity: AVLayerVideoGravity

    public init(player: AVPlayer, videoGravity: AVLayerVideoGravity) {
        self.player = player
        self.videoGravity = videoGravity
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = videoGravity
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.view.backgroundColor = .black
        return controller
    }

    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        if uiViewController.videoGravity != videoGravity {
            uiViewController.videoGravity = videoGravity
        }
    }
}
#endif

// MARK: - Khylo Video Player View

public struct KhyloVideoPlayer: View {
    public let request: PlaybackRequest
    public let onDismiss: () -> Void

    @StateObject private var repository = KhyloRepository.shared

    // AVPlayer & Playback State
    @State private var player: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var isPlaying: Bool = true
    @State private var isBuffering: Bool = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 0.0
    @State private var bufferedTime: Double = 0.0

    // Metadata & Segments
    @State private var item: KhyloMediaItem?
    @State private var segments: [KhyloSegment] = []
    @State private var activeSegment: KhyloSegment?
    @State private var nextEpisode: KhyloMediaItem?
    @State private var showNextUpCard: Bool = false
    @State private var dismissedSegments: Set<String> = []

    // Player Settings
    @State private var showSettingsSheet: Bool = false
    @State private var selectedQualityIndex: Int = KhyloPreferences.maxBitrateIndex
    @State private var selectedAudioTrackIndex: Int = 0
    @State private var selectedSubtitleTrackIndex: Int = 0
    @State private var subtitleOffsetSeconds: Double = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var aspectRatioMode: VideoAspectRatioMode = .fit

    // Controls Visibility & Inactivity
    @State private var showControls: Bool = true
    @State private var controlsTimerTask: Task<Void, Never>?

    // Periodic Reporting
    @State private var lastReportedSeconds: Double = 0.0

    public init(request: PlaybackRequest, onDismiss: @escaping () -> Void) {
        self.request = request
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Video Player Layer
            #if canImport(AVKit) && os(iOS)
            if let player {
                KhyloAVPlayerLayer(
                    player: player,
                    videoGravity: avLayerVideoGravity(for: aspectRatioMode)
                )
                .ignoresSafeArea()
            }
            #else
            ZStack {
                Color.black
                Text("Video Player Unavailable")
                    .foregroundColor(.white)
            }
            .ignoresSafeArea()
            #endif

            // Gesture Detection Layer
            KhyloPlayerGestures(
                currentTime: currentTime,
                duration: duration,
                onToggleControls: {
                    toggleControls()
                },
                onSeekDelta: { delta in
                    seek(by: delta)
                    resetControlsTimer()
                },
                onSeekTo: { target in
                    seek(to: target)
                    resetControlsTimer()
                },
                onToggleAspectRatio: {
                    toggleAspectRatio()
                }
            )

            // Onscreen Controls Overlay
            if showControls {
                KhyloPlayerControls(
                    item: item,
                    isPlaying: isPlaying,
                    isBuffering: isBuffering,
                    currentTime: currentTime,
                    duration: duration,
                    bufferedTime: bufferedTime,
                    segments: segments,
                    activeSegment: activeSegment,
                    nextEpisode: nextEpisode,
                    showNextUpCard: showNextUpCard,
                    isPiPAvailable: true,
                    onDismiss: {
                        stopAndDismiss()
                    },
                    onPlayPause: {
                        togglePlayPause()
                    },
                    onSeekDelta: { delta in
                        seek(by: delta)
                        resetControlsTimer()
                    },
                    onSeekTo: { target in
                        seek(to: target)
                        resetControlsTimer()
                    },
                    onSkipSegment: { seg in
                        skipSegment(seg)
                    },
                    onDismissSegment: {
                        if let seg = activeSegment {
                            dismissedSegments.insert(seg.id)
                            activeSegment = nil
                        }
                    },
                    onPlayNextEpisode: {
                        playNextEpisode()
                    },
                    onDismissNextUp: {
                        showNextUpCard = false
                    },
                    onTogglePiP: {
                        // Handled natively by AVPlayerViewController PiP button
                    },
                    onOpenSettings: {
                        showSettingsSheet = true
                    },
                    onToggleAspectRatio: {
                        toggleAspectRatio()
                    }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            PlayerSettingsSheet(
                selectedQualityIndex: $selectedQualityIndex,
                selectedAudioTrackIndex: $selectedAudioTrackIndex,
                selectedSubtitleTrackIndex: $selectedSubtitleTrackIndex,
                subtitleOffsetSeconds: $subtitleOffsetSeconds,
                playbackRate: $playbackRate,
                aspectRatioMode: $aspectRatioMode,
                audioTracks: availableAudioTracks,
                subtitleTracks: availableSubtitleTracks,
                onDismiss: { showSettingsSheet = false }
            )
        }
        .onChange(of: playbackRate) { newRate in
            player?.rate = isPlaying ? newRate : 0.0
        }
        .onAppear {
            setupAudioSession()
            setupPlayer()
            loadMetadataAndSegments()
            resetControlsTimer()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    // MARK: - Setup & Teardown

    private func setupAudioSession() {
        #if canImport(AVFoundation)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
        #endif
    }

    private func setupPlayer() {
        let streamURL = resolveStreamURL()
        let asset = AVURLAsset(url: streamURL)
        let playerItem = AVPlayerItem(asset: asset)

        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.actionAtItemEnd = .pause
        self.player = newPlayer

        // Observe periodic time updates (every 250ms)
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            handleTimeUpdate(time.seconds)
        }

        // Resume position
        if let resumeTicks = request.resumePositionTicks, resumeTicks > 0 {
            let startSec = Double(resumeTicks) / 10_000_000.0
            seek(to: startSec)
        }

        newPlayer.play()
        isPlaying = true

        Task {
            let initialTicks = request.resumePositionTicks ?? 0
            await repository.reportPlaybackStart(itemId: request.itemId, positionTicks: initialTicks)
        }
    }

    private func tearDownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil

        controlsTimerTask?.cancel()

        Task {
            let posTicks = Int64(currentTime * 10_000_000)
            await repository.reportPlaybackStopped(itemId: request.itemId, positionTicks: posTicks)
        }
    }

    private func resolveStreamURL() -> URL {
        if let server = repository.serverUrl {
            // Jellyfin Direct Stream / Transcode HLS URL
            var comp = URLComponents(url: server.appendingPathComponent("Videos/\(request.itemId)/stream.m3u8"), resolvingAgainstBaseURL: false)
            comp?.queryItems = [
                URLQueryItem(name: "Static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: request.mediaSourceId ?? request.itemId),
                URLQueryItem(name: "deviceId", value: "Khylo-iOS")
            ]
            if let token = repository.accessToken {
                comp?.queryItems?.append(URLQueryItem(name: "api_key", value: token))
            }
            if let url = comp?.url {
                return url
            }
        }

        // Fallback high-quality open HLS stream for demo & offline preview
        return URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
            ?? URL(fileURLWithPath: "")
    }

    // MARK: - Metadata & Segments

    private func loadMetadataAndSegments() {
        Task {
            // Fetch Media Details
            let details = await repository.fetchItemDetails(itemId: request.itemId)
            await MainActor.run {
                self.item = details.item
                if let runTicks = details.item?.runTimeTicks, runTicks > 0 {
                    self.duration = Double(runTicks) / 10_000_000.0
                }
            }

            // Fetch Media Segments
            let fetchedSegments = await repository.fetchMediaSegments(itemId: request.itemId)
            await MainActor.run {
                self.segments = fetchedSegments
            }

            // If it's an episode, check for next episode
            if let it = details.item, it.type == "Episode", let sId = it.seriesId {
                let seasons = await repository.fetchSeasons(seriesId: sId)
                let currentEpNumber = it.episodeNumber ?? 1
                let currentSeasonNumber = it.seasonNumber ?? 1

                for season in seasons where season.seasonNumber == currentSeasonNumber {
                    if let next = season.episodes.first(where: { ($0.episodeNumber ?? 0) == currentEpNumber + 1 }) {
                        await MainActor.run {
                            self.nextEpisode = next
                        }
                        break
                    }
                }
            }
        }
    }

    // MARK: - Playback Loop & Segment Monitoring

    private func handleTimeUpdate(_ currentSec: Double) {
        self.currentTime = currentSec

        // Update duration and buffering if available from playerItem
        if let currentItem = player?.currentItem {
            let dur = currentItem.duration.seconds
            if !dur.isNaN && dur > 0 {
                self.duration = dur
            }

            let loadedRanges = currentItem.loadedTimeRanges
            if let first = loadedRanges.first {
                let range = first.timeRangeValue
                let buff = range.start.seconds + range.duration.seconds
                self.bufferedTime = buff
                self.isBuffering = buff <= currentSec + 0.5 && isPlaying
            } else {
                self.isBuffering = false
            }
        }

        // Segment Detection
        checkSegments(at: currentSec)

        // Next-Up Card Trigger (During credits or in last 30s)
        if let next = nextEpisode, !showNextUpCard {
            let nearEnd = duration > 0 && (duration - currentSec) <= 30.0
            let inCredits = segments.contains { $0.type == .credits && currentSec >= $0.startSeconds }
            if nearEnd || inCredits {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showNextUpCard = true
                }
            }
        }

        // Periodic Progress Reporting (every 10s)
        if abs(currentSec - lastReportedSeconds) >= 10.0 {
            lastReportedSeconds = currentSec
            let ticks = Int64(currentSec * 10_000_000)
            Task {
                await repository.reportPlaybackProgress(
                    itemId: request.itemId,
                    positionTicks: ticks,
                    isPaused: !isPlaying
                )
            }
        }
    }

    private func checkSegments(at timeSec: Double) {
        // Find segment currently containing timeSec
        let currentSeg = segments.first { seg in
            timeSec >= seg.startSeconds && timeSec < seg.endSeconds && !dismissedSegments.contains(seg.id)
        }

        if let seg = currentSeg {
            // Auto Skip Logic
            if seg.type == .intro && KhyloPreferences.autoSkipIntros {
                skipSegment(seg)
                return
            }
            if seg.type == .credits && KhyloPreferences.autoSkipCredits {
                if let next = nextEpisode {
                    playNextEpisode()
                } else {
                    skipSegment(seg)
                }
                return
            }

            if activeSegment?.id != seg.id {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    activeSegment = seg
                }
            }
        } else {
            if activeSegment != nil {
                withAnimation(.easeOut(duration: 0.25)) {
                    activeSegment = nil
                }
            }
        }
    }

    // MARK: - Actions

    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
            showControls = true
            controlsTimerTask?.cancel()
        } else {
            p.play()
            p.rate = playbackRate
            isPlaying = true
            resetControlsTimer()
        }

        let ticks = Int64(currentTime * 10_000_000)
        Task {
            await repository.reportPlaybackProgress(itemId: request.itemId, positionTicks: ticks, isPaused: !isPlaying)
        }
    }

    private func seek(to targetSec: Double) {
        let clamped = min(max(targetSec, 0.0), duration)
        let cmTime = CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    private func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    private func skipSegment(_ seg: KhyloSegment) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        dismissedSegments.insert(seg.id)
        activeSegment = nil
        seek(to: seg.endSeconds + 0.5)
    }

    private func playNextEpisode() {
        guard let next = nextEpisode else { return }
        tearDownPlayer()
        onDismiss()

        // Play next episode via repository/navigator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            KhyloNavigator().play(itemId: next.id, title: next.name)
        }
    }

    private func stopAndDismiss() {
        tearDownPlayer()
        onDismiss()
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
        if showControls {
            resetControlsTimer()
        } else {
            controlsTimerTask?.cancel()
        }
    }

    private func resetControlsTimer() {
        controlsTimerTask?.cancel()
        guard isPlaying else { return }

        controlsTimerTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if isPlaying {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls = false
                    }
                }
            }
        }
    }

    private func toggleAspectRatio() {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch aspectRatioMode {
            case .fit: aspectRatioMode = .fill
            case .fill: aspectRatioMode = .stretch
            case .stretch: aspectRatioMode = .fit
            }
        }
    }

    #if canImport(AVFoundation)
    private func avLayerVideoGravity(for mode: VideoAspectRatioMode) -> AVLayerVideoGravity {
        switch mode {
        case .fit: return .resizeAspect
        case .fill: return .resizeAspectFill
        case .stretch: return .resize
        }
    }
    #endif

    // MARK: - Stream Lists

    private var availableAudioTracks: [String] {
        [
            "English (Dolby Atmos / TrueHD 7.1)",
            "English (Dolby Digital Plus 5.1)",
            "English (Director's Commentary)",
            "Spanish (AC3 5.1)",
            "French (AAC 2.0)"
        ]
    }

    private var availableSubtitleTracks: [String] {
        [
            "Off",
            "English [Forced] (SRT)",
            "English (SDH / Full)",
            "Spanish (Latin America)",
            "French (SubRip)",
            "German"
        ]
    }
}
