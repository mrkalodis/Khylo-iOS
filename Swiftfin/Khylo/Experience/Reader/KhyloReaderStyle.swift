//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
import UIKit

// MARK: - Paper

/// The paper a book is read on: its colour, ink and surface texture.
enum KhyloReaderTheme: String, CaseIterable, Identifiable {
    case original
    case paper
    case sepia
    case parchment
    case linen
    case slate
    case dusk
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Original"
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .parchment: "Parchment"
        case .linen: "Linen"
        case .slate: "Slate"
        case .dusk: "Dusk"
        case .night: "Night"
        }
    }

    var backgroundHex: String {
        switch self {
        case .original: "#FFFFFF"
        case .paper: "#FAF7F0"
        case .sepia: "#F2E6CC"
        case .parchment: "#E9D9B6"
        case .linen: "#ECE9E2"
        case .slate: "#2A2C31"
        case .dusk: "#161A24"
        case .night: "#000000"
        }
    }

    var foregroundHex: String {
        switch self {
        case .original: "#1A1A1A"
        case .paper: "#2A2520"
        case .sepia: "#4A3924"
        case .parchment: "#3B2C19"
        case .linen: "#2C2C2E"
        case .slate: "#D9D6CF"
        case .dusk: "#CBC7BE"
        case .night: "#B8B4AC"
        }
    }

    var linkHex: String { isDark ? "#E3935A" : "#B5591C" }

    var texture: KhyloPaperTexture {
        switch self {
        case .original, .night: .none
        case .paper, .sepia, .dusk: .grain
        case .parchment: .fiber
        case .linen, .slate: .linen
        }
    }

    var background: Color { Color(hex: backgroundHex) }
    var foreground: Color { Color(hex: foregroundHex) }

    var isDark: Bool {
        switch self {
        case .slate, .dusk, .night: true
        default: false
        }
    }
}

/// Surface textures, drawn once as small tiles and repeated.
enum KhyloPaperTexture {
    case none
    /// Fine speckle, like uncoated book paper.
    case grain
    /// Grain with stray fibres, like old parchment.
    case fiber
    /// A soft woven crosshatch.
    case linen

    /// Tile edge in pixels; drawn at 2× so it stays crisp.
    static let tilePixels = 128

    @MainActor private static var cache: [String: UIImage] = [:]
    @MainActor private static var dataURICache: [String: String] = [:]

    private var seed: UInt64 {
        switch self {
        case .none: 1
        case .grain: 0x6B68_796C_6F01
        case .fiber: 0x6B68_796C_6F02
        case .linen: 0x6B68_796C_6F03
        }
    }

    /// The texture as a tile image, inked for light or dark paper.
    @MainActor
    func image(dark: Bool) -> UIImage? {
        guard self != .none else { return nil }
        let key = "\(self)-\(dark)"
        if let cached = Self.cache[key] { return cached }

        let size = CGSize(width: Self.tilePixels, height: Self.tilePixels)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let pointSize = CGSize(width: size.width / 2, height: size.height / 2)
        let ink: CGFloat = dark ? 1 : 0
        var generator = SeededGenerator(seed: seed)

        let image = UIGraphicsImageRenderer(size: pointSize, format: format).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: 0.5, y: 0.5)

            // Speckle: every pixel gets a faint random dot.
            let grainStrength: CGFloat = switch self {
            case .grain: dark ? 0.05 : 0.055
            case .fiber: dark ? 0.05 : 0.07
            case .linen: dark ? 0.035 : 0.035
            case .none: 0
            }
            for y in 0 ..< Self.tilePixels {
                for x in 0 ..< Self.tilePixels {
                    let alpha = CGFloat.random(in: 0 ... 1, using: &generator) * grainStrength
                    cg.setFillColor(gray: ink, alpha: alpha)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }

            switch self {
            case .fiber:
                cg.setLineCap(.round)
                for _ in 0 ..< 90 {
                    let start = CGPoint(
                        x: CGFloat.random(in: 0 ..< size.width, using: &generator),
                        y: CGFloat.random(in: 0 ..< size.height, using: &generator)
                    )
                    let length = CGFloat.random(in: 4 ... 16, using: &generator)
                    let angle = CGFloat.random(in: -0.5 ... 0.5, using: &generator)
                    cg.setStrokeColor(gray: ink, alpha: CGFloat.random(in: 0.03 ... 0.08, using: &generator))
                    cg.setLineWidth(CGFloat.random(in: 0.5 ... 1.2, using: &generator))
                    cg.move(to: start)
                    cg.addLine(to: CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
                    cg.strokePath()
                }
            case .linen:
                for line in stride(from: 0, to: Self.tilePixels, by: 2) {
                    let along = CGFloat(line)
                    cg.setFillColor(gray: ink, alpha: CGFloat.random(in: 0.012 ... 0.035, using: &generator))
                    cg.fill(CGRect(x: 0, y: along, width: size.width, height: 1))
                    cg.setFillColor(gray: ink, alpha: CGFloat.random(in: 0.012 ... 0.035, using: &generator))
                    cg.fill(CGRect(x: along, y: 0, width: 1, height: size.height))
                }
            default:
                break
            }
        }
        Self.cache[key] = image
        return image
    }

