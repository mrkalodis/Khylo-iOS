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

// MARK: - Item Option Action

public enum ItemOptionAction {
    case resume(KhyloMediaItem)
    case playFromBeginning(KhyloMediaItem)
    case goToSeries(seriesId: String)
    case toggleWatched(KhyloMediaItem)
    case toggleFavorite(KhyloMediaItem)
    case hideFromUpNext(seriesId: String)
    case removeFromContinueWatching(itemId: String)
    case viewDetails(KhyloMediaItem)
}

// MARK: - Item Options Sheet

public struct ItemOptionsSheet: View {

    public let item: KhyloMediaItem
    public let isInContinueWatching: Bool
    public let isInNextUp: Bool
    public let onAction: (ItemOptionAction) -> Void
    public let onDismiss: () -> Void

    public init(
        item: KhyloMediaItem,
        isInContinueWatching: Bool = false,
        isInNextUp: Bool = false,
        onAction: @escaping (ItemOptionAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.isInContinueWatching = isInContinueWatching
        self.isInNextUp = isInNextUp
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(KhyloColors.textTertiary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, KhyloSpacing.sm)
                .padding(.bottom, KhyloSpacing.md)

            // Header: Artwork + Titles
            HStack(spacing: KhyloSpacing.md) {
                // Artwork thumbnail
                let artUrl = item.backdropURL() ?? item.posterURL()
                AsyncImage(url: artUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ZStack {
                            KhyloColors.surfaceElevated
                            Image(systemName: item.type == "Episode" ? "tv" : "film")
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                    }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: KhyloRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: KhyloRadius.sm)
                        .stroke(KhyloColors.border.opacity(0.5), lineWidth: 1)
                )

                // Title & Metadata
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(KhyloTypography.headline)
                        .foregroundColor(KhyloColors.textPrimary)
                        .lineLimit(1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                            .lineLimit(1)
                    }

                    if item.progress > 0 {
                        KhyloProgressBar(
                            progress: item.progress,
                            height: 3,
                            trackColor: Color.white.opacity(0.15),
                            fillColor: KhyloColors.accent
                        )
                        .padding(.top, 2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.bottom, KhyloSpacing.lg)

            Divider()
                .background(KhyloColors.border.opacity(0.6))

            // Action Options List
            ScrollView {
                VStack(spacing: 4) {
                    // Resume if in progress
                    if item.progress > 0 {
                        optionRow(
                            icon: "play.circle.fill",
                            title: "Resume",
                            subtitle: formattedResumeTime(ticks: item.playbackPositionTicks),
                            accentColor: KhyloColors.accent
                        ) {
                            triggerAction(.resume(item))
                        }

                        optionRow(
                            icon: "backward.end.fill",
                            title: "Play from Beginning"
                        ) {
                            triggerAction(.playFromBeginning(item))
                        }
                    } else {
                        optionRow(
                            icon: "play.fill",
                            title: "Play",
                            accentColor: KhyloColors.accent
                        ) {
                            triggerAction(.playFromBeginning(item))
                        }
                    }

                    // Series details
                    if let seriesId = item.seriesId {
                        optionRow(
                            icon: "rectangle.stack.fill",
                            title: "Go to Series"
                        ) {
                            triggerAction(.goToSeries(seriesId: seriesId))
                        }
                    }

                    // Details
                    optionRow(
                        icon: "info.circle",
                        title: "View Details"
                    ) {
                        triggerAction(.viewDetails(item))
                    }

                    // Watched / Unwatched
                    optionRow(
                        icon: item.isPlayed ? "arrow.uturn.backward.circle" : "checkmark.circle",
                        title: item.isPlayed ? "Mark as Unwatched" : "Mark as Watched"
                    ) {
                        triggerAction(.toggleWatched(item))
                    }

                    // Favorite / List
                    optionRow(
                        icon: item.isFavorite ? "heart.slash" : "heart",
                        title: item.isFavorite ? "Remove from Favorites" : "Add to Favorites"
                    ) {
                        triggerAction(.toggleFavorite(item))
                    }

                    // Hide from Up Next
                    if isInNextUp, let seriesId = item.seriesId {
                        optionRow(
                            icon: "eye.slash",
                            title: "Hide from Up Next",
                            destructive: true
                        ) {
                            triggerAction(.hideFromUpNext(seriesId: seriesId))
                        }
                    }

                    // Remove from Continue Watching
                    if isInContinueWatching {
                        optionRow(
                            icon: "xmark.circle",
                            title: "Remove from Continue Watching",
                            destructive: true
                        ) {
                            triggerAction(.removeFromContinueWatching(itemId: item.id))
                        }
                    }
                }
                .padding(.vertical, KhyloSpacing.sm)
            }
        }
        .background(KhyloColors.surface)
        .presentationDetents([.fraction(0.55), .medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func optionRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        accentColor: Color? = nil,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { action() }) {
            HStack(spacing: KhyloSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(destructive ? .red : (accentColor ?? KhyloColors.textSecondary))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KhyloTypography.bodyMedium)
                        .foregroundColor(destructive ? .red : KhyloColors.textPrimary)

                    if let subtitle {
                        Text(subtitle)
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textTertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.vertical, KhyloSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    private func triggerAction(_ action: ItemOptionAction) {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        onAction(action)
        onDismiss()
    }

    private func formattedResumeTime(ticks: Int64?) -> String {
        guard let ticks, ticks > 0 else { return "" }
        let totalSeconds = Int(ticks / 10_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
