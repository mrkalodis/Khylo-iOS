//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

/// A row on Home or a library's For You page.
struct KhyloFeedSection: Identifiable {

    enum Action {
        /// Tap resumes playback right away (Continue Watching, Up Next).
        case play
        /// Tap resumes the audiobook with its whole book queued.
        case resumeListening
        /// Tap opens the item's page.
        case open
    }

    let id: String
    let title: String
    var subtitle: String? = nil
    var shape: KhyloShelfCard.Shape = .portrait
    var action: Action = .open
    var items: [BaseItemDto]
    /// Where the row's "See All" leads, if anywhere.
    var seeAll: NavigationRoute? = nil
    /// Per-item caption override (e.g. a rating).
    var detail: ((BaseItemDto) -> String?)? = nil
}

enum KhyloFeedBuilder {

    /// Rows for one library: what's in progress there, what's new, the best of it, and a few genres.
    static func sections(for library: BaseItemDto, includeResume: Bool) async -> [KhyloFeedSection] {
        guard let id = library.id else { return [] }
        let kind = KhyloLibraryKind(library)
        let name = library.name ?? "Library"
        let extended = KhyloAPI.extendedCollectionType(for: library)

        switch (library.collectionType, extended) {
        case (_, .audiobooks?):
            async let listening = KhyloAPI.resume(limit: 20, mediaTypes: [.audio])
            async let latest = KhyloAPI.latest(in: id, limit: 24)
            var rows: [KhyloFeedSection] = []
            let resumeParts = uniqueBooks((try? await listening) ?? [])
            if includeResume, !resumeParts.isEmpty {
                rows.append(.init(id: "\(id)-listening", title: "Continue Listening", shape: .square, action: .resumeListening, items: resumeParts))
            }
            let newBooks = uniqueBooks((try? await latest) ?? [])
            if !newBooks.isEmpty {
                rows.append(.init(id: "\(id)-new", title: "Recently Added Audiobooks", shape: .square, items: newBooks, seeAll: .khyloLibrary(library)))
            }
            return rows

        case (.music, _):
            async let latest = KhyloAPI.latest(in: id, limit: 20)
            async let mostPlayed = KhyloAPI.items(parentID: id, types: [.musicAlbum], sortBy: [.playCount], sortOrder: .descending, limit: 20)
            async let random = KhyloAPI.items(parentID: id, types: [.musicAlbum], sortBy: [.random], limit: 20)
            var rows: [KhyloFeedSection] = []
            if let items = try? await latest, !items.isEmpty {
                rows.append(.init(id: "\(id)-new", title: "Recently Added Music", shape: .square, items: items, seeAll: .khyloLibrary(library)))
            }
            if let items = try? await mostPlayed.items, !items.isEmpty {
                rows.append(.init(id: "\(id)-top", title: "Most Played", shape: .square, items: items))
            }
            if let items = try? await random.items, !items.isEmpty {
                rows.append(.init(id: "\(id)-discover", title: "Rediscover", shape: .square, items: items))
            }
            return rows

        case (.books, _):
            async let latest = KhyloAPI.items(parentID: id, types: [.book], sortBy: [.dateCreated], sortOrder: .descending, limit: 20)
            async let random = KhyloAPI.items(parentID: id, types: [.book], sortBy: [.random], limit: 20)
            var rows: [KhyloFeedSection] = []
            if let items = try? await latest.items, !items.isEmpty {
                rows.append(.init(id: "\(id)-new", title: "Recently Added Books", items: items, seeAll: .khyloLibrary(library)))
            }
            if let items = try? await random.items, !items.isEmpty {
                rows.append(.init(id: "\(id)-pick", title: "Something to Read", items: items))
            }
            return rows

        case (.movies, _), (.tvshows, _):
            let isMovies = library.collectionType == .movies
            let types = kind.types ?? [.movie]
            async let resume = KhyloAPI.resume(limit: 20)
            async let latest = KhyloAPI.latest(in: id, limit: 20)
            async let top = KhyloAPI.items(parentID: id, types: types, sortBy: [.communityRating], sortOrder: .descending, limit: 20)
            async let unwatched = KhyloAPI.items(parentID: id, types: types, sortBy: [.random], filters: [.isUnplayed], limit: 20)
            async let genreList = KhyloAPI.genres(parentID: id, types: types)

            var rows: [KhyloFeedSection] = []

            if includeResume {
                let inLibrary = ((try? await resume) ?? []).filter { item in
                    isMovies ? item.type == .movie : item.type == .episode
                }
                if !inLibrary.isEmpty {
                    rows.append(.init(id: "\(id)-resume", title: "Continue Watching", action: .play, items: inLibrary))
                }
            }

            if let items = try? await latest, !items.isEmpty {
                rows.append(.init(id: "\(id)-new", title: isMovies ? "Recently Added Movies" : "Recently Added Shows", items: items, seeAll: .khyloLibrary(library)))
            }

            if let items = try? await top.items, items.count >= 5 {
                rows.append(.init(
                    id: "\(id)-top",
                    title: "Highest Rated",
                    items: items,
                    detail: { item in
                        guard let score = item.communityRating, score > 0 else { return nil }
                        return "★ " + String(format: "%.1f", score) + (item.productionYear.map { " · \($0)" } ?? "")
                    }
                ))
            }

            // Two genres, rotating daily.
            let genres = ((try? await genreList) ?? []).compactMap(\.name)
            if !genres.isEmpty {
                let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
                let picks = [genres[day % genres.count], genres[(day * 7 + 3) % genres.count]]
                for genre in Set(picks).sorted() {
                    if let items = try? await KhyloAPI.items(parentID: id, types: types, sortBy: [.random], genres: [genre], limit: 20).items,
                       items.count >= 4 {
                        rows.append(.init(
                            id: "\(id)-genre-\(genre)",
                            title: genre,
                            items: items,
                            seeAll: .khyloCollection(title: genre, id: "\(id)-genre-\(genre)") { start, limit in
                                try await KhyloAPI.items(parentID: id, types: types, sortBy: [.communityRating], sortOrder: .descending, genres: [genre], startIndex: start, limit: limit)
                            }
                        ))
                    }
                }
            }

            if let items = try? await unwatched.items, !items.isEmpty {
                rows.append(.init(id: "\(id)-unwatched", title: "Haven't Watched Yet", items: items))
            }
            return rows

        default:
            guard let items = try? await KhyloAPI.latest(in: id, limit: 20), !items.isEmpty else { return [] }
            return [.init(id: "\(id)-new", title: "Recently Added in \(name)", shape: kind.shape == .square ? .square : .portrait, items: items, seeAll: .khyloLibrary(library))]
        }
    }

