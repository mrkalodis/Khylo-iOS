//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

/// Search across everything, kept tidy by a scope switcher: All, Movies & TV,
/// Music and Books. Idle, each scope shows its categories as artwork tiles
/// fronted by the most popular title in them.
struct KhyloSearchScreen: View {

    enum Scope: String, CaseIterable {
        case all = "All"
        case video = "Movies & TV"
        case music = "Music"
        case books = "Books"

        var kinds: Set<BaseItemKind> {
            switch self {
            case .all: []
            case .video: [.movie, .series, .episode, .tvChannel]
            case .music: [.musicArtist, .musicAlbum, .audio]
            case .books: [.book, .audioBook]
            }
        }

        var prompt: String {
            switch self {
            case .all: "Movies, shows, music, books"
            case .video: "Movies and shows"
            case .music: "Artists, albums, songs"
            case .books: "Books and audiobooks"
            }
        }
    }

    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var results: [BaseItemDto] = []
    @State private var isSearching = false
    @AppStorage("khylo.search.recent") private var recentStorage = ""
    @ObservedObject private var libraryStore = KhyloLibraryStore.shared
    @FocusState private var isFieldFocused: Bool
    @Router private var router

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var recent: [String] {
        recentStorage.split(separator: "\n").map(String.init)
    }

