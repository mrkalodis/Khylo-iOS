//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Library store

/// The user's libraries and which one the Libraries tab shows. Shared by the tab
/// bar (which opens the picker) and the Libraries screen.
@MainActor
final class KhyloLibraryStore: ObservableObject {

    static let shared = KhyloLibraryStore()
    static let favoritesID = "khylo-favorites"
    static let downloadsID = "khylo-downloads"

    @Published private(set) var libraries: [BaseItemDto] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published var isPickerPresented = false
    @Published var selectedID: String = UserDefaults.standard.string(forKey: "khylo.libraries.selected") ?? "" {
        didSet { UserDefaults.standard.set(selectedID, forKey: "khylo.libraries.selected") }
    }

    var selected: BaseItemDto? {
        libraries.first { $0.id == selectedID } ?? libraries.first
    }

    var isFavoritesSelected: Bool { selectedID == Self.favoritesID }
    var isDownloadsSelected: Bool { selectedID == Self.downloadsID }

    func load() async {
        do {
            // Live TV has its own tab.
            libraries = try await KhyloAPI.libraries().filter { $0.collectionType != .livetv }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func select(_ id: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        selectedID = id
        isPickerPresented = false
    }
}

// MARK: - Libraries tab

/// The Libraries tab shows one library at a time; its title opens the picker.
struct KhyloLibrariesScreen: View {

    @ObservedObject private var store = KhyloLibraryStore.shared

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            if store.isDownloadsSelected {
                // On the phone, so it works without a connection.
                KhyloDownloadsScreen { header(title: "Downloads") }
                    .id(KhyloLibraryStore.downloadsID)
            } else if store.isLoading {
                KhyloLoadingState()
            } else if store.libraries.isEmpty {
                KhyloEmptyState(
                    systemImage: "square.stack",
                    title: "No libraries",
                    message: store.errorMessage ?? "Libraries you have access to will appear here.",
                    actionTitle: "Try Again"
                ) {
                    Task { await store.load() }
                }
            } else {
                browser
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            if store.libraries.isEmpty { await store.load() }
        }
    }

    @ViewBuilder
    private var browser: some View {
        if store.isFavoritesSelected {
            KhyloSearchableGrid(
                shape: .poster,
                id: KhyloLibraryStore.favoritesID,
                placeholder: "Search Favorites",
                header: { header(title: "Favorites") }
            ) { term, start, limit in
                try await KhyloAPI.items(
                    types: [.movie, .series, .book, .audioBook, .musicAlbum],
                    sortBy: [.sortName],
                    isFavorite: true,
                    searchTerm: term,
                    startIndex: start,
                    limit: limit
                )
            }
            .id(KhyloLibraryStore.favoritesID)
        } else if let library = store.selected {
            KhyloLibraryHome(library: library) {
                header(title: library.name ?? "Library")
            }
            .id(library.id)
        }
    }

    /// Big library name with a chevron; tapping it switches library.
    private func header(title: String) -> some View {
        HStack(alignment: .center) {
            Button {
                store.isPickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.white.opacity(0.15))
                }
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityHint("Choose a library")

            Spacer()
            KhyloProfileButton()
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.top, 8)
    }
}

// MARK: - Library picker

/// Slides up from the bottom with every library to choose from.
struct KhyloLibraryPickerSheet: View {

    @ObservedObject private var store = KhyloLibraryStore.shared
    @ObservedObject private var downloads = KhyloDownloads.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Libraries")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, KhyloStyle.gutter)
                .padding(.top, 28)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.libraries, id: \.id) { library in
                        row(
                            title: library.name ?? "",
                            subtitle: subtitle(for: library),
                            symbol: KhyloLibraryKind(library).symbol,
                            isSelected: !store.isFavoritesSelected && !store.isDownloadsSelected && store.selected?.id == library.id
                        ) {
                            store.select(library.id ?? "")
                        }
                    }

                    row(
                        title: "Favorites",
                        subtitle: "Everything you've hearted",
                        symbol: "heart.fill",
                        isSelected: store.isFavoritesSelected
                    ) {
                        store.select(KhyloLibraryStore.favoritesID)
                    }

                    if KhyloDownloads.isAllowed || downloads.hasDownloads {
                        row(
                            title: "Downloads",
                            subtitle: downloads.hasDownloads
                                ? "On this iPhone · \(ByteCountFormatter.string(fromByteCount: downloads.usedBytes, countStyle: .file))"
                                : "Watch and listen offline",
                            symbol: "arrow.down.circle.fill",
                            isSelected: store.isDownloadsSelected
                        ) {
                            store.select(KhyloLibraryStore.downloadsID)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
    }

    private func subtitle(for library: BaseItemDto) -> String {
        if let extended = KhyloAPI.extendedCollectionType(for: library) {
            return extended == .audiobooks ? "Audiobooks" : "Podcasts"
        }
        switch library.collectionType {
        case .movies: return "Movies"
        case .tvshows: return "TV Shows"
        case .books: return "Books"
        case .music: return "Music"
        case .boxsets: return "Collections"
        case .playlists: return "Playlists"
        case .homevideos: return "Home Videos"
        case .musicvideos: return "Music Videos"
        default: return "Library"
        }
    }

    private func row(
        title: String,
        subtitle: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? KhyloStyle.accent.opacity(0.22) : Color.white.opacity(0.08))
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isSelected ? KhyloStyle.accent : .white.opacity(0.85))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    if subtitle.caseInsensitiveCompare(title) != .orderedSame {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(KhyloStyle.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pills & chips

/// Library switcher pill: solid white when selected, frosted otherwise.
struct KhyloPill: View {

    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(isSelected ? .black : .white.opacity(0.85))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0 : 0.1), lineWidth: 1))
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }
}