    /// Audiobooks arrive as parts; keep one per book.
    static func uniqueBooks(_ parts: [BaseItemDto]) -> [BaseItemDto] {
        var seen = Set<String>()
        return parts.filter { part in
            guard part.type == .audioBook || part.type == .audio else { return true }
            return seen.insert(part.parentID ?? part.album ?? part.id ?? "").inserted
        }
    }
}

// MARK: - Removing from rows

extension Notification.Name {
    /// Watch progress changed outside the player (removed from a row, marked watched).
    static let khyloProgressDidChange = Notification.Name("khyloProgressDidChange")
}

/// Items taken off Continue Watching or Up Next.
///
/// Continue Watching removal clears the saved position on the server, so it's
/// gone on every device. The server has no way to hide an Up Next episode, so
/// those are remembered here by episode: once you watch on, the show's next
/// episode appears again.
@MainActor
final class KhyloRowRemovals: ObservableObject {

    static let shared = KhyloRowRemovals()

    /// Removed this session, hidden at once while the server catches up.
    @Published private(set) var removedIDs: Set<String> = []

    private static let upNextKey = "khylo.upnext.hidden"
    private var hiddenUpNext: [String] = UserDefaults.standard.stringArray(forKey: upNextKey) ?? []
    private var playbackObserver: NSObjectProtocol?

    private init() {
        // After watching something, the server's rows are the truth again
        // (a removed title you went back to belongs in Continue Watching).
        playbackObserver = NotificationCenter.default.addObserver(forName: .khyloPlaybackDidEnd, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.removedIDs.removeAll() }
        }
    }

    func removeFromContinueWatching(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        withAnimation(.easeInOut(duration: 0.25)) { _ = removedIDs.insert(id) }
        Task {
            try? await KhyloAPI.removeFromResume(itemID: id)
            NotificationCenter.default.post(name: .khyloProgressDidChange, object: nil)
        }
    }

    func removeFromUpNext(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        withAnimation(.easeInOut(duration: 0.25)) { _ = removedIDs.insert(id) }
        hiddenUpNext = Array(([id] + hiddenUpNext.filter { $0 != id }).prefix(200))
        UserDefaults.standard.set(hiddenUpNext, forKey: Self.upNextKey)
    }

    func visibleUpNext(_ items: [BaseItemDto]) -> [BaseItemDto] {
        items.filter { !hiddenUpNext.contains($0.id ?? "") }
    }
}