    /// Only offer scopes the server has libraries for.
    private var scopes: [Scope] {
        let types = Set(libraryStore.libraries.compactMap(\.collectionType))
        let hasBooks = types.contains(.books)
            || libraryStore.libraries.contains { KhyloAPI.extendedCollectionType(for: $0) == .audiobooks }
        return Scope.allCases.filter { scope in
            switch scope {
            case .all: true
            case .video: types.contains(.movies) || types.contains(.tvshows) || types.isEmpty
            case .music: types.contains(.music) || types.isEmpty
            case .books: hasBooks
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            KhyloStyle.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if trimmed.isEmpty {
                        idleContent
                    } else if isSearching && results.isEmpty {
                        ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 60)
                    } else if scopedResults.isEmpty {
                        KhyloEmptyState(
                            systemImage: "magnifyingglass",
                            title: "No results",
                            message: scope == .all
                                ? "Nothing matches \u{201C}\(trimmed)\u{201D}. Check the spelling or try another title."
                                : "Nothing in \(scope.rawValue) matches \u{201C}\(trimmed)\u{201D}."
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
            .padding(.horizontal, KhyloStyle.gutter)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KhyloStyle.secondaryText)
                TextField(
                    "",
                    text: $query,
                    prompt: Text(scope.prompt).foregroundColor(KhyloStyle.tertiaryText)
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
            .padding(.horizontal, KhyloStyle.gutter)

            if scopes.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    KhyloSegmentTabs(tabs: scopes.map { ($0, $0.rawValue) }, selection: $scope)
                        .padding(.horizontal, KhyloStyle.gutter)
                }
                .scrollClipDisabled()
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleContent: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent")
                        .font(KhyloStyle.title(20))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Clear") { recentStorage = "" }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KhyloStyle.accent)
                }
                ForEach(recent.prefix(4), id: \.self) { term in
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
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KhyloStyle.gutter)
        }

        switch scope {
        case .all:
            ForEach(scopes.filter { $0 != .all }, id: \.self) { section in
                KhyloCategoryGrid(scope: section, limit: 4) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { scope = section }
                }
            }
        default:
            KhyloCategoryGrid(scope: scope, limit: nil, onSeeAll: nil)
                .id(scope)
        }
    }

    private func remember(_ term: String) {
        guard !term.isEmpty else { return }
        let updated = [term] + recent.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentStorage = updated.prefix(6).joined(separator: "\n")
    }

    // MARK: - Results

    private var scopedResults: [BaseItemDto] {
        guard scope != .all else { return results }
        return results.filter { $0.type.map(scope.kinds.contains) ?? false }
    }

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
                    KhyloTopResultCard(item: top)
                }
                .buttonStyle(KhyloScaleButtonStyle())
            }
            .padding(.horizontal, KhyloStyle.gutter)
        }

        ForEach(groups, id: \.title) { group in
            switch group.style {
            case .songs:
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(KhyloStyle.title(20))
                        .foregroundColor(.white)
                        .padding(.horizontal, KhyloStyle.gutter)
                    ForEach(Array(group.items.prefix(6).enumerated()), id: \.element.id) { index, song in
                        KhyloTrackRow(track: song, style: .artwork) {
                            remember(trimmed)
                            // The song, then a mix built from it.
                            KhyloAudioPlayer.shared.play([song], kind: .music, startTicks: 0)
                        }
                    }
                }
            default:
                KhyloShelf(title: group.title) {
                    ForEach(group.items, id: \.id) { item in
                        Button {
                            open(item)
                        } label: {
                            switch group.style {
                            case .artists: KhyloArtistCell(artist: item, size: 112)
                            case .albums: KhyloAlbumCard(album: item, width: 140)
                            case .square: KhyloShelfCard(item: item, shape: .square, width: 130)
                            case .landscape: KhyloLandscapeCard(item: item, width: 220)
                            default: KhyloShelfCard(item: item, shape: .portrait, width: 112)
                            }
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                }
            }
        }
    }

    private func open(_ item: BaseItemDto) {
        remember(trimmed)
        router.route(to: .khyloItem(item))
    }

    /// Best match in the current scope: an exact title first, then one that starts
    /// with the query, preferring things you'd open (titles, artists, albums).
    private var topHit: BaseItemDto? {
        let candidates = scopedResults.filter { item in
            switch item.type {
            case .movie, .series: item.backdropImageTags?.isEmpty == false || item.imageTags?["Primary"] != nil
            case .musicArtist, .musicAlbum, .book, .audioBook: true
            default: false
            }
        }
        let term = trimmed.lowercased()
        let name = { (item: BaseItemDto) in (item.name ?? "").lowercased() }
        return candidates.first { name($0) == term }
            ?? candidates.first { name($0).hasPrefix(term) }
            ?? candidates.first { name($0).contains(term) }
    }

    private enum GroupStyle {
        case poster
        case landscape
        case square
        case albums
        case artists
        case songs
    }

    private struct Group {
        let title: String
        let style: GroupStyle
        let items: [BaseItemDto]
    }

    private var groups: [Group] {
        let sections: [(String, GroupStyle, BaseItemKind)] = [
            ("Artists", .artists, .musicArtist),
            ("Movies", .poster, .movie),
            ("Shows", .poster, .series),
            ("Albums", .albums, .musicAlbum),
            ("Songs", .songs, .audio),
            ("Episodes", .landscape, .episode),
            ("Books", .poster, .book),
            ("Audiobooks", .square, .audioBook),
            ("Channels", .square, .tvChannel),
        ]
        let topID = topHit?.id
        return sections.compactMap { title, style, kind in
            let matches = scopedResults.filter { $0.type == kind && $0.id != topID }
            return matches.isEmpty ? nil : Group(title: title, style: style, items: matches)
        }
    }
}

// MARK: - Top result

private struct KhyloTopResultCard: View {
    let item: BaseItemDto

    var body: some View {
        switch item.type {
        case .musicArtist, .musicAlbum, .book, .audioBook:
            compact
        default:
            wide
        }
    }

