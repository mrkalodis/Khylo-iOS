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

// MARK: - Khylo Home View

public struct KhyloHomeView: View {

    @StateObject private var repository = KhyloRepository.shared
    @EnvironmentObject private var navigator: KhyloNavigator

    @State private var selectedItemForOptions: KhyloMediaItem?
    @State private var isItemFromContinueWatching: Bool = false
    @State private var isItemFromNextUp: Bool = false
    @State private var showOptionsSheet: Bool = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: KhyloSpacing.xl) {
                    // Hero Billboard
                    if !repository.heroBillboardItems.isEmpty {
                        HeroBillboard(
                            items: repository.heroBillboardItems,
                            onPlay: { item in
                                handleItemPlayback(item: item, resume: true)
                            },
                            onToggleList: { item in
                                Task {
                                    await repository.toggleFavorite(itemId: item.id, isFavorite: !item.isFavorite)
                                }
                            },
                            onInfo: { item in
                                navigateToItemDetails(item: item)
                            }
                        )
                    }

                    // Continue Watching
                    if !repository.continueWatchingItems.isEmpty {
                        ContinueWatchingRow(
                            items: repository.continueWatchingItems,
                            onSelect: { item in
                                handleItemPlayback(item: item, resume: true)
                            },
                            onLongPress: { item in
                                openOptions(for: item, isContinueWatching: true, isNextUp: false)
                            },
                            onSeeAll: {
                                navigator.push(.library)
                            }
                        )
                    }

                    // Next Up
                    if !repository.nextUpItems.isEmpty {
                        NextUpRow(
                            items: repository.nextUpItems,
                            onSelect: { item in
                                handleItemPlayback(item: item, resume: true)
                            },
                            onLongPress: { item in
                                openOptions(for: item, isContinueWatching: false, isNextUp: true)
                            },
                            onDismissSeries: { seriesId in
                                repository.dismissFromNextUp(seriesId: seriesId)
                            }
                        )
                    }

                    // Recently Added
                    if !repository.recentlyAddedItems.isEmpty {
                        RecentlyAddedRow(
                            items: repository.recentlyAddedItems,
                            onSelect: { item in
                                navigateToItemDetails(item: item)
                            },
                            onLongPress: { item in
                                openOptions(for: item, isContinueWatching: false, isNextUp: false)
                            },
                            onFilterChange: { filter in
                                Task {
                                    _ = await repository.fetchRecentlyAdded(itemType: filter.itemType)
                                }
                            },
                            onSeeAll: {
                                navigator.push(.library)
                            }
                        )
                    }

                    // Recommendations
                    if !repository.recommendedItems.isEmpty {
                        RecommendedRow(
                            title: "Recommended For You",
                            items: repository.recommendedItems,
                            onSelect: { item in
                                navigateToItemDetails(item: item)
                            },
                            onLongPress: { item in
                                openOptions(for: item, isContinueWatching: false, isNextUp: false)
                            }
                        )
                    }
                }
                .padding(.bottom, 100) // Space for bottom tab bar
            }
            .refreshable {
                await repository.refreshAll()
            }

            // Floating Top Header
            topHeaderBar
        }
        .task {
            if repository.heroBillboardItems.isEmpty {
                await repository.refreshAll()
            }
        }
        .sheet(isPresented: $showOptionsSheet) {
            if let item = selectedItemForOptions {
                ItemOptionsSheet(
                    item: item,
                    isInContinueWatching: isItemFromContinueWatching,
                    isInNextUp: isItemFromNextUp,
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

    // MARK: - Floating Top Header

    private var topHeaderBar: some View {
        HStack {
            // Khylo Wordmark or Logo
            HStack(spacing: 8) {
                #if canImport(UIKit)
                if let logo = loadBrandImage(named: "khylo_wordmark") {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                } else {
                    Text("KHYLO")
                        .font(KhyloTypography.title2)
                        .fontWeight(.heavy)
                        .foregroundColor(KhyloColors.accent)
                }
                #else
                Text("KHYLO")
                    .font(KhyloTypography.title2)
                    .fontWeight(.heavy)
                    .foregroundColor(KhyloColors.accent)
                #endif
            }

            Spacer()

            // Header Action Buttons
            HStack(spacing: KhyloSpacing.md) {
                Button(action: {
                    navigator.selectTab(.search)
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(KhyloColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(KhyloColors.surfaceElevated.opacity(0.85))
                        .clipShape(Circle())
                }

                Button(action: {
                    navigator.selectTab(.profile)
                }) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(KhyloColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(KhyloColors.surfaceElevated.opacity(0.85))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
        .padding(.top, KhyloSpacing.sm)
        .padding(.bottom, KhyloSpacing.sm)
        .background(
            LinearGradient(
                colors: [
                    KhyloColors.background.opacity(0.85),
                    KhyloColors.background.opacity(0.4),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Actions & Navigation

    private func handleItemPlayback(item: KhyloMediaItem, resume: Bool) {
        if item.type == "Audio" {
            navigator.push(.music(item: item))
        } else if item.type == "Audiobook" {
            navigator.push(.audiobook(item: item))
        } else if item.type == "Book" {
            navigator.push(.reader(item: item))
        } else {
            let resumeTicks = resume ? item.playbackPositionTicks : 0
            navigator.play(
                itemId: item.id,
                resumePositionTicks: resumeTicks,
                title: item.name
            )
        }
    }

    private func navigateToItemDetails(item: KhyloMediaItem) {
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

    private func openOptions(for item: KhyloMediaItem, isContinueWatching: Bool, isNextUp: Bool) {
        self.selectedItemForOptions = item
        self.isItemFromContinueWatching = isContinueWatching
        self.isItemFromNextUp = isNextUp
        self.showOptionsSheet = true
    }

    private func handleOptionAction(_ action: ItemOptionAction) {
        switch action {
        case .resume(let item):
            handleItemPlayback(item: item, resume: true)

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
            Task {
                await repository.markPlayed(itemId: item.id, isPlayed: !item.isPlayed)
            }

        case .toggleFavorite(let item):
            Task {
                await repository.toggleFavorite(itemId: item.id, isFavorite: !item.isFavorite)
            }

        case .hideFromUpNext(let seriesId):
            repository.dismissFromNextUp(seriesId: seriesId)

        case .removeFromContinueWatching(let itemId):
            Task {
                await repository.markPlayed(itemId: itemId, isPlayed: true)
            }

        case .viewDetails(let item):
            navigateToItemDetails(item: item)
        }
    }

    #if canImport(UIKit)
    private func loadBrandImage(named: String) -> UIImage? {
        if let path = Bundle.main.path(forResource: named, ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }
    #endif
}
