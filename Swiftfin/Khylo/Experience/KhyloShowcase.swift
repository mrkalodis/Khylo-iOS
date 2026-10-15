//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// Khylo's browse vocabulary: one card, one row, one set of tabs.
//
// The card is a portrait cover with a two-line caption. Everything that's
// "in progress" shows a slim amber bar on the cover's bottom edge, so where you
// left off reads the same on Home, in libraries and in grids.

// MARK: - Card

struct KhyloShelfCard: View {

    enum Shape {
        /// 2:3 covers: movies, shows, episodes (shown with their show's cover), books.
        case portrait
        /// 1:1 covers: albums, audiobooks.
        case square
    }

    let item: BaseItemDto
    var shape: Shape = .portrait
    var width: CGFloat = 118
    /// Overrides the generated caption's second line.
    var detail: String? = nil

    private var coverHeight: CGFloat { shape == .portrait ? width * 1.5 : width }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cover
                .frame(width: width, height: coverHeight)
                .overlay(alignment: .bottom) { progressBar }
                .overlay(alignment: .topTrailing) { badge }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let line = detail ?? secondLine {
                    Text(line)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    // MARK: Cover

    @ViewBuilder
    private var cover: some View {
        let style: KhyloArtwork.Style = shape == .portrait ? .poster : .square
        if let url = KhyloArtwork.url(for: item, style: style, width: width) {
            KhyloImage(url: url, placeholderSymbol: placeholderSymbol)
        } else if let parent = item.parentID, item.type == .audioBook || item.type == .audio {
            KhyloImage(url: KhyloArtwork.url(itemID: parent, type: .primary, tag: nil, width: width), placeholderSymbol: placeholderSymbol)
        } else if item.type == .book {
            KhyloGeneratedCover(name: item.name ?? "", width: width)
        } else {
            ZStack {
                KhyloStyle.placeholder
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress = item.khyloProgress {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.55))
                    Rectangle().fill(KhyloStyle.accent).frame(width: max(3, proxy.size.width * progress))
                }
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if item.khyloIsPlayed, item.type != .series {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(KhyloStyle.accent))
                .padding(6)
        } else if let unplayed = item.userData?.unplayedItemCount, unplayed > 0, item.type == .series {
            Text("\(unplayed)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(KhyloStyle.accent))
                .padding(6)
        }
    }

    // MARK: Caption

    private var title: String {
        switch item.type {
        case .episode: item.seriesName ?? item.name ?? ""
        case .audioBook, .audio where shape == .square: KhyloAudiobook.cleanTitle(item.album ?? item.name ?? "").title
        case .book: KhyloGeneratedCover.parse(item.name ?? "").title
        default: item.name ?? ""
        }
    }

    /// "S1 · E4 · 24m left", "2019", "James Patterson", …
    private var secondLine: String? {
        var parts: [String] = []
        switch item.type {
        case .episode:
            if let label = item.khyloEpisodeLabel { parts.append(label) }
            if let remaining = item.khyloRemaining {
                parts.append(remaining)
            } else if let name = item.name, item.khyloProgress == nil {
                parts.append(name)
            }
        case .movie:
            if let remaining = item.khyloRemaining {
                parts.append(remaining)
            } else if let year = item.productionYear {
                parts.append(String(year))
            }
        case .series:
            if let year = item.productionYear { parts.append(String(year)) }
        case .book:
            if let author = KhyloGeneratedCover.parse(item.name ?? "").author { parts.append(author) }
        case .audioBook, .audio:
            if let remaining = item.khyloRemaining {
                parts.append(remaining)
            } else if let author = item.albumArtist ?? item.artists?.first {
                parts.append(author)
            }
        case .musicAlbum:
            if let artist = item.albumArtist ?? item.artists?.first { parts.append(artist) }
        default:
            if let year = item.productionYear { parts.append(String(year)) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var placeholderSymbol: String {
        switch item.type {
        case .audioBook, .audio: "headphones"
        case .musicAlbum: "music.note"
        case .book: "book.closed"
        case .series, .episode, .season: "tv"
        default: "film"
        }
    }
}

// MARK: - Row

/// Section header with an optional "See All", over a sideways list.
struct KhyloRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                }
                Spacer()
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        Text("See All")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(KhyloStyle.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KhyloStyle.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    content()
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Tabs

/// Segmented text tabs for a library's For You · Browse · Collections.
struct KhyloSegmentTabs<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.0) { tab, title in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = tab }
                } label: {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selection == tab ? .white : KhyloStyle.secondaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(Color.white.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Status bar scrim

/// Darkens the status bar area so scrolled artwork never collides with the clock.
struct KhyloStatusBarScrim: View {

    /// Measured from the window: overlays don't always receive the real safe-area inset.
    private var statusBarHeight: CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        return max(window?.safeAreaInsets.top ?? 0, 44)
    }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: KhyloStyle.canvas.opacity(0.94), location: 0),
                    .init(color: KhyloStyle.canvas.opacity(0.8), location: 0.65),
                    .init(color: KhyloStyle.canvas.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: statusBarHeight + 10)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
