//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Next Up Row

public struct NextUpRow: View {

    public let items: [KhyloMediaItem]
    public let onSelect: (KhyloMediaItem) -> Void
    public let onLongPress: (KhyloMediaItem) -> Void
    public let onDismissSeries: ((String) -> Void)?

    public init(
        items: [KhyloMediaItem],
        onSelect: @escaping (KhyloMediaItem) -> Void,
        onLongPress: @escaping (KhyloMediaItem) -> Void,
        onDismissSeries: ((String) -> Void)? = nil
    ) {
        self.items = items
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        self.onDismissSeries = onDismissSeries
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text("Next Up")
                            .font(KhyloTypography.title3)
                            .foregroundColor(KhyloColors.textPrimary)

                        Circle()
                            .fill(KhyloColors.accent)
                            .frame(width: 6, height: 6)
                    }

                    Spacer()
                }
                .padding(.horizontal, KhyloSpacing.lg)

                // 16:9 Horizontal Row
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: KhyloSpacing.md) {
                        ForEach(items) { item in
                            nextUpCard(for: item)
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                }
            }
        }
    }

    // MARK: - Next Up Card

    @ViewBuilder
    private func nextUpCard(for item: KhyloMediaItem) -> some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                // Artwork
                GeometryReader { proxy in
                    let artUrl = item.backdropURL() ?? item.posterURL()
                    AsyncImage(url: artUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        default:
                            ZStack {
                                KhyloColors.surfaceElevated
                                Image(systemName: "tv")
                                    .font(.system(size: 24))
                                    .foregroundColor(KhyloColors.textTertiary)
                            }
                        }
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(KhyloColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: KhyloRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KhyloRadius.md, style: .continuous)
                        .stroke(KhyloColors.border.opacity(0.6), lineWidth: 1)
                )

                // Play overlay pill
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(item.durationString.isEmpty ? "Play" : item.durationString)
                        .font(KhyloTypography.caption2Medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.72))
                .foregroundColor(KhyloColors.textPrimary)
                .cornerRadius(4)
                .padding(8)
            }

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(item.seriesName ?? item.name)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let epSub = item.formattedEpisodeSubtitle {
                        Text(epSub)
                            .font(KhyloTypography.captionMedium)
                            .foregroundColor(KhyloColors.accent)
                    }

                    if let name = item.seriesName != nil ? item.name : nil {
                        Text("•")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textTertiary)
                        Text(name)
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .frame(width: 260)
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect(item)
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onLongPress(item)
        }
    }
}
