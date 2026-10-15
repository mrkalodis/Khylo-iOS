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

/// Music: Albums, Artists and Songs, switched with pills like the Libraries tab.
struct KhyloMusicLibraryScreen: View {

    let library: BaseItemDto
    /// Replaces the plain title, e.g. with the Libraries tab's switcher.
    var header: AnyView? = nil

    enum Section: String, CaseIterable {
        case albums = "Albums"
        case artists = "Artists"
        case songs = "Songs"
    }

    @State private var section: Section = .albums
    @Router private var router

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            switch section {
            case .albums:
                KhyloSearchableGrid(
                    shape: .square,
                    id: "albums",
                    placeholder: "Search albums and artists",
                    header: { sectionHeader }
                ) { term, start, limit in
                    if let term {
                        // Match album titles or the artists who made them.
                        async let byTitle = KhyloAPI.items(
                            parentID: library.id, types: [.musicAlbum], sortBy: [.sortName],
                            searchTerm: term, startIndex: start, limit: limit
                        )
                        async let artists = KhyloAPI.items(
                            parentID: library.id, types: [.musicArtist], searchTerm: term, limit: 5
                        )
                        let titled = try await byTitle
                        let artistIDs = ((try? await artists)?.items ?? []).compactMap(\.id)
                        guard start == 0, !artistIDs.isEmpty else { return titled }
                        let byArtist = (try? await KhyloAPI.items(
                            parentID: library.id, types: [.musicAlbum], sortBy: [.productionYear],
                            sortOrder: .descending, artistIDs: artistIDs, limit: 60
                        ))?.items ?? []
                        let known = Set(titled.items.compactMap(\.id))
                        let merged = titled.items + byArtist.filter { !known.contains($0.id ?? "") }
                        return KhyloAPI.Page(items: merged, total: merged.count)
                    }
                    return try await KhyloAPI.items(
                        parentID: library.id,
                        types: [.musicAlbum],
                        sortBy: [.dateCreated, .sortName],
                        sortOrder: .descending,
                        startIndex: start,
                        limit: limit
                    )
                }
                .id(Section.albums)
            case .artists:
                KhyloArtistGrid(libraryID: library.id) { sectionHeader }
                    .id(Section.artists)
            case .songs:
                KhyloSongList(libraryID: library.id) { sectionHeader }
                    .id(Section.songs)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let header {
                header
            } else {
                Text(library.name ?? "Music")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, KhyloStyle.gutter)
            }

            HStack(spacing: 8) {
                ForEach(Section.allCases, id: \.self) { option in
                    KhyloPill(title: option.rawValue, isSelected: section == option) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) { section = option }
                    }
                }
                Spacer()
                Button {
                    shuffleAll()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(KhyloStyle.accent))
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .accessibilityLabel("Shuffle all")
            }
            .padding(.horizontal, KhyloStyle.gutter)
        }
    }

    private func shuffleAll() {
        Task {
            let songs = try? await KhyloAPI.items(
                parentID: library.id,
                types: [.audio],
                sortBy: [.random],
                limit: 200
            ).items
            if let songs, !songs.isEmpty {
                KhyloAudioPlayer.shared.play(songs, kind: .music, startTicks: 0)
            }
        }
    }
}

/// Artists as circles.
private struct KhyloArtistGrid<Header: View>: View {

    let libraryID: String?
    @ViewBuilder let header: () -> Header

    @State private var artists: [BaseItemDto] = []
    @State private var isLoading = true
    @Router private var router

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - KhyloStyle.gutter * 2 - 28) / 3
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header()
                    if isLoading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(artists, id: \.id) { artist in
                                Button {
                                    router.route(to: .khyloItem(artist))
                                } label: {
                                    KhyloTileCard(item: artist, width: width, isCircular: true)
                                }
                                .buttonStyle(KhyloScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, KhyloStyle.gutter)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .task {
            artists = (try? await KhyloAPI.albumArtists(parentID: libraryID, limit: 500).items) ?? []
            isLoading = false
        }
    }
}

/// All songs, alphabetical; tapping plays from that song.
private struct KhyloSongList<Header: View>: View {

    let libraryID: String?
    @ViewBuilder let header: () -> Header

    @State private var songs: [BaseItemDto] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header()
                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                            KhyloTrackRow(track: song, showsArtwork: true) {
                                KhyloAudioPlayer.shared.play(songs, startAt: index, kind: .music, startTicks: 0)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .task {
            songs = (try? await KhyloAPI.items(parentID: libraryID, types: [.audio], sortBy: [.sortName], limit: 500).items) ?? []
            isLoading = false
        }
    }
}

// MARK: - Track row

struct KhyloTrackRow: View {

    let track: BaseItemDto
    var number: Int? = nil
    var showsArtwork = false
    let action: () -> Void

    @ObservedObject private var player = KhyloAudioPlayer.shared

