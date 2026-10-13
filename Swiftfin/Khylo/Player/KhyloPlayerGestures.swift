//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif

// MARK: - Player Gestures Overlay

public struct KhyloPlayerGestures: View {
    public let currentTime: Double
    public let duration: Double
    public let onToggleControls: () -> Void
    public let onSeekDelta: (Double) -> Void
    public let onSeekTo: (Double) -> Void
    public let onToggleAspectRatio: () -> Void

    // HUD States
    @State private var showSeekRipple: Bool = false
    @State private var seekRippleDirection: Int = 0 // -1: backward, 1: forward
    @State private var seekRippleLocation: CGPoint = .zero

    @State private var showBrightnessHUD: Bool = false
    @State private var currentBrightness: CGFloat = 0.5

    @State private var showVolumeHUD: Bool = false
    @State private var currentVolume: CGFloat = 0.7

    @State private var isScrubbingHorizontal: Bool = false
    @State private var scrubDeltaSeconds: Double = 0.0
    @State private var scrubStartPosition: Double = 0.0

    // Double-tap tracker
    @State private var lastTapTime: Date = .distantPast
    @State private var lastTapLocation: CGPoint = .zero
    @State private var singleTapWorkItem: DispatchWorkItem?

    // Fade timers
    @State private var hudFadeTask: Task<Void, Never>?

