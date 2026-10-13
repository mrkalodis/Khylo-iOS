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

// MARK: - Series Season View

public struct SeriesSeasonView: View {

    public let seriesId: String
    public let seasons: [KhyloSeason]
    public let onPlayEpisode: (KhyloMediaItem) -> Void
    public let onEpisodeOptions: (KhyloMediaItem) -> Void

    @State private var selectedSeasonIndex: Int = 0

    public init(
        seriesId: String,
        seasons: [KhyloSeason],
        onPlayEpisode: @escaping (KhyloMediaItem) -> Void,
        onEpisodeOptions: @escaping (KhyloMediaItem) -> Void
    ) {
        self.seriesId = seriesId
        self.seasons = seasons
        self.onPlayEpisode = onPlayEpisode
        self.onEpisodeOptions = onEpisodeOptions
    }

    public var body: some View {
        if seasons.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: KhyloSpacing.md) {
                // Season Selector Menu / Horizontal Pills
                HStack {
                    Menu {
                        ForEach(Array(seasons.enumerated()), id: \.element.id) { index, season in
                            Button(action: {
                                selectedSeasonIndex = index
                            }) {
                                HStack {
                                    Text(season.name)
                                    if index == selectedSeasonIndex {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentSeason.name)
                                .font(KhyloTypography.title3)
                                .foregroundColor(KhyloColors.textPrimary)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(KhyloColors.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(KhyloColors.surfaceElevated)
                        .cornerRadius(KhyloRadius.sm)
                    }

                    Spacer()

                    Text("\(currentSeason.episodes.count) episodes")
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textTertiary)
                }
                .padding(.horizontal, KhyloSpacing.lg)

                // Episode Cards List
                VStack(spacing: KhyloSpacing.md) {
                    ForEach(currentSeason.episodes) { episode in
                        episodeCard(for: episode)
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)
            }
        }
    }

    private var currentSeason: KhyloSeason {
        guard seasons.indices.contains(selectedSeasonIndex) else {
            return seasons[0]
        }
        return seasons[selectedSeasonIndex]
    }

    // MARK: - Episode Card

    @ViewBuilder
    private func episodeCard(for episode: KhyloMediaItem) -> some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            HStack(alignment: .top, spacing: KhyloSpacing.md) {
                // 16:9 Thumbnail
                ZStack(alignment: .bottom) {
                    let thumbUrl = episode.backdropURL() ?? episode.posterURL()
                    AsyncImage(url: thumbUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            ZStack {
                                KhyloColors.surfaceElevated
                                Image(systemName: "play.tv")
                                    .foregroundColor(KhyloColors.textTertiary)
                            }
                        }
                    }
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: KhyloRadius.sm))

                    if episode.progress > 0 {
                        KhyloProgressBar(
                            progress: episode.progress,
                            height: 3,
                            trackColor: Color.black.opacity(0.6),
                            fillColor: KhyloColors.accent
                        )
                        .padding(.horizontal, 2)
                        .padding(.bottom, 2)
                    }

                    // Play icon overlay
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 120, height: 68)

                // Titles & Duration
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        if let epNum = episode.episodeNumber {
                            Text("\(epNum).")
                                .font(KhyloTypography.bodyMedium)
                                .foregroundColor(KhyloColors.accent)
                        }

                        Text(episode.name)
                            .font(KhyloTypography.bodyMedium)
                            .foregroundColor(KhyloColors.textPrimary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if !episode.durationString.isEmpty {
                            Text(episode.durationString)
                                .font(KhyloTypography.caption)
                                .foregroundColor(KhyloColors.textTertiary)
                        }

                        if episode.isPlayed {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Watched")
                                    .font(KhyloTypography.caption2Medium)
                            }
                            .foregroundColor(Color.green)
                        }
                    }
                }

                Spacer()

                // Options trigger button
                Button(action: {
                    onEpisodeOptions(episode)
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(KhyloColors.textTertiary)
                        .frame(width: 32, height: 32)
                }
            }

            // Overview Synopsis
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(KhyloSpacing.md)
        .background(KhyloColors.surface)
        .cornerRadius(KhyloRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: KhyloRadius.sm)
                .stroke(KhyloColors.border.opacity(0.4), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onPlayEpisode(episode)
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onEpisodeOptions(episode)
        }
    }
}
