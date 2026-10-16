//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - For You

/// The music library's landing page: what you've been playing, mixes built
/// around your artists, and new and forgotten albums.
struct KhyloMusicForYou: View {

    let library: BaseItemDto

    @State private var jumpBackIn: [BaseItemDto] = []
    @State private var mixArtists: [BaseItemDto] = []
    @State private var onRepeat: [BaseItemDto] = []
    @State private var recentlyAdded: [BaseItemDto] = []
    @State private var favorites: [BaseItemDto] = []
    @State private var rediscover: [BaseItemDto] = []
    @State private var isLoading = true
    @Router private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if isLoading {
                ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                if !jumpBackIn.isEmpty { jumpBackInGrid }

                if !mixArtists.isEmpty {
                    KhyloRow(title: "Your Mixes", subtitle: "Built around the artists you play") {
                        ForEach(mixArtists, id: \.id) { artist in
                            KhyloMixCard(artist: artist)
                        }
                    }
                }

                albumRow("Recently Added", recentlyAdded)

                if !onRepeat.isEmpty { onRepeatSection }

                albumRow("Favorites", favorites)
                albumRow("Rediscover", rediscover)

                if jumpBackIn.isEmpty, recentlyAdded.isEmpty, rediscover.isEmpty {
                    Text("No music here yet.")
                        .font(.system(size: 15))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
        }
        .padding(.top, 4)
        .task { await load() }
    }

    // MARK: Sections

