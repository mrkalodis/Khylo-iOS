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

// MARK: - Sort Options

public enum LibrarySortOption: String, CaseIterable, Identifiable {
    case titleAsc = "Title (A-Z)"
    case titleDesc = "Title (Z-A)"
    case dateAddedDesc = "Recently Added"
    case dateAddedAsc = "Oldest Added"
    case releaseDateDesc = "Release Date (Newest)"
    case releaseDateAsc = "Release Date (Oldest)"
    case ratingDesc = "Highest Rated"

    public var id: String { rawValue }

    public var sortBy: String {
        switch self {
        case .titleAsc, .titleDesc: return "SortName"
        case .dateAddedDesc, .dateAddedAsc: return "DateCreated"
        case .releaseDateDesc, .releaseDateAsc: return "PremiereDate"
        case .ratingDesc: return "CommunityRating"
        }
    }

    public var sortOrder: String {
        switch self {
        case .titleAsc, .dateAddedAsc, .releaseDateAsc: return "Ascending"
        case .titleDesc, .dateAddedDesc, .releaseDateDesc, .ratingDesc: return "Descending"
        }
    }
}

// MARK: - Library Grid View

public struct LibraryGridView: View {

    public let items: [KhyloMediaItem]
    public let isLoadingMore: Bool
    public let onSelect: (KhyloMediaItem) -> Void
    public let onLongPress: (KhyloMediaItem) -> Void
    public let onSortChange: (LibrarySortOption) -> Void
    public let onSearchChange: (String) -> Void
    public let onLoadMore: () -> Void

    @State private var searchText: String = ""
    @State private var currentSort: LibrarySortOption = .titleAsc

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: KhyloSpacing.md)
    ]

    public init(
        items: [KhyloMediaItem],
        isLoadingMore: Bool = false,
        onSelect: @escaping (KhyloMediaItem) -> Void,
        onLongPress: @escaping (KhyloMediaItem) -> Void,
        onSortChange: @escaping (LibrarySortOption) -> Void,
        onSearchChange: @escaping (String) -> Void,
        onLoadMore: @escaping () -> Void
    ) {
        self.items = items
        self.isLoadingMore = isLoadingMore
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        self.onSortChange = onSortChange
        self.onSearchChange = onSearchChange
        self.onLoadMore = onLoadMore
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search & Filter Toolbar
            HStack(spacing: KhyloSpacing.sm) {
                // Search Input
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(KhyloColors.textTertiary)

                    TextField("Filter library...", text: $searchText)
                        .font(KhyloTypography.body)
                        .foregroundColor(KhyloColors.textPrimary)
                        .onChange(of: searchText) { newValue in
                            onSearchChange(newValue)
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            onSearchChange("")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, KhyloSpacing.md)
                .frame(height: 40)
                .background(KhyloColors.surfaceElevated)
                .cornerRadius(KhyloRadius.sm)

                // Sort Menu
                Menu {
                    Picker("Sort By", selection: $currentSort) {
                        ForEach(LibrarySortOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(width: 40, height: 40)
                    .background(KhyloColors.surfaceElevated)
                    .foregroundColor(KhyloColors.accent)
                    .cornerRadius(KhyloRadius.sm)
                }
                .onChange(of: currentSort) { newSort in
                    onSortChange(newSort)
                }
            }
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.vertical, KhyloSpacing.sm)

            // Responsive Poster Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: KhyloSpacing.md) {
                    ForEach(filteredItems) { item in
                        KhyloPosterCard(
                            imageURL: item.posterURL() ?? item.backdropURL(),
                            title: item.name,
                            subtitle: item.displaySubtitle,
                            progress: item.progress > 0 ? item.progress : nil,
                            isUnplayed: item.isUnplayed,
                            width: nil,
                            onTap: { onSelect(item) },
                            onLongPress: { onLongPress(item) }
                        )
                        .onAppear {
                            if item == filteredItems.last {
                                onLoadMore()
                            }
                        }
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)
                .padding(.top, KhyloSpacing.sm)
                .padding(.bottom, 120)

                if isLoadingMore {
                    ProgressView()
                        .tint(KhyloColors.accent)
                        .padding(.vertical, KhyloSpacing.lg)
                }
            }
        }
    }

    private var filteredItems: [KhyloMediaItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
