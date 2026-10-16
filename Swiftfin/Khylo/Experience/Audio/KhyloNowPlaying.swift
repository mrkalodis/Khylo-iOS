//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import AVKit
import JellyfinAPI
import SwiftUI

private extension KhyloAudioPlayer {

    var displayTitle: String {
        guard let item = current else { return "" }
        return kind == .audiobook ? (collectionTitle ?? item.name ?? "") : (item.name ?? "")
    }

    var displaySubtitle: String {
        guard let item = current else { return "" }
        switch kind {
        case .audiobook: return item.name ?? ""
        case .music: return item.khyloArtistLine
        }
    }

    /// "Playing from" line: the album for music, the book for audiobooks.
    var sourceTitle: String {
        guard let item = current else { return "" }
        switch kind {
        case .audiobook: return collectionTitle ?? item.album ?? ""
        case .music: return collectionTitle ?? item.album ?? ""
        }
    }

    var sourceLabel: String {
        switch kind {
        case .audiobook: "LISTENING TO"
        case .music: collectionTitle == nil ? "PLAYING FROM ALBUM" : "PLAYING FROM MIX"
        }
    }
}

// MARK: - Mini player

/// Frosted bar above the tab bar while something is playing, tinted by the artwork.
struct KhyloMiniPlayer: View {

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @State private var isShowingNowPlaying = false
    @State private var tint: Color?

    var body: some View {
        if player.isActive {
            let artwork = player.displayArtworkURL(width: 120)
            Button {
                isShowingNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    KhyloImage(url: artwork, placeholderSymbol: player.kind == .audiobook ? "headphones" : "music.note")
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(player.displaySubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 21))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.kind == .audiobook ? player.skip(by: 30) : player.next()
                    } label: {
                        Image(systemName: player.kind == .audiobook ? "goforward.30" : "forward.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill((tint ?? Color.white.opacity(0.1)).opacity(0.55))
                )
                .overlay(alignment: .bottom) {
                    KhyloMiniProgress(clock: player.clock)
                        .padding(.horizontal, 16)
                }
                .backport
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: artwork) {
                let color = await KhyloArtColor.color(for: player.displayArtworkURL(width: 120))
                withAnimation(.easeInOut(duration: 0.4)) { tint = color }
            }
            .fullScreenCover(isPresented: $isShowingNowPlaying) {
                KhyloNowPlayingScreen()
            }
        }
    }
}

// MARK: - Now playing

struct KhyloNowPlayingScreen: View {

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingQueue = false
    @State private var tint: Color?
    @State private var isFavorite = false
    @State private var dragOffset: CGFloat = 0

    private let speeds: [Float] = [0.75, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0]

    private var artwork: URL? { player.displayArtworkURL(width: 900) }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer(minLength: 20)

