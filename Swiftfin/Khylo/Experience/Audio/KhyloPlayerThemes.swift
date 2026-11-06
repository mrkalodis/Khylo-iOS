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
/// Hi-Fi each have a layout of their own.
enum KhyloPlayerTheme: String, CaseIterable, Identifiable {
    case khylo
    case aurora
    case mono
    case vinyl
    case hifi
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
        case .hifi: "Hi-Fi"
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
        case .hifi: "Amber VU meters, like a vintage amp"
        case .glass: "Frosted, quiet, cover first"
        case .poster: "The cover, full width, like a record sleeve"
        }
    }

    /// A layout of its own, rather than a restyle of the standard player.
    var hasOwnLayout: Bool {
        self == .vinyl || self == .hifi
    }
}

private struct KhyloLandscapeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The Now Playing screen is wider than it is tall.
    var khyloLandscape: Bool {
        get { self[KhyloLandscapeKey.self] }
        set { self[KhyloLandscapeKey.self] = newValue }
    }
}

/// How the record in the Vinyl player is pressed.
enum KhyloVinylStyle: String, CaseIterable, Identifiable {
    case marbled
    case classic
    case picture
    case splatter
    case galaxy
    case amber
    case smoke
    case gold
    case ink
    case halo
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
        case .galaxy: "Galaxy"
        case .amber: "Amber"
        case .smoke: "Smoke"
        case .gold: "Gold"
        case .ink: "Ink Drop"
        case .halo: "Halo"
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
    @Environment(\.khyloLandscape) private var isLandscape
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

