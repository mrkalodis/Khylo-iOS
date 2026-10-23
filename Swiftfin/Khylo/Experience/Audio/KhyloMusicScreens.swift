//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Music library

/// Music: Albums, Artists and Songs, each searchable.
struct KhyloMusicLibraryScreen: View {

    let library: BaseItemDto
    /// Replaces the plain title, e.g. with the Libraries tab's switcher.
    var header: AnyView? = nil

    /// Artists and categories; albums and songs are found through them, or with search.
    enum Section: String, CaseIterable {
        case artists = "Artists"
        case categories = "Categories"
    }

    @State private var section: Section = .artists
    @State private var query = ""
    @State private var searchTerm = ""
    @State private var contentWidth: CGFloat = UIScreen.main.bounds.width

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeader

                    switch section {
                    case .artists:
                        KhyloArtistGrid(libraryID: library.id, searchTerm: searchTerm, width: contentWidth)
                            .id("artists-\(searchTerm)")
                    case .categories:
                        // Each genre, fronted by its most played album.
                        KhyloCategoryGrid(scope: .music, limit: nil, onSeeAll: nil, showsTitle: false)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            searchTerm = trimmed
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let header {
                header
            } else {
                Text(library.name ?? "Music")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, KhyloStyle.gutter)
            }

            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    KhyloSegmentTabs(tabs: Section.allCases.map { ($0, $0.rawValue) }, selection: $section)
                }
                .scrollClipDisabled()
                Button {
                    shuffleAll()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(KhyloStyle.accent))
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .accessibilityLabel("Shuffle all music")
            }
            .padding(.horizontal, KhyloStyle.gutter)

            if section == .artists {
                KhyloLibrarySearchField(placeholder: "Search artists", text: $query)
            }
        }
    }

    private func shuffleAll() {
        Task {
            let songs = try? await KhyloAPI.items(parentID: library.id, types: [.audio], sortBy: [.random], limit: 200).items
            if let songs, !songs.isEmpty {
                KhyloAudioPlayer.shared.play(songs, kind: .music, startTicks: 0)
            }
        }
    }
}

// MARK: - Paged loading

/// Loads pages of items as the user scrolls.
@MainActor
private final class KhyloPager: ObservableObject {
    @Published private(set) var items: [BaseItemDto] = []
    @Published private(set) var isLoading = true
    private var total = Int.max
    private var isLoadingMore = false
    private let loader: (Int, Int) async throws -> KhyloAPI.Page

    init(loader: @escaping (Int, Int) async throws -> KhyloAPI.Page) {
        self.loader = loader
    }

    func loadFirst() async {
        guard items.isEmpty else { return }
        if let page = try? await loader(0, 60) {
            items = page.items
            total = page.total
        }
        isLoading = false
    }

    func loadMore(after item: BaseItemDto) async {
        guard !isLoadingMore, items.count < total,
              let position = items.firstIndex(where: { $0.id == item.id }), position >= items.count - 12
        else { return }
        isLoadingMore = true
        if let page = try? await loader(items.count, 60) {
            let known = Set(items.compactMap(\.id))
            items += page.items.filter { !known.contains($0.id ?? "") }
            total = page.total
        }
        isLoadingMore = false
    }
}

private struct KhyloArtistGrid: View {
    @StateObject private var pager: KhyloPager
    @Router private var router
    let width: CGFloat

    init(libraryID: String?, searchTerm: String, width: CGFloat) {
        self.width = width
        let term = searchTerm.isEmpty ? nil : searchTerm
        _pager = StateObject(wrappedValue: KhyloPager { start, limit in
            try await KhyloAPI.albumArtists(parentID: libraryID, searchTerm: term, startIndex: start, limit: limit)
        })
    }

