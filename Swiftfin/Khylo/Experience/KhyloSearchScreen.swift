//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

/// Search with a frosted field, recent searches and genre browsing when idle,
/// and results grouped by kind with a featured top hit.
struct KhyloSearchScreen: View {

    @State private var query = ""
    @State private var results: [BaseItemDto] = []
    @State private var isSearching = false
    @State private var genres: [BaseItemDto] = []
    @AppStorage("khylo.search.recent") private var recentStorage = ""
    @FocusState private var isFieldFocused: Bool
    @Router private var router

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var recent: [String] {
        recentStorage.split(separator: "\n").map(String.init)
    }

    var body: some View {
        ZStack(alignment: .top) {
            KhyloStyle.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if trimmed.isEmpty {
                        idleContent
                    } else if isSearching && results.isEmpty {
                        ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 60)
                    } else if results.isEmpty {
                        KhyloEmptyState(
                            systemImage: "magnifyingglass",
                            title: "No results",
                            message: "Nothing matches \u{201C}\(trimmed)\u{201D}. Check the spelling or try another title."
                        )
                        .padding(.top, 20)
                    } else {
                        resultsContent
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            if genres.isEmpty { genres = (try? await KhyloAPI.genres()) ?? [] }
        }
        .task(id: trimmed) {
            guard !trimmed.isEmpty else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = (try? await KhyloAPI.search(trimmed)) ?? []
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { results = found }
            isSearching = false
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Search")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                KhyloProfileButton()
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KhyloStyle.secondaryText)
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Movies, shows, books, music").foregroundColor(KhyloStyle.tertiaryText)
                )
                .font(.system(size: 17))
                .foregroundColor(.white)
                .tint(KhyloStyle.accent)
                .focused($isFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { remember(trimmed) }

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isFieldFocused ? KhyloStyle.accent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.15), value: isFieldFocused)
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.top, 8)
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleContent: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent")
                        .font(KhyloStyle.title(20))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Clear") { recentStorage = "" }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KhyloStyle.accent)
                }
                ForEach(recent, id: \.self) { term in
                    Button {
                        query = term
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(KhyloStyle.tertiaryText)
                            Text(term)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(KhyloStyle.tertiaryText)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KhyloStyle.gutter)
        }

        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Browse by Genre")
                    .font(KhyloStyle.title(20))
                    .foregroundColor(.white)
                    .padding(.horizontal, KhyloStyle.gutter)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(genres.enumerated()), id: \.offset) { index, genre in
                        Button {
                            openGenre(genre)
                        } label: {
                            KhyloGenreTile(name: genre.name ?? "", index: index)
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
        }
    }

    private func openGenre(_ genre: BaseItemDto) {
        guard let name = genre.name else { return }
        router.route(to: .khyloCollection(title: name, id: "genre-\(name)") { start, limit in
            try await KhyloAPI.items(
                types: [.movie, .series],
                sortBy: [.communityRating, .sortName],
                sortOrder: .descending,
                genres: [name],
                startIndex: start,
                limit: limit
            )
        })
    }

    private func remember(_ term: String) {
        guard !term.isEmpty else { return }
        let updated = [term] + recent.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentStorage = updated.prefix(6).joined(separator: "\n")
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        if let top = topHit {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Result")
                    .font(KhyloStyle.title(20))
                    .foregroundColor(.white)
                Button {
                    open(top)
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        KhyloImage(url: KhyloArtwork.url(for: top, style: .backdrop, width: 800))
                            .aspectRatio(16 / 9, contentMode: .fit)
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(top.khyloCardTitle)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Text(topHitSubtitle(top))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(KhyloStyle.secondaryText)
                        }
                        .padding(16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(KhyloStyle.hairline, lineWidth: 0.5)
                    )
                }
                .buttonStyle(KhyloScaleButtonStyle())
            }
            .padding(.horizontal, KhyloStyle.gutter)
        }

        ForEach(groups, id: \.title) { group in
            KhyloShelf(title: group.title) {
                ForEach(group.items, id: \.id) { item in
                    Button {
                        open(item)
                    } label: {
                        if item.type == .musicArtist {
                            KhyloArtistCell(artist: item, size: 120)
                        } else if item.type == .musicAlbum {
                            KhyloAlbumCard(album: item, width: 140)
                        } else {
                            switch group.shape {
                            case .poster: KhyloShelfCard(item: item, shape: .portrait, width: 112)
                            case .square: KhyloShelfCard(item: item, shape: .square, width: 130)
                            case .landscape: KhyloLandscapeCard(item: item, width: 220)
                            }
                        }
                    }
                    .buttonStyle(KhyloScaleButtonStyle())
                }
            }
        }
    }

    private func open(_ item: BaseItemDto) {
        remember(trimmed)
        router.route(to: .khyloItem(item))
    }

    /// Best match: a movie or show whose title starts with the query, else the first with art.
    private var topHit: BaseItemDto? {
        let visual = results.filter { ($0.type == .movie || $0.type == .series) && $0.backdropImageTags?.isEmpty == false }
        return visual.first { ($0.name ?? "").localizedCaseInsensitiveContains(trimmed) } ?? visual.first
    }

    private func topHitSubtitle(_ item: BaseItemDto) -> String {
        var parts = [item.type == .series ? "Series" : "Movie"]
        if let year = item.productionYear { parts.append(String(year)) }
        if let genre = item.genres?.first { parts.append(genre) }
        return parts.joined(separator: " · ")
    }

    private struct Group {
        let title: String
        let shape: KhyloLibraryKind.Shape
        let items: [BaseItemDto]
    }

    private var groups: [Group] {
        let sections: [(String, KhyloLibraryKind.Shape, Set<BaseItemKind>)] = [
            ("Movies", .poster, [.movie]),
            ("Shows", .poster, [.series]),
            ("Episodes", .landscape, [.episode]),
            ("Books", .poster, [.book]),
            ("Audiobooks", .square, [.audioBook]),
            ("Albums", .square, [.musicAlbum]),
            ("Artists", .square, [.musicArtist]),
            ("Songs", .square, [.audio]),
            ("Channels", .square, [.tvChannel]),
        ]
        return sections.compactMap { title, shape, kinds in
            let matches = results.filter { $0.type.map(kinds.contains) ?? false }
            return matches.isEmpty ? nil : Group(title: title, shape: shape, items: matches)
        }
    }
}

/// Deep, tasteful gradient tile for a genre.
private struct KhyloGenreTile: View {

    let name: String
    let index: Int

    private static let palettes: [(String, String)] = [
        ("#3A1C71", "#D76D77"),
        ("#0F2027", "#2C5364"),
        ("#42275A", "#734B6D"),
        ("#1D4350", "#A43931"),
        ("#141E30", "#243B55"),
        ("#3C1053", "#AD5389"),
        ("#232526", "#414345"),
        ("#4B1248", "#F0C27B"),
        ("#0B486B", "#F56217"),
        ("#1F1C2C", "#928DAB"),
        ("#16222A", "#3A6073"),
        ("#5C258D", "#4389A2"),
    ]

    var body: some View {
        let palette = Self.palettes[index % Self.palettes.count]
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: palette.0), Color(hex: palette.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft light from the top corner for depth.
            RadialGradient(
                colors: [Color.white.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 160
            )
            Text(name)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                .padding(14)
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
