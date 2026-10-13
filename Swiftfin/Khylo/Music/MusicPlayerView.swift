//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(AVKit) && os(iOS)
import AVKit
#endif

// MARK: - Repeat Mode

public enum MusicRepeatMode: String, CaseIterable {
    case off
    case all
    case one

    public var iconName: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Music Player View

public struct MusicPlayerView: View {
    public let initialTrack: MusicTrack
    public let initialQueue: [MusicTrack]
    public let onDismiss: () -> Void

    @State private var currentTrack: MusicTrack
    @State private var queue: [MusicTrack]
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0.0
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0
    @State private var isFavorite: Bool = false
    @State private var isShuffle: Bool = false
    @State private var repeatMode: MusicRepeatMode = .off
    @State private var showQueueSheet: Bool = false

    @State private var playbackTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init(
        track: MusicTrack,
        queue: [MusicTrack] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.initialTrack = track
        self.initialQueue = queue
        self._currentTrack = State(initialValue: track)
        self._queue = State(initialValue: queue)
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Full-Bleed Ken Burns Animated Backdrop
            KenBurnsView(
                imageURL: currentTrack.imageURL,
                duration: 22.0,
                maxScale: 1.15
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar
                topHeaderBar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                Spacer(minLength: 16)

                // High-Res Album Art
                albumArtworkView
                    .padding(.horizontal, 40)

                Spacer(minLength: 20)

                // Track Metadata & Favorite
                metadataSection
                    .padding(.horizontal, 32)

                // Timeline Scrubber
                scrubberSection
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                // Main Transport Controls
                transportControls
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                Spacer(minLength: 16)

                // Bottom Up Next Peek Card
                bottomPeekCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showQueueSheet) {
            MusicQueueView(
                currentTrack: currentTrack,
                queue: $queue,
                onSelectTrack: { next in
                    playTrack(next)
                    showQueueSheet = false
                },
                onClearQueue: {
                    queue.removeAll()
                },
                onDismiss: {
                    showQueueSheet = false
                }
            )
        }
        .onReceive(playbackTimer) { _ in
            guard isPlaying && !isScrubbing else { return }
            let duration = max(currentTrack.durationSeconds, 1.0)
            if currentTime < duration {
                currentTime += 0.5
            } else {
                handleTrackCompletion()
            }
        }
    }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack {
            // Dismiss Chevron
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onDismiss()
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("PLAYING FROM")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.textTertiary)

                Text(currentTrack.album ?? currentTrack.artist)
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                // AirPlay Route Picker
                #if canImport(AVKit) && os(iOS)
                AirPlayPickerButton()
                    .frame(width: 32, height: 32)
                #endif

                // Queue Button
                Button(action: {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    showQueueSheet = true
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Album Artwork

    private var albumArtworkView: some View {
        ZStack {
            if let url = currentTrack.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    default:
                        artworkFallback
                    }
                }
            } else {
                artworkFallback
            }
        }
        .frame(maxWidth: 320, maxHeight: 320)
        .aspectRatio(1, contentMode: .fit)
        .cornerRadius(KhyloRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: KhyloRadius.lg)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
    }

    private var artworkFallback: some View {
        ZStack {
            KhyloColors.surfaceElevated
            Image(systemName: "music.note")
                .font(.system(size: 72))
                .foregroundColor(KhyloColors.textTertiary)
        }
    }

    // MARK: - Metadata & Favorite

    private var metadataSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(currentTrack.title)
                        .font(KhyloTypography.title2)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    EqualizerBarsView(isPlaying: isPlaying, maxHeight: 18)
                }

                Text(currentTrack.artist)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Favorite Button
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isFavorite.toggle()
                }
            }) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isFavorite ? Color.red : Color.white.opacity(0.8))
                    .scaleEffect(isFavorite ? 1.15 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Scrubber

    private var scrubberSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let activeSec = isScrubbing ? scrubTime : currentTime
                let totalSec = max(currentTrack.durationSeconds, 1.0)
                let progress = min(max(activeSec / totalSec, 0.0), 1.0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: isScrubbing ? 8 : 5)

                    Capsule()
                        .fill(KhyloColors.accent)
                        .frame(width: width * progress, height: isScrubbing ? 8 : 5)

                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 20 : 14, height: isScrubbing ? 20 : 14)
                        .shadow(color: Color.black.opacity(0.4), radius: 4)
                        .offset(x: max((width * progress) - (isScrubbing ? 10 : 7), 0))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isScrubbing { isScrubbing = true }
                            let locationX = min(max(gesture.location.x, 0.0), width)
                            let ratio = locationX / width
                            scrubTime = ratio * totalSec
                        }
                        .onEnded { _ in
                            currentTime = scrubTime
                            isScrubbing = false
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                )
            }
            .frame(height: 24)

            // Timestamps
            HStack {
                let activeSec = isScrubbing ? scrubTime : currentTime
                Text(formatDuration(activeSec))
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(Color.white.opacity(0.7))

                Spacer()

                let remaining = max(currentTrack.durationSeconds - activeSec, 0.0)
                Text("-\(formatDuration(remaining))")
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(Color.white.opacity(0.7))
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 28) {
            // Shuffle
            Button(action: {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                isShuffle.toggle()
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isShuffle ? KhyloColors.accent : Color.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())

            // Previous Track
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                previousTrack()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())

            // Big Center Play / Pause
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPlaying.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(KhyloColors.accent)
                        .frame(width: 72, height: 72)
                        .shadow(color: KhyloColors.accent.opacity(0.45), radius: 14)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Next Track
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                nextTrack()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())

            // Repeat Mode
            Button(action: {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                cycleRepeatMode()
            }) {
                Image(systemName: repeatMode.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(repeatMode != .off ? KhyloColors.accent : Color.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Up Next Peek Card

    @ViewBuilder
    private var bottomPeekCard: some View {
        if let next = queue.first {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                playTrack(next)
            }) {
                HStack(spacing: 12) {
                    // Small thumbnail
                    ZStack {
                        if let url = next.imageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(1, contentMode: .fill)
                                default:
                                    KhyloColors.surfaceElevated
                                }
                            }
                        } else {
                            KhyloColors.surfaceElevated
                        }
                    }
                    .frame(width: 36, height: 36)
                    .cornerRadius(KhyloRadius.xs)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT")
                            .font(KhyloTypography.captionBold)
                            .foregroundColor(KhyloColors.accent)

                        Text("\(next.title) • \(next.artist)")
                            .font(KhyloTypography.caption)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KhyloRadius.sm)
                        .fill(Color.black.opacity(0.55))
                        .background(
                            RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Helper Methods

    private func playTrack(_ track: MusicTrack) {
        currentTrack = track
        currentTime = 0.0
        isPlaying = true
        if let idx = queue.firstIndex(where: { $0.id == track.id }) {
            queue.remove(at: idx)
        }
    }

    private func nextTrack() {
        if repeatMode == .one {
            currentTime = 0.0
            return
        }
        guard !queue.isEmpty else {
            if repeatMode == .all {
                currentTime = 0.0
            } else {
                isPlaying = false
            }
            return
        }
        let next = queue.removeFirst()
        currentTrack = next
        currentTime = 0.0
        isPlaying = true
    }

    private func previousTrack() {
        if currentTime > 3.0 {
            currentTime = 0.0
        } else {
            // Restart track
            currentTime = 0.0
        }
    }

    private func handleTrackCompletion() {
        if repeatMode == .one {
            currentTime = 0.0
        } else {
            nextTrack()
        }
    }

    private func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
