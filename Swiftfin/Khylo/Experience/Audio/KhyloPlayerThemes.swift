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
        case .vinyl: "A record that spins"
        case .retro: "A cassette deck"
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

/// A turntable: the cover is the record's label, the record turns while it
/// plays and the tonearm swings onto it.
struct KhyloVinylPlayer: View {

    let actions: KhyloPlayerActions
    let tint: Color?

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @State private var spinBase: Double = 0
    @State private var spinStart: Date?

    private let cream = Color(hex: "#EFE4CF")

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#21170F"), Color(hex: "#0B0806")], startPoint: .top, endPoint: .bottom)
                .overlay((tint ?? .clear).opacity(0.12))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                KhyloThemedTopBar(actions: actions, foreground: cream, labelFont: .system(size: 12, weight: .semibold, design: .serif))
                    .padding(.top, 8)

                turntable
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Spacer(minLength: 14)

                VStack(spacing: 6) {
                    Text(player.current?.name ?? "")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(cream)
                        .lineLimit(1)
                    KhyloThemedArtistLine(actions: actions, color: cream.opacity(0.65), font: .system(size: 16, design: .serif))
                }
                .padding(.horizontal, 28)

                KhyloClockScrubber(clock: player.clock, fill: cream, track: cream.opacity(0.2), text: cream.opacity(0.6)) { player.seek(to: $0) }
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                KhyloThemedTransport(fill: cream, glyph: Color(hex: "#21170F"), secondary: cream)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)

                Spacer(minLength: 12)

                KhyloThemedBottomRow(actions: actions, color: cream.opacity(0.85))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
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

    private var turntable: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let recordSize = side * 0.8
            ZStack(alignment: .topLeading) {
                // Walnut plinth.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#5A3A24"), Color(hex: "#3A2416"), Color(hex: "#2A190F")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Canvas { context, size in
                            for row in stride(from: 0, to: size.height, by: 5) {
                                var line = Path()
                                line.move(to: CGPoint(x: 0, y: row))
                                line.addCurve(
                                    to: CGPoint(x: size.width, y: row + 6),
                                    control1: CGPoint(x: size.width * 0.3, y: row - 4),
                                    control2: CGPoint(x: size.width * 0.7, y: row + 8)
                                )
                                context.stroke(line, with: .color(.black.opacity(0.08)), lineWidth: 1)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    )
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 14)

                // Platter and record.
                TimelineView(.animation(paused: !player.isPlaying)) { context in
                    record(size: recordSize)
                        .rotationEffect(.degrees(angle(at: context.date)))
                }
                .overlay(
                    // The light on the record stays still while it turns.
                    Circle()
                        .fill(AngularGradient(
                            colors: [.clear, .white.opacity(0.09), .clear, .clear, .white.opacity(0.06), .clear, .clear],
                            center: .center
                        ))
                        .allowsHitTesting(false)
                )
                .frame(width: recordSize, height: recordSize)
                .offset(x: side * 0.05, y: side * 0.1)

                tonearm(side: side)
                    .offset(x: side * 0.74, y: side * 0.04)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func angle(at date: Date) -> Double {
        spinBase + (spinStart.map { date.timeIntervalSince($0) * 200 } ?? 0)
    }

    private func record(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: "#0C0C0E"))
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outer = canvasSize.width / 2
                for radius in stride(from: outer * 0.38, to: outer * 0.97, by: 2.5) {
                    let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.stroke(ring, with: .color(.white.opacity(0.035)), lineWidth: 0.6)
                }
            }
            KhyloImage(url: player.displayArtworkURL(width: 400), placeholderSymbol: "music.note")
                .frame(width: size * 0.36, height: size * 0.36)
                .clipShape(Circle())
            Circle()
                .fill(Color(hex: "#D9D4CB"))
                .frame(width: size * 0.03, height: size * 0.03)
        }
        .frame(width: size, height: size)
    }

    private func tonearm(side: CGFloat) -> some View {
        let width = side * 0.2
        let height = side * 0.72
        return ZStack(alignment: .top) {
            Path { path in
                path.move(to: CGPoint(x: width / 2, y: width / 2))
                path.addLine(to: CGPoint(x: width / 2, y: height * 0.78))
                path.addLine(to: CGPoint(x: width * 0.3, y: height * 0.92))
            }
            .stroke(LinearGradient(colors: [Color(hex: "#E6E1D6"), Color(hex: "#9C978C")], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            // Headshell.
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "#C9C3B7"))
                .frame(width: width * 0.32, height: height * 0.09)
                .rotationEffect(.degrees(30))
                .offset(x: -width * 0.2, y: height * 0.9)
            // Pivot.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#F1EDE4"), Color(hex: "#7E796F")], center: .topLeading, startRadius: 1, endRadius: width * 0.6))
                .frame(width: width * 0.7, height: width * 0.7)
                .offset(y: width * 0.15)
        }
        .frame(width: width, height: height, alignment: .top)
        .rotationEffect(.degrees(player.isPlaying ? 24 : 2), anchor: UnitPoint(x: 0.5, y: (width / 2) / height))
        .animation(.spring(response: 0.9, dampingFraction: 0.8), value: player.isPlaying)
        .shadow(color: .black.opacity(0.5), radius: 6, x: 4, y: 6)
    }
}