    var body: some View {
        let size = max(80, (width - KhyloStyle.gutter * 2 - 32) / 3)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 16), count: 3), spacing: 24) {
            ForEach(pager.items, id: \.id) { artist in
                Button {
                    router.route(to: .khyloItem(artist))
                } label: {
                    KhyloArtistCell(artist: artist, size: size)
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .task { await pager.loadMore(after: artist) }
            }
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .frame(maxWidth: .infinity, minHeight: 400, alignment: .top)
        .overlay { loadingOverlay(isLoading: pager.isLoading, isEmpty: pager.items.isEmpty, noun: "artists") }
        .task { await pager.loadFirst() }
    }
}

@ViewBuilder
private func loadingOverlay(isLoading: Bool, isEmpty: Bool, noun: String) -> some View {
    if isLoading {
        ProgressView().tint(.white.opacity(0.6)).padding(.top, 60).frame(maxHeight: .infinity, alignment: .top)
    } else if isEmpty {
        Text("No \(noun) found")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(KhyloStyle.tertiaryText)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Search in For You

/// Artists, albums and songs in one music library that match what was typed,
/// shown on For You in place of its rows.
struct KhyloMusicSearchResults: View {

    let libraryID: String?
    let term: String

    @State private var artists: [BaseItemDto] = []
    @State private var albums: [BaseItemDto] = []
    @State private var songs: [BaseItemDto] = []
    @State private var isLoading = true
    @Router private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if isLoading {
                ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 40)
            } else if artists.isEmpty, albums.isEmpty, songs.isEmpty {
                Text("No music found for \u{201C}\(term)\u{201D}")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                if !artists.isEmpty {
                    KhyloRow(title: "Artists") {
                        ForEach(artists, id: \.id) { artist in
                            Button {
                                router.route(to: .khyloItem(artist))
                            } label: {
                                KhyloArtistCell(artist: artist, size: 110)
                            }
                            .buttonStyle(KhyloScaleButtonStyle())
                        }
                    }
                }
                if !albums.isEmpty {
                    KhyloRow(title: "Albums") {
                        ForEach(albums, id: \.id) { album in
                            Button {
                                router.route(to: .khyloItem(album))
                            } label: {
                                KhyloAlbumCard(album: album, width: 140)
                            }
                            .buttonStyle(KhyloScaleButtonStyle())
                        }
                    }
                }
                if !songs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Songs")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, KhyloStyle.gutter)
                        ForEach(songs, id: \.id) { song in
                            KhyloTrackRow(track: song, style: .artwork) {
                                // The song, then a mix built from it.
                                KhyloAudioPlayer.shared.play([song], kind: .music, startTicks: 0)
                            }
                        }
                    }
                }
            }
        }
        .task(id: term) { await search() }
    }

    private func search() async {
        isLoading = true
        async let foundArtists = KhyloAPI.albumArtists(parentID: libraryID, searchTerm: term, limit: 12)
        async let foundAlbums = KhyloAPI.items(parentID: libraryID, types: [.musicAlbum], sortBy: [.sortName], searchTerm: term, limit: 20)
        async let foundSongs = KhyloAPI.items(parentID: libraryID, types: [.audio], sortBy: [.sortName], searchTerm: term, limit: 20)
        let a = (try? await foundArtists)?.items ?? []
        let b = (try? await foundAlbums)?.items ?? []
        let c = (try? await foundSongs)?.items ?? []
        guard !Task.isCancelled else { return }
        artists = a
        albums = b
        songs = c
        isLoading = false
    }
}

// MARK: - Cards & rows

/// Square album cover with title and artist (or year) beneath.
struct KhyloAlbumCard: View {
    let album: BaseItemDto
    var width: CGFloat = 150
    var showsYear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            KhyloImage(url: KhyloArtwork.url(for: album, style: .square, width: width), placeholderSymbol: "music.note")
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(showsYear ? album.khyloAlbumKind : album.khyloArtistLine)
                    .font(.system(size: 12))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

struct KhyloTrackRow: View {