    /// Two columns of compact tiles for the albums you played last.
    private var jumpBackInGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jump Back In")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(jumpBackIn.prefix(6), id: \.id) { album in
                    Button {
                        router.route(to: .khyloItem(album))
                    } label: {
                        HStack(spacing: 10) {
                            KhyloImage(url: KhyloArtwork.url(for: album, style: .square, width: 112), placeholderSymbol: "music.note")
                                .frame(width: 56, height: 56)
                            Text(album.name ?? "")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                        }
                        .frame(height: 56)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(KhyloScaleButtonStyle())
                }
            }
        }
        .padding(.horizontal, KhyloStyle.gutter)
    }

    private var onRepeatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text("On Repeat")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    KhyloAudioPlayer.shared.play(onRepeat, kind: .music, collectionTitle: "On Repeat", startTicks: 0)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KhyloStyle.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, KhyloStyle.gutter)

            ForEach(Array(onRepeat.prefix(5).enumerated()), id: \.element.id) { index, song in
                KhyloTrackRow(track: song, style: .ranked(index + 1)) {
                    KhyloAudioPlayer.shared.play(onRepeat, startAt: index, kind: .music, collectionTitle: "On Repeat", startTicks: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func albumRow(_ title: String, _ albums: [BaseItemDto]) -> some View {
        if !albums.isEmpty {
            KhyloRow(title: title) {
                ForEach(albums, id: \.id) { album in
                    Button {
                        router.route(to: .khyloItem(album))
                    } label: {
                        KhyloAlbumCard(album: album, width: 150)
                    }
                    .buttonStyle(KhyloScaleButtonStyle())
                }
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard isLoading, let id = library.id else { return }

        async let recentTracks = KhyloAPI.items(
            parentID: id, types: [.audio], sortBy: [.datePlayed], sortOrder: .descending,
            filters: [.isPlayed], limit: 80
        )
        async let topTracks = KhyloAPI.items(
            parentID: id, types: [.audio], sortBy: [.playCount, .datePlayed], sortOrder: .descending,
            filters: [.isPlayed], limit: 150
        )
        async let latest = KhyloAPI.latest(in: id, limit: 20)
        async let favoriteAlbums = KhyloAPI.items(parentID: id, types: [.musicAlbum], sortBy: [.random], isFavorite: true, limit: 20)
        async let randomAlbums = KhyloAPI.items(parentID: id, types: [.musicAlbum], sortBy: [.random], limit: 20)

        let recent = (try? await recentTracks)?.items ?? []
        let top = (try? await topTracks)?.items ?? []

        jumpBackIn = Self.albums(from: recent)
        onRepeat = Array(top.prefix(20))
        recentlyAdded = (try? await latest) ?? []
        favorites = (try? await favoriteAlbums)?.items ?? []
        rediscover = (try? await randomAlbums)?.items ?? []

        var artists = Self.topArtists(from: top + recent)
        if artists.count < 4 {
            // Little listening history yet: build mixes from artists in the library.
            let known = Set(artists.compactMap(\.id))
            artists += Self.topArtists(from: rediscover).filter { !known.contains($0.id ?? "") }
        }
        mixArtists = Array(artists.prefix(8))

        withAnimation(.easeOut(duration: 0.25)) { isLoading = false }
    }

    /// The albums of a list of tracks, most recent first, as lightweight album items.
    static func albums(from tracks: [BaseItemDto]) -> [BaseItemDto] {
        var seen = Set<String>()
        return tracks.compactMap { track in
            guard let albumID = track.albumID, seen.insert(albumID).inserted else { return nil }
            return BaseItemDto(
                albumArtist: track.albumArtist,
                albumArtists: track.albumArtists,
                id: albumID,
                imageTags: track.albumPrimaryImageTag.map { ["Primary": $0] },
                name: track.album,
                type: .musicAlbum
            )
        }
    }

    /// Artists ranked by how often they appear (weighted by play count).
    static func topArtists(from items: [BaseItemDto]) -> [BaseItemDto] {
        var score: [String: Int] = [:]
        var names: [String: String] = [:]
        for item in items {
            guard let artist = item.albumArtists?.first, let id = artist.id else { continue }
            score[id, default: 0] += max(1, item.userData?.playCount ?? 1)
            names[id] = artist.name
        }
        return score.sorted { $0.value > $1.value }.map { id, _ in
            BaseItemDto(id: id, name: names[id], type: .musicArtist)
        }
    }
}

// MARK: - Mix card

/// Square card that starts a mix around an artist.
struct KhyloMixCard: View {

    let artist: BaseItemDto
    var size: CGFloat = 150

    @State private var art: URL?
    @State private var tint: Color?
    @State private var isStarting = false

    var body: some View {
        Button {
            start()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(tint ?? Color.white.opacity(0.08))
                    if let art {
                        KhyloImage(url: art, showsPlaceholder: false)
                            .opacity(0.9)
                    }
                    LinearGradient(
                        colors: [.clear, (tint ?? .black).opacity(0.55), (tint ?? .black).opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MIX")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.4)
                            .foregroundColor(KhyloStyle.accent)
                        Text(artist.name ?? "")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(12)

                    if isStarting {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(10)
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

                Text("\(artist.name ?? "Artist") and similar artists")
                    .font(.system(size: 12))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .lineLimit(2)
                    .frame(width: size, alignment: .leading)
            }
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .task(id: artist.id) {
            let url = await KhyloArtistArt.shared.image(for: artist, width: size * 2)
            withAnimation(.easeOut(duration: 0.25)) { art = url }
            tint = await KhyloArtColor.color(for: url)
        }
    }

    private func start() {
        guard let id = artist.id, !isStarting else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isStarting = true
        Task {
            var songs = (try? await KhyloAPI.instantMix(from: id)) ?? []
            if songs.isEmpty {
                songs = (try? await KhyloAPI.items(types: [.audio], sortBy: [.random], artistIDs: [id], limit: 100).items) ?? []
            }
            isStarting = false
            guard !songs.isEmpty else { return }
            KhyloAudioPlayer.shared.play(songs, kind: .music, collectionTitle: "\(artist.name ?? "Artist") Mix", startTicks: 0)
        }
    }
}

// MARK: - Quality badge

/// Compact quality tag for album headers: "HI-RES 24/96", "LOSSLESS", "320 kbps".
struct KhyloQualityBadge: View {
    let quality: KhyloAudioQuality

    var body: some View {
        HStack(spacing: 4) {
            if quality.isLossless {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .tracking(0.5)
        }
        .foregroundColor(quality.isHiRes ? KhyloStyle.accent : .white.opacity(0.75))
        .padding(.horizontal, 7)
        .frame(height: 20)
        .overlay(
            Capsule().strokeBorder(quality.isHiRes ? KhyloStyle.accent.opacity(0.7) : Color.white.opacity(0.3), lineWidth: 1)
        )
        .accessibilityLabel("Audio quality \(quality.detail)")
    }

    private var label: String {
        if quality.isHiRes { return "HI-RES \(quality.short)" }
        if quality.isLossless { return "LOSSLESS" }
        return quality.short.uppercased()
    }
}
