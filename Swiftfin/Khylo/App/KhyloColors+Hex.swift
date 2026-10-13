//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

public extension Color {

    /// Initializes a SwiftUI `Color` from a hexadecimal string.
    /// Handles 3-digit (`#RGB`), 4-digit (`#RGBA`), 6-digit (`#RRGGBB`),
    /// and 8-digit (`#AARRGGBB`) hex codes with or without the `#` prefix.
    ///
    /// - Parameter hex: The hexadecimal color string (e.g., `"#D97732"`, `"#FFD97732"`).
    /// - Returns: A valid `Color` or `nil` if the hex string is invalid.
    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }

        var hexNumber: UInt64 = 0
        let scanner = Scanner(string: cleanHex)
        guard scanner.scanHexInt64(&hexNumber) else {
            return nil
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
            return nil
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