                if isLandscape {
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
        case .galaxy:
            galaxy(size: size)
        case .amber:
            amber(size: size)
        case .smoke:
            smoke(size: size)
        case .gold:
            gold(size: size)
        case .ink:
            inkDrop(size: size)
        case .halo:
            halo(size: size)
        case .solid:
            let colors = palette.isEmpty ? [Color(hex: "#3A3B40")] : palette
            let base = chosenColor.isEmpty ? colors[0] : Color(hex: chosenColor)
            Circle()
                .fill(RadialGradient(colors: [base.khyloShifted(hue: 0, brightness: 1.1), base.khyloShifted(hue: 0, brightness: 0.62)], center: .center, startRadius: 0, endRadius: size / 2))
                .overlay(Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.4)], center: .center, startRadius: size * 0.3, endRadius: size / 2)))
                .frame(width: size, height: size)
        }
    }

    private var coverColors: [Color] {
        palette.isEmpty ? [Color(hex: "#3A3B40"), Color(hex: "#8A8F99")] : palette
    }

    /// Deep space in the cover's colours, with a scatter of stars.
    private func galaxy(size: CGFloat) -> some View {
        let colors = coverColors
        var random = KhyloSeededRandom(seed: (player.current?.id ?? "") + "galaxy")
        let clouds: [(color: Color, x: CGFloat, y: CGFloat, radius: CGFloat)] = (0 ..< 7).map { index in
            (colors[index % colors.count], CGFloat(random.next() - 0.5) * 0.7, CGFloat(random.next() - 0.5) * 0.7, CGFloat(0.22 + random.next() * 0.25))
        }
        let stars: [(x: CGFloat, y: CGFloat, radius: CGFloat, alpha: Double)] = (0 ..< 120).map { _ in
            let angle = random.next() * .pi * 2
            let distance = CGFloat(random.next().squareRoot()) * 0.48
            return (CGFloat(cos(angle)) * distance, CGFloat(sin(angle)) * distance, CGFloat(0.002 + random.next() * 0.004), 0.4 + random.next() * 0.6)
        }
        return ZStack {
            Circle().fill(Color(hex: "#07070C"))
            ForEach(0 ..< clouds.count, id: \.self) { index in
                let cloud = clouds[index]
                Circle()
                    .fill(cloud.color.opacity(0.55))
                    .frame(width: size * cloud.radius * 2, height: size * cloud.radius * 2)
                    .offset(x: size * cloud.x, y: size * cloud.y)
            }
            .blur(radius: size * 0.09)
            ForEach(0 ..< stars.count, id: \.self) { index in
                let star = stars[index]
                Circle()
                    .fill(Color.white.opacity(star.alpha))
                    .frame(width: size * star.radius * 2, height: size * star.radius * 2)
                    .offset(x: size * star.x, y: size * star.y)
            }
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.45)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
        .animation(.easeInOut(duration: 0.6), value: palette)
    }

    /// Warm, see-through resin, speckled with dark.
    private func amber(size: CGFloat) -> some View {
        var random = KhyloSeededRandom(seed: (player.current?.id ?? "") + "amber")
        let flecks: [(x: CGFloat, y: CGFloat, length: CGFloat, thickness: CGFloat, angle: Double)] = (0 ..< 46).map { _ in
            let angle = random.next() * .pi * 2
            let distance = CGFloat(random.next().squareRoot()) * 0.46
            return (CGFloat(cos(angle)) * distance, CGFloat(sin(angle)) * distance, CGFloat(0.02 + random.next() * 0.07), CGFloat(0.006 + random.next() * 0.014), random.next() * 180)
        }
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: "#F2B04A"), Color(hex: "#C57A1E"), Color(hex: "#7A3F0E")], center: .center, startRadius: 0, endRadius: size / 2))
            ForEach(0 ..< flecks.count, id: \.self) { index in
                let fleck = flecks[index]
                Capsule()
                    .fill(Color(hex: "#2B1403").opacity(0.55))
                    .frame(width: size * fleck.length, height: size * fleck.thickness)
                    .rotationEffect(.degrees(fleck.angle))
                    .offset(x: size * fleck.x, y: size * fleck.y)
            }
            .blur(radius: size * 0.004)
            Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: max(1, size * 0.008))
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.4)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
    }

    /// Black with pale wisps curling through it, in no colour at all.
    private func smoke(size: CGFloat) -> some View {
        var random = KhyloSeededRandom(seed: (player.current?.id ?? "") + "smoke")
        let wisps: [(x: CGFloat, y: CGFloat, length: CGFloat, thickness: CGFloat, angle: Double, alpha: Double)] = (0 ..< 9).map { _ in
            (CGFloat(random.next() - 0.5) * 0.7, CGFloat(random.next() - 0.5) * 0.7, CGFloat(0.55 + random.next() * 0.5), CGFloat(0.03 + random.next() * 0.05), random.next() * 180, 0.16 + random.next() * 0.26)
        }
        let clouds: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = (0 ..< 4).map { _ in
            (CGFloat(random.next() - 0.5) * 0.6, CGFloat(random.next() - 0.5) * 0.6, CGFloat(0.16 + random.next() * 0.16))
        }
        return ZStack {
            Circle().fill(Color(hex: "#0C0C0E"))
            ForEach(0 ..< clouds.count, id: \.self) { index in
                let cloud = clouds[index]
                Circle()
                    .fill(Color.white.opacity(0.13))
                    .frame(width: size * cloud.radius * 2, height: size * cloud.radius * 2)
                    .offset(x: size * cloud.x, y: size * cloud.y)
            }
            .blur(radius: size * 0.09)
            ForEach(0 ..< wisps.count, id: \.self) { index in
                let wisp = wisps[index]
                Capsule()
                    .fill(Color.white.opacity(wisp.alpha))
                    .frame(width: size * wisp.length, height: size * wisp.thickness)
                    .rotationEffect(.degrees(wisp.angle))
                    .offset(x: size * wisp.x, y: size * wisp.y)
            }
            .blur(radius: size * 0.03)
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.5)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
    }

    /// Brushed gold foil, bright and dark in turn around the record.
    private func gold(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(AngularGradient(
                colors: ["#B88A2E", "#F7E29A", "#B88A2E", "#6F4A12", "#E9C566", "#B88A2E", "#F7E29A", "#80561A", "#B88A2E"].map { Color(hex: $0) },
                center: .center,
                angle: .degrees(-20)
            ))
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: size * 0.3))
            Circle().strokeBorder(Color(hex: "#FFF3C4").opacity(0.5), lineWidth: max(1, size * 0.008))
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.42)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
    }

    /// Black vinyl with one big drop of the cover's colour bleeding in from the edge.
    private func inkDrop(size: CGFloat) -> some View {
        let colors = coverColors
        var random = KhyloSeededRandom(seed: (player.current?.id ?? "") + "ink")
        let angle = random.next() * .pi * 2
        let centre = CGPoint(x: CGFloat(cos(angle)) * 0.32, y: CGFloat(sin(angle)) * 0.32)
        let main = colors[0]
        let second = colors.count > 1 ? colors[1] : main.khyloShifted(hue: 0.08, brightness: 0.9)
        return ZStack {
            Circle().fill(Color(hex: "#0B0B0D"))
            Circle()
                .fill(main.opacity(0.95))
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(x: size * centre.x, y: size * centre.y)
                .blur(radius: size * 0.11)
            Circle()
                .fill(second.opacity(0.8))
                .frame(width: size * 0.4, height: size * 0.4)
                .offset(x: size * centre.x * 1.25, y: size * centre.y * 1.25)
                .blur(radius: size * 0.08)
            ForEach(0 ..< 7, id: \.self) { index in
                let drift = CGFloat(index) * 0.1 + 0.05
                Circle()
                    .fill(main.opacity(0.7))
                    .frame(width: size * (0.014 + CGFloat(index % 3) * 0.008), height: size * (0.014 + CGFloat(index % 3) * 0.008))
                    .offset(x: size * (centre.x * 1.5 + CGFloat(sin(Double(index) * 1.9)) * drift), y: size * (centre.y * 1.5 + CGFloat(cos(Double(index) * 2.3)) * drift))
            }
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.45)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
        .animation(.easeInOut(duration: 0.6), value: palette)
    }

    /// Plain black with a glowing ring of the cover's colour just outside the label.
    private func halo(size: CGFloat) -> some View {
        let colors = coverColors
        let glow = colors[0]
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: "#1E1E21"), Color(hex: "#09090A")], center: .center, startRadius: 0, endRadius: size / 2))
            Circle()
                .stroke(glow.opacity(0.55), lineWidth: size * 0.05)
                .frame(width: size * 0.56, height: size * 0.56)
                .blur(radius: size * 0.03)
            Circle()
                .stroke(glow, lineWidth: max(2, size * 0.01))
                .frame(width: size * 0.56, height: size * 0.56)
            Circle()
                .stroke(glow.opacity(0.35), lineWidth: max(1, size * 0.004))
                .frame(width: size * 0.9, height: size * 0.9)
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.4)], center: .center, startRadius: size * 0.3, endRadius: size / 2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .drawingGroup()
        .animation(.easeInOut(duration: 0.6), value: palette)
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