    /// Movies and shows: their backdrop, title over a gradient.
    private var wide: some View {
        ZStack(alignment: .bottomLeading) {
            KhyloImage(url: KhyloArtwork.url(for: item, style: .backdrop, width: 800))
                .aspectRatio(16 / 9, contentMode: .fit)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.khyloCardTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(subtitle)
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

    /// Artists, albums and books: their art beside the name, on a frosted card.
    private var compact: some View {
        HStack(spacing: 16) {
            artwork
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if item.type == .musicArtist {
            KhyloArtistAvatar(artist: item, size: 92)
        } else {
            let isBook = item.type == .book
            KhyloImage(
                url: KhyloArtwork.url(for: item, style: isBook ? .poster : .square, width: 200),
                placeholderSymbol: isBook ? "book.closed" : "music.note"
            )
            .frame(width: isBook ? 64 : 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var subtitle: String {
        switch item.type {
        case .musicArtist: return "ARTIST"
        case .musicAlbum: return item.khyloArtistLine.isEmpty ? "ALBUM" : "ALBUM · \(item.khyloArtistLine.uppercased())"
        case .book: return "BOOK"
        case .audioBook: return "AUDIOBOOK"
        default:
            var parts = [item.type == .series ? "Series" : "Movie"]
            if let year = item.productionYear { parts.append(String(year)) }
            if let genre = item.genres?.first { parts.append(genre) }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: - Categories

/// A genre from the library's own metadata, with its most popular title.
struct KhyloCategory: Identifiable, Hashable {
    let name: String
    let titleCount: Int
    let top: BaseItemDto?
    var id: String { name }
}

/// A scope's categories as artwork tiles.
struct KhyloCategoryGrid: View {

    let scope: KhyloSearchScreen.Scope
    /// Show only the first few, with a See All that switches to the scope.
    let limit: Int?
    let onSeeAll: (() -> Void)?
    /// The music library's Browse shows the tiles without a title above them.
    var showsTitle = true

    @State private var categories: [KhyloCategory] = []
    @Router private var router

    private var title: String {
        switch scope {
        case .music: "Music"
        case .books: "Books"
        default: "Movies & TV"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !categories.isEmpty {
                if showsTitle {
                HStack(alignment: .lastTextBaseline) {
                    Text(limit == nil ? "Browse \(scope.rawValue)" : title)
                        .font(KhyloStyle.title(20))
                        .foregroundColor(.white)
                    Spacer()
                    if let onSeeAll, let limit, categories.count > limit {
                        Button("See All", action: onSeeAll)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(KhyloStyle.accent)
                    }
                }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(categories.prefix(limit ?? categories.count).enumerated()), id: \.element.id) { index, category in
                        Button {
                            open(category)
                        } label: {
                            KhyloCategoryTile(category: category, scope: scope, index: index)
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .task(id: scope) {
            if categories.isEmpty {
                let found = await KhyloCategoryCache.shared.categories(for: scope)
                withAnimation(.easeOut(duration: 0.25)) { categories = found }
            }
        }
    }

    private func open(_ category: KhyloCategory) {
        let name = category.name
        let types = KhyloCategoryCache.itemTypes(for: scope)
        let isMusic = scope == .music
        router.route(to: NavigationRoute(id: "khylo-genre-\(scope.rawValue)-\(name)") {
            KhyloGridScreen(title: name, shape: isMusic ? .square : .poster) { start, limit in
                try await KhyloAPI.items(
                    types: types,
                    sortBy: isMusic ? [.playCount, .communityRating, .sortName] : [.communityRating, .sortName],
                    sortOrder: .descending,
                    genres: [name],
                    startIndex: start,
                    limit: limit
                )
            }
        })
    }
}

/// A category tile fronted by the most popular title in it.
private struct KhyloCategoryTile: View {

    let category: KhyloCategory
    let scope: KhyloSearchScreen.Scope
    let index: Int

    @State private var tint: Color?

    /// Music and books show their cover tilted on the tile; video fills it.
    private var usesCover: Bool { scope == .music || scope == .books }

    private var art: URL? {
        guard let top = category.top else { return nil }
        switch scope {
        case .music: return KhyloArtwork.url(for: top, style: .square, width: 180)
        case .books: return KhyloArtwork.url(for: top, style: .poster, width: 140)
        default: return KhyloArtwork.url(for: top, style: .backdrop, width: 420)
        }
    }

    /// The top title's name: the artist for music, the title otherwise.
    private var topLabel: String? {
        guard let top = category.top else { return nil }
        if scope == .music {
            let artist = top.khyloArtistLine
            return artist.isEmpty ? top.name : artist
        }
        return top.name
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(tint ?? Self.fallback(index))

            if let art {
                if usesCover {
                    KhyloImage(url: art, showsPlaceholder: false)
                        .frame(width: scope == .books ? 62 : 80, height: scope == .books ? 92 : 80)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                        .rotationEffect(.degrees(18))
                        .offset(x: 18, y: 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else {
                    KhyloImage(url: art, showsPlaceholder: false)
                    LinearGradient(
                        colors: [.black.opacity(0.05), .black.opacity(0.35), .black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let topLabel {
                    Text(topLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            .padding(12)
            .frame(maxWidth: usesCover ? 112 : .infinity, alignment: .leading)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .task(id: category.id) {
            guard usesCover, let art else { return }
            let color = await KhyloArtColor.color(for: art)
            withAnimation(.easeOut(duration: 0.3)) { tint = color }
        }
    }

    private static let palette: [String] = ["#2B2F45", "#3B2A3F", "#1F3A3D", "#3D2E22", "#22303F", "#33263A", "#2A3826", "#3A2828"]

    static func fallback(_ index: Int) -> Color {
        Color(hex: palette[index % palette.count])
    }
}

/// Builds each scope's categories once per session from the library's genre metadata.
///
/// One request per scope fetches a large sample of titles, most popular first,
/// with just their genres and artwork. Every genre that appears becomes a
/// category (most common first), fronted by its most popular title with art.
@MainActor
private final class KhyloCategoryCache {

    static let shared = KhyloCategoryCache()

    private var results: [String: [KhyloCategory]] = [:]
    /// Loads run apart from any one screen, so leaving the page doesn't cancel them.
    private var loads: [String: Task<[KhyloCategory], Never>] = [:]

    static func itemTypes(for scope: KhyloSearchScreen.Scope) -> [BaseItemKind] {
        switch scope {
        case .music: [.musicAlbum]
        case .books: [.book]
        default: [.movie, .series]
        }
    }

    func categories(for scope: KhyloSearchScreen.Scope) async -> [KhyloCategory] {
        let key = scope.rawValue
        if let cached = results[key] { return cached }
        if let load = loads[key] { return await load.value }

        let load = Task<[KhyloCategory], Never> {
            let types = Self.itemTypes(for: scope)
            let popularity: [ItemSortBy] = switch scope {
            case .music: [.playCount, .communityRating, .dateCreated]
            case .books: [.communityRating, .dateCreated]
            default: [.communityRating, .criticRating, .dateCreated]
            }
            guard let sample = try? await KhyloAPI.genreSample(types: types, sortBy: popularity) else { return [] }
            return Self.build(from: sample, scope: scope)
        }
        loads[key] = load
        let found = await load.value
        loads[key] = nil
        // Keep only a real answer; an empty one is retried next time.
        if !found.isEmpty { results[key] = found }
        return found
    }

    private static func build(from sample: [BaseItemDto], scope: KhyloSearchScreen.Scope) -> [KhyloCategory] {
        var counts: [String: Int] = [:]
        var top: [String: BaseItemDto] = [:]
        // Several spellings of one genre ("Sci-Fi", "Science Fiction") stay separate,
        // as they are in the library; only case and spacing are folded together.
        var display: [String: String] = [:]

        for item in sample {
            for raw in item.genres ?? [] {
                let name = raw.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let key = name.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = name }
                // The sample is most popular first, so the first title with art wins.
                if top[key] == nil, hasArt(item, scope: scope) { top[key] = item }
            }
        }

        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { key, count in KhyloCategory(name: display[key] ?? key, titleCount: count, top: top[key]) }
    }

    private static func hasArt(_ item: BaseItemDto, scope: KhyloSearchScreen.Scope) -> Bool {
        switch scope {
        case .music, .books: item.imageTags?["Primary"] != nil
        default: item.backdropImageTags?.isEmpty == false
        }
    }
}