// MARK: - Rendering

struct KhyloFeedView: View {

    let sections: [KhyloFeedSection]

    @Router private var router
    @ObservedObject private var removals = KhyloRowRemovals.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ForEach(visibleSections) { section in
                KhyloRow(
                    title: section.title,
                    subtitle: section.subtitle,
                    onSeeAll: section.seeAll.map { route in { router.route(to: route) } }
                ) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        Button {
                            open(item, in: section)
                        } label: {
                            KhyloShelfCard(
                                item: item,
                                shape: section.shape,
                                width: section.shape == .square ? 140 : 118,
                                detail: section.detail?(item)
                            )
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                        .contextMenu { menu(for: item, in: section) }
                    }
                }
            }
        }
    }

    /// Sections without anything just removed (and without rows left empty by it).
    private var visibleSections: [KhyloFeedSection] {
        guard !removals.removedIDs.isEmpty else { return sections }
        return sections.compactMap { section in
            let items = section.items.filter { !removals.removedIDs.contains($0.id ?? "") }
            guard !items.isEmpty else { return nil }
            var copy = section
            copy.items = items
            return copy
        }
    }

    private enum Removal {
        case continueWatching
        case upNext
    }

    private func removal(for section: KhyloFeedSection) -> Removal? {
        if section.id.hasSuffix("-resume") { return .continueWatching }
        if section.id.hasSuffix("-upnext") { return .upNext }
        return nil
    }

    private func open(_ item: BaseItemDto, in section: KhyloFeedSection) {
        switch section.action {
        case .play:
            Task {
                do {
                    try await KhyloPlayback.play(item, router: router)
                } catch {
                    router.route(to: .khyloItem(item))
                }
            }
        case .resumeListening:
            KhyloFeedActions.resumeListening(item)
        case .open:
            router.route(to: .khyloItem(item))
        }
    }

    @ViewBuilder
    private func menu(for item: BaseItemDto, in section: KhyloFeedSection) -> some View {
        switch removal(for: section) {
        case .continueWatching:
            Button(role: .destructive) {
                removals.removeFromContinueWatching(item)
            } label: {
                Label("Remove from Continue Watching", systemImage: "minus.circle")
            }
        case .upNext:
            Button(role: .destructive) {
                removals.removeFromUpNext(item)
            } label: {
                Label("Remove from Up Next", systemImage: "minus.circle")
            }
        case nil:
            EmptyView()
        }
        Button {
            router.route(to: .khyloItem(item))
        } label: {
            Label("Details", systemImage: "info.circle")
        }
        if item.type == .episode, let seriesID = item.seriesID {
            Button {
                Task {
                    if let series = try? await KhyloAPI.item(seriesID) {
                        router.route(to: .khyloItem(series))
                    }
                }
            } label: {
                Label("Go to Show", systemImage: "tv")
            }
        }
        if item.type == .movie || item.type == .episode || item.type == .series {
            Button {
                Task {
                    try? await KhyloAPI.setPlayed(!item.khyloIsPlayed, itemID: item.id ?? "")
                    NotificationCenter.default.post(name: .khyloProgressDidChange, object: nil)
                }
            } label: {
                Label(item.khyloIsPlayed ? "Mark as Unwatched" : "Mark as Watched", systemImage: "checkmark.circle")
            }
        }
    }
}

enum KhyloFeedActions {

    /// Resumes an audiobook from its part in progress, with the whole book queued.
    @MainActor
    static func resumeListening(_ part: BaseItemDto) {
        Task {
            guard let parentID = part.parentID,
                  let book = try? await KhyloAPI.item(parentID),
                  let parts = try? await KhyloAudiobook.parts(of: parentID),
                  let index = parts.firstIndex(where: { $0.id == part.id })
            else {
                KhyloAudioPlayer.shared.play([part], kind: part.type == .audioBook ? .audiobook : .music)
                return
            }
            KhyloAudiobook.play(book: book, parts: parts, startAt: index)
        }
    }
}
