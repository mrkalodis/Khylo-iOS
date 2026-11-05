//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Themes

/// How the music player looks. Three restyle the standard player; Vinyl and
/// Cyberpunk each have a layout of their own.
enum KhyloPlayerTheme: String, CaseIterable, Identifiable {
    case khylo
    case aurora
    case mono
    case vinyl
    case cyberpunk
    case glass
    case poster

    static let storageKey = "khylo.player.theme"
    /// Vinyl in dark instead of light.
    static let vinylDarkKey = "khylo.player.vinylDark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .khylo: "Khylo"
        case .aurora: "Aurora"
        case .mono: "Mono"
        case .vinyl: "Vinyl"
        case .cyberpunk: "Cyberpunk"
        case .glass: "Glass"
        case .poster: "Poster"
        }
    }

    var detail: String {
        switch self {
        case .khylo: "Your album's colours"
        case .aurora: "Slow light from the cover"
        case .mono: "Black, white, nothing else"
        case .vinyl: "Light, with a spinning record"
        case .cyberpunk: "Neon, grids and glitches"
        case .glass: "Frosted, quiet, cover first"
        case .poster: "The cover, full width, like a record sleeve"
        }
    }

    /// A layout of its own, rather than a restyle of the standard player.
    var hasOwnLayout: Bool {
        self == .vinyl || self == .cyberpunk
    }
}

/// How the record in the Vinyl player is pressed.
enum KhyloVinylStyle: String, CaseIterable, Identifiable {
    case marbled
    case classic
    case picture
    case splatter
    case solid

    static let storageKey = "khylo.player.vinylStyle"
    /// Keeps the record still even while music plays.
    static let stillKey = "khylo.player.vinylStill"
    /// A colour the person chose for the Colour record, as hex; empty uses the cover's.
    static let colorKey = "khylo.player.vinylColor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .marbled: "Marbled"
        case .classic: "Classic Black"
        case .picture: "Picture Disc"
        case .splatter: "Splatter"
        case .solid: "Colour"
        }
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
    /// "#RRGGBB"
    var khyloHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

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

/// A light, clean player built around the record. The cover sits in the
/// middle; when music plays the record slides out from behind it and turns,
/// cover and record staying centred together, and slides back in on pause.
struct KhyloVinylPlayer: View {

    let actions: KhyloPlayerActions
    let tint: Color?

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @AppStorage(KhyloPlayerTheme.vinylDarkKey) private var isDark = false
    @AppStorage(KhyloVinylStyle.storageKey) private var style: KhyloVinylStyle = .marbled
    @AppStorage(KhyloVinylStyle.stillKey) private var keepStill = false
    @AppStorage(KhyloVinylStyle.colorKey) private var chosenColor = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var spinBase: Double = 0
    @State private var spinStart: Date?
    @State private var palette: [Color] = []

