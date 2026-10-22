//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Themes

/// How the music player looks. Three restyle the standard player; Vinyl,
/// Retro and Cyberpunk each have a layout of their own.
enum KhyloPlayerTheme: String, CaseIterable, Identifiable {
    case khylo
    case aurora
    case mono
    case vinyl
    case retro
    case cyberpunk

    static let storageKey = "khylo.player.theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .khylo: "Khylo"
        case .aurora: "Aurora"
        case .mono: "Mono"
        case .vinyl: "Vinyl"
        case .retro: "Retro"
        case .cyberpunk: "Cyberpunk"
        }
    }

    var detail: String {
        switch self {
        case .khylo: "Your album's colours"
        case .aurora: "Slow light from the cover"
        case .mono: "Black, white, nothing else"
        case .vinyl: "A record out of its sleeve"
        case .retro: "A 1960s radio"
        case .cyberpunk: "Neon, grids and glitches"
        }
    }

    /// A layout of its own, rather than a restyle of the standard player.
    var hasOwnLayout: Bool {
        self == .vinyl || self == .retro || self == .cyberpunk
    }
}

/// What every player layout can do, handed in by the Now Playing screen.
struct KhyloPlayerActions {
    let close: () -> Void
    let showQueue: () -> Void
    let showSettings: () -> Void
    let toggleFavorite: () -> Void
    let isFavorite: Bool
    let openArtist: (String) -> Void
}

// MARK: - Aurora background

/// Slow, soft light in the cover's colours, drifting behind the player.
struct KhyloAuroraBackground: View {

    let tint: Color?
    let isPlaying: Bool

    var body: some View {
        let base = tint ?? Color(hex: "#3A2D6B")
        let colors: [Color] = [
            base.khyloShifted(hue: -0.06, brightness: 0.9), base, base.khyloShifted(hue: 0.08, brightness: 1.1),
            base.khyloShifted(hue: 0.14, brightness: 0.7), KhyloStyle.accent.opacity(0.85), base.khyloShifted(hue: -0.12, brightness: 0.8),
            Color(hex: "#07070A"), base.khyloShifted(hue: 0.05, brightness: 0.35), Color(hex: "#07070A"),
        ]
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5 + 0.08 * sin(t * 0.21), 0], [1, 0],
                    [0, 0.45 + 0.08 * cos(t * 0.17)], [0.5 + 0.12 * sin(t * 0.13), 0.42 + 0.1 * cos(t * 0.19)], [1, 0.5 + 0.08 * sin(t * 0.23)],
                    [0, 1], [0.5 + 0.1 * cos(t * 0.15), 1], [1, 1],
                ],
                colors: colors
            )
        }
        .overlay(Color.black.opacity(0.18))
        .ignoresSafeArea()
    }
}

extension Color {
    /// The same colour with its hue turned and its brightness scaled.
    func khyloShifted(hue shift: Double, brightness scale: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = h + CGFloat(shift)
        hue -= floor(hue)
        return Color(hue: Double(hue), saturation: Double(s), brightness: min(1, Double(b) * scale), opacity: Double(a))
    }
}

// MARK: - Vinyl

/// The record in its sleeve: the cover is the sleeve, and when music plays the
/// record slides out beside it and turns, the cover art printed on its label.
/// Quiet, editorial type underneath.
struct KhyloVinylPlayer: View {

    let actions: KhyloPlayerActions
    let tint: Color?

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @State private var spinBase: Double = 0
    @State private var spinStart: Date?

    private let cream = Color(hex: "#F1E9DA")