// MARK: - Retro

/// A cassette deck: the song's title is written on the tape's label, the reels
/// turn as it plays, and the keys are big and chunky.
struct KhyloRetroPlayer: View {

    let actions: KhyloPlayerActions

    @ObservedObject private var player = KhyloAudioPlayer.shared

    private let paper = Color(hex: "#F1E7D2")
    private let ink = Color(hex: "#3A2A1F")
    private let orange = Color(hex: "#E36F2C")
    private let amber = Color(hex: "#F2A93B")
    private let brown = Color(hex: "#8C4A27")

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#F6EEDC"), Color(hex: "#E2D3B5")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                KhyloThemedTopBar(actions: actions, foreground: ink, labelFont: .system(size: 12, weight: .bold, design: .rounded))
                    .padding(.top, 8)

                cassette
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                counter
                    .padding(.horizontal, 24)
                    .padding(.top, 22)

                KhyloClockScrubber(clock: player.clock, fill: orange, track: ink.opacity(0.15), text: ink.opacity(0.6)) { player.seek(to: $0) }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Spacer(minLength: 10)

                keys
                    .padding(.horizontal, 20)

                Spacer(minLength: 10)

                KhyloThemedBottomRow(actions: actions, color: ink.opacity(0.85))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
            }
        }
        .preferredColorScheme(.light)
    }

    private var cassette: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = w * 0.64
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#34302B"), Color(hex: "#1F1C19")], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 10)

                // Screws.
                ForEach(0 ..< 4, id: \.self) { corner in
                    Circle()
                        .fill(Color(hex: "#8E877C"))
                        .overlay(Rectangle().fill(Color(hex: "#3D3833")).frame(width: 7, height: 1.5).rotationEffect(.degrees(35)))
                        .frame(width: 9, height: 9)
                        .position(x: corner % 2 == 0 ? 14 : w - 14, y: corner < 2 ? 14 : h - 14)
                }

                // Label.
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.current?.name ?? "")
                                .font(.custom("MarkerFelt-Wide", size: 19))
                                .foregroundColor(ink)
                                .lineLimit(1)
                            Text(player.current?.khyloArtistLine ?? "")
                                .font(.custom("Noteworthy-Bold", size: 13))
                                .foregroundColor(ink.opacity(0.75))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text("A")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(paper)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(ink))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    ZStack {
                        VStack(spacing: 3) {
                            Rectangle().fill(orange).frame(height: 6)
                            Rectangle().fill(amber).frame(height: 6)
                            Rectangle().fill(brown).frame(height: 6)
                        }
                        // The window with the reels.
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "#1A1613"))
                            .frame(width: w * 0.56, height: h * 0.27)
                            .overlay(reels(windowWidth: w * 0.56, windowHeight: h * 0.27))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                    }
                    .padding(.vertical, 8)
                }
                .frame(width: w * 0.88, height: h * 0.62)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(paper))
                .position(x: w / 2, y: h * 0.38)

                // The bottom ridge with its two holes.
                Path { path in
                    path.move(to: CGPoint(x: w * 0.2, y: h))
                    path.addLine(to: CGPoint(x: w * 0.26, y: h * 0.8))
                    path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.8))
                    path.addLine(to: CGPoint(x: w * 0.8, y: h))
                    path.closeSubpath()
                }
                .fill(Color(hex: "#2A2622"))
                ForEach([0.36, 0.64], id: \.self) { x in
                    Circle().fill(Color(hex: "#0E0C0B")).frame(width: 10, height: 10).position(x: w * x, y: h * 0.9)
                }
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1 / 0.64, contentMode: .fit)
    }

    /// Two reels; tape moves from the left one to the right one as the song plays.
    private func reels(windowWidth: CGFloat, windowHeight: CGFloat) -> some View {
        let progress = player.clock.duration > 0 ? player.clock.currentTime / player.clock.duration : 0
        let hub = windowHeight * 0.36
        let full = windowHeight * 0.92
        return TimelineView(.animation(paused: !player.isPlaying)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate * 140
            HStack(spacing: 0) {
                reel(tape: hub + (full - hub) * (1 - progress), hub: hub, angle: angle)
                Spacer(minLength: 0)
                reel(tape: hub + (full - hub) * progress, hub: hub, angle: angle)
            }
            .padding(.horizontal, windowWidth * 0.08)
        }
    }

    private func reel(tape: CGFloat, hub: CGFloat, angle: Double) -> some View {
        ZStack {
            Circle().fill(Color(hex: "#3B2518")).frame(width: tape, height: tape)
            Circle().fill(paper).frame(width: hub, height: hub)
            ForEach(0 ..< 6, id: \.self) { tooth in
                Rectangle()
                    .fill(Color(hex: "#1A1613"))
                    .frame(width: 2.5, height: hub * 0.3)
                    .offset(y: -hub * 0.32)
                    .rotationEffect(.degrees(Double(tooth) * 60 + angle))
            }
        }
        .frame(width: hub * 2.6, height: hub * 2.6)
    }

    /// Track number and an LCD time counter.
    private var counter: some View {
        HStack(spacing: 10) {
            lcd("TRK \(String(format: "%02d", player.index + 1))")
            KhyloRetroTime(clock: player.clock)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "#1D261B")))
        }
    }

    private func lcd(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(hex: "#B8F28C"))
            .shadow(color: Color(hex: "#B8F28C").opacity(0.6), radius: 4)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "#1D261B")))
    }

    /// Piano keys: back, play (stays down while playing), pause, forward, plus shuffle and repeat.
    private var keys: some View {
        HStack(spacing: 6) {
            KhyloPianoKey(symbol: "backward.end.fill", isDown: false, color: ink) { player.previous() }
            KhyloPianoKey(symbol: "play.fill", isDown: player.isPlaying, color: ink) { if !player.isPlaying { player.togglePlayPause() } }
            KhyloPianoKey(symbol: "pause.fill", isDown: !player.isPlaying, color: ink) { if player.isPlaying { player.togglePlayPause() } }
            KhyloPianoKey(symbol: "forward.end.fill", isDown: false, color: ink) { player.next() }
            VStack(spacing: 6) {
                KhyloPianoKey(symbol: "shuffle", isDown: player.isShuffled, color: player.isShuffled ? orange : ink, height: 37) { player.toggleShuffle() }
                KhyloPianoKey(
                    symbol: player.repeatMode == .one ? "repeat.1" : "repeat",
                    isDown: player.repeatMode != .off,
                    color: player.repeatMode != .off ? orange : ink,
                    height: 37
                ) { player.repeatMode = player.repeatMode.next }
            }
            .frame(width: 58)
        }
    }
}

