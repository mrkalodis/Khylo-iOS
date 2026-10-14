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

// MARK: - Person Card

public struct PersonCard: View {
    public let person: KhyloPerson
    public let onTap: () -> Void

    public init(person: KhyloPerson, onTap: @escaping () -> Void) {
        self.person = person
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onTap()
        } label: {
            VStack(spacing: KhyloSpacing.xs) {
                let photoUrl = person.imageURL(width: 200)
                AsyncImage(url: photoUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ZStack {
                            KhyloColors.surfaceElevated
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(KhyloColors.border, lineWidth: 1)
                )

                Text(person.name)
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 80)

                if let role = person.role {
                    Text(role)
                        .font(KhyloTypography.caption2)
                        .foregroundColor(KhyloColors.textSecondary)
                        .lineLimit(1)
                        .frame(width: 80)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Title Details View

public struct DetailsView: View {

    public let itemId: String

    @StateObject private var repository = KhyloRepository.shared
    @EnvironmentObject private var navigator: KhyloNavigator
    @EnvironmentObject private var ambientState: KhyloAmbientState

    @State private var item: KhyloMediaItem?
    @State private var castMembers: [KhyloPerson] = []
    @State private var seasons: [KhyloSeason] = []
    @State private var specs: TechnicalSpecs?
    @State private var similarItems: [KhyloMediaItem] = []
    @State private var isLoading: Bool = true
    @State private var isOverviewExpanded: Bool = false
    @State private var isFavorite: Bool = false
    @State private var selectedEpisodeForOptions: KhyloMediaItem?
    @State private var showOptionsSheet: Bool = false

    public init(itemId: String) {
        self.itemId = itemId
    }

    public var body: some View {
        ZStack(alignment: .top) {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Full-Bleed Backdrop Header
                    backdropHeader

                    // Main Details Body
                    VStack(alignment: .leading, spacing: KhyloSpacing.lg) {
                        // Title & Logo
                        titleSection

                        // Action Buttons (Play, Resume, My List)
                        actionButtonsRow

                        // Metadata Badges (Rating, Year, Resolution, Audio)
                        metadataBadgesRow

                        // Synopsis Overview
                        synopsisSection

                        // Cast & Crew Row
                        if !castMembers.isEmpty {
                            castSection
                        }

                        // Seasons & Episodes (if Series)
                        if let activeItem = item, (activeItem.type == "Series" || activeItem.type == "Show"), !seasons.isEmpty {
                            SeriesSeasonView(
                                seriesId: activeItem.id,
                                seasons: seasons,
                                onPlayEpisode: { ep in
                                    navigator.play(itemId: ep.id, resumePositionTicks: ep.playbackPositionTicks, title: "\(activeItem.name) - \(ep.name)")
                                },
                                onEpisodeOptions: { ep in
                                    selectedEpisodeForOptions = ep
                                    showOptionsSheet = true
                                }
                            )
                        }

                        // Technical Specifications Panel
                        if let specs {
                            technicalSpecsPanel(specs)
                        }

                        // More Like This Shelf
                        if !similarItems.isEmpty {
                            similarShelf
                        }
                    }
                    .padding(.top, KhyloSpacing.lg)
                    .padding(.bottom, 120)
                }
            }

            // Top Floating Navigation Bar
            topNavigationBar
        }
        .task {
            await loadDetails()
        }
        .sheet(isPresented: $showOptionsSheet) {
            if let ep = selectedEpisodeForOptions {
                ItemOptionsSheet(
                    item: ep,
                    isInContinueWatching: false,
                    isInNextUp: false,
                    onAction: { action in
                        handleOptionAction(action)
                    },
                    onDismiss: {
                        showOptionsSheet = false
                        selectedEpisodeForOptions = nil
                    }
                )
            }
        }
    }

    // MARK: - Backdrop Header

    private var backdropHeader: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                let backdropUrl = item?.backdropURL(width: 1440) ?? item?.posterURL(width: 1000)
                AsyncImage(url: backdropUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: 380)
                            .clipped()
                    default:
                        LinearGradient(
                            colors: [KhyloColors.surfaceElevated, KhyloColors.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }

                // Vertical scrim gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        KhyloColors.background.opacity(0.4),
                        KhyloColors.background.opacity(0.85),
                        KhyloColors.background
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(height: 380)
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack {
            Button {
                navigator.pop()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(KhyloColors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            Button {
                if let item {
                    Task {
                        isFavorite.toggle()
                        await repository.toggleFavorite(itemId: item.id, isFavorite: isFavorite)
                    }
                }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isFavorite ? Color.red : KhyloColors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
        .padding(.top, KhyloSpacing.md)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
            if let logoUrl = item?.logoURL(width: 600) {
                AsyncImage(url: logoUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 80, alignment: .leading)
                    default:
                        titleTextFallback
                    }
                }
            } else {
                titleTextFallback
            }

            if let genres = item?.genres, !genres.isEmpty {
                Text(genres.joined(separator: " • "))
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(KhyloColors.accent)
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
    }

    private var titleTextFallback: some View {
        Text(item?.name ?? "Title")
            .font(KhyloTypography.title1)
            .fontWeight(.heavy)
            .foregroundColor(KhyloColors.textPrimary)
    }

    // MARK: - Action Buttons

    private var actionButtonsRow: some View {
        HStack(spacing: KhyloSpacing.md) {
            // Play / Resume Button
            Button {
                if let item {
                    navigator.play(itemId: item.id, resumePositionTicks: item.playbackPositionTicks, title: item.name)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(item?.progress ?? 0 > 0 ? "Resume" : "Play")
                        .font(KhyloTypography.headline)
                }
                .foregroundColor(KhyloColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(KhyloColors.accent)
                .cornerRadius(KhyloRadius.sm)
            }

            // Trailer Button
            Button {
                // Trailer playback or secondary action
                if let item {
                    navigator.play(itemId: item.id, resumePositionTicks: 0, title: "\(item.name) (Trailer)")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 15))
                    Text("Trailer")
                        .font(KhyloTypography.bodyMedium)
                }
                .foregroundColor(KhyloColors.textPrimary)
                .frame(width: 110, height: 48)
                .background(KhyloColors.surfaceElevated)
                .cornerRadius(KhyloRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: KhyloRadius.sm)
                        .stroke(KhyloColors.border, lineWidth: 1)
                )
            }

            // My List Button
            Button {
                if let item {
                    Task {
                        isFavorite.toggle()
                        await repository.toggleFavorite(itemId: item.id, isFavorite: isFavorite)
                    }
                }
            } label: {
                Image(systemName: isFavorite ? "checkmark" : "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KhyloColors.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(KhyloColors.surfaceElevated)
                    .cornerRadius(KhyloRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: KhyloRadius.sm)
                            .stroke(KhyloColors.border, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
    }

    // MARK: - Metadata Badges

    private var metadataBadgesRow: some View {
        HStack(spacing: KhyloSpacing.sm) {
            if let rating = item?.communityRating, rating > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(KhyloTypography.captionMedium)
                        .foregroundColor(KhyloColors.textPrimary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(KhyloColors.surfaceElevated)
                .cornerRadius(4)
            }

            if let cert = item?.officialRating, !cert.isEmpty {
                Text(cert)
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(KhyloColors.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(4)
            }

            if let year = item?.productionYear {
                Text("\(year)")
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
            }

            if let duration = item?.durationString, !duration.isEmpty {
                Text(duration)
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
            }

            if let res = specs?.resolution {
                Text(res)
                    .font(KhyloTypography.caption2Medium)
                    .foregroundColor(KhyloColors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KhyloColors.accent.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
    }

    // MARK: - Synopsis Section

    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
            if let overview = item?.overview, !overview.isEmpty {
                Text(overview)
                    .font(KhyloTypography.body)
                    .foregroundColor(KhyloColors.textSecondary)
                    .lineLimit(isOverviewExpanded ? nil : 3)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isOverviewExpanded.toggle()
                    }
                } label: {
                    Text(isOverviewExpanded ? "Show Less" : "See More")
                        .font(KhyloTypography.captionMedium)
                        .foregroundColor(KhyloColors.accent)
                }
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
    }

    // MARK: - Cast & Crew

    private var castSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            Text("Cast & Crew")
                .font(KhyloTypography.title3)
                .foregroundColor(KhyloColors.textPrimary)
                .padding(.horizontal, KhyloSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: KhyloSpacing.md) {
                    ForEach(castMembers) { person in
                        PersonCard(person: person) {
                            navigator.push(.personDetail(personId: person.id, name: person.name))
                        }
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)
            }
        }
    }

    // MARK: - Technical Specs Panel

    private func technicalSpecsPanel(_ specs: TechnicalSpecs) -> some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            Text("Technical Specifications")
                .font(KhyloTypography.title3)
                .foregroundColor(KhyloColors.textPrimary)
                .padding(.horizontal, KhyloSpacing.lg)

            VStack(spacing: KhyloSpacing.xs) {
                if let codec = specs.videoCodec {
                    specRow(label: "Video Codec", value: codec)
                }
                if let container = specs.container {
                    specRow(label: "Container", value: container)
                }
                if let bitrate = specs.formattedBitrate {
                    specRow(label: "Bitrate", value: bitrate)
                }
                if !specs.audioStreams.isEmpty {
                    specRow(label: "Audio Streams", value: specs.audioStreams.joined(separator: "\n"))
                }
                if !specs.subtitleStreams.isEmpty {
                    specRow(label: "Subtitles", value: specs.subtitleStreams.joined(separator: ", "))
                }
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.sm)
            .padding(.horizontal, KhyloSpacing.lg)
        }
    }

    private func specRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(KhyloTypography.caption)
                .foregroundColor(KhyloColors.textTertiary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(KhyloTypography.captionMedium)
                .foregroundColor(KhyloColors.textPrimary)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Similar Titles Shelf

    private var similarShelf: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            Text("More Like This")
                .font(KhyloTypography.title3)
                .foregroundColor(KhyloColors.textPrimary)
                .padding(.horizontal, KhyloSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: KhyloSpacing.md) {
                    ForEach(similarItems) { sim in
                        KhyloPosterCard(
                            imageURL: sim.posterURL() ?? sim.backdropURL(),
                            title: sim.name,
                            subtitle: sim.displaySubtitle,
                            width: 130,
                            onTap: {
                                if sim.type == "Series" || sim.type == "Show" {
                                    navigator.push(.seriesDetail(seriesId: sim.seriesId ?? sim.id))
                                } else {
                                    navigator.push(.itemDetail(itemId: sim.id))
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)
            }
        }
    }

    // MARK: - Load & Actions

    private func loadDetails() async {
        isLoading = true
        let (fetchedItem, people, fetchedSeasons, fetchedSpecs, similar) = await repository.fetchItemDetails(itemId: itemId)
        await MainActor.run {
            self.item = fetchedItem
            self.castMembers = people
            self.seasons = fetchedSeasons
            self.specs = fetchedSpecs
            self.similarItems = similar
            self.isFavorite = fetchedItem?.isFavorite ?? false
            self.isLoading = false

            if let firstGenre = fetchedItem?.genres.first {
                ambientState.tint(GenreColors.color(for: firstGenre))
            }
        }
    }

    private func handleOptionAction(_ action: ItemOptionAction) {
        switch action {
        case .resume(let ep):
            navigator.play(itemId: ep.id, resumePositionTicks: ep.playbackPositionTicks, title: ep.name)
        case .playFromBeginning(let ep):
            navigator.play(itemId: ep.id, resumePositionTicks: 0, title: ep.name)
        case .goToSeries(let sId):
            navigator.push(.seriesDetail(seriesId: sId))
        case .toggleWatched(let ep):
            Task { await repository.markPlayed(itemId: ep.id, isPlayed: !ep.isPlayed) }
        case .toggleFavorite(let ep):
            Task { await repository.toggleFavorite(itemId: ep.id, isFavorite: !ep.isFavorite) }
        case .hideFromUpNext(let sId):
            repository.dismissFromNextUp(seriesId: sId)
        case .removeFromContinueWatching(let epId):
            Task { await repository.markPlayed(itemId: epId, isPlayed: true) }
        case .viewDetails(let ep):
            navigator.push(.itemDetail(itemId: ep.id))
        }
    }
}
