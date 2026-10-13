//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Equalizer Bars View

public struct EqualizerBarsView: View {
    public let isPlaying: Bool
    public let barColor: Color
    public let barWidth: CGFloat
    public let maxHeight: CGFloat

    @State private var barHeights: [CGFloat] = [0.3, 0.6, 0.9, 0.5, 0.2]
    @State private var timerActive: Bool = false
    @State private var timer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    public init(
        isPlaying: Bool,
        barColor: Color = Color(red: 217/255, green: 119/255, blue: 50/255), // #D97732
        barWidth: CGFloat = 3.5,
        maxHeight: CGFloat = 20.0
    ) {
        self.isPlaying = isPlaying
        self.barColor = barColor
        self.barWidth = barWidth
        self.maxHeight = maxHeight
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(barColor)
                    .frame(
                        width: barWidth,
                        height: isPlaying ? max(barHeights[index] * maxHeight, 4.0) : 4.0
                    )
                    .animation(
                        .easeInOut(duration: 0.18),
                        value: barHeights[index]
                    )
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .onReceive(timer) { _ in
            guard isPlaying else { return }
            randomizeBars()
        }
        .onChange(of: isPlaying) { playing in
            if !playing {
                barHeights = [0.2, 0.2, 0.2, 0.2, 0.2]
            } else {
                randomizeBars()
            }
        }
    }

    private func randomizeBars() {
        barHeights = [
            CGFloat.random(in: 0.25...0.95),
            CGFloat.random(in: 0.4...1.0),
            CGFloat.random(in: 0.3...0.9),
            CGFloat.random(in: 0.5...1.0),
            CGFloat.random(in: 0.2...0.85)
        ]
    }
}
