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

// MARK: - Recommended Row

public struct RecommendedRow: View {

    public let title: String
    public let items: [KhyloMediaItem]
    public let onSelect: (KhyloMediaItem) -> Void
    public let onLongPress: (KhyloMediaItem) -> Void

    public init(
        title: String = "Recommended For You",
        items: [KhyloMediaItem],
        onSelect: @escaping (KhyloMediaItem) -> Void,
        onLongPress: @escaping (KhyloMediaItem) -> Void
    ) {
        self.title = title
        self.items = items
        self.onSelect = onSelect
        self.onLongPress = onLongPress
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundColor(KhyloColors.accent)

                        Text(title)
                            .font(KhyloTypography.title3)
                            .foregroundColor(KhyloColors.textPrimary)
                    }

                    Spacer()
                }
                .padding(.horizontal, KhyloSpacing.lg)

                // Carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: KhyloSpacing.md) {
                        ForEach(items) { item in
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
}