    var body: some View {
        ZStack {
            Color(hex: "#151311").ignoresSafeArea()
            RadialGradient(colors: [(tint ?? Color(hex: "#5A4632")).opacity(0.35), .clear], center: .top, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                KhyloThemedTopBar(actions: actions, foreground: cream, labelFont: .system(size: 11, weight: .semibold, design: .serif))
                    .padding(.top, 8)

                Spacer(minLength: 8)

                sleeve
                    .padding(.horizontal, 24)

                Spacer(minLength: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Now Playing")
                        .font(.system(size: 13, weight: .regular, design: .serif).italic())
                        .foregroundColor(cream.opacity(0.5))
                    Text(player.current?.name ?? "")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundColor(cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 4) {
                        Text("By")
                            .font(.system(size: 15, design: .serif).italic())
                            .foregroundColor(cream.opacity(0.5))
                        KhyloThemedArtistLine(actions: actions, color: cream.opacity(0.85), font: .system(size: 15, weight: .semibold, design: .serif))
                    }
                    if let meta = albumLine {
                        Text(meta)
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(cream.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                KhyloClockScrubber(clock: player.clock, fill: cream, track: cream.opacity(0.16), text: cream.opacity(0.5)) { player.seek(to: $0) }
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                KhyloThemedTransport(fill: cream, glyph: Color(hex: "#151311"), secondary: cream)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                KhyloThemedBottomRow(actions: actions, color: cream.opacity(0.8))
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
            }
        }
        .onAppear { if player.isPlaying { spinStart = Date() } }
        .onChange(of: player.isPlaying) { _, playing in
            if playing {
                spinStart = Date()
            } else if let start = spinStart {
                spinBase += Date().timeIntervalSince(start) * 200
                spinStart = nil
            }
        }
    }

    private var albumLine: String? {
        let parts = [player.current?.album, player.current?.productionYear.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The sleeve, with the record sliding out to the right while it plays.
    private var sleeve: some View {
        GeometryReader { proxy in
            let cover = proxy.size.height
            let record = cover * 0.94
            let out = player.isPlaying ? cover * 0.4 : cover * 0.1
            ZStack(alignment: .leading) {
                TimelineView(.animation(paused: !player.isPlaying)) { context in
                    disc(size: record)
                        .rotationEffect(.degrees(angle(at: context.date)))
                }
                .overlay(
                    // The light on the record stays put while it turns.
                    Circle()
                        .fill(AngularGradient(
                            colors: [.clear, .white.opacity(0.08), .clear, .clear, .white.opacity(0.05), .clear, .clear],
                            center: .center
                        ))
                        .allowsHitTesting(false)
                )
                .frame(width: record, height: record)
                .offset(x: (cover - record) / 2 + out)
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: player.isPlaying)

                KhyloImage(url: player.displayArtworkURL(width: 900), placeholderSymbol: "music.note")
                    .frame(width: cover, height: cover)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        // The open edge of the sleeve.
                        LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .init(x: 0.9, y: 0.5), endPoint: .trailing)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    )
                    .shadow(color: .black.opacity(0.55), radius: 22, x: 8, y: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .aspectRatio(1 / 0.68, contentMode: .fit)
    }

    private func angle(at date: Date) -> Double {
        spinBase + (spinStart.map { date.timeIntervalSince($0) * 200 } ?? 0)
    }

    private func disc(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: "#0B0B0C"))
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outer = canvasSize.width / 2
                for radius in stride(from: outer * 0.4, to: outer * 0.97, by: 2.4) {
                    let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.stroke(ring, with: .color(.white.opacity(0.03)), lineWidth: 0.6)
                }
            }
            KhyloImage(url: player.displayArtworkURL(width: 300), placeholderSymbol: "music.note")
                .frame(width: size * 0.36, height: size * 0.36)
                .clipShape(Circle())
            Circle()
                .fill(Color(hex: "#151311"))
                .frame(width: size * 0.035, height: size * 0.035)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Retro

/// A 1960s radio in the spirit of Braun: an off-white face with round speaker
/// grilles either side of the cover, a tuning scale whose needle shows where
/// you are in the song, slide switches and a row of small piano keys.
struct KhyloRetroPlayer: View {

    let actions: KhyloPlayerActions

    @ObservedObject private var player = KhyloAudioPlayer.shared

    private let ink = Color(hex: "#3B3832")
    private let orange = Color(hex: "#E2552C")

    var body: some View {
        ZStack {
            Color(hex: "#DEDAD1").ignoresSafeArea()

            VStack(spacing: 0) {
                KhyloThemedTopBar(actions: actions, foreground: ink, labelFont: .system(size: 10, weight: .semibold))
                    .padding(.top, 8)

                face
                    .padding(.horizontal, 14)
                    .padding(.top, 6)

                KhyloThemedBottomRow(actions: actions, color: ink.opacity(0.8))
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.light)
    }

    /// The radio's front panel; it takes the whole height, spacing its parts evenly.
    private var face: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 14)

            GeometryReader { proxy in
                let width = proxy.size.width
                let cover = min(width * 0.52, proxy.size.height)
                HStack(spacing: 0) {
                    KhyloSpeakerGrille(color: ink)
                        .frame(maxWidth: .infinity)
                    KhyloImage(url: player.displayArtworkURL(width: 700), placeholderSymbol: "music.note")
                        .frame(width: cover, height: cover)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    KhyloSpeakerGrille(color: ink)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .aspectRatio(1 / 0.52, contentMode: .fit)
            .padding(.horizontal, 12)

            VStack(spacing: 3) {
                Text(player.current?.name ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ink)
                    .lineLimit(1)
                Text(player.current?.khyloArtistLine ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(ink.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Spacer(minLength: 14)

            KhyloTuningScale(clock: player.clock, ink: ink, needle: orange) { player.seek(to: $0) }
                .padding(.horizontal, 22)

            Spacer(minLength: 14)

            HStack(spacing: 10) {
                KhyloDeckSwitch(title: "SHUFFLE", isOn: player.isShuffled, ink: ink, light: orange) {
                    player.toggleShuffle()
                }
                KhyloDeckSwitch(
                    title: player.repeatMode == .one ? "REPEAT 1" : "REPEAT",
                    isOn: player.repeatMode != .off,
                    ink: ink,
                    light: orange
                ) {
                    player.repeatMode = player.repeatMode.next
                }
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 14)

            HStack(alignment: .top, spacing: 10) {
                KhyloPianoKey(symbol: "backward.end.fill", label: "BACK", isDown: false, color: ink) { player.previous() }
                KhyloPianoKey(symbol: "play.fill", label: "PLAY", isDown: player.isPlaying, color: ink) {
                    if !player.isPlaying { player.togglePlayPause() }
                }
                KhyloPianoKey(symbol: "pause.fill", label: "PAUSE", isDown: !player.isPlaying, color: ink) {
                    if player.isPlaying { player.togglePlayPause() }
                }
                KhyloPianoKey(symbol: "forward.end.fill", label: "NEXT", isDown: false, color: ink) { player.next() }
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 16)
        }
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#F6F3EC"), Color(hex: "#ECE7DC")], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
    }
}

/// A round speaker grille: dots set in rings.
private struct KhyloSpeakerGrille: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * 0.86
            let spacing = max(radius / 6.5, 4)
            let dot = spacing * 0.34
            var ring: CGFloat = 0
            while ring <= radius {
                let count = ring == 0 ? 1 : Int((2 * .pi * ring) / spacing)
                for i in 0 ..< count {
                    let angle = 2 * .pi * CGFloat(i) / CGFloat(count)
                    let point = CGPoint(x: center.x + cos(angle) * ring, y: center.y + sin(angle) * ring)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)), with: .color(color.opacity(0.55)))
                }
                ring += spacing
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A radio tuning scale: minute marks along a window, and an orange needle at
/// the point in the song. Drag along it to move through the song.
private struct KhyloTuningScale: View {
    @ObservedObject var clock: KhyloPlaybackClock
    let ink: Color
    let needle: Color
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        let value = dragValue ?? clock.currentTime
        let duration = max(clock.duration, 1)
        let fraction = min(1, max(0, value / duration))
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let inset: CGFloat = 14
                let usable = width - inset * 2
                let minutes = max(Int(ceil(duration / 60)), 1)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(hex: "#FBF8F1"))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ink.opacity(0.25), lineWidth: 1))
                    Canvas { context, size in
                        // Fine ticks every quarter minute, longer ones each minute.
                        let quarters = minutes * 4
                        for q in 0 ... quarters {
                            let x = inset + usable * CGFloat(Double(q) * 15 / duration)
                            guard x <= width - inset + 0.5 else { break }
                            let isMinute = q % 4 == 0
                            var tick = Path()
                            tick.move(to: CGPoint(x: x, y: size.height - 6))
                            tick.addLine(to: CGPoint(x: x, y: size.height - (isMinute ? 18 : 11)))
                            context.stroke(tick, with: .color(ink.opacity(isMinute ? 0.7 : 0.35)), lineWidth: 1)
                        }
                    }
                    ForEach(0 ... minutes, id: \.self) { minute in
                        let x = inset + usable * CGFloat(Double(minute) * 60 / duration)
                        if x <= width - inset + 0.5 {
                            Text("\(minute)")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundColor(ink.opacity(0.6))
                                .position(x: x, y: 11)
                        }
                    }
                    Rectangle()
                        .fill(needle)
                        .frame(width: 2)
                        .padding(.vertical, 4)
                        .offset(x: inset + usable * fraction - 1)
                        .animation(dragValue == nil ? .linear(duration: 0.5) : nil, value: fraction)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragValue = Double(min(1, max(0, ($0.location.x - inset) / usable))) * duration }
                        .onEnded { gesture in
                            onSeek(Double(min(1, max(0, (gesture.location.x - inset) / usable))) * duration)
                            dragValue = nil
                        }
                )
            }
            .frame(height: 46)

            HStack {
                Text(KhyloNowPlayingScreen.format(value))
                Spacer()
                Text("-" + KhyloNowPlayingScreen.format(max(0, clock.duration - value)))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundColor(ink.opacity(0.55))
        }
    }
}

