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
    @State private var tint: Color?

    var body: some View {
        if player.isActive {
            let artwork = player.displayArtworkURL(width: 120)
            Button {
                player.isNowPlayingRequested = true
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
        }
    }
}

/// Presents Now Playing over whatever is on screen when it's asked for.
struct KhyloNowPlayingPresenter: ViewModifier {

    @ObservedObject private var player = KhyloAudioPlayer.shared

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $player.isNowPlayingRequested) {
            KhyloNowPlayingScreen()
        }
    }
}

// MARK: - Now playing

struct KhyloNowPlayingScreen: View {

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingQueue = false
    @State private var isShowingSettings = false
    @State private var isLandscape = false
    @State private var isSavingQueue = false
    @AppStorage(KhyloPlayerTheme.storageKey) private var theme: KhyloPlayerTheme = .khylo
    @AppStorage(KhyloPlayerTheme.vinylDarkKey) private var vinylDark = false
    @State private var tint: Color?
    @State private var isFavorite = false
    @State private var dragOffset: CGFloat = 0

    private let speeds: [Float] = [0.75, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0]

    private var artwork: URL? { player.displayArtworkURL(width: 900) }

    /// Audiobooks always use the standard player.
    private var activeTheme: KhyloPlayerTheme {
        player.kind == .audiobook ? .khylo : theme
    }

    private var actions: KhyloPlayerActions {
        KhyloPlayerActions(
            close: { dismiss() },
            showQueue: { isShowingQueue = true },
            showSettings: { isShowingSettings = true },
            toggleFavorite: toggleFavorite,
            isFavorite: isFavorite,
            openArtist: { artistID in
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    KhyloPageRelay.shared.openArtist(id: artistID)
                }
            }
        )
    }

    var body: some View {
        Group {
            switch activeTheme {
            case .vinyl:
                KhyloVinylPlayer(actions: actions, tint: tint)
            case .hifi:
                KhyloHiFiPlayer(actions: actions)
            case .khylo, .aurora, .mono, .glass, .poster:
                standardPlayer
            }
        }
        .onAppear { KhyloOrientationState.shared.setNowPlayingOpen(true) }
        .onDisappear { KhyloOrientationState.shared.setNowPlayingOpen(false) }
        .environment(\.khyloLandscape, isLandscape)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscape = $0 }
        .offset(y: dragOffset)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(activeTheme == .vinyl && !vinylDark ? .light : .dark)
        .animation(.easeInOut(duration: 0.35), value: activeTheme)
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
        .sheet(isPresented: $isShowingSettings) {
            KhyloPlayerSettingsSheet(isAudiobook: player.kind == .audiobook) { dismiss() }
        }
        .onChange(of: player.isActive) { _, isActive in
            if !isActive { dismiss() }
        }
        .task(id: player.current?.id) {
            isFavorite = player.current?.khyloIsFavorite ?? false
            let color = await KhyloArtColor.color(for: player.displayArtworkURL(width: 120))
            withAnimation(.easeInOut(duration: 0.6)) { tint = color }
        }
    }

    // MARK: Standard player

    /// The standard layout, restyled by the Khylo, Aurora and Mono themes.
    private var standardPlayer: some View {
        ZStack {
            switch activeTheme {
            case .aurora: KhyloAuroraBackground(tint: tint, isPlaying: player.isPlaying)
            case .mono: Color.black.ignoresSafeArea()
            case .glass: glassBackground
            case .poster: isLandscape ? AnyView(background) : AnyView(posterBackground)
            default: background
            }

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                if isLandscape {
                    // Sideways: the cover on the left at full height, the song and controls on the right.
                    HStack(spacing: 20) {
                        standardCover
                            .padding(.leading, 28)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            standardControls
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, 12)
                    }
                } else {
                    // Equal space above and below: the cover sits centred between
                    // the top bar and the song details.
                    Spacer(minLength: 12)

                    if activeTheme == .poster {
                        // The cover is the background; leave the room it takes up.
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .padding(.horizontal, 12)
                    } else {
                        standardCover
                            .padding(.horizontal, 12)
                    }

                    Spacer(minLength: 12)

                    standardControls
                }
            }
        }
    }

    private var standardCover: some View {
        KhyloImage(url: artwork, placeholderSymbol: player.kind == .audiobook ? "headphones" : "music.note")
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: activeTheme == .mono ? 2 : (activeTheme == .glass ? 24 : 12), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(activeTheme == .glass ? 0.22 : 0), lineWidth: 1)
            )
            .shadow(color: activeTheme == .mono ? .clear : (activeTheme == .aurora ? (tint ?? .black) : .black).opacity(0.5), radius: 30, y: 18)
            .scaleEffect(player.isPlaying ? 1 : 0.88)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
            .id(player.current?.id)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var standardControls: some View {
        VStack(spacing: 0) {
            titleRow
                .padding(.horizontal, 28)

            KhyloClockScrubber(clock: player.clock) { player.seek(to: $0) }
                .padding(.horizontal, 28)
                .padding(.top, 22)

            if let quality = player.quality {
                KhyloQualityLabel(quality: quality)
                    .padding(.top, 4)
                    .transition(.opacity)
            }

            transport
                .padding(.horizontal, 22)
                .padding(.top, 18)

            bottomRow
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 12)
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

    /// Glass: the cover blurred into a calm, frosted field.
    private var glassBackground: some View {
        ZStack {
            Color.black
            KhyloImage(url: artwork, showsPlaceholder: false)
                .scaleEffect(2.2)
                .blur(radius: 70)
                .saturation(1.15)
                .opacity(0.8)
            Rectangle().fill(.ultraThinMaterial).opacity(0.55)
            LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    /// Poster: the cover across the top of the screen, fading into black below.
    private var posterBackground: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black
                KhyloImage(url: artwork, placeholderSymbol: "music.note")
                    .frame(width: proxy.size.width, height: proxy.size.width * 1.25)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0.35), location: 0),
                                .init(color: .clear, location: 0.22),
                                .init(color: .clear, location: 0.5),
                                .init(color: Color.black, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
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
            .frame(width: 88, alignment: .leading)

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

            HStack(spacing: 0) {
                KhyloHandoffButton(color: .white)
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Player settings")
            }
            .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeTheme == .mono ? player.displayTitle.uppercased() : player.displayTitle)
                    .font(activeTheme == .poster
                        ? .system(size: 28, weight: .bold, design: .serif)
                        : .system(size: activeTheme == .mono ? 22 : 24, weight: activeTheme == .mono ? .black : .bold))
                    .tracking(activeTheme == .mono ? 0.6 : 0)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if player.kind == .music, let track = player.current, !track.khyloArtistLinks.isEmpty {
                    // Tap an artist to go to their page, like Spotify.
                    KhyloArtistLinks(artists: track.khyloArtistLinks, fallback: player.displaySubtitle) { artistID in
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            KhyloPageRelay.shared.openArtist(id: artistID)
                        }
                    }
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.7))
                } else {
                    Text(player.displaySubtitle)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundColor(isOn ? (activeTheme == .mono ? .white : KhyloStyle.accent) : .white.opacity(0.75))
                Circle()
                    .fill(isOn ? (activeTheme == .mono ? .white : KhyloStyle.accent) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 44, height: 50)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// One gap between each control, every icon in the same size slot, so the
    /// row is evenly spaced.
    private var bottomRow: some View {
        HStack(spacing: 0) {
            KhyloRoutePicker()
                .frame(width: 44, height: 44)

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

            if player.kind == .music, let current = player.current {
                KhyloDownloadButton(item: current, style: .icon)
                    .frame(width: 44, height: 44)
                Spacer()
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 21))
                        .foregroundColor(isFavorite ? (activeTheme == .mono ? .white : KhyloStyle.accent) : .white.opacity(0.85))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                Spacer()
                KhyloSleepTimerButton(color: .white.opacity(0.85), activeColor: activeTheme == .mono ? .white : KhyloStyle.accent)
            }

            Spacer()

            Button {
                isShowingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
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
                        ForEach(upcoming, id: \.element.id) { entry in
                            Button {
                                player.jump(to: entry.offset)
                            } label: {
                                queueRow(entry.element, isCurrent: false)
                            }
                        }
                        .onMove { player.moveUpcoming(from: $0, to: $1) }
                        .onDelete { player.removeUpcoming(at: $0) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KhyloStyle.canvas)
            .navigationTitle(player.kind == .audiobook ? "Parts" : "Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if player.kind == .music, player.queue.count > player.index + 2 {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if player.kind == .music, !player.queue.isEmpty {
                        Button {
                            isSavingQueue = true
                        } label: {
                            Label("Save Queue as Playlist", systemImage: "music.note.list")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isShowingQueue = false }
                }
            }
        }
        .sheet(isPresented: $isSavingQueue) { KhyloAddToPlaylistSheet(songs: player.queue) }
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
struct KhyloClockScrubber: View {
    @ObservedObject var clock: KhyloPlaybackClock
    var fill: Color = .white
    var track: Color = .white.opacity(0.25)
    var text: Color = .white.opacity(0.6)
    let onSeek: (Double) -> Void

