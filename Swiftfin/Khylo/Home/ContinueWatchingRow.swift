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

// MARK: - Continue Watching Row

public struct ContinueWatchingRow: View {

    public let items: [KhyloMediaItem]
    public let onSelect: (KhyloMediaItem) -> Void
    public let onLongPress: (KhyloMediaItem) -> Void
    public let onSeeAll: (() -> Void)?

    public init(
        items: [KhyloMediaItem],
        onSelect: @escaping (KhyloMediaItem) -> Void,
        onLongPress: @escaping (KhyloMediaItem) -> Void,
        onSeeAll: (() -> Void)? = nil
    ) {
        self.items = items
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        self.onSeeAll = onSeeAll
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                // Section Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Continue Watching")
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
                .padding(.horizontal, KhyloSpacing.lg)

                // 16:9 Horizontal Carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: KhyloSpacing.md) {
                        ForEach(items) { item in
                            KhyloWideCard(
                                imageURL: item.backdropURL() ?? item.posterURL(),
                                title: item.type == "Episode" ? (item.seriesName ?? item.name) : item.name,
                                subtitle: item.type == "Episode" ? item.displaySubtitle : remainingDurationString(for: item),
                                progress: item.progress > 0 ? item.progress : 0.05,
                                isUnplayed: false,
                                width: 260,
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

    private func remainingDurationString(for item: KhyloMediaItem) -> String {
        guard let runTime = item.runTimeTicks, runTime > 0,
              let pos = item.playbackPositionTicks else {
            return item.durationString
        }
        let remainingTicks = max(runTime - pos, 0)
        let remainingSeconds = Int(remainingTicks / 10_000_000)
        let minutes = remainingSeconds / 60
        if minutes > 60 {
            return "\(minutes / 60)h \(minutes % 60)m left"
        } else {
            return "\(minutes)m left"
        }
    }
}
