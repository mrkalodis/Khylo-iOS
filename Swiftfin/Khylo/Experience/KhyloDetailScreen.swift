//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

@MainActor
final class KhyloDetailModel: ObservableObject {

    @Published private(set) var item: BaseItemDto
    @Published private(set) var seasons: [BaseItemDto] = []
    @Published var selectedSeasonID: String?
    @Published private(set) var episodes: [BaseItemDto] = []
    @Published private(set) var isLoadingEpisodes = false
    @Published private(set) var nextEpisode: BaseItemDto?
    @Published private(set) var similar: [BaseItemDto] = []
    @Published var errorMessage: String?

    init(item: BaseItemDto) {
        self.item = item
    }

    var seriesID: String? {
        item.type == .series ? item.id : item.seriesID
    }

    func load() async {
        guard let id = item.id else { return }
        do {
            item = try await KhyloAPI.item(id)
        } catch {
            errorMessage = error.localizedDescription
        }

        async let similarItems = try? KhyloAPI.similar(to: id)

        if item.type == .series || item.type == .season {
            await loadSeasons()
        }
        if item.type == .series {
            nextEpisode = try? await KhyloAPI.nextUp(limit: 1, seriesID: id).first
        }
        similar = await similarItems ?? []
    }

    func refreshUserData() async {
        guard let id = item.id, let fresh = try? await KhyloAPI.item(id) else { return }
        item = fresh
        if item.type == .series {
            nextEpisode = try? await KhyloAPI.nextUp(limit: 1, seriesID: id).first
        }
        if let season = selectedSeasonID {
            await loadEpisodes(seasonID: season)
        }
    }

    private func loadSeasons() async {
        guard let seriesID else { return }
        seasons = (try? await KhyloAPI.seasons(seriesID: seriesID)) ?? []

        // Open on the season being watched, else the first real season.
        var initial: String?
        if item.type == .season {
            initial = item.id
        } else {
            if nextEpisode == nil {
                nextEpisode = try? await KhyloAPI.nextUp(limit: 1, seriesID: seriesID).first
            }
            initial = nextEpisode?.seasonID
                ?? seasons.first(where: { ($0.indexNumber ?? 0) > 0 })?.id
                ?? seasons.first?.id
        }

        if let initial {
            await selectSeason(initial)
        }
    }

    func selectSeason(_ id: String) async {
        selectedSeasonID = id
        await loadEpisodes(seasonID: id)
    }

    private func loadEpisodes(seasonID: String) async {
        guard let seriesID else { return }
        isLoadingEpisodes = episodes.isEmpty
        episodes = (try? await KhyloAPI.episodes(seriesID: seriesID, seasonID: seasonID)) ?? []
        isLoadingEpisodes = false
    }

    func toggleFavorite() async {
        guard let id = item.id else { return }
        let target = !item.khyloIsFavorite
        if let data = try? await KhyloAPI.setFavorite(target, itemID: id) {
            item.userData = data
        }
    }

    func togglePlayed() async {
        guard let id = item.id else { return }
        let target = !item.khyloIsPlayed
        if let data = try? await KhyloAPI.setPlayed(target, itemID: id) {
            item.userData = data
            await refreshUserData()
        }
    }

    func setEpisodePlayed(_ episode: BaseItemDto, _ played: Bool) async {
        guard let id = episode.id else { return }
        _ = try? await KhyloAPI.setPlayed(played, itemID: id)
        await refreshUserData()
    }
}

struct KhyloDetailScreen: View {

    @StateObject private var model: KhyloDetailModel
    @Router private var router
    @State private var isOverviewExpanded = false
    @State private var playError: String?

    init(item: BaseItemDto) {
        _model = StateObject(wrappedValue: KhyloDetailModel(item: item))
    }