/// A labelled slide switch with a light that glows when it's on.
private struct KhyloDeckSwitch: View {
    let title: String
    let isOn: Bool
    let ink: Color
    let light: Color
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isOn ? light : ink.opacity(0.2))
                    .frame(width: 9, height: 9)
                    .shadow(color: isOn ? light.opacity(0.9) : .clear, radius: 5)
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(ink.opacity(0.85))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#F4F1EA"), Color(hex: "#B9B2A4")], startPoint: .top, endPoint: .bottom))
                        .frame(width: 18, height: 16)
                        .padding(3)
                }
                .frame(width: 46, height: 22)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isOn)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ink.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A small white radio key that sinks when pressed (and stays down when
/// latched), with its name printed underneath. Its depth is a solid base under
/// the key, so the symbol never gets a shadow.
private struct KhyloPianoKey: View {
    let symbol: String
    let label: String
    let isDown: Bool
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    private let height: CGFloat = 58
    private let depth: CGFloat = 5

    var body: some View {
        let down = isDown || isPressed
        VStack(spacing: 7) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: "#B5AFA3"))
                    .frame(height: height)
                    .offset(y: depth)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(
                        colors: down ? [Color(hex: "#E6E1D6"), Color(hex: "#DAD4C7")] : [Color.white, Color(hex: "#EDE8DE")],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.14), lineWidth: 1))
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(color.opacity(0.85))
                    )
                    .frame(height: height)
                    .offset(y: down ? depth - 1 : 0)
            }
            .frame(height: height + depth, alignment: .top)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(color.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: down)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label.capitalized)
    }
}