/// Small rounded control for sort/filter menus.
struct KhyloChipLabel: View {

    let title: String
    let systemImage: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
        }
        .foregroundColor(isActive ? KhyloStyle.accent : .white.opacity(0.85))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(isActive ? KhyloStyle.accent.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Library browser

/// Sort and filter chips plus the library's grid.
struct KhyloLibraryBrowser<Header: View>: View {

    let library: BaseItemDto
    @ViewBuilder let header: (Int?) -> Header

    @State private var sort: KhyloSortOption = .recentlyAdded
    @State private var filter: KhyloFilterOption = .all
    @State private var total: Int?
    @State private var query = ""
    /// `query` after the user pauses typing; drives the reload.
    @State private var searchTerm = ""

    var body: some View {
        let kind = KhyloLibraryKind(library)
        let isSearching = !searchTerm.isEmpty

        KhyloItemGrid(
            shape: kind.shape,
            reloadKey: "\(library.id ?? "")-\(sort.rawValue)-\(filter.rawValue)-\(searchTerm)",
            onTotal: { total = $0 },
            header: {
                VStack(alignment: .leading, spacing: 14) {
                    header(total)
                    KhyloLibrarySearchField(
                        placeholder: "Search \(library.name ?? "Library")",
                        text: $query
                    )
                    chips
                }
            }
        ) { start, limit in
            try await KhyloAPI.items(
                parentID: library.id,
                // Folder-organized libraries search the whole tree for matching folders (books).
                types: isSearching && !kind.recursive ? [.folder] : kind.types,
                sortBy: isSearching ? [.sortName] : sort.sortBy,
                sortOrder: isSearching ? .ascending : sort.order,
                filters: filter.filters,
                isFavorite: filter.isFavorite,
                searchTerm: isSearching ? searchTerm : nil,
                recursive: isSearching ? true : kind.recursive,
                startIndex: start,
                limit: limit
            )
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            searchTerm = trimmed
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(KhyloSortOption.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                KhyloChipLabel(title: sort.rawValue, systemImage: "arrow.up.arrow.down")
            }

            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(KhyloFilterOption.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                KhyloChipLabel(title: filter.rawValue, systemImage: "line.3.horizontal.decrease", isActive: filter != .all)
            }

            Spacer()

            if let total {
                Text(total.formatted())
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .animation(.easeInOut(duration: 0.2), value: total)
    }
}

/// A library pushed from elsewhere (e.g. a Home row's chevron).
struct KhyloLibraryScreen: View {

    let library: BaseItemDto

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            if library.collectionType == .livetv {
                KhyloLiveTVScreen()
            } else {
                KhyloLibraryHome(library: library) {
                    Text(library.name ?? "Library")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, KhyloStyle.gutter)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Library kinds

/// What a library holds, which decides its item types and card shape.
struct KhyloLibraryKind {

    enum Shape {
        case poster
        case square
        case landscape
    }

    let types: [BaseItemKind]?
    let shape: Shape
    let symbol: String
    /// Folder-organized libraries (audiobooks, podcasts) browse one level at a time.
    var recursive = true

    init(_ library: BaseItemDto) {
        switch KhyloAPI.extendedCollectionType(for: library) {
        case .audiobooks:
            self.init(types: nil, shape: .square, symbol: "headphones")
            recursive = false
            return
        case .podcasts:
            self.init(types: nil, shape: .square, symbol: "mic")
            recursive = false
            return
        case nil:
            break
        }

        switch library.collectionType {
        case .movies:
            self.init(types: [.movie], shape: .poster, symbol: "film")
        case .tvshows:
            self.init(types: [.series], shape: .poster, symbol: "tv")
        case .books:
            self.init(types: [.book], shape: .poster, symbol: "books.vertical")
        case .music:
            self.init(types: [.musicAlbum], shape: .square, symbol: "music.note")
        case .boxsets:
            self.init(types: [.boxSet], shape: .poster, symbol: "square.stack")
        case .musicvideos:
            self.init(types: [.musicVideo], shape: .landscape, symbol: "music.note.tv")
        case .homevideos, .photos:
            self.init(types: [.video], shape: .landscape, symbol: "video")
        case .playlists:
            self.init(types: [.playlist], shape: .square, symbol: "music.note.list")
        case .livetv:
            self.init(types: [.tvChannel], shape: .square, symbol: "antenna.radiowaves.left.and.right")
        default:
            self.init(types: nil, shape: .poster, symbol: "folder")
        }
    }

    private init(types: [BaseItemKind]?, shape: Shape, symbol: String) {
        self.types = types
        self.shape = shape
        self.symbol = symbol
    }
}

// MARK: - Sort & filter

enum KhyloSortOption: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case title = "Title"
    case releaseDate = "Release Date"
    case rating = "Rating"
    case random = "Shuffle"

    var id: String { rawValue }

    var sortBy: [ItemSortBy] {
        switch self {
        case .recentlyAdded: [.dateCreated, .sortName]
        case .title: [.sortName]
        case .releaseDate: [.premiereDate, .productionYear, .sortName]
        case .rating: [.communityRating, .sortName]
        case .random: [.random]
        }
    }

    var order: JellyfinAPI.SortOrder {
        self == .title ? .ascending : .descending
    }
}

enum KhyloFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case unwatched = "Unwatched"
    case inProgress = "In Progress"
    case favorites = "Favorites"

    var id: String { rawValue }

    var filters: [JellyfinAPI.ItemFilter]? {
        switch self {
        case .unwatched: [.isUnplayed]
        case .inProgress: [.isResumable]
        default: nil
        }
    }

    var isFavorite: Bool? {
        self == .favorites ? true : nil
    }
}

// MARK: - Grid

/// Paged grid of items under an optional header. Reloads when `reloadKey` changes.
struct KhyloItemGrid<Header: View>: View {

    var shape: KhyloLibraryKind.Shape = .poster
    var reloadKey: String = ""
    var onTotal: ((Int) -> Void)? = nil
    @ViewBuilder var header: () -> Header
    let loader: (Int, Int) async throws -> KhyloAPI.Page

    @State private var items: [BaseItemDto] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @Router private var router

    private let pageSize = 60
    private let spacing: CGFloat = 12

    private var columnCount: Int {
        switch shape {
        case .poster: 3
        case .square, .landscape: 2
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - KhyloStyle.gutter * 2 - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header()

                    if isLoading {
                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if items.isEmpty {
                        KhyloEmptyState(
                            systemImage: "rectangle.stack",
                            title: "Nothing here",
                            message: errorMessage ?? "Try a different filter."
                        )
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(width), spacing: spacing, alignment: .top), count: columnCount),
                            spacing: 22
                        ) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    router.route(to: .khyloItem(item))
                                } label: {
                                    card(for: item, width: width)
                                }
                                .buttonStyle(KhyloScaleButtonStyle())
                                .onAppear {
                                    if index >= items.count - 12 { Task { await loadMore() } }
                                }
                            }
                        }
                        .padding(.horizontal, KhyloStyle.gutter)

                        if isLoadingMore {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .refreshable { await reload() }
        }
        .task(id: reloadKey) { await reload() }
    }

    @ViewBuilder
    private func card(for item: BaseItemDto, width: CGFloat) -> some View {
        switch shape {
        case .poster: KhyloShelfCard(item: item, shape: .portrait, width: width)
        case .square: KhyloShelfCard(item: item, shape: .square, width: width)
        case .landscape: KhyloLandscapeCard(item: item, width: width)
        }
    }

    private func reload() async {
        isLoading = items.isEmpty
        do {
            let page = try await loader(0, pageSize)
            withAnimation(.easeOut(duration: 0.2)) {
                items = page.items
                total = page.total
            }
            onTotal?(page.total)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, items.count < total else { return }
        isLoadingMore = true
        if let page = try? await loader(items.count, pageSize) {
            let known = Set(items.compactMap(\.id))
            items += page.items.filter { !known.contains($0.id ?? "") }
            total = page.total
        }
        isLoadingMore = false
    }
}

/// A titled grid pushed onto the navigation stack.
struct KhyloGridScreen: View {

    let title: String
    var shape: KhyloLibraryKind.Shape = .poster
    let loader: (Int, Int) async throws -> KhyloAPI.Page

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()
            KhyloItemGrid(shape: shape, reloadKey: title, header: {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, KhyloStyle.gutter)
            }, loader: loader)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - In-library search

/// Compact frosted search field that filters the current library.
struct KhyloLibrarySearchField: View {

    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(KhyloStyle.tertiaryText)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(KhyloStyle.tertiaryText))
                .font(.system(size: 16))
                .foregroundColor(.white)
                .tint(KhyloStyle.accent)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(KhyloStyle.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isFocused ? KhyloStyle.accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .padding(.horizontal, KhyloStyle.gutter)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A grid with its own search field; the loader receives the search term (nil when empty).
struct KhyloSearchableGrid<Header: View>: View {

    var shape: KhyloLibraryKind.Shape = .poster
    var id: String
    let placeholder: String
    @ViewBuilder var header: () -> Header
    let loader: (String?, Int, Int) async throws -> KhyloAPI.Page

    @State private var query = ""
    @State private var searchTerm = ""

    var body: some View {
        KhyloItemGrid(
            shape: shape,
            reloadKey: "\(id)-\(searchTerm)",
            header: {
                VStack(alignment: .leading, spacing: 14) {
                    header()
                    KhyloLibrarySearchField(placeholder: placeholder, text: $query)
                }
            }
        ) { start, limit in
            try await loader(searchTerm.isEmpty ? nil : searchTerm, start, limit)
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            searchTerm = trimmed
        }
    }
}

// MARK: - Library home (For You · Browse · Collections)

/// A library page in the Plex mould: a curated For You view, a full Browse grid,
/// and Collections for movies.
struct KhyloLibraryHome<Header: View>: View {

    enum Tab: Hashable {
        case forYou
        case browse
        case collections
    }

    let library: BaseItemDto
    @ViewBuilder let header: () -> Header

    @State private var tab: Tab = .forYou
    @State private var musicQuery = ""
    @State private var musicTerm = ""
    @State private var sections: [KhyloFeedSection] = []
    @State private var isLoading = true

    private var tabs: [(Tab, String)] {
        var result: [(Tab, String)] = [(.forYou, "For You"), (.browse, "Browse")]
        if library.collectionType == .movies { result.append((.collections, "Collections")) }
        return result
    }

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            switch tab {
            case .forYou where library.collectionType == .music:
                // Music has its own For You: Jump Back In, mixes, On Repeat and more,
                // with a search right at the top for finding something specific.
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        top
                        KhyloLibrarySearchField(placeholder: "Search artists, albums and songs", text: $musicQuery)
                        if musicTerm.isEmpty {
                            KhyloMusicForYou(library: library)
                        } else {
                            KhyloMusicSearchResults(libraryID: library.id, term: musicTerm)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.immediately)
                .task(id: musicQuery) {
                    let trimmed = musicQuery.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                    }
                    musicTerm = trimmed
                }

            case .forYou:
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        top
                        if isLoading {
                            ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 80)
                        } else if sections.isEmpty {
                            KhyloEmptyState(systemImage: "sparkles", title: "Nothing to show yet", message: "Browse the full library instead.", actionTitle: "Browse") {
                                tab = .browse
                            }
                            .padding(.top, 30)
                        } else {
                            KhyloFeedView(sections: sections)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .refreshable { await load() }

            case .browse:
                if library.collectionType == .music {
                    KhyloMusicLibraryScreen(library: library, header: AnyView(top))
                } else {
                    KhyloLibraryBrowser(library: library) { _ in top }
                }

            case .collections:
                KhyloSearchableGrid(shape: .poster, id: "collections-\(library.id ?? "")", placeholder: "Search collections", header: { top }) { term, start, limit in
                    try await KhyloAPI.items(types: [.boxSet], sortBy: [.sortName], searchTerm: term, startIndex: start, limit: limit)
                }
            }
        }
        .task(id: library.id) { await load() }
        .onAppear {
            Task { await refreshResume() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .khyloPlaybackDidEnd)) { _ in
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await refreshResume()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshResume() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .khyloProgressDidChange)) { _ in
            Task { await refreshResume() }
        }
    }

    /// Swaps in a fresh Continue Watching row for this library.
    private func refreshResume() async {
        guard !sections.isEmpty, let id = library.id,
              library.collectionType == .movies || library.collectionType == .tvshows,
              let resume = try? await KhyloAPI.resume(limit: 20)
        else { return }
        let isMovies = library.collectionType == .movies
        let items = resume.filter { isMovies ? $0.type == .movie : $0.type == .episode }
        var rest = sections.filter { $0.id != "\(id)-resume" }
        if !items.isEmpty {
            rest.insert(.init(id: "\(id)-resume", title: "Continue Watching", action: .play, items: items), at: 0)
        }
        withAnimation(.easeInOut(duration: 0.25)) { sections = rest }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 14) {
            header()
            KhyloSegmentTabs(tabs: tabs, selection: $tab)
                .padding(.horizontal, KhyloStyle.gutter - 4)
        }
    }

    private func load() async {
        isLoading = sections.isEmpty
        sections = await KhyloFeedBuilder.sections(for: library, includeResume: true)
        isLoading = false
    }
}