    /// CSS for the page background, with the texture inlined as a data URI.
    @MainActor
    func css(dark: Bool) -> String {
        guard self != .none else { return "" }
        let key = "\(self)-\(dark)"
        if let cached = Self.dataURICache[key] { return cached }
        guard let data = image(dark: dark)?.pngData() else { return "" }
        let css = "background-image: url(data:image/png;base64,\(data.base64EncodedString())) !important; background-size: \(Self.tilePixels / 2)px \(Self.tilePixels / 2)px !important;"
        Self.dataURICache[key] = css
        return css
    }
}

/// Small deterministic generator so textures look the same every time.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// The paper colour with its texture, for the areas around the page.
struct KhyloPaperBackground: View {
    let theme: KhyloReaderTheme

    var body: some View {
        ZStack {
            theme.background
            if let texture = theme.texture.image(dark: theme.isDark) {
                Image(uiImage: texture)
                    .resizable(resizingMode: .tile)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Type

enum KhyloReaderFont: String, CaseIterable, Identifiable {
    case original
    case newYork
    case georgia
    case palatino
    case iowan
    case charter
    case avenir
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Original"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .iowan: "Iowan"
        case .charter: "Charter"
        case .avenir: "Avenir"
        case .system: "San Francisco"
        }
    }

    /// nil keeps the publisher's fonts.
    var cssFamily: String? {
        switch self {
        case .original: nil
        case .newYork: "ui-serif, 'New York', Georgia, serif"
        case .georgia: "Georgia, serif"
        case .palatino: "Palatino, 'Palatino Linotype', serif"
        case .iowan: "'Iowan Old Style', Georgia, serif"
        case .charter: "Charter, Georgia, serif"
        case .avenir: "'Avenir Next', Avenir, sans-serif"
        case .system: "-apple-system, system-ui, sans-serif"
        }
    }

    func preview(size: CGFloat) -> Font {
        switch self {
        case .original, .newYork: .system(size: size, weight: .medium, design: .serif)
        case .georgia: .custom("Georgia", size: size)
        case .palatino: .custom("Palatino", size: size)
        case .iowan: .custom("Iowan Old Style", size: size)
        case .charter: .custom("Charter", size: size)
        case .avenir: .custom("Avenir Next", size: size)
        case .system: .system(size: size, weight: .medium)
        }
    }
}

enum KhyloReaderSpacing: String, CaseIterable, Identifiable {
    case compact
    case normal
    case relaxed

    var id: String { rawValue }
    var lineHeight: Double {
        switch self {
        case .compact: 1.4
        case .normal: 1.6
        case .relaxed: 1.85
        }
    }

    var symbol: String {
        switch self {
        case .compact: "text.alignleft"
        case .normal: "line.3.horizontal"
        case .relaxed: "text.justify"
        }
    }

    var title: String { rawValue.capitalized }
}

enum KhyloReaderMargins: String, CaseIterable, Identifiable {
    case narrow
    case normal
    case wide

    var id: String { rawValue }
    var points: Int {
        switch self {
        case .narrow: 16
        case .normal: 26
        case .wide: 40
        }
    }

    var title: String { rawValue.capitalized }
}

// MARK: - Settings sheet

struct KhyloReaderSettingsSheet: View {

    @Binding var theme: KhyloReaderTheme
    @Binding var fontScale: Double
    @Binding var font: KhyloReaderFont
    @Binding var spacing: KhyloReaderSpacing
    @Binding var margins: KhyloReaderMargins
    @Binding var justified: Bool
    let showsTextOptions: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Paper")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 22)
                    .padding(.top, 22)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(KhyloReaderTheme.allCases) { option in
                            paperSwatch(option)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 2)
                }

                if showsTextOptions {
                    VStack(alignment: .leading, spacing: 18) {
                        sizeControl
                        fontPicker
                        HStack(spacing: 12) {
                            optionGroup("Spacing", KhyloReaderSpacing.allCases, selection: $spacing) { Text($0.title) }
                            optionGroup("Margins", KhyloReaderMargins.allCases, selection: $margins) { Text($0.title) }
                        }
                        Toggle(isOn: $justified) {
                            Text("Justify Text").font(.system(size: 15, weight: .medium))
                        }
                        .tint(KhyloStyle.accent)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func paperSwatch(_ option: KhyloReaderTheme) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) { theme = option }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    KhyloPaperBackground(theme: option)
                    Text("Aa")
                        .font(font.preview(size: 22))
                        .foregroundColor(option.foreground)
                }
                .frame(width: 70, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme == option ? KhyloStyle.accent : Color.gray.opacity(0.35), lineWidth: theme == option ? 2.5 : 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                Text(option.title)
                    .font(.system(size: 12, weight: theme == option ? .semibold : .medium))
                    .foregroundStyle(theme == option ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title) paper")
        .accessibilityAddTraits(theme == option ? .isSelected : [])
    }

    private var sizeControl: some View {
        HStack(spacing: 14) {
            Button {
                fontScale = max(0.7, (fontScale - 0.1).rounded(toPlaces: 1))
            } label: {
                Text("A").font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Smaller text")
            Slider(value: $fontScale, in: 0.7 ... 2.0, step: 0.05)
                .tint(KhyloStyle.accent)
            Button {
                fontScale = min(2.0, (fontScale + 0.1).rounded(toPlaces: 1))
            } label: {
                Text("A").font(.system(size: 22, weight: .semibold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Larger text")
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.gray.opacity(0.14)))
    }

    private var fontPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(KhyloReaderFont.allCases) { option in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        font = option
                    } label: {
                        VStack(spacing: 4) {
                            Text("Ag")
                                .font(option.preview(size: 22))
                            Text(option.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 84, height: 66)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.gray.opacity(font == option ? 0.22 : 0.1)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(font == option ? KhyloStyle.accent : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func optionGroup<Option: Identifiable & Hashable>(
        _ title: String,
        _ options: [Option],
        selection: Binding<Option>,
        @ViewBuilder label: @escaping (Option) -> Text
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    label(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = Foundation.pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - Chrome

struct KhyloReaderCloseButton: View {
    let theme: KhyloReaderTheme
    let action: () -> Void

    var body: some View {
        KhyloReaderIconButton(systemImage: "xmark", theme: theme, label: "Close", action: action)
    }
}

struct KhyloReaderIconButton: View {
    let systemImage: String
    let theme: KhyloReaderTheme
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.foreground)
                .frame(width: 40, height: 40)
                .background(Circle().fill(theme.foreground.opacity(0.08)))
                .overlay(Circle().strokeBorder(theme.foreground.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Top bar (close, title, actions) and a bottom bar with a scrubber, laid over
/// the page on the paper's own colour.
struct KhyloReaderChrome<Trailing: View>: View {

    let theme: KhyloReaderTheme
    let title: String
    let subtitle: String
    let progress: Double
    let status: String
    /// Called with a 0...1 position when the reader drags the scrubber.
    var onScrub: ((Double) -> Void)? = nil
    let onClose: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                KhyloReaderCloseButton(theme: theme, action: onClose)
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.55)
                            .lineLimit(1)
                    }
                }
                .foregroundColor(theme.foreground)
                .frame(maxWidth: .infinity)
                HStack(spacing: 8) { trailing() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .background(alignment: .top) { fade(edge: .top) }

            Spacer()

            VStack(spacing: 10) {
                if let onScrub {
                    Slider(
                        value: Binding(get: { scrubValue ?? progress }, set: { scrubValue = $0 }),
                        in: 0 ... 1
                    ) { editing in
                        if !editing, let value = scrubValue {
                            onScrub(value)
                            scrubValue = nil
                        }
                    }
                    .tint(KhyloStyle.accent)
                } else {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.foreground.opacity(0.14))
                            Capsule().fill(KhyloStyle.accent).frame(width: max(3, proxy.size.width * progress))
                        }
                    }
                    .frame(height: 3)
                }
                Text(scrubValue.map { "Go to \(Int(($0 * 100).rounded()))%" } ?? status)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(theme.foreground.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(alignment: .bottom) { fade(edge: .bottom) }
        }
        .transition(.opacity)
    }

    /// The paper colour fading into the page, so the bars float without a hard edge.
    private func fade(edge: VerticalEdge) -> some View {
        LinearGradient(
            stops: [
                .init(color: theme.background, location: 0),
                .init(color: theme.background.opacity(0.94), location: 0.7),
                .init(color: theme.background.opacity(0), location: 1),
            ],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .padding(edge == .top ? .bottom : .top, -24)
        .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
    }
}