    enum Style {
        /// Track number (album page).
        case numbered(Int)
        /// Album art thumbnail (song lists, Popular).
        case artwork
        /// Rank number plus artwork (artist Popular).
        case ranked(Int)
    }

    let track: BaseItemDto
    var style: Style = .artwork
    /// Hide the artist line when it repeats the album artist.
    var hidesArtist = false
    let action: () -> Void

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @ObservedObject private var downloads = KhyloDownloads.shared
    @Router private var router

    private var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                leading

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name ?? "")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isCurrent ? KhyloStyle.accent : .white)
                        .lineLimit(1)
                    if !hidesArtist {
                        KhyloArtistLinks(artists: track.khyloArtistLinks, fallback: track.khyloArtistLine) { artistID in
                            Task {
                                if let artist = try? await KhyloAPI.item(artistID) { router.route(to: .khyloItem(artist)) }
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.tertiaryText)
                    }
                }

                Spacer(minLength: 8)

                if downloads.isDownloaded(track.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(KhyloStyle.accent)
                        .accessibilityLabel("Downloaded")
                }

                Text(track.khyloRuntimeClock ?? "")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(KhyloStyle.tertiaryText)

                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .frame(width: 30, height: 40)
                        .contentShape(Rectangle())
                }
            }
            .padding(.leading, KhyloStyle.gutter)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var leading: some View {
        switch style {
        case let .numbered(number):
            ZStack {
                if isCurrent {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                        .foregroundColor(KhyloStyle.accent)
                } else {
                    Text("\(number)")
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundColor(KhyloStyle.tertiaryText)
                }
            }
            .frame(width: 24)
        case .artwork:
            artwork
        case let .ranked(rank):
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundColor(isCurrent ? KhyloStyle.accent : KhyloStyle.secondaryText)
                    .frame(width: 18)
                artwork
            }
        }
    }

    private var artwork: some View {
        KhyloImage(url: KhyloArtwork.url(for: track, style: .square, width: 100), placeholderSymbol: "music.note")
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.black.opacity(0.45))
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                        .foregroundColor(KhyloStyle.accent)
                }
            }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            player.playNext(track)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            player.addToQueue(track)
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        if let albumID = track.albumID {
            Button {
                Task {
                    if let album = try? await KhyloAPI.item(albumID) { router.route(to: .khyloItem(album)) }
                }
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
        if let artistID = track.albumArtists?.first?.id ?? track.artistItems?.first?.id {
            Button {
                Task {
                    if let artist = try? await KhyloAPI.item(artistID) { router.route(to: .khyloItem(artist)) }
                }
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
    }
}

extension BaseItemDto {
    /// "3:42"
    var khyloRuntimeClock: String? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        let seconds = ticks / 10_000_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Round accent play button with a smaller shuffle button beside it.
private struct KhyloPlayCluster: View {
    let isPlayingThis: Bool
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: shuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel("Shuffle")

            Button(action: play) {
                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(KhyloStyle.accent))
                    .shadow(color: KhyloStyle.accent.opacity(0.4), radius: 12, y: 4)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(isPlayingThis ? "Pause" : "Play")
        }
    }
}

// MARK: - Album

struct KhyloAlbumScreen: View {

    @State var album: BaseItemDto

    @State private var tracks: [BaseItemDto] = []
    @State private var moreByArtist: [BaseItemDto] = []
    @State private var tint: Color?
    @State private var isLoading = true
    @State private var pageWidth: CGFloat = UIScreen.main.bounds.width
    @ObservedObject private var player = KhyloAudioPlayer.shared
    @Router private var router

    init(album: BaseItemDto) {
        _album = State(initialValue: album)
    }

    private var coverURL: URL? { KhyloArtwork.url(for: album, style: .square, width: 600) }

    private var isPlayingThis: Bool {
        player.isPlaying && tracks.contains { $0.id == player.current?.id }
    }

    private var totalMinutes: Int {
        tracks.reduce(0) { $0 + ($1.runTimeTicks ?? 0) } / 600_000_000
    }

    /// Discs, when the album has more than one.
    private var discs: [(Int, [BaseItemDto])] {
        let grouped = Dictionary(grouping: tracks) { $0.parentIndexNumber ?? 1 }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 18)
                    .background(alignment: .top) { coverBackdrop }

                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 30)
                } else {
                    trackList
                    footer
                }
            }
            .padding(.bottom, 40)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .background(KhyloTintedBackdrop(color: tint, height: 620))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    /// The album's own cover, enlarged and softly blurred behind the top of the
    /// page, fading into the album's colour.
    private var coverBackdrop: some View {
        KhyloImage(url: KhyloArtwork.url(for: album, style: .square, width: 300), showsPlaceholder: false)
            .frame(height: 640)
            .frame(maxWidth: .infinity)
            .scaleEffect(1.35)
            .blur(radius: 46)
            .saturation(1.25)
            .opacity(0.6)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.85), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(.top, -160)
            .allowsHitTesting(false)
    }

    private var coverSize: CGFloat {
        min(max(pageWidth - 72, 220), 340)
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 18) {
            KhyloImage(url: coverURL, placeholderSymbol: "music.note")
                .frame(width: coverSize, height: coverSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.6), radius: 34, y: 18)
                // Eases back a little as the page scrolls up.
                .scrollTransition(.interactive, axis: .vertical) { content, phase in
                    content
                        .scaleEffect(phase.value < 0 ? 1 + phase.value * 0.12 : 1)
                        .opacity(phase.value < 0 ? 1 + phase.value * 0.5 : 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            VStack(alignment: .center, spacing: 7) {
                Text(album.name ?? "")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Button {
                    openArtist()
                } label: {
                    HStack(spacing: 8) {
                        if let artist = album.albumArtists?.first {
                            KhyloArtistAvatar(artist: artistStub(artist), size: 24)
                        }
                        Text(album.khyloArtistLine)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Text(metadata)
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.secondaryText)
                    if let quality = tracks.lazy.compactMap(KhyloAudioQuality.init).first {
                        KhyloQualityBadge(quality: quality)
                    }
                }
            }

            HStack(spacing: 22) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: album.khyloIsFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(album.khyloIsFavorite ? KhyloStyle.accent : .white.opacity(0.85))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .accessibilityLabel(album.khyloIsFavorite ? "Remove from favorites" : "Add to favorites")

                KhyloDownloadButton(item: album, style: .icon)

                Spacer()

                KhyloPlayCluster(isPlayingThis: isPlayingThis) {
                    if tracks.contains(where: { $0.id == player.current?.id }) {
                        player.togglePlayPause()
                    } else {
                        play(shuffled: false)
                    }
                } shuffle: {
                    play(shuffled: true)
                }
            }
            .disabled(tracks.isEmpty)
        }
        .padding(.horizontal, KhyloStyle.gutter)
    }

    private var metadata: String {
        var parts = [album.khyloAlbumKind]
        if !tracks.isEmpty {
            parts.append("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
            parts.append(totalMinutes >= 60 ? "\(totalMinutes / 60) hr \(totalMinutes % 60) min" : "\(totalMinutes) min")
        }
        return parts.joined(separator: " · ")
    }

    private var trackList: some View {
        let albumArtist = album.khyloArtistLine
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(discs, id: \.0) { disc, discTracks in
                if discs.count > 1 {
                    Label("Disc \(disc)", systemImage: "opticaldisc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(KhyloStyle.secondaryText)
                        .padding(.horizontal, KhyloStyle.gutter)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
                ForEach(discTracks, id: \.id) { track in
                    KhyloTrackRow(
                        track: track,
                        style: .numbered(track.indexNumber ?? ((tracks.firstIndex { $0.id == track.id } ?? 0) + 1)),
                        hidesArtist: track.khyloArtistLine == albumArtist
                    ) {
                        let index = tracks.firstIndex { $0.id == track.id } ?? 0
                        player.play(tracks, startAt: index, kind: .music, startTicks: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let date = album.premiereDate {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .padding(.horizontal, KhyloStyle.gutter)
            }

            if !moreByArtist.isEmpty {
                KhyloRow(title: "More by \(album.albumArtists?.first?.name ?? album.albumArtist ?? "this artist")") {
                    ForEach(moreByArtist, id: \.id) { other in
                        Button {
                            router.route(to: .khyloItem(other))
                        } label: {
                            KhyloAlbumCard(album: other, width: 140, showsYear: true)
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                }
            }
        }
        .padding(.top, 22)
    }

    private func load() async {
        guard let id = album.id else { return }
        async let fullAlbum = try? KhyloAPI.item(id)
        tracks = (try? await KhyloAPI.tracks(albumID: id)) ?? []
        isLoading = false
        if let fresh = await fullAlbum { album = fresh }
        tint = await KhyloArtColor.color(for: KhyloArtwork.url(for: album, style: .square, width: 120))

        if let artistID = album.albumArtists?.first?.id {
            let others = (try? await KhyloAPI.items(
                types: [.musicAlbum], sortBy: [.productionYear, .sortName], sortOrder: .descending,
                albumArtistIDs: [artistID], limit: 20
            ))?.items ?? []
            moreByArtist = others.filter { $0.id != id }
        }
    }

    private func play(shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        if shuffled {
            player.play(tracks.shuffled(), kind: .music, startTicks: 0)
        } else {
            player.play(tracks, kind: .music, startTicks: 0)
        }
    }

    private func toggleFavorite() {
        guard let id = album.id else { return }
        Task {
            if let data = try? await KhyloAPI.setFavorite(!album.khyloIsFavorite, itemID: id) {
                album.userData = data
            }
        }
    }

    private func openArtist() {
        guard let artistID = album.albumArtists?.first?.id else { return }
        Task {
            if let artist = try? await KhyloAPI.item(artistID) {
                router.route(to: .khyloItem(artist))
            }
        }
    }

    private func artistStub(_ pair: NameIDPair) -> BaseItemDto {
        BaseItemDto(id: pair.id, name: pair.name)
    }
}

// MARK: - Artist

struct KhyloArtistScreen: View {

    @State var artist: BaseItemDto

    @State private var albums: [BaseItemDto] = []
    @State private var popular: [BaseItemDto] = []
    @State private var songCount = 0
    @State private var heroURL: URL?
    @State private var heroIsPhoto = false
    @State private var tint: Color?
    @State private var showsAllPopular = false
    @State private var isLoading = true
    @State private var similar: [BaseItemDto] = []
    @ObservedObject private var player = KhyloAudioPlayer.shared
    @Router private var router

    init(artist: BaseItemDto) {
        _artist = State(initialValue: artist)
    }

    private var fullAlbums: [BaseItemDto] { albums.filter { !$0.khyloIsSingleOrEP } }
    private var singles: [BaseItemDto] { albums.filter(\.khyloIsSingleOrEP) }

    private var isPlayingThis: Bool {
        player.isPlaying && (player.current?.albumArtists?.contains { $0.id == artist.id } ?? false
            || player.current?.artistItems?.contains { $0.id == artist.id } ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero
                controls
                    .padding(.top, -14)

                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    if !popular.isEmpty { popularSection }
                    if !fullAlbums.isEmpty { discography(title: "Albums", items: fullAlbums) }
                    if !singles.isEmpty { discography(title: "Singles & EPs", items: singles) }
                    if albums.isEmpty, popular.isEmpty {
                        Text("No music found for this artist.")
                            .font(.system(size: 15))
                            .foregroundColor(KhyloStyle.tertiaryText)
                            .padding(.horizontal, KhyloStyle.gutter)
                    }
                    if !similar.isEmpty { similarSection }
                    if let overview = artist.overview, !overview.isEmpty {
                        about(overview)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(KhyloTintedBackdrop(color: tint, height: 700))
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(height: 420)
                .overlay {
                    if let heroURL {
                        KhyloImage(url: heroURL, showsPlaceholder: false)
                            // Album art isn't a photo: soften it so the name stays the hero.
                            .blur(radius: heroIsPhoto ? 0 : 2)
                            .transition(.opacity)
                    }
                }
                .clipped()
                // The picture itself fades away into the page, so there's no edge.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.45),
                            .init(color: .black.opacity(0.55), location: 0.72),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // A soft shade at the top for the status bar and behind the name for legibility.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.55),
                    .init(color: .black.opacity(0.28), location: 0.85),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text(artist.name ?? "")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
                if !stats.isEmpty {
                    Text(stats)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
                }
            }
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.bottom, 22)
        }
        .frame(height: 420)
    }

    private var stats: String {
        var parts: [String] = []
        if !albums.isEmpty { parts.append("\(albums.count) release\(albums.count == 1 ? "" : "s")") }
        if songCount > 0 { parts.append("\(songCount) song\(songCount == 1 ? "" : "s")") }
        if let genre = artist.genres?.first { parts.append(genre) }
        return parts.joined(separator: " · ")
    }

    private var controls: some View {
        HStack(spacing: 22) {
            Button {
                playMix()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold))
                    Text("Artist Mix")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityHint("Plays songs by this artist and similar artists")

            Spacer()

            KhyloPlayCluster(isPlayingThis: isPlayingThis) {
                if isPlayingThis { player.pause() } else { playAll(shuffled: false) }
            } shuffle: {
                playAll(shuffled: true)
            }
        }
        .padding(.horizontal, KhyloStyle.gutter)
    }

    // MARK: Sections

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popular")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, KhyloStyle.gutter)

            let shown = showsAllPopular ? popular : Array(popular.prefix(5))
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, song in
                KhyloTrackRow(track: song, style: .ranked(index + 1), hidesArtist: true) {
                    player.play(popular, startAt: index, kind: .music, startTicks: 0)
                }
            }

            HStack {
                if popular.count > 5 {
                    Button(showsAllPopular ? "Show less" : "See more") {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllPopular.toggle() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(KhyloStyle.secondaryText)
                }
                Spacer()
                Button("All songs") { openAllSongs() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(KhyloStyle.accent)
            }
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.top, 4)
        }
    }

    private func discography(title: String, items: [BaseItemDto]) -> some View {
        KhyloRow(title: title, subtitle: "\(items.count)") {
            ForEach(items, id: \.id) { album in
                Button {
                    router.route(to: .khyloItem(album))
                } label: {
                    KhyloAlbumCard(album: album, width: 150, showsYear: true)
                }
                .buttonStyle(KhyloScaleButtonStyle())
            }
        }
    }

    private var similarSection: some View {
        KhyloRow(title: "Fans Also Like") {
            ForEach(similar, id: \.id) { other in
                Button {
                    router.route(to: .khyloItem(other))
                } label: {
                    KhyloArtistCell(artist: other, size: 118)
                }
                .buttonStyle(KhyloScaleButtonStyle())
            }
        }
    }

    private func about(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(KhyloStyle.secondaryText)
                .lineSpacing(3)
                .lineLimit(6)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .padding(.horizontal, KhyloStyle.gutter)
    }

    // MARK: Data

    private func load() async {
        guard let id = artist.id else { return }
        if let fresh = try? await KhyloAPI.item(id) { artist = fresh }

        async let albumPage = KhyloAPI.items(
            types: [.musicAlbum], sortBy: [.productionYear, .premiereDate, .sortName], sortOrder: .descending,
            albumArtistIDs: [id], limit: 300
        )
        async let songPage = KhyloAPI.items(
            types: [.audio], sortBy: [.playCount, .communityRating, .sortName], sortOrder: .descending,
            artistIDs: [id], limit: 20
        )

        var found = (try? await albumPage)?.items ?? []
        if found.isEmpty {
            // Some libraries only tag the track artists, not the album artist.
            found = (try? await KhyloAPI.items(
                types: [.musicAlbum], sortBy: [.productionYear, .sortName], sortOrder: .descending,
                artistIDs: [id], limit: 300
            ))?.items ?? []
        }
        albums = found
        let songs = try? await songPage
        popular = songs?.items ?? []
        songCount = songs?.total ?? 0
        isLoading = false

        if let own = KhyloArtistArt.ownImage(for: artist, width: 1000) {
            heroURL = own
            heroIsPhoto = true
        } else {
            heroURL = found.first { $0.imageTags?["Primary"] != nil }
                .flatMap { KhyloArtwork.url(for: $0, style: .square, width: 1000) }
        }
        tint = await KhyloArtColor.color(for: heroURL)
        similar = (try? await KhyloAPI.similarArtists(to: id)) ?? []
    }

    private func playMix() {
        guard let id = artist.id else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let songs = (try? await KhyloAPI.instantMix(from: id)) ?? []
            if !songs.isEmpty {
                player.play(songs, kind: .music, collectionTitle: "\(artist.name ?? "Artist") Mix", startTicks: 0)
            } else {
                playAll(shuffled: true)
            }
        }
    }

    private func playAll(shuffled: Bool) {
        guard let id = artist.id else { return }
        Task {
            let songs = (try? await KhyloAPI.items(
                types: [.audio], sortBy: shuffled ? [.random] : [.playCount, .sortName],
                sortOrder: .descending, artistIDs: [id], limit: 300
            ))?.items ?? popular
            guard !songs.isEmpty else { return }
            player.play(songs, kind: .music, startTicks: 0)
        }
    }

    private func openAllSongs() {
        guard let id = artist.id else { return }
        router.route(to: NavigationRoute(id: "khylo-artist-songs-\(id)") {
            KhyloArtistSongsScreen(artist: artist)
        })
    }
}

/// Every song by an artist.
private struct KhyloArtistSongsScreen: View {
    let artist: BaseItemDto
    @State private var songs: [BaseItemDto] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(artist.name ?? "")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, KhyloStyle.gutter)
                Text("\(songs.count) songs")
                    .font(.system(size: 14))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .padding(.horizontal, KhyloStyle.gutter)

                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        KhyloTrackRow(track: song, style: .artwork) {
                            KhyloAudioPlayer.shared.play(songs, startAt: index, kind: .music, startTicks: 0)
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let id = artist.id else { return }
            songs = (try? await KhyloAPI.items(types: [.audio], sortBy: [.album, .parentIndexNumber, .indexNumber], artistIDs: [id], limit: 1000).items) ?? []
            isLoading = false
        }
    }
}

/// Opening a song plays it within its album.
struct KhyloTrackRedirect: View {
    let track: BaseItemDto
    @State private var album: BaseItemDto?

    var body: some View {
        Group {
            if let album {
                KhyloAlbumScreen(album: album)
            } else {
                KhyloLoadingState().background(KhyloStyle.canvas.ignoresSafeArea())
            }
        }
        .task {
            if let albumID = track.albumID, let found = try? await KhyloAPI.item(albumID) {
                album = found
                let tracks = (try? await KhyloAPI.tracks(albumID: albumID)) ?? [track]
                let index = tracks.firstIndex { $0.id == track.id } ?? 0
                KhyloAudioPlayer.shared.play(tracks, startAt: index, kind: .music, startTicks: 0)
            } else {
                KhyloAudioPlayer.shared.play([track], kind: .music, startTicks: 0)
                album = track
            }
        }
    }
}