                KhyloImage(url: artwork, placeholderSymbol: player.kind == .audiobook ? "headphones" : "music.note")
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
                    .scaleEffect(player.isPlaying ? 1 : 0.86)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
                    .padding(.horizontal, 28)
                    .id(player.current?.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

                Spacer(minLength: 28)

                titleRow
                    .padding(.horizontal, 28)

                KhyloClockScrubber(clock: player.clock) { player.seek(to: $0) }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                if let quality = player.quality {
                    KhyloQualityLabel(quality: quality)
                        .padding(.top, 2)
                        .transition(.opacity)
                }

                transport
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                bottomRow
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
            }
            .offset(y: dragOffset)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: player.current?.id)
        .gesture(
            DragGesture()
                .onChanged { value in dragOffset = max(0, value.translation.height) }
                .onEnded { value in
                    if value.translation.height > 140 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                    }
                }
        )
        .sheet(isPresented: $isShowingQueue) { queueSheet }
        .onChange(of: player.isActive) { _, isActive in
            if !isActive { dismiss() }
        }
        .task(id: player.current?.id) {
            isFavorite = player.current?.khyloIsFavorite ?? false
            let color = await KhyloArtColor.color(for: player.displayArtworkURL(width: 120))
            withAnimation(.easeInOut(duration: 0.6)) { tint = color }
        }
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            KhyloStyle.canvas
            LinearGradient(
                colors: [tint ?? Color(white: 0.18), (tint ?? Color(white: 0.12)).opacity(0.6), KhyloStyle.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            KhyloImage(url: artwork, showsPlaceholder: false)
                .scaleEffect(1.8)
                .blur(radius: 90)
                .opacity(0.35)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")

            Spacer()

            VStack(spacing: 1) {
                Text(player.sourceLabel)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.65))
                Text(player.sourceTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                isShowingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.kind == .audiobook ? "Parts" : "Up Next")
        }
        .padding(.horizontal, 14)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.displayTitle)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(player.displaySubtitle)
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if player.kind == .music {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 24))
                        .foregroundColor(isFavorite ? KhyloStyle.accent : .white.opacity(0.85))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            if player.kind == .music {
                modeButton(
                    symbol: "shuffle",
                    isOn: player.isShuffled,
                    label: player.isShuffled ? "Shuffle on" : "Shuffle off"
                ) { player.toggleShuffle() }
                Spacer()
                transportButton("backward.end.fill", size: 30) { player.previous() }
            } else {
                transportButton("gobackward.15", size: 30) { player.skip(by: -15) }
            }

            Spacer()

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(Color.white)
                    if player.isBuffering && player.isPlaying {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.black)
                            .offset(x: player.isPlaying ? 0 : 2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 74, height: 74)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Spacer()

            if player.kind == .music {
                transportButton("forward.end.fill", size: 30) { player.next() }
                Spacer()
                modeButton(
                    symbol: player.repeatMode == .one ? "repeat.1" : "repeat",
                    isOn: player.repeatMode != .off,
                    label: "Repeat"
                ) { player.repeatMode = player.repeatMode.next }
            } else {
                transportButton("goforward.30", size: 30) { player.skip(by: 30) }
            }
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private func modeButton(symbol: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(isOn ? KhyloStyle.accent : .white.opacity(0.75))
                Circle()
                    .fill(isOn ? KhyloStyle.accent : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 44, height: 50)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var bottomRow: some View {
        HStack {
            KhyloRoutePicker()
                .frame(width: 36, height: 36)

            Spacer()

            if player.kind == .audiobook {
                Menu {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            player.rate = speed
                        } label: {
                            if speed == player.rate {
                                Label(Self.formatSpeed(speed), systemImage: "checkmark")
                            } else {
                                Text(Self.formatSpeed(speed))
                            }
                        }
                    }
                } label: {
                    Text(Self.formatSpeed(player.rate))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 56, height: 34)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }

                Menu {
                    Button("Off") { player.setSleepTimer(minutes: nil) }
                    Button("End of Part") { player.setSleepTimer(minutes: 0) }
                    ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) Minutes") { player.setSleepTimer(minutes: minutes) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz")
                        if let end = player.sleepTimerEnd {
                            Text(end, style: .timer).monospacedDigit()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(player.sleepTimerEnd == nil ? .white.opacity(0.85) : KhyloStyle.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }

            Spacer()

            Button {
                isShowingQueue = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(player.kind == .audiobook ? "Parts" : "Up Next")
        }
    }

    // MARK: Queue

    private var queueSheet: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section("Now Playing") {
                        queueRow(current, isCurrent: true)
                    }
                }
                let upcoming = Array(player.queue.enumerated()).filter { $0.offset > player.index }
                if !upcoming.isEmpty {
                    Section(player.kind == .audiobook ? "Next Parts" : "Next Up") {
                        ForEach(upcoming, id: \.offset) { offset, item in
                            Button {
                                player.jump(to: offset)
                            } label: {
                                queueRow(item, isCurrent: false)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KhyloStyle.canvas)
            .navigationTitle(player.kind == .audiobook ? "Parts" : "Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isShowingQueue = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func queueRow(_ item: BaseItemDto, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            KhyloImage(url: KhyloArtwork.url(for: item, style: .square, width: 90), placeholderSymbol: "music.note")
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "")
                    .foregroundStyle(isCurrent ? KhyloStyle.accent : .primary)
                    .lineLimit(1)
                Text(player.kind == .audiobook ? (item.khyloRuntime ?? "") : item.khyloArtistLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    .foregroundColor(KhyloStyle.accent)
            }
        }
    }

    // MARK: Actions

    private func toggleFavorite() {
        guard let id = player.current?.id else { return }
        let target = !isFavorite
        isFavorite = target
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { _ = try? await KhyloAPI.setFavorite(target, itemID: id) }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func formatSpeed(_ speed: Float) -> String {
        let text = speed == speed.rounded() ? String(format: "%.0f", speed) : String(format: "%g", speed)
        return text + "×"
    }
}

// MARK: - Progress

/// The mini player's thin progress line; the only part of it that redraws as time passes.
private struct KhyloMiniProgress: View {
    @ObservedObject var clock: KhyloPlaybackClock

    var body: some View {
        if clock.duration > 0 {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.white)
                    .frame(width: proxy.size.width * min(1, clock.currentTime / clock.duration), height: 2)
            }
            .frame(height: 2)
        }
    }
}

/// Scrubber bound to the playback clock, holding its own drag state.
private struct KhyloClockScrubber: View {
    @ObservedObject var clock: KhyloPlaybackClock
    let onSeek: (Double) -> Void

    @State private var scrubValue: Double?

    var body: some View {
        KhyloScrubber(
            value: scrubValue ?? clock.currentTime,
            duration: clock.duration,
            onChanged: { scrubValue = $0 },
            onEnded: { value in
                onSeek(value)
                scrubValue = nil
            }
        )
    }
}

/// "HI-RES  FLAC · 24-bit / 96 kHz" under the scrubber.
struct KhyloQualityLabel: View {
    let quality: KhyloAudioQuality

    var body: some View {
        HStack(spacing: 7) {
            if let badge = quality.badge {
                Text(badge.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(quality.isHiRes ? KhyloStyle.accent : Color.white.opacity(0.85)))
            }
            Text(quality.detail)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .tracking(0.4)
                .foregroundColor(.white.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio quality \(quality.detail)")
    }
}

// MARK: - Scrubber

/// Slim progress bar that thickens and shows a knob while you drag it.
private struct KhyloScrubber: View {
    let value: Double
    let duration: Double
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = duration > 0 ? min(1, max(0, value / duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white).frame(width: width * fraction)
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                        .offset(x: width * fraction - (isDragging ? 8 : 5))
                }
                .frame(height: isDragging ? 8 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            onChanged(min(1, max(0, gesture.location.x / width)) * duration)
                        }
                        .onEnded { gesture in
                            isDragging = false
                            onEnded(min(1, max(0, gesture.location.x / width)) * duration)
                        }
                )
            }
            .frame(height: 20)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)

            HStack {
                Text(KhyloNowPlayingScreen.format(value))
                Spacer()
                Text("-" + KhyloNowPlayingScreen.format(max(0, duration - value)))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundColor(.white.opacity(isDragging ? 0.95 : 0.6))
        }
    }
}

// MARK: - AirPlay

/// The system AirPlay / output picker.
private struct KhyloRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.85)
        view.activeTintColor = UIColor(KhyloStyle.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