    public init(
        currentTime: Double,
        duration: Double,
        onToggleControls: @escaping () -> Void,
        onSeekDelta: @escaping (Double) -> Void,
        onSeekTo: @escaping (Double) -> Void,
        onToggleAspectRatio: @escaping () -> Void
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.onToggleControls = onToggleControls
        self.onSeekDelta = onSeekDelta
        self.onSeekTo = onSeekTo
        self.onToggleAspectRatio = onToggleAspectRatio
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent touch capture area
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { value in
                                handleDragChange(value: value, in: geometry.size)
                            }
                            .onEnded { value in
                                handleDragEnd(value: value, in: geometry.size)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { tap in
                                handleTap(at: tap.location, in: geometry.size)
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onEnded { scale in
                                if scale > 1.2 || scale < 0.8 {
                                    #if os(iOS)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    #endif
                                    onToggleAspectRatio()
                                }
                            }
                    )

                // Seek Ripple Indicators
                if showSeekRipple {
                    seekRippleOverlay(in: geometry.size)
                }

                // Brightness HUD (Left Side)
                if showBrightnessHUD {
                    verticalHUD(
                        iconName: currentBrightness < 0.3 ? "sun.min.fill" : (currentBrightness < 0.7 ? "sun.max.fill" : "sun.max.fill"),
                        title: "Brightness",
                        value: currentBrightness,
                        alignment: .leading
                    )
                    .padding(.leading, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Volume HUD (Right Side)
                if showVolumeHUD {
                    verticalHUD(
                        iconName: currentVolume == 0 ? "speaker.slash.fill" : (currentVolume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
                        title: "Volume",
                        value: currentVolume,
                        alignment: .trailing
                    )
                    .padding(.trailing, 32)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Horizontal Scrub Delta Overlay
                if isScrubbingHorizontal {
                    horizontalScrubOverlay
                }
            }
        }
        .onAppear {
            #if os(iOS)
            currentBrightness = UIScreen.main.brightness
            #endif
        }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let now = Date()
        let interval = now.timeIntervalSince(lastTapLocation != .zero ? lastTapTime : .distantPast)
        let distance = hypot(location.x - lastTapLocation.x, location.y - lastTapLocation.y)

        if interval < 0.32 && distance < 80 {
            // Cancel pending single tap
            singleTapWorkItem?.cancel()
            singleTapWorkItem = nil
            lastTapTime = .distantPast

            // Double Tap seek
            let isLeft = location.x < (size.width * 0.45)
            let isRight = location.x > (size.width * 0.55)

            if isLeft {
                triggerSeekRipple(direction: -1, at: location)
                onSeekDelta(-10.0)
            } else if isRight {
                triggerSeekRipple(direction: 1, at: location)
                onSeekDelta(10.0)
            } else {
                // Center double tap toggles controls
                onToggleControls()
            }
        } else {
            // Potential single tap: schedule after double-tap window
            lastTapTime = now
            lastTapLocation = location

            singleTapWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                onToggleControls()
            }
            singleTapWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: workItem)
        }
    }

    private func triggerSeekRipple(direction: Int, at location: CGPoint) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        seekRippleDirection = direction
        seekRippleLocation = location
        withAnimation(.easeOut(duration: 0.2)) {
            showSeekRipple = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.2)) {
                showSeekRipple = false
            }
        }
    }

    // MARK: - Drag Handling

    private func handleDragChange(value: DragGesture.Value, in size: CGSize) {
        let translation = value.translation
        let isHorizontal = abs(translation.width) > abs(translation.height) * 1.5

        if isHorizontal {
            // Horizontal Scrubbing
            if !isScrubbingHorizontal {
                isScrubbingHorizontal = true
                scrubStartPosition = currentTime
            }

            // Scrub sensitivity: 1 pt corresponds to 0.3s
            let deltaSeconds = Double(translation.width) * 0.35
            scrubDeltaSeconds = deltaSeconds
        } else {
            // Vertical Gestures: Left half = Brightness, Right half = Volume
            let startX = value.startLocation.x
            let isLeftSide = startX < (size.width * 0.5)

            // Sensitivity: full screen height = 1.0 change
            let delta = -translation.height / (size.height * 0.7)

            if isLeftSide {
                // Brightness
                #if os(iOS)
                let newBrightness = min(max(currentBrightness + (delta * 0.03), 0.0), 1.0)
                currentBrightness = newBrightness
                UIScreen.main.brightness = newBrightness
                #endif
                showBrightnessHUD = true
                scheduleHUDDismiss()
            } else {
                // Volume
                let newVolume = min(max(currentVolume + (delta * 0.03), 0.0), 1.0)
                currentVolume = newVolume
                #if os(iOS)
                setSystemVolume(Float(newVolume))
                #endif
                showVolumeHUD = true
                scheduleHUDDismiss()
            }
        }
    }

    private func handleDragEnd(value: DragGesture.Value, in size: CGSize) {
        if isScrubbingHorizontal {
            let target = min(max(scrubStartPosition + scrubDeltaSeconds, 0.0), duration)
            onSeekTo(target)
            isScrubbingHorizontal = false
            scrubDeltaSeconds = 0.0
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
        scheduleHUDDismiss()
    }

    private func scheduleHUDDismiss() {
        hudFadeTask?.cancel()
        hudFadeTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    showBrightnessHUD = false
                    showVolumeHUD = false
                }
            }
        }
    }

    #if os(iOS)
    private func setSystemVolume(_ volume: Float) {
        let volumeView = MPVolumeView(frame: .zero)
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                slider.value = volume
            }
        }
    }
    #endif

    // MARK: - Overlays

    @ViewBuilder
    private func seekRippleOverlay(in size: CGSize) -> some View {
        let isLeft = seekRippleDirection < 0
        HStack {
            if isLeft {
                seekPill(icon: "gobackward.10", text: "10s")
                    .padding(.leading, 60)
                Spacer()
            } else {
                Spacer()
                seekPill(icon: "goforward.10", text: "10s")
                    .padding(.trailing, 60)
            }
        }
    }

    private func seekPill(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(.white)

            Text(text)
                .font(KhyloTypography.captionBold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            Circle()
                .fill(Color.black.opacity(0.65))
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .scaleEffect(showSeekRipple ? 1.05 : 0.8)
        .opacity(showSeekRipple ? 1.0 : 0.0)
    }

    private func verticalHUD(iconName: String, title: String, value: CGFloat, alignment: Alignment) -> some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 8, height: 120)

                Capsule()
                    .fill(KhyloColors.accent)
                    .frame(width: 8, height: 120 * value)
            }

            Text("\(Int(value * 100))%")
                .font(KhyloTypography.captionBold)
                .foregroundColor(.white)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.65))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 10)
        )
    }

    private var horizontalScrubOverlay: some View {
        let target = min(max(scrubStartPosition + scrubDeltaSeconds, 0.0), duration)
        let isForward = scrubDeltaSeconds >= 0
        let sign = isForward ? "+" : "-"
        let absDelta = abs(scrubDeltaSeconds)
        let deltaMinutes = Int(absDelta) / 60
        let deltaSecs = Int(absDelta) % 60

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isForward ? "forward.fill" : "backward.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(KhyloColors.accent)

                Text("\(sign)\(deltaMinutes):\(String(format: "%02d", deltaSecs))")
                    .font(KhyloTypography.title2)
                    .foregroundColor(.white)
            }

            Text(formatTime(target))
                .font(KhyloTypography.captionMedium)
                .foregroundColor(KhyloColors.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: KhyloRadius.md)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: KhyloRadius.md)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 12)
        )
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