// MARK: - Cyberpunk

/// A neon heads-up display: grid floor, scanlines, a glitching cover, a
/// visualizer and a segmented time bar.
struct KhyloCyberpunkPlayer: View {

    let actions: KhyloPlayerActions

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @ObservedObject private var network = KhyloNetwork.shared

    static let magenta = Color(hex: "#FF2BD6")
    static let cyan = Color(hex: "#00F0FF")
    static let yellow = Color(hex: "#F5FF3B")

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                KhyloThemedTopBar(
                    actions: actions,
                    foreground: Self.cyan,
                    labelFont: .system(size: 11, weight: .bold, design: .monospaced),
                    labelPrefix: "// "
                )
                .padding(.top, 8)

                Spacer(minLength: 6)

                art
                    .padding(.horizontal, 36)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text((player.current?.name ?? "").uppercased())
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: Self.magenta.opacity(0.9), radius: 8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    KhyloThemedArtistLine(actions: actions, color: Self.cyan, font: .system(size: 15, weight: .semibold, design: .monospaced))
                    HStack(spacing: 14) {
                        Text("SRC ▸ \(player.quality?.short.uppercased() ?? "STREAM")")
                        Text("SIG ▸ \(network.isOnline ? "ONLINE" : "OFFLINE")")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Self.yellow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                KhyloNeonVisualizer(isPlaying: player.isPlaying)
                    .frame(height: 34)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)

