//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Ken Burns View

public struct KenBurnsView: View {
    public let imageURL: URL?
    public let duration: Double
    public let maxScale: CGFloat

    @State private var isAnimating: Bool = false
    @State private var currentImageURL: URL?

    public init(
        imageURL: URL?,
        duration: Double = 18.0,
        maxScale: CGFloat = 1.14
    ) {
        self.imageURL = imageURL
        self.duration = duration
        self.maxScale = maxScale
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background base color
                Color.black

                // Ken Burns Animated Image
                if let url = imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .scaleEffect(isAnimating ? maxScale : 1.0)
                                .offset(
                                    x: isAnimating ? -geometry.size.width * 0.04 : geometry.size.width * 0.04,
                                    y: isAnimating ? -geometry.size.height * 0.03 : geometry.size.height * 0.03
                                )
                                .animation(
                                    Animation.easeInOut(duration: duration)
                                        .repeatForever(autoreverses: true),
                                    value: isAnimating
                                )
                        case .failure, .empty:
                            fallbackGradient(in: geometry.size)
                        @unknown default:
                            fallbackGradient(in: geometry.size)
                        }
                    }
                } else {
                    fallbackGradient(in: geometry.size)
                }

                // Vignette & Darkness Scrim
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.4),
                        Color.black.opacity(0.85)
                    ],
                    center: .center,
                    startRadius: 80,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.7
                )

                // Top & Bottom Readability Gradients
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.8),
                        Color.black.opacity(0.2),
                        Color.clear,
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .ignoresSafeArea()
            .onAppear {
                isAnimating = true
            }
        }
    }

    private func fallbackGradient(in size: CGSize) -> some View {
        LinearGradient(
            colors: [
                KhyloColors.surfaceElevated,
                KhyloColors.background,
                KhyloColors.accent.opacity(0.18)
            ],
            startPoint: isAnimating ? .topLeading : .bottomTrailing,
            endPoint: isAnimating ? .bottomTrailing : .topLeading
        )
        .frame(width: size.width, height: size.height)
        .scaleEffect(isAnimating ? maxScale : 1.0)
        .animation(
            Animation.easeInOut(duration: duration)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
    }
}
