//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(AVKit) && canImport(UIKit)
import AVKit
import UIKit
#endif

// MARK: - AirPlay Route Picker Representable

#if canImport(AVKit) && os(iOS)
public struct AirPlayPickerButton: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(KhyloColors.accent)
        picker.prioritizesVideoDevices = true
        return picker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - Khylo Player Controls Overlay

public struct KhyloPlayerControls: View {
    public let item: KhyloMediaItem?
    public let isPlaying: Bool
    public let isBuffering: Bool
    public let currentTime: Double
    public let duration: Double
    public let bufferedTime: Double
    public let segments: [KhyloSegment]
    public let activeSegment: KhyloSegment?
    public let nextEpisode: KhyloMediaItem?
    public let showNextUpCard: Bool
    public let isPiPAvailable: Bool

    // Actions
    public let onDismiss: () -> Void
    public let onPlayPause: () -> Void
    public let onSeekDelta: (Double) -> Void
    public let onSeekTo: (Double) -> Void
    public let onSkipSegment: (KhyloSegment) -> Void
    public let onDismissSegment: () -> Void
    public let onPlayNextEpisode: () -> Void
    public let onDismissNextUp: () -> Void
    public let onTogglePiP: () -> Void
    public let onOpenSettings: () -> Void
    public let onToggleAspectRatio: () -> Void

    // Interactive scrubber state
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0

    public init(
        item: KhyloMediaItem?,
        isPlaying: Bool,
        isBuffering: Bool,
        currentTime: Double,
        duration: Double,
        bufferedTime: Double,
        segments: [KhyloSegment],
        activeSegment: KhyloSegment?,
        nextEpisode: KhyloMediaItem?,
        showNextUpCard: Bool,
        isPiPAvailable: Bool,
        onDismiss: @escaping () -> Void,
        onPlayPause: @escaping () -> Void,
        onSeekDelta: @escaping (Double) -> Void,
        onSeekTo: @escaping (Double) -> Void,
        onSkipSegment: @escaping (KhyloSegment) -> Void,
        onDismissSegment: @escaping () -> Void,
        onPlayNextEpisode: @escaping () -> Void,
        onDismissNextUp: @escaping () -> Void,
        onTogglePiP: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onToggleAspectRatio: @escaping () -> Void
    ) {
        self.item = item
        self.isPlaying = isPlaying
        self.isBuffering = isBuffering
        self.currentTime = currentTime
        self.duration = duration
        self.bufferedTime = bufferedTime
        self.segments = segments
        self.activeSegment = activeSegment
        self.nextEpisode = nextEpisode
        self.showNextUpCard = showNextUpCard
        self.isPiPAvailable = isPiPAvailable
        self.onDismiss = onDismiss
        self.onPlayPause = onPlayPause
        self.onSeekDelta = onSeekDelta
        self.onSeekTo = onSeekTo
        self.onSkipSegment = onSkipSegment
        self.onDismissSegment = onDismissSegment
        self.onPlayNextEpisode = onPlayNextEpisode
        self.onDismissNextUp = onDismissNextUp
        self.onTogglePiP = onTogglePiP
        self.onOpenSettings = onOpenSettings
        self.onToggleAspectRatio = onToggleAspectRatio
    }

