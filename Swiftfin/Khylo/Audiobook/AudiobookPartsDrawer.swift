//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Audiobook Parts Drawer

public struct AudiobookPartsDrawer: View {
    public let parts: [AudiobookPart]
    public let currentPartIndex: Int
    public let onSelectPart: (Int) -> Void
    public let onDismiss: () -> Void

    private let warmBackground = Color(red: 21/255, green: 16/255, blue: 11/255) // #15100B
    private let warmAmber = Color(red: 227/255, green: 168/255, blue: 87/255) // #E3A857
    private let warmSurface = Color(red: 32/255, green: 25/255, blue: 18/255)

    public init(
        parts: [AudiobookPart],
        currentPartIndex: Int,
        onSelectPart: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.parts = parts
        self.currentPartIndex = currentPartIndex
        self.onSelectPart = onSelectPart
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                warmBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                            AudiobookPartRow(
                                part: part,
                                index: index,
                                isCurrent: index == currentPartIndex,
                                warmAmber: warmAmber,
                                warmSurface: warmSurface,
                                onSelect: {
                                    onSelectPart(index)
                                    onDismiss()
                                }
                            )
                        }
                    }
                    .padding(KhyloSpacing.md)
                }
            }
            .navigationTitle("Chapters & Parts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(warmAmber)
                }
            }
        }
    }
}

// MARK: - Audiobook Part Row

private struct AudiobookPartRow: View {
    let part: AudiobookPart
    let index: Int
    let isCurrent: Bool
    let warmAmber: Color
    let warmSurface: Color
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            HStack(spacing: 14) {
                // Part Index / Playing Indicator
                ZStack {
                    if isCurrent {
                        Circle()
                            .fill(warmAmber.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(warmAmber)
                    } else {
                        Text("\(part.partNumber)")
                            .font(KhyloTypography.bodyMedium)
                            .foregroundColor(Color.white.opacity(0.6))
                            .frame(width: 36, height: 36)
                    }
                }

                // Title & Progress Bar
                VStack(alignment: .leading, spacing: 6) {
                    Text(part.title)
                        .font(isCurrent ? KhyloTypography.headline : KhyloTypography.bodyMedium)
                        .foregroundColor(isCurrent ? warmAmber : .white)
                        .lineLimit(1)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 3)

                            Capsule()
                                .fill(warmAmber)
                                .frame(width: geometry.size.width * CGFloat(part.progress), height: 3)
                        }
                    }
                    .frame(height: 3)
                }

                Spacer()

                // Duration
                Text(part.durationFormatted)
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(Color.white.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                    .fill(isCurrent ? warmSurface : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: KhyloRadius.sm)
                            .strokeBorder(isCurrent ? warmAmber.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
