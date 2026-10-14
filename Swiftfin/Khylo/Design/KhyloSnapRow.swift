//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Snapping Helpers

private extension View {
    @ViewBuilder
    func khyloScrollSnapping() -> some View {
        if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
            self.scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }

    @ViewBuilder
    func khyloScrollTarget() -> some View {
        if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
            self.scrollTargetLayout()
        } else {
            self
        }
    }
}

// MARK: - Generic Snap Row

public struct KhyloSnapRow<Item: Identifiable, Card: View>: View {
    public let title: String
    public let items: [Item]
    public let spacing: CGFloat
    public let contentPadding: CGFloat
    public let onSeeAll: (() -> Void)?
    public let cardBuilder: (Item) -> Card

    public init(
        title: String,
        items: [Item],
        spacing: CGFloat = KhyloSpacing.md,
        contentPadding: CGFloat = KhyloSpacing.lg,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder cardBuilder: @escaping (Item) -> Card
    ) {
        self.title = title
        self.items = items
        self.spacing = spacing
        self.contentPadding = contentPadding
        self.onSeeAll = onSeeAll
        self.cardBuilder = cardBuilder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            // Row Header
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(KhyloTypography.title3)
                    .foregroundColor(KhyloColors.textPrimary)

                Spacer()

                if let onSeeAll {
                    Button(action: { onSeeAll() }) {
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
            .padding(.horizontal, contentPadding)

            // Horizontal scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        cardBuilder(item)
                    }
                }
                .padding(.horizontal, contentPadding)
                .khyloScrollTarget()
            }
            .khyloScrollSnapping()
        }
    }
}

// MARK: - Convenience Poster Row

public struct KhyloPosterRow: View {
    public let title: String
    public let items: [KhyloMediaItem]
    public let cardWidth: CGFloat?
    public let onSeeAll: (() -> Void)?
    public let onSelect: (KhyloMediaItem) -> Void
    public let onLongPress: ((KhyloMediaItem) -> Void)?

    public init(
        title: String,
        items: [KhyloMediaItem],
        cardWidth: CGFloat? = 140,
        onSeeAll: (() -> Void)? = nil,
        onSelect: @escaping (KhyloMediaItem) -> Void,
        onLongPress: ((KhyloMediaItem) -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.cardWidth = cardWidth
        self.onSeeAll = onSeeAll
        self.onSelect = onSelect
        self.onLongPress = onLongPress
    }

    public var body: some View {
        KhyloSnapRow(
            title: title,
            items: items,
            onSeeAll: onSeeAll
        ) { item in
            KhyloPosterCard(
                imageURL: item.imageURL,
                title: item.title,
                subtitle: item.subtitle,
                progress: item.progress,
                isUnplayed: item.isUnplayed,
                width: cardWidth,
                onTap: { onSelect(item) },
                onLongPress: { onLongPress?(item) }
            )
        }
    }
}

// MARK: - Convenience Wide Row

public struct KhyloWideRow: View {
    public let title: String
    public let items: [KhyloMediaItem]
    public let cardWidth: CGFloat?
    public let onSeeAll: (() -> Void)?
    public let onSelect: (KhyloMediaItem) -> Void
    public let onLongPress: ((KhyloMediaItem) -> Void)?

    public init(
        title: String,
        items: [KhyloMediaItem],
        cardWidth: CGFloat? = 260,
        onSeeAll: (() -> Void)? = nil,
        onSelect: @escaping (KhyloMediaItem) -> Void,
        onLongPress: ((KhyloMediaItem) -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.cardWidth = cardWidth
        self.onSeeAll = onSeeAll
        self.onSelect = onSelect
        self.onLongPress = onLongPress
    }

    public var body: some View {
        KhyloSnapRow(
            title: title,
            items: items,
            onSeeAll: onSeeAll
        ) { item in
            KhyloWideCard(
                imageURL: item.imageURL,
                title: item.title,
                subtitle: item.subtitle,
                progress: item.progress,
                isUnplayed: item.isUnplayed,
                width: cardWidth,
                onTap: { onSelect(item) },
                onLongPress: { onLongPress?(item) }
            )
        }
    }
}