/// The deck's time readout, redrawn on its own as time passes.
private struct KhyloRetroTime: View {
    @ObservedObject var clock: KhyloPlaybackClock

    var body: some View {
        Text("\(KhyloNowPlayingScreen.format(clock.currentTime)) ▸ \(KhyloNowPlayingScreen.format(clock.duration))")
            .font(.system(size: 19, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(hex: "#B8F28C"))
            .shadow(color: Color(hex: "#B8F28C").opacity(0.6), radius: 4)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// A chunky deck key that sinks when pressed (and stays down when latched).
private struct KhyloPianoKey: View {
    let symbol: String
    let isDown: Bool
    let color: Color
    var height: CGFloat = 80
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        let down = isDown || isPressed
        Image(systemName: symbol)
            .font(.system(size: height > 50 ? 22 : 14, weight: .bold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(
                        colors: down ? [Color(hex: "#DDD6C8"), Color(hex: "#CFC7B6")] : [Color(hex: "#FBF8F1"), Color(hex: "#DED7C9")],
                        startPoint: .top, endPoint: .bottom
                    ))
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 0, y: down ? 1 : 5)
            .offset(y: down ? 4 : 0)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: down)
            .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                action()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(symbol)
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

                art
                    .padding(.horizontal, 36)
                    .padding(.top, 10)

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

                Spacer(minLength: 10)

                KhyloThemedBottomRow(actions: actions, color: Self.cyan)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
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
                .gesture(
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
                Color(hex: "#2A1A10")
                Circle().fill(Color(hex: "#0C0C0E")).frame(width: 46, height: 46)
                    .overlay(Circle().fill(KhyloStyle.accent).frame(width: 15, height: 15))
                    .offset(x: -6, y: -6)
                Capsule().fill(Color(hex: "#D8D2C5")).frame(width: 3, height: 30).rotationEffect(.degrees(22)).offset(x: 22, y: -10)
            case .retro:
                Color(hex: "#F1E7D2")
                RoundedRectangle(cornerRadius: 5).fill(Color(hex: "#2A2622")).frame(width: 64, height: 42)
                    .overlay(
                        VStack(spacing: 2) {
                            Rectangle().fill(Color(hex: "#E36F2C")).frame(height: 3)
                            Rectangle().fill(Color(hex: "#F2A93B")).frame(height: 3)
                            HStack(spacing: 14) {
                                Circle().fill(Color(hex: "#F1E7D2")).frame(width: 9, height: 9)
                                Circle().fill(Color(hex: "#F1E7D2")).frame(width: 9, height: 9)
                            }
                        }
                        .padding(6)
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
