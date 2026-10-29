//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

extension KhyloLibraryKind {

    /// The scope a library's categories are built in, or nil for libraries
    /// that aren't organised by genre (audiobooks, podcasts, photos, playlists).
    static func categoryScope(for library: BaseItemDto) -> KhyloSearchScreen.Scope? {
        switch KhyloAPI.extendedCollectionType(for: library) {
        case .comics: return .books
        case .audiobooks, .podcasts: return nil
        case nil: break
        }
        switch library.collectionType {
        case .movies, .tvshows: return .video
        case .books: return .books
        case .music: return .music
        default: return nil
        }
    }
}

// MARK: - For You

/// A library's landing page, in the same style as Music's: search at the top,
/// a featured title, rows with a title and a line about them, and the library's
/// categories as artwork tiles.
struct KhyloLibraryForYou: View {

    let library: BaseItemDto
    let sections: [KhyloFeedSection]
    let isLoading: Bool
    let onBrowse: () -> Void

    @State private var query = ""
    @State private var term = ""

    private var isVideo: Bool {
        library.collectionType == .movies || library.collectionType == .tvshows
    }

    private var featured: (item: BaseItemDto, label: String, resumes: Bool)? {
        if let resume = sections.first(where: { $0.id.hasSuffix("-resume") || $0.id.hasSuffix("-listening") })?.items.first {
            return (resume, isVideo ? "Continue Watching" : "Continue Listening", !isVideo)
        }
        if let latest = sections.first(where: { $0.id.hasSuffix("-new") })?.items.first {
            return (latest, "New in \(library.name ?? "your library")", false)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            KhyloLibrarySearchField(placeholder: "Search \(library.name ?? "this library")", text: $query)

            if term.isEmpty {
                if isLoading {
                    ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 60)
                } else if sections.isEmpty {
                    KhyloEmptyState(systemImage: "sparkles", title: "Nothing to show yet", message: "Browse the full library instead.", actionTitle: "Browse", action: onBrowse)
                        .padding(.top, 20)
                } else {
                    if let featured {
                        if isVideo {
                            KhyloLibraryHero(item: featured.item, label: featured.label)
                        } else {
                            KhyloCoverHero(
                                item: featured.item,
                                label: featured.label,
                                shape: KhyloLibraryKind(library).shape,
                                symbol: KhyloLibraryKind(library).symbol,
                                resumes: featured.resumes
                            )
                        }
                    }
                    KhyloFeedView(sections: sections)
                    if KhyloLibraryKind.categoryScope(for: library) != nil {
                        KhyloCategoryGrid(
                            scope: KhyloLibraryKind.categoryScope(for: library) ?? .video,
                            limit: 6,
                            onSeeAll: onBrowse,
                            library: library
                        )
                    }
                }
            } else {
                KhyloLibrarySearchResults(library: library, term: term)
            }
        }
        .padding(.top, 4)
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            term = trimmed
        }
    }
}

/// The title to feature at the top of a movie or show library.
private struct KhyloLibraryHero: View {

    let item: BaseItemDto
    let label: String

    @Router private var router

    private var meta: String {
        var parts: [String] = []
        if item.type == .episode {
            if let season = item.parentIndexNumber, let episode = item.indexNumber { parts.append("S\(season) · E\(episode)") }
            if let name = item.name { parts.append(name) }
        } else {
            if let year = item.productionYear { parts.append(String(year)) }
            if let genre = item.genres?.first { parts.append(genre) }
            if let rating = item.officialRating { parts.append(rating) }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            router.route(to: .khyloItem(item))
        } label: {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color.white.opacity(0.06))
                KhyloImage(url: KhyloArtwork.url(for: item, style: .backdrop, width: 900), showsPlaceholder: false)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35), .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(label.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                        .foregroundColor(KhyloStyle.accent)
                    Text(item.seriesName ?? item.name ?? "")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(18)

                if let progress = item.khyloProgress, progress > 0 {
                    KhyloProgressLine(progress: progress)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .padding(.horizontal, KhyloStyle.gutter)
    }
}

/// The title to feature at the top of a books, audiobooks, podcasts or comics
/// library: its cover, large, over a soft blur of the same artwork.
private struct KhyloCoverHero: View {

    let item: BaseItemDto
    let label: String
    let shape: KhyloLibraryKind.Shape
    let symbol: String
    /// Tapping goes straight back to listening instead of opening the page.
    let resumes: Bool

    @Router private var router

