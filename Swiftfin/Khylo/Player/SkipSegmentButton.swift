//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Skip Segment Button View

public struct SkipSegmentButton: View {
    public let segment: KhyloSegment
    public let autoSkipCountdown: Int?
    public let onSkip: () -> Void
    public let onDismiss: (() -> Void)?

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    public init(
        segment: KhyloSegment,
        autoSkipCountdown: Int? = nil,
        onSkip: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.segment = segment
        self.autoSkipCountdown = autoSkipCountdown
        self.onSkip = onSkip
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onSkip()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: segment.type.iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(KhyloColors.accent)

                    if let countdown = autoSkipCountdown, countdown > 0 {
                        Text("\(segment.type.title) (\(countdown)s)")
                            .font(KhyloTypography.subheadlineBold)
                            .foregroundColor(.white)
                    } else {
                        Text(segment.type.title)
                            .font(KhyloTypography.subheadlineBold)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(KhyloColors.surfaceElevated.opacity(0.85))
                        .background(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isPressed ? 0.95 : 1.0)

            if let onDismiss {
                Button(action: {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(KhyloColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(KhyloColors.surfaceElevated.opacity(0.7))
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: autoSkipCountdown)
    }
}
