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

// MARK: - Internal Library Tab

public enum MediaLibraryTab: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case browse = "Browse"
    case collections = "Collections"
    case playlists = "Playlists"
    case genres = "Genres"

    public var id: String { rawValue }
}

// MARK: - Media Library View

public struct MediaLibraryView: View {

    public let libraryId: String
    public let title: String
    public let collectionType: String

    @StateObject private var repository = KhyloRepository.shared
    @EnvironmentObject private var navigator: KhyloNavigator

    @State private var selectedTab: MediaLibraryTab = .browse
    @State private var items: [KhyloMediaItem] = []
    @State private var recommendedItems: [KhyloMediaItem] = []
    @State private var isLoading: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var currentSort: LibrarySortOption = .titleAsc
    @State private var currentSearch: String = ""
    @State private var selectedGenre: String?
    @State private var selectedItemForOptions: KhyloMediaItem?
    @State private var showOptionsSheet: Bool = false

    private let libraryGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime",
        "Documentary", "Drama", "Fantasy", "Horror", "Mystery",
        "Romance", "Sci-Fi", "Thriller", "Western"
    ]

    public init(
        libraryId: String,
        title: String,
        collectionType: String = "movies"
    ) {
        self.libraryId = libraryId
        self.title = title
        self.collectionType = collectionType
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Custom Navigation Bar
                HStack(spacing: KhyloSpacing.md) {
                    Button(action: {
                        navigator.pop()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Libraries")
                        }
                        .font(KhyloTypography.bodyMedium)
                        .foregroundColor(KhyloColors.textPrimary)
                    }

                    Spacer()

                    Text(title)
                        .font(KhyloTypography.headline)
                        .foregroundColor(KhyloColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Balance spacer width
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal, KhyloSpacing.lg)
                .padding(.vertical, KhyloSpacing.sm)

                // Sub-navigation Segmented Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KhyloSpacing.sm) {
                        ForEach(MediaLibraryTab.allCases) { tab in
                            Button(action: {
                                #if os(iOS)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = tab
                                }
                            }) {
                                Text(tab.rawValue)
                                    .font(selectedTab == tab ? KhyloTypography.bodyMedium : KhyloTypography.body)
                                    .foregroundColor(selectedTab == tab ? KhyloColors.textPrimary : KhyloColors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedTab == tab ? KhyloColors.accent : KhyloColors.surfaceElevated)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.vertical, KhyloSpacing.xs)
                }

                Divider()
                    .background(KhyloColors.border.opacity(0.6))
                    .padding(.top, KhyloSpacing.xs)

                // Tab Content
                switch selectedTab {
                case .recommended:
                    recommendedSection

                case .browse:
                    LibraryGridView(
                        items: items,
                        isLoadingMore: isLoadingMore,
                        onSelect: { item in
                            navigateToDetail(for: item)
                        },
                        onLongPress: { item in
                            selectedItemForOptions = item
                            showOptionsSheet = true
                        },
                        onSortChange: { newSort in
                            currentSort = newSort
                            Task { await loadLibraryItems(reset: true) }
                        },
                        onSearchChange: { query in
                            currentSearch = query
                        },
                        onLoadMore: {
                            Task { await loadMoreItems() }
                        }
                    )

                case .collections:
                    collectionsSection

                case .playlists:
                    playlistsSection

                case .genres:
                    genresSection
                }
            }
        }
        .task {
            await loadLibraryItems(reset: true)
            await loadRecommended()
        }
        .sheet(isPresented: $showOptionsSheet) {
            if let item = selectedItemForOptions {
                ItemOptionsSheet(
                    item: item,
                    isInContinueWatching: false,
                    isInNextUp: false,
                    onAction: { action in
                        handleOptionAction(action)
                    },
                    onDismiss: {
                        showOptionsSheet = false
                        selectedItemForOptions = nil
                    }
                )
            }
        }
    }

    // MARK: - Recommended Section

    private var recommendedSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KhyloSpacing.xl) {
                if !recommendedItems.isEmpty {
                    KhyloSnapRow(
                        title: "Featured in \(title)",
                        items: recommendedItems
                    ) { item in
                        KhyloPosterCard(
                            imageURL: item.posterURL() ?? item.backdropURL(),
                            title: item.name,
                            subtitle: item.displaySubtitle,
                            width: 140,
                            onTap: { navigateToDetail(for: item) },
                            onLongPress: {
                                selectedItemForOptions = item
                                showOptionsSheet = true
                            }
                        )
                    }
                }

                KhyloSnapRow(
                    title: "Recently Added",
                    items: items.prefix(10).map { $0 }
                ) { item in
                    KhyloWideCard(
                        imageURL: item.backdropURL() ?? item.posterURL(),
                        title: item.name,
                        subtitle: item.displaySubtitle,
                        width: 240,
                        onTap: { navigateToDetail(for: item) },
                        onLongPress: {
                            selectedItemForOptions = item
                            showOptionsSheet = true
                        }
                    )
                }
            }
            .padding(.top, KhyloSpacing.md)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        ScrollView {
            VStack(spacing: KhyloSpacing.md) {
                ForEach(["Criterion Collection", "Cinematic Sagas", "Oscar Winners", "Directors' Cuts"], id: \.self) { col in
                    Button(action: {
                        navigator.push(.libraryCollection(collectionId: col.lowercased(), title: col))
                    }) {
                        HStack(spacing: KhyloSpacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                    .fill(KhyloColors.surfaceElevated)
                                    .frame(width: 60, height: 60)

                                Image(systemName: "square.stack.3d.up.fill")
                                    .foregroundColor(KhyloColors.accent)
                                    .font(.system(size: 24))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(col)
                                    .font(KhyloTypography.headline)
                                    .foregroundColor(KhyloColors.textPrimary)

                                Text("Collection Boxset")
                                    .font(KhyloTypography.caption)
                                    .foregroundColor(KhyloColors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                        .padding(KhyloSpacing.md)
                        .background(KhyloColors.surface)
                        .cornerRadius(KhyloRadius.sm)
                    }
                }
            }
            .padding(KhyloSpacing.lg)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Playlists Section

    private var playlistsSection: some View {
        ScrollView {
            VStack(spacing: KhyloSpacing.md) {
                ForEach(["Weekend Movie Night", "Staff Picks", "Holiday Specials", "Action Marathon"], id: \.self) { pl in
                    HStack(spacing: KhyloSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(KhyloColors.accent.opacity(0.18))
                                .frame(width: 48, height: 48)

                            Image(systemName: "music.note.list")
                                .foregroundColor(KhyloColors.accent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pl)
                                .font(KhyloTypography.headline)
                                .foregroundColor(KhyloColors.textPrimary)

                            Text("Curated Playlist")
                                .font(KhyloTypography.caption)
                                .foregroundColor(KhyloColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(KhyloColors.accent)
                    }
                    .padding(KhyloSpacing.md)
                    .background(KhyloColors.surface)
                    .cornerRadius(KhyloRadius.sm)
                }
            }
            .padding(KhyloSpacing.lg)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Genres Section

    private var genresSection: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: KhyloSpacing.md),
                    GridItem(.flexible(), spacing: KhyloSpacing.md)
                ],
                spacing: KhyloSpacing.md
            ) {
                ForEach(libraryGenres, id: \.self) { genre in
                    GenreExploreCard(
                        genre: genre,
                        onSelect: {
                            selectedGenre = genre
                            selectedTab = .browse
                            currentSearch = genre
                        }
                    )
                }
            }
            .padding(KhyloSpacing.lg)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Actions & Navigation

    private func navigateToDetail(for item: KhyloMediaItem) {
        if item.type == "Audio" {
            navigator.push(.music(item: item))
        } else if item.type == "Audiobook" {
            navigator.push(.audiobook(item: item))
        } else if item.type == "Book" {
            navigator.push(.reader(item: item))
        } else if item.type == "Series" || item.type == "Show" {
            navigator.push(.seriesDetail(seriesId: item.seriesId ?? item.id))
        } else {
            navigator.push(.itemDetail(itemId: item.id))
        }
    }

    private func handleOptionAction(_ action: ItemOptionAction) {
        switch action {
        case .resume(let item):
            if item.type == "Audio" {
                navigator.push(.music(item: item))
            } else if item.type == "Audiobook" {
                navigator.push(.audiobook(item: item))
            } else if item.type == "Book" {
                navigator.push(.reader(item: item))
            } else {
                navigator.play(itemId: item.id, resumePositionTicks: item.playbackPositionTicks, title: item.name)
            }
        case .playFromBeginning(let item):
            if item.type == "Audio" {
                navigator.push(.music(item: item))
            } else if item.type == "Audiobook" {
                navigator.push(.audiobook(item: item))
            } else if item.type == "Book" {
                navigator.push(.reader(item: item))
            } else {
                navigator.play(itemId: item.id, resumePositionTicks: 0, title: item.name)
            }
        case .goToSeries(let seriesId):
            navigator.push(.seriesDetail(seriesId: seriesId))
        case .toggleWatched(let item):
            Task { await repository.markPlayed(itemId: item.id, isPlayed: !item.isPlayed) }
        case .toggleFavorite(let item):
            Task { await repository.toggleFavorite(itemId: item.id, isFavorite: !item.isFavorite) }
        case .hideFromUpNext(let seriesId):
            repository.dismissFromNextUp(seriesId: seriesId)
        case .removeFromContinueWatching(let itemId):
            Task { await repository.markPlayed(itemId: itemId, isPlayed: true) }
        case .viewDetails(let item):
            navigateToDetail(for: item)
        }
    }

    private func loadLibraryItems(reset: Bool) async {
        if reset { isLoading = true }
        let startIndex = reset ? 0 : items.count
        let fetched = await repository.fetchLibraryItems(
            libraryId: libraryId,
            sortBy: currentSort.sortBy,
            sortOrder: currentSort.sortOrder,
            limit: 60,
            startIndex: startIndex
        )
        await MainActor.run {
            if reset {
                self.items = fetched
            } else {
                self.items.append(contentsOf: fetched)
            }
            self.isLoading = false
        }
    }

    private func loadMoreItems() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        let fetched = await repository.fetchLibraryItems(
            libraryId: libraryId,
            sortBy: currentSort.sortBy,
            sortOrder: currentSort.sortOrder,
            limit: 40,
            startIndex: items.count
        )
        await MainActor.run {
            self.items.append(contentsOf: fetched)
            self.isLoadingMore = false
        }
    }

    private func loadRecommended() async {
        let rec = await repository.fetchRecommendations()
        await MainActor.run {
            self.recommendedItems = rec
        }
    }
}

// MARK: - Genre Explore Card

private struct GenreExploreCard: View {
    let genre: String
    let onSelect: () -> Void

    private var color: Color {
        GenreColors.color(for: genre)
    }

    var body: some View {
        Button(action: { onSelect() }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(genre)
                        .font(KhyloTypography.headline)
                        .foregroundColor(.white)

                    Text("Explore")
                        .font(KhyloTypography.caption2Medium)
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
            }
            .padding(KhyloSpacing.md)
            .frame(height: 80)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(KhyloRadius.md)
        }
    }
}
