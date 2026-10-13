//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Genre Gradient

public struct GenreGradient: Equatable, Hashable, Sendable {
    public let leading: Color
    public let trailing: Color

    public init(leading: Color, trailing: Color) {
        self.leading = leading
        self.trailing = trailing
    }

    /// Converts the pair to a SwiftUI `LinearGradient`.
    public func asLinearGradient(
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        LinearGradient(
            colors: [leading, trailing],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}

// MARK: - Color Helper

private extension Color {
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255.0, green: g / 255.0, blue: b / 255.0, opacity: 1.0)
    }
}

// MARK: - Genre Colors

public enum GenreColors {

    // Preset cinematic gradient pairs
    private static let action = GenreGradient(
        leading: .rgb(185, 28, 28),
        trailing: .rgb(217, 119, 50)
    )
    private static let adventure = GenreGradient(
        leading: .rgb(30, 58, 138),
        trailing: .rgb(4, 120, 87)
    )
    private static let animation = GenreGradient(
        leading: .rgb(124, 58, 237),
        trailing: .rgb(236, 72, 153)
    )
    private static let comedy = GenreGradient(
        leading: .rgb(217, 119, 6),
        trailing: .rgb(245, 158, 11)
    )
    private static let crime = GenreGradient(
        leading: .rgb(39, 39, 42),
        trailing: .rgb(127, 29, 29)
    )
    private static let documentary = GenreGradient(
        leading: .rgb(6, 78, 59),
        trailing: .rgb(59, 130, 246)
    )
    private static let drama = GenreGradient(
        leading: .rgb(49, 46, 129),
        trailing: .rgb(131, 24, 67)
    )
    private static let fantasy = GenreGradient(
        leading: .rgb(88, 28, 135),
        trailing: .rgb(14, 116, 144)
    )
    private static let horror = GenreGradient(
        leading: .rgb(69, 10, 10),
        trailing: .rgb(28, 25, 23)
    )
    private static let music = GenreGradient(
        leading: .rgb(147, 51, 234),
        trailing: .rgb(192, 38, 211)
    )
    private static let mystery = GenreGradient(
        leading: .rgb(30, 41, 59),
        trailing: .rgb(76, 29, 149)
    )
    private static let romance = GenreGradient(
        leading: .rgb(157, 23, 77),
        trailing: .rgb(225, 29, 72)
    )
    private static let scienceFiction = GenreGradient(
        leading: .rgb(3, 105, 161),
        trailing: .rgb(2, 132, 199)
    )
    private static let thriller = GenreGradient(
        leading: .rgb(31, 41, 55),
        trailing: .rgb(153, 27, 27)
    )
    private static let western = GenreGradient(
        leading: .rgb(120, 53, 15),
        trailing: .rgb(217, 119, 50)
    )
    private static let family = GenreGradient(
        leading: .rgb(4, 120, 87),
        trailing: .rgb(245, 158, 11)
    )
    private static let history = GenreGradient(
        leading: .rgb(69, 26, 3),
        trailing: .rgb(120, 53, 15)
    )
    private static let war = GenreGradient(
        leading: .rgb(54, 83, 20),
        trailing: .rgb(41, 37, 36)
    )
    private static let sport = GenreGradient(
        leading: .rgb(30, 64, 175),
        trailing: .rgb(21, 128, 61)
    )

    // Fallback gradients for unknown/custom genres
    private static let deterministicFallbacks: [GenreGradient] = [
        GenreGradient(leading: .rgb(51, 65, 85), trailing: .rgb(30, 41, 59)),
        GenreGradient(leading: .rgb(88, 28, 135), trailing: .rgb(49, 46, 129)),
        GenreGradient(leading: .rgb(15, 118, 110), trailing: .rgb(17, 94, 89)),
        GenreGradient(leading: .rgb(180, 83, 9), trailing: .rgb(146, 64, 14)),
        GenreGradient(leading: .rgb(71, 85, 105), trailing: .rgb(100, 116, 139)),
        GenreGradient(leading: .rgb(190, 24, 93), trailing: .rgb(157, 23, 77)),
        GenreGradient(leading: .rgb(3, 105, 161), trailing: .rgb(30, 58, 138)),
        GenreGradient(leading: .rgb(127, 29, 29), trailing: .rgb(69, 10, 10))
    ]

    /// Maps a genre string to a rich, dark cinematic gradient pair.
    ///
    /// - Parameter genre: The name of the genre (e.g. "Action", "Drama", "Sci-Fi").
    /// - Returns: A `GenreGradient` pair suitable for posters, badges, and backdrops.
    public static func gradient(for genre: String) -> GenreGradient {
        let normalized = genre
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "action":
            return action
        case "adventure":
            return adventure
        case "animation":
            return animation
        case "comedy":
            return comedy
        case "crime":
            return crime
        case "documentary":
            return documentary
        case "drama":
            return drama
        case "fantasy":
            return fantasy
        case "horror":
            return horror
        case "music", "musical":
            return music
        case "mystery":
            return mystery
        case "romance", "romantic":
            return romance
        case "science fiction", "sci-fi", "scifi":
            return scienceFiction
        case "thriller", "suspense":
            return thriller
        case "western":
            return western
        case "family", "kids", "children":
            return family
        case "history", "historical", "biography":
            return history
        case "war", "military":
            return war
        case "sport", "sports":
            return sport
        default:
            return fallbackGradient(for: normalized)
        }
    }

    private static func fallbackGradient(for genre: String) -> GenreGradient {
        var hash: UInt64 = 5381
        for byte in genre.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(deterministicFallbacks.count))
        return deterministicFallbacks[index]
    }
}