// MARK: - Hi-Fi

/// A vintage amplifier: brushed dark metal, two amber-lit VU meters whose needles
/// swing with the music, the cover in a recessed frame, and warm lettering.
struct KhyloHiFiPlayer: View {

    let actions: KhyloPlayerActions

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @Environment(\.khyloLandscape) private var isLandscape
    @State private var gain: Double = 0

    static let amber = Color(hex: "#F2C77A")
    static let amberSoft = Color(hex: "#C9A468")
    static let metal = Color(hex: "#15120F")

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                KhyloThemedTopBar(
                    actions: actions,
                    foreground: Self.amber,
                    labelFont: .system(size: 10, weight: .semibold, design: .serif),
                    labelPrefix: ""
                )
                .padding(.top, 8)

                if isLandscape {
                    HStack(spacing: 18) {
                        cover
                            .padding(.leading, 28)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            meters
                            controls
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, 16)
                    }
                } else {
                    Spacer(minLength: 8)
                    cover
                        .padding(.horizontal, 54)
                    Spacer(minLength: 14)
                    meters
                    Spacer(minLength: 10)
                    controls
                }
            }
        }
        .onAppear { gain = player.isPlaying ? 1 : 0 }
        .onChange(of: player.isPlaying) { _, playing in
            withAnimation(.easeOut(duration: playing ? 0.5 : 1.1)) { gain = playing ? 1 : 0 }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#221B14"), Color(hex: "#0C0A08")], startPoint: .top, endPoint: .bottom)
            // Fine brushing across the metal.
            Canvas { context, size in
                var random = KhyloSeededRandom(seed: "brushed")
                for _ in 0 ..< 220 {
                    let y = CGFloat(random.next()) * size.height
                    let x = CGFloat(random.next()) * size.width
                    let length = 60 + CGFloat(random.next()) * 220
                    context.fill(
                        Path(CGRect(x: x, y: y, width: length, height: 0.6)),
                        with: .color(Color.white.opacity(0.012 + random.next() * 0.025))
                    )
                }
            }
            RadialGradient(colors: [Self.amber.opacity(0.10), .clear], center: .top, startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }

    private var cover: some View {
        KhyloImage(url: player.displayArtworkURL(width: 700), placeholderSymbol: "music.note")
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#050403"), Color(hex: "#1B1611")], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Self.amberSoft.opacity(0.7), Self.amberSoft.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            )
            .shadow(color: Self.amber.opacity(0.18), radius: 28, y: 8)
            .shadow(color: .black.opacity(0.6), radius: 18, y: 12)
    }

    private var meters: some View {
        HStack(spacing: 14) {
            KhyloVUMeter(label: "L", phase: 0, gain: gain)
            KhyloVUMeter(label: "R", phase: 1.7, gain: gain)
        }
        .padding(.horizontal, 28)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(player.current?.name ?? "")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundColor(Self.amber)
                    .shadow(color: Self.amber.opacity(0.45), radius: 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                KhyloThemedArtistLine(actions: actions, color: Self.amberSoft, font: .system(size: 15, weight: .medium, design: .serif))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
            .padding(.top, 14)

            KhyloWaveScrubber(
                clock: player.clock,
                seed: player.current?.id ?? "",
                played: Self.amber,
                rest: Self.amberSoft.opacity(0.22),
                text: Self.amberSoft
            ) { player.seek(to: $0) }
                .padding(.horizontal, 28)
                .padding(.top, 16)

            KhyloThemedTransport(fill: Self.amber, glyph: Color(hex: "#1A1208"), secondary: Self.amber)
                .padding(.horizontal, 26)
                .padding(.top, 12)

            KhyloThemedBottomRow(actions: actions, color: Self.amberSoft)
                .padding(.horizontal, 30)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
    }
}

/// One analogue VU meter: a backlit face, a printed scale with a red end, and a needle
/// that swings while music plays and settles when it stops.
struct KhyloVUMeter: View, Animatable {

    let label: String
    let phase: Double
    var gain: Double

    var animatableData: Double {
        get { gain }
        set { gain = newValue }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate + phase
            // Two slow waves and a quick one, so the needle never settles into a pattern.
            let swing = (sin(t * 2.9) * 0.5 + sin(t * 1.7 + 1.3) * 0.35 + sin(t * 6.1) * 0.15) * 0.5 + 0.5
            let level = 0.06 + gain * (0.18 + 0.62 * swing)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: "#F7E0AE"), Color(hex: "#D39B4C"), Color(hex: "#8E5E22")], center: .center, startRadius: 0, endRadius: 120))
                Canvas { context, size in
                    let pivot = CGPoint(x: size.width / 2, y: size.height * 1.12)
                    let radius = size.height * 0.92
                    let sweep = 100.0
                    for i in 0 ... 20 {
                        let fraction = Double(i) / 20
                        let angle = (-sweep / 2 + sweep * fraction - 90) * .pi / 180
                        let major = i % 4 == 0
                        let inner = radius - (major ? 11 : 6)
                        var tick = Path()
                        tick.move(to: CGPoint(x: pivot.x + CGFloat(cos(angle)) * inner, y: pivot.y + CGFloat(sin(angle)) * inner))
                        tick.addLine(to: CGPoint(x: pivot.x + CGFloat(cos(angle)) * radius, y: pivot.y + CGFloat(sin(angle)) * radius))
                        let red = fraction > 0.72
                        context.stroke(tick, with: .color(red ? Color(hex: "#B0301F") : Color(hex: "#3A2610")), lineWidth: major ? 1.6 : 0.9)
                    }
                    var arc = Path()
                    arc.addArc(center: pivot, radius: radius - 2, startAngle: .degrees(-90 - sweep / 2), endAngle: .degrees(-90 + sweep / 2), clockwise: false)
                    context.stroke(arc, with: .color(Color(hex: "#3A2610").opacity(0.7)), lineWidth: 0.8)
                    var redArc = Path()
                    redArc.addArc(center: pivot, radius: radius - 2, startAngle: .degrees(-90 - sweep / 2 + sweep * 0.72), endAngle: .degrees(-90 + sweep / 2), clockwise: false)
                    context.stroke(redArc, with: .color(Color(hex: "#B0301F")), lineWidth: 2.2)
                }
                Text("VU")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(Color(hex: "#3A2610"))
                    .offset(y: 14)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .foregroundColor(Color(hex: "#3A2610").opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                // The needle, pivoting below the face.
                GeometryReader { proxy in
                    let pivot = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 1.12)
                    let length = proxy.size.height * 0.88
                    let angle = (-50 + 100 * level - 90) * .pi / 180
                    Path { path in
                        path.move(to: pivot)
                        path.addLine(to: CGPoint(x: pivot.x + CGFloat(cos(angle)) * length, y: pivot.y + CGFloat(sin(angle)) * length))
                    }
                    .stroke(Color(hex: "#24160A"), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 2, y: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Glass over the top.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .center))
            }
            .frame(height: 96)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: "#050403"), lineWidth: 4))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: "#6B5330").opacity(0.7), lineWidth: 1))
            .shadow(color: Color(hex: "#F2C77A").opacity(0.18), radius: 14)
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
            case .hifi:
                LinearGradient(colors: [Color(hex: "#2A2118"), Color(hex: "#0D0B09")], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 8) {
                    ForEach(0 ..< 2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(RadialGradient(colors: [Color(hex: "#F6DDA8"), Color(hex: "#C58F3F")], center: .center, startRadius: 0, endRadius: 30))
                            .frame(width: 34, height: 26)
                            .overlay(Capsule().fill(Color(hex: "#2A1A0C")).frame(width: 1.5, height: 20).rotationEffect(.degrees(24)).offset(y: 2))
                    }
                }
                .offset(y: 16)
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#C9B79C")).frame(width: 30, height: 30).offset(y: -18)
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
            Text("Vinyl and Hi-Fi change the whole player. The others restyle it.")
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
