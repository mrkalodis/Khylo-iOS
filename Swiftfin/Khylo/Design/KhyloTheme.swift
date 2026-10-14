//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Color Hex Initializer

extension Color {

    /// Parses a hexadecimal color string (e.g. `"#D97732"`, `"#1A1C1F"`, or `"#FFAA2200"`).
    /// Defaults to opaque black if parsing fails.
    fileprivate init(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }

        var hexNumber: UInt64 = 0
        let scanner = Scanner(string: cleanHex)
        guard scanner.scanHexInt64(&hexNumber) else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
            return
        }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch cleanHex.count {
        case 3: // RGB (12-bit)
            red = Double((hexNumber >> 8) & 0xF) / 15.0
            green = Double((hexNumber >> 4) & 0xF) / 15.0
            blue = Double(hexNumber & 0xF) / 15.0
            alpha = 1.0
        case 4: // RGBA (16-bit)
            red = Double((hexNumber >> 12) & 0xF) / 15.0
            green = Double((hexNumber >> 8) & 0xF) / 15.0
            blue = Double((hexNumber >> 4) & 0xF) / 15.0
            alpha = Double(hexNumber & 0xF) / 15.0
        case 6: // RRGGBB (24-bit)
            red = Double((hexNumber >> 16) & 0xFF) / 255.0
            green = Double((hexNumber >> 8) & 0xFF) / 255.0
            blue = Double(hexNumber & 0xFF) / 255.0
            alpha = 1.0
        case 8: // AARRGGBB (32-bit)
            alpha = Double((hexNumber >> 24) & 0xFF) / 255.0
            red = Double((hexNumber >> 16) & 0xFF) / 255.0
            green = Double((hexNumber >> 8) & 0xFF) / 255.0
            blue = Double(hexNumber & 0xFF) / 255.0
        default:
            red = 0
            green = 0
            blue = 0
            alpha = 1.0
        }

        self.init(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: alpha
        )
    }
}

// MARK: - Khylo Colors

public enum KhyloColors {
    /// Charcoal dark base background (`#08090A`).
    public static let background = Color(hex: "#08090A")

    /// Primary surface color (`#111214`).
    public static let surface = Color(hex: "#111214")

    /// Elevated surface for cards, sheets, and popups (`#1A1C1F`).
    public static let surfaceElevated = Color(hex: "#1A1C1F")

    /// Brand accent orange (`#D97732`).
    public static let accent = Color(hex: "#D97732")

    /// Dimmed accent orange for borders and secondary highlights (`#A85A22`).
    public static let accentDim = Color(hex: "#A85A22")

    /// High-contrast primary text (`#F4F4F5`).
    public static let textPrimary = Color(hex: "#F4F4F5")

    /// Subtle secondary text (`#9A9DA5`).
    public static let textSecondary = Color(hex: "#9A9DA5")

    /// Muted tertiary text and placeholders (`#555860`).
    public static let textTertiary = Color(hex: "#555860")

    /// Warm amber gold for audiobooks (`#E3A857`).
    public static let audiobookWarm = Color(hex: "#E3A857")

    /// Warm dark background for audiobook player (`#15100B`).
    public static let audiobookBackground = Color(hex: "#15100B")

    // Semantic aliases
    public static let border = Color(hex: "#22252A")
    public static let cardBackground = surface
    public static let unplayedDot = accent
}

// MARK: - Khylo Typography

public enum KhyloTypography {
    public static let largeTitle: Font = .system(size: 34, weight: .bold)
    public static let heroTitle: Font = .system(size: 32, weight: .bold)
    public static let title1: Font = .system(size: 24, weight: .bold)
    public static let title2: Font = .system(size: 20, weight: .semibold)
    public static let title3: Font = .system(size: 17, weight: .semibold)
    public static let headline: Font = .system(size: 16, weight: .semibold)
    public static let headlineBold: Font = .system(size: 16, weight: .bold)
    public static let body: Font = .system(size: 15, weight: .regular)
    public static let bodyMedium: Font = .system(size: 15, weight: .medium)
    public static let bodyBold: Font = .system(size: 15, weight: .bold)
    public static let callout: Font = .system(size: 14, weight: .medium)
    public static let subheadline: Font = .system(size: 13, weight: .regular)
    public static let subheadlineMedium: Font = .system(size: 13, weight: .medium)
    public static let subheadlineBold: Font = .system(size: 13, weight: .bold)
    public static let caption: Font = .system(size: 12, weight: .regular)
    public static let captionMedium: Font = .system(size: 12, weight: .medium)
    public static let captionBold: Font = .system(size: 12, weight: .bold)
    public static let caption2: Font = .system(size: 11, weight: .regular)
    public static let caption2Medium: Font = .system(size: 11, weight: .medium)
    public static let caption2Bold: Font = .system(size: 11, weight: .bold)
    public static let badge: Font = .system(size: 11, weight: .bold)
    public static let audiobookTitle: Font = .system(size: 22, weight: .bold, design: .serif)
}

// MARK: - Khylo Spacing

public enum KhyloSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

// MARK: - Khylo Radius

public enum KhyloRadius {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let full: CGFloat = 9999
    public static let pill: CGFloat = 9999
}

// MARK: - Khylo Theme Environment

public struct KhyloTheme: Equatable {
    public init() {}
}

private struct KhyloThemeKey: EnvironmentKey {
    static let defaultValue: KhyloTheme = KhyloTheme()
}

public extension EnvironmentValues {
    var khyloTheme: KhyloTheme {
        get { self[KhyloThemeKey.self] }
        set { self[KhyloThemeKey.self] = newValue }
    }
}

public extension View {
    func khyloTheme(_ theme: KhyloTheme = KhyloTheme()) -> some View {
        environment(\.khyloTheme, theme)
    }
}