    @State private var scrubValue: Double?

    var body: some View {
        KhyloScrubber(
            value: scrubValue ?? clock.currentTime,
            duration: clock.duration,
            fill: fill,
            track: track,
            text: text,
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
    let fill: Color
    let track: Color
    let text: Color
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = duration > 0 ? min(1, max(0, value / duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(fill).frame(width: width * fraction)
                    Circle()
                        .fill(fill)
                        .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                        .offset(x: width * fraction - (isDragging ? 8 : 5))
                }
                .frame(height: isDragging ? 8 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                // Ahead of the swipe-down-to-close gesture on the whole screen.
                .highPriorityGesture(
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
            .foregroundColor(isDragging ? fill : text)
        }
    }
}

// MARK: - AirPlay

/// The system AirPlay / output picker.
struct KhyloRoutePicker: UIViewRepresentable {
    var tint: UIColor = UIColor.white.withAlphaComponent(0.85)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = UIColor(KhyloStyle.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}


// MARK: - Turning the phone

/// Phones stay upright everywhere except video and the Now Playing screen, which
/// turns sideways when the phone does.
@MainActor
final class KhyloOrientationState: ObservableObject {

    static let shared = KhyloOrientationState()

    @Published private(set) var allowsLandscape = false

    func setNowPlayingOpen(_ isOpen: Bool) {
        guard allowsLandscape != isOpen else { return }
        allowsLandscape = isOpen
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        // Let the new list of orientations take hold, then apply it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scene?.windows.first { $0.isKeyWindow }?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if !isOpen, !UIDevice.isPad {
                scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

struct KhyloOrientationGate<Content: View>: View {

    @ObservedObject private var state = KhyloOrientationState.shared
    @ViewBuilder let content: Content

    var body: some View {
        content
            .supportedOrientations(UIDevice.isPad ? .allButUpsideDown : (state.allowsLandscape ? .allButUpsideDown : .portrait))
    }
}