    private var ink: Color { isDark ? Color(hex: "#F2F3F5") : Color(hex: "#1D1F24") }
    private var soft: Color { isDark ? Color(hex: "#8E939C") : Color(hex: "#8A8F99") }
    private var backdrop: [Color] {
        isDark ? [Color(hex: "#17181B"), Color(hex: "#0C0D0F")] : [Color(hex: "#F7F7F9"), Color(hex: "#ECEEF3")]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: backdrop, startPoint: .top, endPoint: .bottom)
                .overlay((tint ?? .clear).opacity(isDark ? 0.1 : 0.06))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: isDark)

            VStack(spacing: 0) {
                KhyloThemedTopBar(actions: actions, foreground: ink, labelFont: .system(size: 10, weight: .semibold))
                    .padding(.top, 8)

                if verticalSizeClass == .compact {
                    // Sideways: the record on the left, the song and controls on the right.
                    HStack(spacing: 12) {
                        record
                            .padding(.leading, 28)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            controls
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, 20)
                    }
                } else {
                    Spacer(minLength: 10)

                    record
                        .padding(.horizontal, 8)

                    Spacer(minLength: 22)

                    controls
                }
            }
        }
        .task(id: player.current?.id) {
            palette = await KhyloArtColor.palette(for: player.displayArtworkURL(width: 120))
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

    /// The song, its wave scrubber, the transport and the bottom row.
    private var controls: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(player.current?.name ?? "")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                KhyloThemedArtistLine(actions: actions, color: soft, font: .system(size: 16, weight: .medium))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            KhyloWaveScrubber(clock: player.clock, seed: player.current?.id ?? "", played: KhyloStyle.accent, rest: ink.opacity(isDark ? 0.18 : 0.14), text: soft) {
                player.seek(to: $0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            transport
                .padding(.horizontal, 26)
                .padding(.top, 18)

            KhyloThemedBottomRow(actions: actions, color: soft)
                .padding(.horizontal, 30)
                .padding(.top, 22)
                .padding(.bottom, 12)
        }
    }

    /// Cover and record, centred as a pair. Paused, the record is tucked behind
    /// the cover; playing, it slides out to the right while the cover moves
    /// left by the same amount, so the two stay in the middle.
    private var record: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cover = width * 0.88
            let playing = player.isPlaying
            let shown = playing ? cover * 0.82 : cover
            let disc = shown * 0.96
            let slide = playing ? width * 0.13 : 0
            ZStack {
                TimelineView(.animation(paused: !playing || keepStill || reduceMotion)) { context in
                    discView(size: disc)
                        .rotationEffect(.degrees(angle(at: context.date)))
                }
                .overlay(
                    // The light on the record stays put while it turns, so it sweeps across the grooves.
                    Circle()
                        .fill(AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .clear, location: 0.07),
                                .init(color: .white.opacity(0.34), location: 0.105),
                                .init(color: .clear, location: 0.15),
                                .init(color: .clear, location: 0.52),
                                .init(color: .white.opacity(0.20), location: 0.585),
                                .init(color: .clear, location: 0.65),
                                .init(color: .clear, location: 1.00),
                            ],
                            center: .center,
                            angle: .degrees(-30)
                        ))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
                .frame(width: disc, height: disc)
                // In the dark, a faint rim keeps the record from vanishing into the background.
                .overlay(Circle().strokeBorder(Color.white.opacity(isDark ? 0.08 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(isDark ? 0.6 : 0.25), radius: 18, y: 12)
                .offset(x: slide)

                KhyloImage(url: player.displayArtworkURL(width: 900), placeholderSymbol: "music.note")
                    .frame(width: shown, height: shown)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(isDark ? 0.55 : 0.22), radius: 24, y: 14)
                    .offset(x: -slide)
            }
            .frame(width: width, height: proxy.size.height)
            .animation(.spring(response: 0.75, dampingFraction: 0.86), value: playing)
        }
        .aspectRatio(1 / 0.88, contentMode: .fit)
    }

    private func angle(at date: Date) -> Double {
        if keepStill || reduceMotion { return spinBase }
        return spinBase + (spinStart.map { date.timeIntervalSince($0) * 200 } ?? 0)
    }

    /// The record: pressed in colours taken from the cover, fine grooves and gaps between
    /// tracks, and the cover itself as the centre label.
    private func discView(size: CGFloat) -> some View {
        ZStack {
            pressing(size: size)
            grooves(size: size)

            // Centre label: the cover, with a paper rim and the spindle hole.
            // A picture disc already shows the cover across the whole record.
            if style != .picture {
                KhyloImage(url: player.displayArtworkURL(width: 300), placeholderSymbol: "music.note")
                    .frame(width: size * 0.34, height: size * 0.34)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: max(2, size * 0.008)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1).padding(size * 0.008))
            }
            Circle()
                .fill(isDark ? Color(hex: "#0C0D0F") : Color(hex: "#ECEEF3"))
                .frame(width: size * 0.034, height: size * 0.034)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
        }
        .frame(width: size, height: size)
    }

    /// The body of the record, in the chosen style.
    @ViewBuilder
    private func pressing(size: CGFloat) -> some View {
        switch style {
        case .marbled:
            marbled(size: size)
        case .classic:
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#232326"), Color(hex: "#0B0B0C")], center: .center, startRadius: 0, endRadius: size / 2))
                .overlay(Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.5)], center: .center, startRadius: size * 0.3, endRadius: size / 2)))
                .frame(width: size, height: size)
        case .picture:
            ZStack {
                Circle().fill(Color(hex: "#111113"))
                KhyloImage(url: player.displayArtworkURL(width: 700), placeholderSymbol: "music.note")
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .saturation(0.7)
                    .opacity(0.72)
                Circle().fill(Color.black.opacity(0.18))
                Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.5)], center: .center, startRadius: size * 0.25, endRadius: size / 2))
            }
            .frame(width: size, height: size)
        case .splatter:
            splatter(size: size)
        case .solid:
            let colors = palette.isEmpty ? [Color(hex: "#3A3B40")] : palette
            let base = chosenColor.isEmpty ? colors[0] : Color(hex: chosenColor)
            Circle()
                .fill(RadialGradient(colors: [base.khyloShifted(hue: 0, brightness: 1.1), base.khyloShifted(hue: 0, brightness: 0.62)], center: .center, startRadius: 0, endRadius: size / 2))
                .overlay(Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.4)], center: .center, startRadius: size * 0.3, endRadius: size / 2)))
                .frame(width: size, height: size)
        }
    }

    /// Black vinyl flecked with the cover's colours, the same for the same song every time.
    private func splatter(size: CGFloat) -> some View {
        let colors = palette.isEmpty ? [Color(hex: "#8A8F99")] : palette
        var random = KhyloSeededRandom(seed: (player.current?.id ?? "") + "splatter")
        // Big blots, then a fine spray of flecks between them.
        let dots: [(color: Color, x: CGFloat, y: CGFloat, radius: CGFloat)] = (0 ..< 190).map { index in
            let angle = random.next() * .pi * 2
            let distance = CGFloat(random.next().squareRoot()) * 0.47
            let isBlot = index < 38
            return (
                colors[index % colors.count],
                CGFloat(cos(angle)) * distance,
                CGFloat(sin(angle)) * distance,
                isBlot ? CGFloat(0.014 + random.next() * random.next() * 0.06) : CGFloat(0.004 + random.next() * 0.012)
            )
        }
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: "#1B1B1E"), Color(hex: "#0A0A0B")], center: .center, startRadius: 0, endRadius: size / 2))
            ForEach(0 ..< dots.count, id: \.self) { index in
                let dot = dots[index]
                Circle()
                    .fill(dot.color.opacity(0.9))
                    .frame(width: size * dot.radius * 2, height: size * dot.radius * 2)
                    .offset(x: size * dot.x, y: size * dot.y)
            }
            .blur(radius: size * 0.004)
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.45)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
        .animation(.easeInOut(duration: 0.6), value: palette)
    }

    /// Streaks and swirls of the cover's colours, the same for the same song every time.
    private func marbled(size: CGFloat) -> some View {
        let colors = palette.isEmpty ? [Color(hex: "#26272B"), Color(hex: "#151618")] : palette
        let base = colors[0]
        var random = KhyloSeededRandom(seed: player.current?.id ?? "")
        let streaks: [(color: Color, angle: Double, x: CGFloat, y: CGFloat, length: CGFloat, thickness: CGFloat)] =
            (0 ..< 9).map { index in
                (
                    colors[index % colors.count],
                    random.next() * 180,
                    CGFloat(random.next() - 0.5) * 0.7,
                    CGFloat(random.next() - 0.5) * 0.7,
                    CGFloat(0.7 + random.next() * 0.6),
                    CGFloat(0.10 + random.next() * 0.2)
                )
            }
        let veins: [(angle: Double, x: CGFloat, y: CGFloat, length: CGFloat)] = (0 ..< 6).map { _ in
            (random.next() * 180, CGFloat(random.next() - 0.5) * 0.8, CGFloat(random.next() - 0.5) * 0.8, CGFloat(0.5 + random.next() * 0.7))
        }

        return ZStack {
            Circle().fill(RadialGradient(colors: [base.opacity(0.85), base.opacity(0.45)], center: .center, startRadius: 0, endRadius: size / 2))
            ForEach(0 ..< streaks.count, id: \.self) { index in
                let streak = streaks[index]
                Capsule()
                    .fill(streak.color.opacity(0.85))
                    .frame(width: size * streak.length, height: size * streak.thickness)
                    .rotationEffect(.degrees(streak.angle))
                    .offset(x: size * streak.x, y: size * streak.y)
            }
            .blur(radius: size * 0.05)
            ForEach(0 ..< veins.count, id: \.self) { index in
                let vein = veins[index]
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: size * vein.length, height: size * 0.014)
                    .rotationEffect(.degrees(vein.angle))
                    .offset(x: size * vein.x, y: size * vein.y)
            }
            .blur(radius: size * 0.012)
            // Depth: the edge of the record falls away into shadow.
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.45)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
        .animation(.easeInOut(duration: 0.6), value: palette)
    }

    /// Fine grooves, darker gaps between tracks, a smooth run-out ring by the label and
    /// a clean rim.
    private func grooves(size: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let outer = canvasSize.width / 2
            func ring(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            var step = 0
            for radius in stride(from: outer * 0.40, to: outer * 0.965, by: 2.2) {
                context.stroke(
                    ring(radius),
                    with: .color(step.isMultiple(of: 2) ? Color.black.opacity(0.13) : Color.white.opacity(0.045)),
                    lineWidth: 0.7
                )
                step += 1
            }
            for fraction in [0.50, 0.63, 0.74, 0.86] {
                context.stroke(ring(outer * fraction), with: .color(Color.black.opacity(0.32)), lineWidth: 2.4)
            }
            context.stroke(ring(outer * 0.375), with: .color(Color.white.opacity(0.14)), lineWidth: 1)
            context.stroke(ring(outer * 0.985), with: .color(Color.white.opacity(0.14)), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }

    private var transport: some View {
        HStack(spacing: 0) {
            toggle("shuffle", isOn: player.isShuffled) { player.toggleShuffle() }
            Spacer()
            button("backward.end") { player.previous() }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(KhyloStyle.accent)
                    if player.isBuffering && player.isPlaying {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: player.isPlaying ? 0 : 2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 76, height: 76)
                .shadow(color: KhyloStyle.accent.opacity(0.35), radius: 14, y: 8)
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            button("forward.end") { player.next() }
            Spacer()
            toggle(player.repeatMode == .one ? "repeat.1" : "repeat", isOn: player.repeatMode != .off) {
                player.repeatMode = player.repeatMode.next
            }
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(ink)
                .frame(width: 54, height: 54)
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private func toggle(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isOn ? KhyloStyle.accent : soft.opacity(0.7))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

/// A small random-number maker that gives the same numbers for the same song, so a
/// record always has the same marbling.
struct KhyloSeededRandom {

    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        state = hash == 0 ? 1 : hash
    }

    /// A number from 0 up to 1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// Time as a row of thin bars shaped like a waveform (the same shape every
/// time a song plays); the part already played is in colour. Drag to move
/// through the song.
private struct KhyloWaveScrubber: View {
    @ObservedObject var clock: KhyloPlaybackClock
    let seed: String
    let played: Color
    let rest: Color
    let text: Color
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    private var heights: [CGFloat] {
        // A stable pseudo-random shape from the song's ID.
        var state = seed.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        return (0 ..< 56).map { i in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let noise = CGFloat((state >> 33) % 1000) / 1000
            let swell = 0.55 + 0.45 * sin(CGFloat(i) / 56 * .pi * 3)
            return max(0.12, min(1, noise * 0.7 * swell + 0.18))
        }
    }

    var body: some View {
        let value = dragValue ?? clock.currentTime
        let fraction = clock.duration > 0 ? min(1, max(0, value / clock.duration)) : 0
        let bars = heights
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let gap: CGFloat = 2.5
                let width = (proxy.size.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
                HStack(alignment: .center, spacing: gap) {
                    ForEach(bars.indices, id: \.self) { i in
                        Capsule()
                            .fill(Double(i) / Double(bars.count) < fraction ? played : rest)
                            .frame(width: width, height: proxy.size.height * bars[i])
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragValue = Double(min(1, max(0, $0.location.x / proxy.size.width))) * clock.duration }
                        .onEnded { gesture in
                            onSeek(Double(min(1, max(0, gesture.location.x / proxy.size.width))) * clock.duration)
                            dragValue = nil
                        }
                )
            }
            .frame(height: 34)

            HStack {
                Text(KhyloNowPlayingScreen.format(value))
                Spacer()
                Text(KhyloNowPlayingScreen.format(clock.duration))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundColor(text)
        }
    }
}

// MARK: - Cyberpunk

/// A neon heads-up display: grid floor, scanlines, a glitching cover, a
/// visualizer and a segmented time bar.
struct KhyloCyberpunkPlayer: View {

    let actions: KhyloPlayerActions

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @ObservedObject private var network = KhyloNetwork.shared
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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

                if verticalSizeClass == .compact {
                    HStack(spacing: 12) {
                        art
                            .padding(.leading, 28)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            controls
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Spacer(minLength: 6)

                    art
                        .padding(.horizontal, 20)

                    Spacer(minLength: 12)

                    controls
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
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
            .frame(width: 88, alignment: .leading)

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

            HStack(spacing: 0) {
                KhyloHandoffButton(color: foreground)
                Button(action: actions.showSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(foreground)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Player settings")
            }
            .frame(width: 88, alignment: .trailing)
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

/// A moon in the player's bottom row: tap for the timer choices; the time left shows beside it.
struct KhyloSleepTimerButton: View {
    let color: Color
    var activeColor: Color = KhyloStyle.accent

    @ObservedObject private var player = KhyloAudioPlayer.shared

    var body: some View {
        Menu {
            Button("Off") { player.setSleepTimer(minutes: nil) }
            Button("End of Song") { player.setSleepTimer(minutes: 0) }
            ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) Minutes") { player.setSleepTimer(minutes: minutes) }
            }
        } label: {
            Image(systemName: player.sleepTimerEnd == nil ? "moon.zzz" : "moon.zzz.fill")
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(player.sleepTimerEnd == nil ? color : activeColor)
                .frame(width: 44, height: 44)
                .overlay(alignment: .bottom) {
                    if let end = player.sleepTimerEnd {
                        Text(end, style: .timer)
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundColor(activeColor)
                            .offset(y: 8)
                    }
                }
        }
        .accessibilityLabel("Sleep timer")
    }
}

/// AirPlay, download, favorite and the queue.
struct KhyloThemedBottomRow: View {
    let actions: KhyloPlayerActions
    let color: Color

    @ObservedObject private var player = KhyloAudioPlayer.shared

    var body: some View {
        HStack(spacing: 0) {
            KhyloRoutePicker(tint: UIColor(color))
                .frame(width: 44, height: 44)
            Spacer()
            if let current = player.current {
                KhyloDownloadButton(item: current, style: .icon)
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button(action: actions.toggleFavorite) {
                Image(systemName: actions.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 21))
                    .foregroundColor(actions.isFavorite ? KhyloStyle.accent : color)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(actions.isFavorite ? "Remove from favorites" : "Add to favorites")
            Spacer()
            KhyloSleepTimerButton(color: color)
            Spacer()
            Button(action: actions.showQueue) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
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
                LinearGradient(colors: [Color(hex: "#F7F7F9"), Color(hex: "#E6E8EE")], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(hex: "#111113")).frame(width: 40, height: 40)
                    .overlay(Circle().fill(KhyloStyle.accent).frame(width: 13, height: 13))
                    .offset(x: 12)
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#C9B79C")).frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .offset(x: -12)
            case .glass:
                LinearGradient(colors: [Color(hex: "#3B4560"), Color(hex: "#151823")], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.75)).frame(width: 30, height: 30).offset(y: -6))
            case .poster:
                LinearGradient(colors: [Color(hex: "#C9A27A"), Color(hex: "#6B4A33"), Color.black], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Capsule().fill(Color.white).frame(width: 46, height: 5)
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 30, height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
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

    /// Audiobooks only get the download settings; themes, the equalizer and
    /// keeping songs ready are for music.
    var isAudiobook = false
    let closePlayer: () -> Void

    @AppStorage(KhyloPlayerTheme.storageKey) private var theme: KhyloPlayerTheme = .khylo
    @AppStorage(KhyloPlayerTheme.vinylDarkKey) private var vinylDark = false
    @AppStorage(KhyloVinylStyle.storageKey) private var vinylStyle: KhyloVinylStyle = .marbled
    @AppStorage(KhyloVinylStyle.stillKey) private var vinylStill = false
    @AppStorage(KhyloVinylStyle.colorKey) private var vinylColor = ""
    @AppStorage(KhyloAudioPlayer.crossfadeKey) private var crossfade = 0.0
    @AppStorage(KhyloSongCache.enabledKey) private var cacheAhead = true
    @ObservedObject private var equalizer = KhyloEqualizer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !isAudiobook {
                    musicSections
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
            .navigationTitle(isAudiobook ? "Settings" : "Player Settings")
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

    @ViewBuilder
    private var musicSections: some View {
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

            if theme == .vinyl {
                Toggle("Dark Vinyl", isOn: $vinylDark.animation(.easeInOut(duration: 0.3)))
                    .tint(KhyloStyle.accent)
                Picker("Record", selection: $vinylStyle) {
                    ForEach(KhyloVinylStyle.allCases) { Text($0.title).tag($0) }
                }
                if vinylStyle == .solid {
                    ColorPicker("Record Colour", selection: Binding(
                        get: { vinylColor.isEmpty ? KhyloStyle.accent : Color(hex: vinylColor) },
                        set: { vinylColor = $0.khyloHex }
                    ), supportsOpacity: false)
                    if !vinylColor.isEmpty {
                        Button("Use the Cover's Colour") { vinylColor = "" }
                    }
                }
                Toggle("Keep the Record Still", isOn: $vinylStill)
                    .tint(KhyloStyle.accent)
            }
        } header: {
            Text("Player Theme")
        } footer: {
            Text("Vinyl and Cyberpunk change the whole player. The others restyle it.")
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
            Picker("Crossfade", selection: $crossfade) {
                Text("Off").tag(0.0)
                ForEach([2.0, 4.0, 6.0, 8.0, 10.0, 12.0], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
            }
        } header: {
            Text("Transitions")
        } footer: {
            Text("One song fades out as the next fades in. Skipping a song never fades.")
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
    }
}