    private var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if showsArtwork {
                    KhyloImage(url: KhyloArtwork.url(for: track, style: .square, width: 96), placeholderSymbol: "music.note")
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ZStack {
                        if isCurrent {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                                .foregroundColor(KhyloStyle.accent)
                        } else {
                            Text(number.map(String.init) ?? "")
                                .font(.system(size: 15, weight: .medium).monospacedDigit())
                                .foregroundColor(KhyloStyle.tertiaryText)
                        }
                    }
                    .frame(width: 26)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name ?? "")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isCurrent ? KhyloStyle.accent : .white)
                        .lineLimit(1)
                    if showsArtwork, let artist = track.artists?.first ?? track.albumArtist {
                        Text(artist)
                            .font(.system(size: 13))
                            .foregroundColor(KhyloStyle.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(track.khyloRuntimeClock ?? "")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(KhyloStyle.tertiaryText)
            }
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - Album

struct KhyloAlbumScreen: View {

    let album: BaseItemDto

    @State private var tracks: [BaseItemDto] = []
    @State private var isLoading = true
    @Router private var router

    private var artworkURL: URL? {
        KhyloArtwork.url(for: album, style: .square, width: 600)
    }

    private var totalMinutes: Int {
        tracks.reduce(0) { $0 + ($1.runTimeTicks ?? 0) } / 600_000_000
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    KhyloImage(url: artworkURL, placeholderSymbol: "music.note")
                        .frame(width: 250, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 28, y: 14)
                        .padding(.top, 70)

                    VStack(spacing: 4) {
                        Text(album.name ?? "")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        if let artist = album.albumArtist ?? album.artists?.first {
                            Button {
                                openArtist()
                            } label: {
                                Text(artist)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(KhyloStyle.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(metadata)
                            .font(.system(size: 13))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    .padding(.horizontal, 30)

                    HStack(spacing: 12) {
                        albumButton("Play", systemImage: "play.fill") { play(shuffled: false) }
                        albumButton("Shuffle", systemImage: "shuffle") { play(shuffled: true) }
                    }
                    .padding(.horizontal, KhyloStyle.gutter)
                    .padding(.top, 6)
                }
                .padding(.bottom, 20)

                if isLoading {
                    ProgressView().tint(.white).padding(.top, 30)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            KhyloTrackRow(track: track, number: track.indexNumber ?? index + 1) {
                                KhyloAudioPlayer.shared.play(tracks, startAt: index, kind: .music, artworkURL: artworkURL, startTicks: 0)
                            }
                            if index < tracks.count - 1 {
                                Divider().overlay(KhyloStyle.hairline).padding(.leading, KhyloStyle.gutter + 40)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(
            ZStack {
                KhyloStyle.canvas
                KhyloImage(url: artworkURL, showsPlaceholder: false)
                    .frame(height: 480)
                    .scaleEffect(1.5)
                    .blur(radius: 80)
                    .opacity(0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            guard let id = album.id else { return }
            tracks = (try? await KhyloAPI.tracks(albumID: id)) ?? []
            isLoading = false
        }
    }

    private var metadata: String {
        var parts: [String] = []
        if let genre = album.genres?.first { parts.append(genre) }
        if let year = album.productionYear { parts.append(String(year)) }
        if !tracks.isEmpty { parts.append("\(tracks.count) songs, \(totalMinutes) min") }
        return parts.joined(separator: " · ")
    }

    private func albumButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(KhyloStyle.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .disabled(tracks.isEmpty)
    }

    private func play(shuffled: Bool) {
        let queue = shuffled ? tracks.shuffled() : tracks
        KhyloAudioPlayer.shared.play(queue, kind: .music, artworkURL: artworkURL, startTicks: 0)
    }

    private func openArtist() {
        guard let artistID = album.albumArtists?.first?.id else { return }
        Task {
            if let artist = try? await KhyloAPI.item(artistID) {
                router.route(to: .khyloItem(artist))
            }
        }
    }
}

// MARK: - Artist

struct KhyloArtistScreen: View {

    let artist: BaseItemDto

    @State private var albums: [BaseItemDto] = []
    @State private var topSongs: [BaseItemDto] = []
    @Router private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack(alignment: .bottomLeading) {
                    KhyloImage(url: KhyloArtwork.url(for: artist, style: .backdrop, width: 1000), placeholderSymbol: "music.mic")
                        .frame(height: 380)
                    LinearGradient(colors: [.clear, KhyloStyle.canvas], startPoint: .center, endPoint: .bottom)
                    HStack(alignment: .bottom) {
                        Text(artist.name ?? "")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            KhyloAudioPlayer.shared.play(topSongs.shuffled(), kind: .music, startTicks: 0)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(KhyloStyle.accent))
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                        .disabled(topSongs.isEmpty)
                    }
                    .padding(.horizontal, KhyloStyle.gutter)
                    .padding(.bottom, 12)
                }

                if !topSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Songs")
                            .font(KhyloStyle.title(21))
                            .foregroundColor(.white)
                            .padding(.horizontal, KhyloStyle.gutter)
                        ForEach(Array(topSongs.prefix(6).enumerated()), id: \.offset) { index, song in
                            KhyloTrackRow(track: song, showsArtwork: true) {
                                KhyloAudioPlayer.shared.play(topSongs, startAt: index, kind: .music, startTicks: 0)
                            }
                        }
                    }
                }

                if !albums.isEmpty {
                    KhyloShelf(title: "Albums") {
                        ForEach(albums, id: \.id) { album in
                            Button {
                                router.route(to: .khyloItem(album))
                            } label: {
                                KhyloTileCard(item: album, width: 150)
                            }
                            .buttonStyle(KhyloScaleButtonStyle())
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            guard let id = artist.id else { return }
            async let albumPage = KhyloAPI.items(
                types: [.musicAlbum],
                sortBy: [.productionYear, .sortName],
                sortOrder: .descending,
                artistIDs: [id],
                limit: 100
            )
            async let songPage = KhyloAPI.items(
                types: [.audio],
                sortBy: [.playCount, .sortName],
                sortOrder: .descending,
                artistIDs: [id],
                limit: 50
            )
            albums = (try? await albumPage.items) ?? []
            topSongs = (try? await songPage.items) ?? []
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