                KhyloSegmentedScrubber(clock: player.clock) { player.seek(to: $0) }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)

                transport
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                KhyloThemedBottomRow(actions: actions, color: Self.cyan)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(hex: "#06050A")
            RadialGradient(colors: [Self.magenta.opacity(0.28), .clear], center: .top, startRadius: 10, endRadius: 420)
            // Perspective grid floor.
            Canvas { context, size in
                let horizon = size.height * 0.62
                let vanish = CGPoint(x: size.width / 2, y: horizon)
                for i in -10 ... 10 {
                    var line = Path()
                    line.move(to: vanish)
                    line.addLine(to: CGPoint(x: size.width / 2 + CGFloat(i) * size.width * 0.18, y: size.height))
                    context.stroke(line, with: .color(Self.magenta.opacity(0.22)), lineWidth: 1)
                }
                var depth: CGFloat = 4
                while horizon + depth < size.height {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: horizon + depth))
                    line.addLine(to: CGPoint(x: size.width, y: horizon + depth))
                    context.stroke(line, with: .color(Self.cyan.opacity(0.14)), lineWidth: 1)
                    depth *= 1.35
                }
            }
            // Scanlines.
            Canvas { context, size in
                for y in stride(from: 0, to: size.height, by: 3) {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var art: some View {
        let shape = KhyloCutCornerShape(cut: 22)
        return TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 8)
            // Every few seconds the cover glitches for a moment.
            let glitch = player.isPlaying && (tick % 41 == 0 || tick % 41 == 1)
            let url = player.displayArtworkURL(width: 700)
            ZStack {
                KhyloImage(url: url, placeholderSymbol: "music.note")
                if glitch {
                    KhyloImage(url: url, showsPlaceholder: false)
                        .colorMultiply(.red)
                        .blendMode(.screen)
                        .offset(x: 6)
                        .opacity(0.7)
                    KhyloImage(url: url, showsPlaceholder: false)
                        .colorMultiply(Self.cyan)
                        .blendMode(.screen)
                        .offset(x: -6, y: 2)
                        .opacity(0.7)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(shape)
            .overlay(shape.stroke(Self.cyan, lineWidth: 2))
            .shadow(color: Self.cyan.opacity(0.7), radius: 12)
            .shadow(color: Self.magenta.opacity(0.4), radius: 28)
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            neonToggle(symbol: "shuffle", isOn: player.isShuffled) { player.toggleShuffle() }
            Spacer()
            neonButton(symbol: "backward.end.fill", size: 54) { player.previous() }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    KhyloCutCornerShape(cut: 14).fill(Self.magenta)
                    KhyloCutCornerShape(cut: 14).stroke(.white.opacity(0.8), lineWidth: 1.5)
                    if player.isBuffering && player.isPlaying {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(.black)
                    }
                }
                .frame(width: 76, height: 76)
                .shadow(color: Self.magenta.opacity(0.9), radius: 16)
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            neonButton(symbol: "forward.end.fill", size: 54) { player.next() }
            Spacer()
            neonToggle(symbol: player.repeatMode == .one ? "repeat.1" : "repeat", isOn: player.repeatMode != .off) {
                player.repeatMode = player.repeatMode.next
            }
        }
    }

    private func neonButton(symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Self.cyan)
                .frame(width: size, height: size)
                .overlay(KhyloCutCornerShape(cut: 10).stroke(Self.cyan.opacity(0.8), lineWidth: 1.5))
                .shadow(color: Self.cyan.opacity(0.6), radius: 8)
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private func neonToggle(symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isOn ? Self.yellow : .white.opacity(0.5))
                .shadow(color: isOn ? Self.yellow.opacity(0.8) : .clear, radius: 6)
                .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
    }
}