    private var coverStyle: KhyloArtwork.Style { shape == .poster ? .poster : .square }

    private var coverSize: CGSize {
        shape == .poster ? CGSize(width: 108, height: 162) : CGSize(width: 140, height: 140)
    }

    private var title: String {
        if item.type == .audio || item.type == .audioBook { return item.album ?? item.seriesName ?? item.name ?? "" }
        return item.seriesName ?? item.name ?? ""
    }

    private var byline: String {
        var parts: [String] = []
        if let author = item.albumArtist ?? item.artists?.first ?? item.people?.first(where: { $0.type == .author })?.name {
            parts.append(author)
        }
        if let year = item.productionYear { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            if resumes {
                KhyloFeedActions.resumeListening(item)
            } else {
                router.route(to: .khyloItem(item))
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color.white.opacity(0.06))
                KhyloImage(url: KhyloArtwork.url(for: item, style: .square, width: 300), showsPlaceholder: false)
                    .blur(radius: 40)
                    .scaleEffect(1.4)
                LinearGradient(
                    colors: [.black.opacity(0.25), .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                HStack(alignment: .bottom, spacing: 16) {
                    KhyloImage(url: KhyloArtwork.url(for: item, style: coverStyle, width: coverSize.width * 2), placeholderSymbol: symbol)
                        .frame(width: coverSize.width, height: coverSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(label.uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.4)
                            .foregroundColor(KhyloStyle.accent)
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(3)
                        if !byline.isEmpty {
                            Text(byline)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)

                if let progress = item.khyloProgress, progress > 0 {
                    KhyloProgressLine(progress: progress)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .padding(.horizontal, KhyloStyle.gutter)
    }
}

// MARK: - Search

/// What matches a search in one library, under the search field.
struct KhyloLibrarySearchResults: View {

    let library: BaseItemDto
    let term: String

    @State private var items: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var contentWidth: CGFloat = UIScreen.main.bounds.width
    @Router private var router

    private let spacing: CGFloat = 12

    var body: some View {
        let kind = KhyloLibraryKind(library)
        let columns = kind.shape == .poster ? 3 : 2
        let width = (contentWidth - KhyloStyle.gutter * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 40)
            } else if items.isEmpty {
                Text("Nothing found for \u{201C}\(term)\u{201D}")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(width), spacing: spacing, alignment: .top), count: columns),
                    spacing: 22
                ) {
                    ForEach(items, id: \.id) { item in
                        Button {
                            router.route(to: .khyloItem(item))
                        } label: {
                            switch kind.shape {
                            case .poster: KhyloShelfCard(item: item, shape: .portrait, width: width)
                            case .square: KhyloShelfCard(item: item, shape: .square, width: width)
                            case .landscape: KhyloLandscapeCard(item: item, width: width)
                            }
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .task(id: term) {
            isLoading = items.isEmpty
            let kind = KhyloLibraryKind(library)
            let found = try? await KhyloAPI.items(
                parentID: library.id,
                // Folder-organised libraries (audiobooks) find matching folders anywhere below.
                types: kind.recursive ? kind.types : [.folder],
                sortBy: [.sortName],
                searchTerm: term,
                recursive: true,
                limit: 60
            )
            withAnimation(.easeOut(duration: 0.2)) { items = found?.items ?? [] }
            isLoading = false
        }
    }
}

// MARK: - Browse

/// A library's Browse tab: its categories as artwork tiles, or every title.
struct KhyloLibraryBrowse: View {

    enum Mode: Hashable {
        case categories
        case titles
    }

    let library: BaseItemDto
    let scope: KhyloSearchScreen.Scope
    let header: AnyView

    @State private var mode: Mode = .categories

    private var switcher: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            KhyloSegmentTabs(tabs: [(Mode.categories, "Categories"), (Mode.titles, "All Titles")], selection: $mode)
                .padding(.horizontal, KhyloStyle.gutter - 4)
        }
    }

    var body: some View {
        switch mode {
        case .categories:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switcher
                    KhyloCategoryGrid(
                        scope: scope,
                        limit: nil,
                        onSeeAll: nil,
                        showsTitle: false,
                        library: library,
                        onLoaded: { count in
                            // A library with no genres goes straight to its titles.
                            if count == 0 { mode = .titles }
                        }
                    )
                }
                .padding(.bottom, 40)
            }
        case .titles:
            KhyloLibraryBrowser(library: library) { _ in switcher }
        }
    }
}
