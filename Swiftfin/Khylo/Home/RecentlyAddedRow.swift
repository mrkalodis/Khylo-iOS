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

// MARK: - Recently Added Category Filter

public enum RecentlyAddedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case movies = "Movies"
    case shows = "TV Shows"

    public var id: String { rawValue }

    public var itemType: String? {
        switch self {
        case .all: return nil
        case .movies: return "Movie"
        case .shows: return "Series"
        }
    }
}

// MARK: - Recently Added Row

public struct RecentlyAddedRow: View {

    public let items: [KhyloMediaItem]
    public let onSelect: (KhyloMediaItem) -> Void
    public let onLongPress: (KhyloMediaItem) -> Void
    public let onFilterChange: ((RecentlyAddedFilter) -> Void)?
    public let onSeeAll: (() -> Void)?

    @State private var selectedFilter: RecentlyAddedFilter = .all

    public init(
        items: [KhyloMediaItem],
        onSelect: @escaping (KhyloMediaItem) -> Void,
        onLongPress: @escaping (KhyloMediaItem) -> Void,
        onFilterChange: ((RecentlyAddedFilter) -> Void)? = nil,
        onSeeAll: (() -> Void)? = nil
    ) {
        self.items = items
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        self.onFilterChange = onFilterChange
        self.onSeeAll = onSeeAll
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                // Header with See All
                HStack(alignment: .firstTextBaseline) {
                    Text("Recently Added")
                        .font(KhyloTypography.title3)
                        .foregroundColor(KhyloColors.textPrimary)

                    Spacer()

                    if let onSeeAll {
                        Button {
                            onSeeAll()
                        } label: {
                            HStack(spacing: 3) {
                                Text("See All")
                                    .font(KhyloTypography.subheadline)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(KhyloColors.accent)
                        }
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)

                // Filter Pills
                HStack(spacing: KhyloSpacing.xs) {
                    ForEach(RecentlyAddedFilter.allCases) { filter in
                        RecentlyAddedFilterPill(
                            filter: filter,
                            isSelected: selectedFilter == filter,
                            onSelect: {
                                selectedFilter = filter
                                onFilterChange?(filter)
                            }
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, KhyloSpacing.lg)
                .padding(.bottom, 2)

                // 2:3 Posters Carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: KhyloSpacing.md) {
                        ForEach(filteredItems) { item in
                            KhyloPosterCard(
                                imageURL: item.posterURL() ?? item.backdropURL(),
                                title: item.name,
                                subtitle: item.displaySubtitle,
                                progress: item.progress > 0 ? item.progress : nil,
                                isUnplayed: item.isUnplayed,
                                width: 140,
                                onTap: { onSelect(item) },
                                onLongPress: { onLongPress(item) }
                            )
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                }
            }
        }
    }

    private var filteredItems: [KhyloMediaItem] {
        guard let filterType = selectedFilter.itemType else { return items }
        return items.filter { $0.type == filterType }
    }
}

// MARK: - Recently Added Filter Pill

private struct RecentlyAddedFilterPill: View {
    let filter: RecentlyAddedFilter
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        } label: {
            Text(filter.rawValue)
                .font(KhyloTypography.captionMedium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? KhyloColors.accent : KhyloColors.surfaceElevated)
                )
                .foregroundColor(isSelected ? KhyloColors.textPrimary : KhyloColors.textSecondary)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : KhyloColors.border.opacity(0.4), lineWidth: 1)
                )
        }
    }
}