/// A rectangle with its corners clipped off at an angle.
struct KhyloCutCornerShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

/// Bars that bounce while music plays (a light show, not a measurement).
private struct KhyloNeonVisualizer: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let count = 32
                let gap: CGFloat = 3
                let width = (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0 ..< count, id: \.self) { i in
                        let wave = abs(sin(t * 2.6 + Double(i) * 0.55) * cos(t * 1.3 + Double(i) * 0.21))
                        let level = isPlaying ? 0.15 + 0.85 * wave : 0.08
                        Rectangle()
                            .fill(LinearGradient(colors: [KhyloCyberpunkPlayer.cyan, KhyloCyberpunkPlayer.magenta], startPoint: .bottom, endPoint: .top))
                            .frame(width: width, height: max(2, proxy.size.height * level))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .shadow(color: KhyloCyberpunkPlayer.magenta.opacity(0.5), radius: 6)
        .accessibilityHidden(true)
    }
}

/// Time as a row of lit segments; drag along it to move through the song.
private struct KhyloSegmentedScrubber: View {
    @ObservedObject var clock: KhyloPlaybackClock
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        let value = dragValue ?? clock.currentTime
        let fraction = clock.duration > 0 ? min(1, max(0, value / clock.duration)) : 0
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let count = 40
                let gap: CGFloat = 2.5
                let width = (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                HStack(spacing: gap) {
                    ForEach(0 ..< count, id: \.self) { i in
                        let lit = Double(i) < fraction * Double(count)
                        Rectangle()
                            .fill(lit ? KhyloCyberpunkPlayer.cyan : Color.white.opacity(0.1))
                            .frame(width: width)
                            .shadow(color: lit ? KhyloCyberpunkPlayer.cyan.opacity(0.7) : .clear, radius: 4)
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragValue = min(1, max(0, $0.location.x / proxy.size.width)) * clock.duration }
                        .onEnded { gesture in
                            onSeek(min(1, max(0, gesture.location.x / proxy.size.width)) * clock.duration)
                            dragValue = nil
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(KhyloNowPlayingScreen.format(value))
                Spacer()
                Text("-" + KhyloNowPlayingScreen.format(max(0, clock.duration - value)))
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(KhyloCyberpunkPlayer.cyan.opacity(0.8))
        }
    }
}

// MARK: - Shared pieces for the themed layouts

/// Close, where it's playing from, and settings, in the theme's colours.
struct KhyloThemedTopBar: View {
    let actions: KhyloPlayerActions
    let foreground: Color
    var labelFont: Font = .system(size: 10, weight: .bold)
    var labelPrefix = ""

    @ObservedObject private var player = KhyloAudioPlayer.shared

