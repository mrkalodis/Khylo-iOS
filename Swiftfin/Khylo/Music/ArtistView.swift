//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Album Summary Model

public struct AlbumSummary: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let year: Int
    public let trackCount: Int
    public let imageURL: URL?

    public init(id: String, title: String, year: Int, trackCount: Int, imageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.year = year
        self.trackCount = trackCount
        self.imageURL = imageURL
    }
}

// MARK: - Artist View

public struct ArtistView: View {
    public let artistId: String
    public let artistName: String
    public let backdropURL: URL?

    @EnvironmentObject private var navigator: KhyloNavigator
    @State private var topTracks: [MusicTrack] = []
    @State private var albums: [AlbumSummary] = []
    @State private var selectedTrackForPlayback: MusicTrack?
    @State private var selectedAlbumForDetail: AlbumSummary?

    public init(
        artistId: String,
        artistName: String,
        backdropURL: URL? = nil
    ) {
        self.artistId = artistId
        self.artistName = artistName
        self.backdropURL = backdropURL
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KhyloSpacing.lg) {
                    // Artist Banner Backdrop
                    artistBanner

                    // Action Buttons (Play & Shuffle)
                    actionButtonsRow
                        .padding(.horizontal, KhyloSpacing.lg)

                    // Popular Tracks Row
                    popularTracksSection
                        .padding(.horizontal, KhyloSpacing.lg)

                    // Albums Discography Grid
                    albumsDiscographySection
                        .padding(.horizontal, KhyloSpacing.lg)
                }
                .padding(.bottom, 100)
            }
        }
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedTrackForPlayback) { track in
            MusicPlayerView(
                track: track,
                queue: topTracks.filter { $0.id != track.id },
                onDismiss: { selectedTrackForPlayback = nil }
            )
        }
        .navigationDestination(item: $selectedAlbumForDetail) { album in
            AlbumView(
                albumId: album.id,
                albumTitle: album.title,
                artistName: artistName,
                releaseYear: album.year,
                artworkURL: album.imageURL
            )
        }
        .onAppear {
            loadSampleArtistData()
        }
    }

    // MARK: - Banner

    private var artistBanner: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Artwork
            ZStack {
                if let url = backdropURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            fallbackBanner
                        }
                    }
                } else {
                    fallbackBanner
                }
            }
            .frame(height: 240)
            .clipped()

            // Gradient scrim
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Artist Title
            VStack(alignment: .leading, spacing: 4) {
                Text("ARTIST")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.accent)

                Text(artistName)
                    .font(KhyloTypography.largeTitle)
                    .foregroundColor(.white)

                Text("Electronic • Ambient • Cinematic")
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
            }
            .padding(KhyloSpacing.lg)
        }
        .frame(height: 240)
    }

    private var fallbackBanner: some View {
        LinearGradient(
            colors: [KhyloColors.accent.opacity(0.6), KhyloColors.surfaceElevated],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Action Buttons

    private var actionButtonsRow: some View {
        HStack(spacing: 14) {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                if let first = topTracks.first {
                    selectedTrackForPlayback = first
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Play Radio")
                        .font(KhyloTypography.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(KhyloColors.accent)
                .cornerRadius(KhyloRadius.sm)
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                if let random = topTracks.randomElement() {
                    selectedTrackForPlayback = random
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .bold))
                    Text("Shuffle")
                        .font(KhyloTypography.headline)
                }
                .foregroundColor(KhyloColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(KhyloColors.surfaceElevated)
                .cornerRadius(KhyloRadius.sm)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Popular Tracks

    private var popularTracksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POPULAR TRACKS")
                .font(KhyloTypography.captionBold)
                .foregroundColor(KhyloColors.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(topTracks.enumerated()), id: \.element.id) { index, track in
                    Button(action: {
                        #if os(iOS)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        selectedTrackForPlayback = track
                    }) {
                        HStack(spacing: 14) {
                            Text("\(index + 1)")
                                .font(KhyloTypography.headline)
                                .foregroundColor(index == 0 ? KhyloColors.accent : KhyloColors.textTertiary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(KhyloTypography.bodyMedium)
                                    .foregroundColor(KhyloColors.textPrimary)
                                    .lineLimit(1)

                                Text(track.album ?? "Single")
                                    .font(KhyloTypography.caption)
                                    .foregroundColor(KhyloColors.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(track.durationString)
                                .font(KhyloTypography.captionMedium)
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    if index < topTracks.count - 1 {
                        Divider().background(KhyloColors.border.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.sm)
        }
    }

    // MARK: - Albums Discography

    private var albumsDiscographySection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            Text("ALBUMS")
                .font(KhyloTypography.captionBold)
                .foregroundColor(KhyloColors.textTertiary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: KhyloSpacing.md),
                    GridItem(.flexible(), spacing: KhyloSpacing.md)
                ],
                spacing: KhyloSpacing.md
            ) {
                ForEach(albums) { album in
                    Button(action: {
                        #if os(iOS)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        selectedAlbumForDetail = album
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack {
                                KhyloColors.surfaceElevated
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 32))
                                    .foregroundColor(KhyloColors.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(KhyloRadius.sm)

                            Text(album.title)
                                .font(KhyloTypography.bodyMedium)
                                .foregroundColor(KhyloColors.textPrimary)
                                .lineLimit(1)

                            Text("\(album.year) • \(album.trackCount) tracks")
                                .font(KhyloTypography.caption)
                                .foregroundColor(KhyloColors.textSecondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func loadSampleArtistData() {
        topTracks = [
            MusicTrack(id: "art-t1", title: "Solaris Reverie", artist: artistName, album: "Starlight Chronicles", durationSeconds: 218),
            MusicTrack(id: "art-t2", title: "Astral Drift", artist: artistName, album: "Infinite Horizons", durationSeconds: 278),
            MusicTrack(id: "art-t3", title: "Neon Horizon", artist: artistName, album: "Starlight Chronicles", durationSeconds: 254),
            MusicTrack(id: "art-t4", title: "Cosmic Resonance", artist: artistName, album: "Infinite Horizons", durationSeconds: 312),
            MusicTrack(id: "art-t5", title: "Silent Orbit", artist: artistName, album: "Orbit One", durationSeconds: 240)
        ]

        albums = [
            AlbumSummary(id: "alb-1", title: "Starlight Chronicles", year: 2024, trackCount: 12),
            AlbumSummary(id: "alb-2", title: "Infinite Horizons", year: 2023, trackCount: 10),
            AlbumSummary(id: "alb-3", title: "Orbit One", year: 2022, trackCount: 8),
            AlbumSummary(id: "alb-4", title: "Resonance EP", year: 2021, trackCount: 5)
        ]
    }
}