    public var body: some View {
        ZStack {
            // Gradient scrims
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.4), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                Spacer()

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.4), Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Main Controls Layout
            VStack(spacing: 0) {
                // Top Header Bar
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                Spacer()

                // Center Transport Controls
                centerTransport
                    .padding(.horizontal, 40)

                Spacer()

                // Floating Next Up / Skip segment buttons above bottom bar
                floatingActionLayer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                // Bottom Timeline & Actions
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Dismiss / Back Button
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onDismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.16))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.name ?? "Now Playing")
                    .font(KhyloTypography.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let sub = item?.displaySubtitle {
                    Text(sub)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Header Right Utilities
            HStack(spacing: 14) {
                // Stream Specs Badge
                Text("4K HDR")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(KhyloColors.accent.opacity(0.18))
                            .overlay(Capsule().strokeBorder(KhyloColors.accent.opacity(0.3), lineWidth: 1))
                    )

                // AirPlay
                #if canImport(AVKit) && os(iOS)
                AirPlayPickerButton()
                    .frame(width: 32, height: 32)
                #endif

                // Picture-in-Picture
                if isPiPAvailable {
                    Button(action: {
                        #if os(iOS)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        onTogglePiP()
                    }) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Settings
                Button(action: {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    onOpenSettings()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Center Transport

    private var centerTransport: some View {
        HStack(spacing: 44) {
            // Seek -10s
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onSeekDelta(-10)
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(PlainButtonStyle())

            // Play / Pause or Buffering Spinner
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onPlayPause()
            }) {
                ZStack {
                    Circle()
                        .fill(KhyloColors.accent)
                        .frame(width: 72, height: 72)
                        .shadow(color: KhyloColors.accent.opacity(0.4), radius: 16)

                    if isBuffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Seek +10s
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onSeekDelta(10)
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Floating Action Layer (Skip Pill & Next Up)

    private var floatingActionLayer: some View {
        HStack {
            Spacer()

            if showNextUpCard, let next = nextEpisode {
                NextUpCard(
                    nextEpisode: next,
                    countdownSeconds: 10,
                    onPlayNext: onPlayNextEpisode,
                    onDismiss: onDismissNextUp
                )
            } else if let seg = activeSegment {
                SkipSegmentButton(
                    segment: seg,
                    onSkip: { onSkipSegment(seg) },
                    onDismiss: onDismissSegment
                )
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Interactive Timeline Scrubber
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let activeSec = isScrubbing ? scrubTime : currentTime
                let progress = duration > 0 ? min(max(activeSec / duration, 0.0), 1.0) : 0.0
                let bufferProgress = duration > 0 ? min(max(bufferedTime / duration, 0.0), 1.0) : 0.0

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: isScrubbing ? 8 : 5)

                    // Buffer bar
                    Capsule()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: trackWidth * bufferProgress, height: isScrubbing ? 8 : 5)

                    // Segment Markers (Intros / Credits)
                    ForEach(segments) { seg in
                        if duration > 0 {
                            let segStartRatio = min(max(seg.startSeconds / duration, 0.0), 1.0)
                            let segEndRatio = min(max(seg.endSeconds / duration, 0.0), 1.0)
                            let segWidth = max(trackWidth * (segEndRatio - segStartRatio), 4.0)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(seg.type == .credits ? Color.purple.opacity(0.8) : KhyloColors.accent.opacity(0.8))
                                .frame(width: segWidth, height: isScrubbing ? 8 : 5)
                                .offset(x: trackWidth * segStartRatio)
                        }
                    }

                    // Played track
                    Capsule()
                        .fill(KhyloColors.accent)
                        .frame(width: trackWidth * progress, height: isScrubbing ? 8 : 5)

                    // Scrubber thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 20 : 14, height: isScrubbing ? 20 : 14)
                        .shadow(color: Color.black.opacity(0.4), radius: 4)
                        .offset(x: max((trackWidth * progress) - (isScrubbing ? 10 : 7), 0))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isScrubbing {
                                isScrubbing = true
                            }
                            let locationX = min(max(gesture.location.x, 0.0), trackWidth)
                            let ratio = locationX / trackWidth
                            scrubTime = ratio * duration
                        }
                        .onEnded { _ in
                            onSeekTo(scrubTime)
                            isScrubbing = false
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                )
            }
            .frame(height: 24)

            // Timestamps and Auxiliary Controls
            HStack {
                let displayTime = isScrubbing ? scrubTime : currentTime
                Text(formatTime(displayTime))
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(.white)

                Text("/")
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textTertiary)

                Text(formatTime(duration))
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)

                Spacer()

                // Aspect Ratio Toggle
                Button(action: {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    onToggleAspectRatio()
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}