    var body: some View {
        HStack {
            Button(action: actions.close) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(foreground)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")

            Spacer()

            VStack(spacing: 1) {
                Text(labelPrefix + (player.collectionTitle == nil ? "PLAYING FROM ALBUM" : "PLAYING FROM MIX"))
                    .font(labelFont)
                    .tracking(1.1)
                    .foregroundColor(foreground.opacity(0.65))
                Text(player.collectionTitle ?? player.current?.album ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(foreground)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: actions.showSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(foreground)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Player settings")
        }
        .padding(.horizontal, 14)
    }
}

/// The artist names; tap one to go to their page.
struct KhyloThemedArtistLine: View {
    let actions: KhyloPlayerActions
    let color: Color
    let font: Font

    @ObservedObject private var player = KhyloAudioPlayer.shared

    var body: some View {
        if let track = player.current, !track.khyloArtistLinks.isEmpty {
            KhyloArtistLinks(artists: track.khyloArtistLinks, fallback: track.khyloArtistLine, open: actions.openArtist)
                .font(font)
                .foregroundColor(color)
        } else {
            Text(player.current?.khyloArtistLine ?? "")
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
        }
    }
}

/// Shuffle, back, play, forward and repeat in the theme's colours.
struct KhyloThemedTransport: View {
    let fill: Color
    let glyph: Color
    let secondary: Color

    @ObservedObject private var player = KhyloAudioPlayer.shared

    var body: some View {
        HStack(spacing: 0) {
            toggle("shuffle", isOn: player.isShuffled) { player.toggleShuffle() }
            Spacer()
            button("backward.end.fill") { player.previous() }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(fill)
                    if player.isBuffering && player.isPlaying {
                        ProgressView().tint(glyph)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(glyph)
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            button("forward.end.fill") { player.next() }
            Spacer()
            toggle(player.repeatMode == .one ? "repeat.1" : "repeat", isOn: player.repeatMode != .off) {
                player.repeatMode = player.repeatMode.next
            }
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(secondary)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private func toggle(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isOn ? secondary : secondary.opacity(0.45))
                Circle().fill(isOn ? secondary : .clear).frame(width: 4, height: 4)
            }
            .frame(width: 44, height: 50)
        }
        .buttonStyle(.plain)
    }
}

/// AirPlay, download, favorite and the queue.
struct KhyloThemedBottomRow: View {
    let actions: KhyloPlayerActions
    let color: Color

    @ObservedObject private var player = KhyloAudioPlayer.shared

    var body: some View {
        HStack {
            KhyloRoutePicker(tint: UIColor(color))
                .frame(width: 36, height: 36)
            Spacer()
            if let current = player.current {
                KhyloDownloadButton(item: current, style: .icon)
                    .foregroundColor(color)
            }
            Spacer()
            Button(action: actions.toggleFavorite) {
                Image(systemName: actions.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 21))
                    .foregroundColor(actions.isFavorite ? KhyloStyle.accent : color)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(actions.isFavorite ? "Remove from favorites" : "Add to favorites")
            Spacer()
            Button(action: actions.showQueue) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Up Next")
        }
    }
}

// MARK: - Theme previews

/// A small picture of a theme for the settings picker.
struct KhyloThemePreview: View {
    let theme: KhyloPlayerTheme

    var body: some View {
        ZStack {
            switch theme {
            case .khylo:
                LinearGradient(colors: [KhyloStyle.accent.opacity(0.8), Color(hex: "#101114")], startPoint: .top, endPoint: .bottom)
                miniStandard(art: .white.opacity(0.85), line: .white)
            case .aurora:
                MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                             colors: [Color(hex: "#5B3CC4"), Color(hex: "#21B5A8"), Color(hex: "#C23C8E"), Color(hex: "#0B0B12")])
                miniStandard(art: .white.opacity(0.85), line: .white)
            case .mono:
                Color.black
                miniStandard(art: .white, line: .white, corner: 1)
            case .vinyl:
                Color(hex: "#151311")
                Circle().fill(Color(hex: "#0B0B0C")).frame(width: 42, height: 42)
                    .overlay(Circle().fill(KhyloStyle.accent).frame(width: 14, height: 14))
                    .offset(x: 10)
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#E8DCC6")).frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 2, y: 2)
                    .offset(x: -12)
            case .retro:
                Color(hex: "#DEDAD1")
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#F6F3EC")).frame(width: 96, height: 62)
                    .overlay(
                        HStack(spacing: 6) {
                            KhyloSpeakerGrillePreview()
                            RoundedRectangle(cornerRadius: 1).fill(Color(hex: "#8C7A66")).frame(width: 26, height: 26)
                            KhyloSpeakerGrillePreview()
                        }
                    )
            case .cyberpunk:
                Color(hex: "#06050A")
                Canvas { context, size in
                    for i in -4 ... 4 {
                        var line = Path()
                        line.move(to: CGPoint(x: size.width / 2, y: size.height * 0.55))
                        line.addLine(to: CGPoint(x: size.width / 2 + CGFloat(i) * 22, y: size.height))
                        context.stroke(line, with: .color(KhyloCyberpunkPlayer.magenta.opacity(0.5)), lineWidth: 1)
                    }
                }
                KhyloCutCornerShape(cut: 6).stroke(KhyloCyberpunkPlayer.cyan, lineWidth: 1.5)
                    .frame(width: 34, height: 34)
                    .shadow(color: KhyloCyberpunkPlayer.cyan, radius: 4)
                    .offset(y: -8)
            }
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func miniStandard(art: Color, line: Color, corner: CGFloat = 4) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: corner).fill(art.opacity(0.9)).frame(width: 34, height: 34)
            Capsule().fill(line.opacity(0.8)).frame(width: 40, height: 3)
            Capsule().fill(line.opacity(0.4)).frame(width: 28, height: 3)
        }
    }
}

/// A tiny dotted grille for the Retro preview.
private struct KhyloSpeakerGrillePreview: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: 1.5, to: size.width, by: 4) {
                for y in stride(from: 1.5, to: size.height, by: 4) where hypot(x - size.width / 2, y - size.height / 2) < size.width / 2 {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Color(hex: "#3B3832").opacity(0.5)))
                }
            }
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Settings