    private var item: BaseItemDto { model.item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 28) {
                    primaryActions
                    overview

                    if !model.seasons.isEmpty {
                        episodesSection
                    }

                    if let people = item.people?.filter({ $0.id != nil }), !people.isEmpty {
                        castSection(people)
                    }

                    if !model.similar.isEmpty {
                        KhyloShelf(title: "More Like This") {
                            ForEach(model.similar, id: \.id) { similar in
                                Button {
                                    router.route(to: .khyloItem(similar))
                                } label: {
                                    KhyloCoverCard(item: similar, width: 112)
                                }
                                .buttonStyle(KhyloScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, -KhyloStyle.gutter)
                    }

                    details
                }
                .padding(.horizontal, KhyloStyle.gutter)
                .padding(.bottom, 48)
            }
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshUserData() }
        }
        .onAppear {
            // Returning from the player: pick up the new position.
            Task { await model.refreshUserData() }
        }
        .alert("Can't Play", isPresented: .constant(playError != nil), presenting: playError) { _ in
            Button("OK") { playError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            KhyloImage(url: KhyloArtwork.url(for: item, style: .backdrop, width: 1200))
                .frame(height: 440)
                .frame(maxWidth: .infinity)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: KhyloStyle.canvas.opacity(0.7), location: 0.7),
                    .init(color: KhyloStyle.canvas, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                if item.type == .episode, let series = item.seriesName {
                    Button {
                        openSeries()
                    } label: {
                        HStack(spacing: 4) {
                            Text(series)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KhyloStyle.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                if let logo = KhyloArtwork.url(for: item, style: .logo, width: 320), item.type != .episode {
                    KhyloImage(url: logo, contentMode: .fit, showsPlaceholder: false)
                        .frame(maxWidth: 270, maxHeight: 110)
                } else {
                    Text(item.name ?? "")
                        .font(.system(size: item.type == .episode ? 26 : 32, weight: .heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                metadataRow
            }
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.bottom, 8)
        }
        .frame(height: 440)
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            ForEach(metadataParts, id: \.self) { part in
                Text(part)
            }
            if let rating = item.officialRating {
                Text(rating)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
            }
            if let score = item.communityRating, score > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 10))
                    Text(String(format: "%.1f", score))
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(KhyloStyle.secondaryText)
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if let episode = item.khyloEpisodeLabel { parts.append(episode) }
        if let year = item.productionYear { parts.append(String(year)) }
        if item.type == .series, let count = item.childCount, count > 0 {
            parts.append(count == 1 ? "1 Season" : "\(count) Seasons")
        } else if let runtime = item.khyloRuntime {
            parts.append(runtime)
        }
        if let genre = item.genres?.prefix(2).joined(separator: ", "), !genre.isEmpty, item.type != .episode {
            parts.append(genre)
        }
        return parts
    }

    // MARK: - Actions

    private var playTarget: BaseItemDto {
        item.type == .series ? (model.nextEpisode ?? item) : item
    }

    private var playTitle: String {
        if item.type == .book { return "Read" }
        let target = playTarget
        let prefix = target.khyloProgress != nil ? "Resume" : "Play"
        if item.type == .series, let label = target.khyloEpisodeLabel {
            return "\(prefix) \(label)"
        }
        return prefix
    }

    private var primaryActions: some View {
        VStack(spacing: 14) {
            KhyloPlayButton(
                title: playTitle,
                systemImage: item.type == .book ? "book.fill" : "play.fill",
                progress: item.type == .book ? nil : playTarget.khyloProgress
            ) {
                startPlayback(from: .resume)
            }

            if let remaining = playTarget.khyloRemaining, item.type != .book {
                Text(remaining)
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.tertiaryText)
            }

            HStack(spacing: 28) {
                if playTarget.khyloProgress != nil, item.type != .book {
                    KhyloIconAction(title: "Start Over", systemImage: "arrow.counterclockwise") {
                        startPlayback(from: .beginning)
                    }
                }
                if item.type != .book {
                    KhyloIconAction(
                        title: item.khyloIsPlayed ? "Watched" : "Mark Watched",
                        systemImage: item.khyloIsPlayed ? "checkmark.circle.fill" : "checkmark.circle",
                        isActive: item.khyloIsPlayed
                    ) {
                        Task { await model.togglePlayed() }
                    }
                }
                KhyloIconAction(
                    title: item.khyloIsFavorite ? "Favorited" : "Favorite",
                    systemImage: item.khyloIsFavorite ? "heart.fill" : "heart",
                    isActive: item.khyloIsFavorite
                ) {
                    Task { await model.toggleFavorite() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private func startPlayback(from start: KhyloPlayback.StartPoint) {
        if item.type == .book {
            router.route(to: .khyloReader(item))
            return
        }
        Task {
            do {
                try await KhyloPlayback.play(playTarget, from: start, router: router)
            } catch {
                playError = error.localizedDescription
            }
        }
    }

    private func openSeries() {
        guard let id = item.seriesID else { return }
        Task {
            if let series = try? await KhyloAPI.item(id) {
                router.route(to: .khyloItem(series))
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overview: some View {
        if let overview = item.overview, !overview.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let tagline = item.taglines?.first, !tagline.isEmpty {
                    Text(tagline)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(overview)
                    .font(.system(size: 15))
                    .foregroundColor(KhyloStyle.secondaryText)
                    .lineSpacing(3)
                    .lineLimit(isOverviewExpanded ? nil : 4)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { isOverviewExpanded.toggle() }
                    }
            }
        }
    }

    // MARK: - Episodes

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.seasons, id: \.id) { season in
                        let isSelected = season.id == model.selectedSeasonID
                        Button {
                            guard let id = season.id else { return }
                            Task { await model.selectSeason(id) }
                        } label: {
                            Text(season.name ?? "Season")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isSelected ? .black : .white)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
            .padding(.horizontal, -KhyloStyle.gutter)

            if model.isLoadingEpisodes {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 22) {
                    ForEach(model.episodes, id: \.id) { episode in
                        KhyloEpisodeRow(episode: episode) {
                            Task {
                                do {
                                    try await KhyloPlayback.play(episode, router: router)
                                } catch {
                                    playError = error.localizedDescription
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                router.route(to: .khyloItem(episode))
                            } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                            Button {
                                Task { await model.setEpisodePlayed(episode, !episode.khyloIsPlayed) }
                            } label: {
                                Label(
                                    episode.khyloIsPlayed ? "Mark as Unwatched" : "Mark as Watched",
                                    systemImage: episode.khyloIsPlayed ? "circle" : "checkmark.circle"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cast

    private func castSection(_ people: [BaseItemPerson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(KhyloStyle.title(21))
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(people.prefix(20).enumerated()), id: \.offset) { _, person in
                        VStack(spacing: 8) {
                            KhyloImage(
                                url: person.id.flatMap {
                                    KhyloArtwork.url(itemID: $0, type: .primary, tag: person.primaryImageTag, width: 90)
                                },
                                placeholderSymbol: "person.fill"
                            )
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())

                            VStack(spacing: 2) {
                                Text(person.name ?? "")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                Text(person.role?.isEmpty == false ? person.role! : (person.type?.rawValue ?? ""))
                                    .font(.system(size: 11))
                                    .foregroundColor(KhyloStyle.tertiaryText)
                            }
                            .lineLimit(1)
                            .frame(width: 84)
                        }
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
            .padding(.horizontal, -KhyloStyle.gutter)
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var details: some View {
        let studios = item.studios?.compactMap(\.name) ?? []
        let directors = item.people?.filter { $0.type == .director }.compactMap(\.name) ?? []
        if !studios.isEmpty || !directors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider().overlay(KhyloStyle.hairline)
                if !directors.isEmpty {
                    detailLine("Directed by", directors.joined(separator: ", "))
                }
                if !studios.isEmpty {
                    detailLine("Studio", studios.prefix(3).joined(separator: ", "))
                }
            }
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(KhyloStyle.tertiaryText)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(KhyloStyle.secondaryText)
        }
    }
}

// MARK: - Episode Row

struct KhyloEpisodeRow: View {

    let episode: BaseItemDto
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: play) {
                HStack(spacing: 14) {
                    ZStack {
                        KhyloImage(
                            url: KhyloArtwork.url(for: episode, style: .landscape, width: 160),
                            placeholderSymbol: "play.rectangle"
                        )
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .frame(width: 140, height: 79)
                    .overlay(alignment: .bottom) {
                        if let progress = episode.khyloProgress {
                            KhyloProgressLine(progress: progress)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(episode.indexNumber.map { "\($0). \(episode.name ?? "")" } ?? episode.name ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if let runtime = episode.khyloRemaining ?? episode.khyloRuntime {
                                Text(runtime)
                            }
                            if episode.khyloIsPlayed {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(KhyloStyle.accent)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(KhyloScaleButtonStyle())

            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.secondaryText)
                    .lineLimit(3)
                    .lineSpacing(2)
            }
        }
    }
}