/// The player's settings: theme, equalizer, keeping songs ready, and downloads.
struct KhyloPlayerSettingsSheet: View {

    let closePlayer: () -> Void

    @AppStorage(KhyloPlayerTheme.storageKey) private var theme: KhyloPlayerTheme = .khylo
    @AppStorage(KhyloSongCache.enabledKey) private var cacheAhead = true
    @ObservedObject private var equalizer = KhyloEqualizer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(KhyloPlayerTheme.allCases) { option in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.easeInOut(duration: 0.3)) { theme = option }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    KhyloThemePreview(theme: option)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(theme == option ? KhyloStyle.accent : Color.white.opacity(0.08), lineWidth: theme == option ? 2.5 : 1)
                                        )
                                        .overlay(alignment: .topTrailing) {
                                            if theme == option {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundStyle(.white, KhyloStyle.accent)
                                                    .padding(6)
                                            }
                                        }
                                    Text(option.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(option.detail)
                                        .font(.system(size: 11))
                                        .foregroundColor(KhyloStyle.tertiaryText)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Player Theme")
                } footer: {
                    Text("Vinyl, Retro and Cyberpunk change the whole player. The others restyle it. Audiobooks always use the standard player.")
                }

                Section("Sound") {
                    NavigationLink {
                        KhyloEqualizerView()
                    } label: {
                        HStack {
                            Label("Equalizer", systemImage: "slider.vertical.3")
                            Spacer()
                            Text(equalizer.isOn ? (equalizer.presetName ?? "Custom") : "Off")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Keep Upcoming Songs Ready", isOn: $cacheAhead)
                        .tint(KhyloStyle.accent)
                        .onChange(of: cacheAhead) { _, isOn in
                            if !isOn { KhyloSongCache.shared.clear() }
                        }
                } header: {
                    Text("Listening")
                } footer: {
                    Text("Keeps the song you're playing and the next two on your iPhone, so music carries on through dead spots and the next song starts straight away.")
                }

                KhyloDownloadSettingsSection {
                    dismiss()
                    closePlayer()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        KhyloPageRelay.shared.showDownloads.send()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KhyloStyle.canvas)
            .navigationTitle("Player Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}
