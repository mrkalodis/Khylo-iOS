//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Music Home Sub-Tabs

public enum MusicHomeTab: String, CaseIterable, Identifiable {
    case listenNow = "Listen Now"
    case albums = "Albums"
    case artists = "Artists"

    public var id: String { rawValue }
}

// MARK: - Artist Summary Model

public struct ArtistSummary: Identifiable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Music Home View

public struct MusicHomeView: View {
    @EnvironmentObject private var navigator: KhyloNavigator
    @State private var selectedTab: MusicHomeTab = .listenNow
    @State private var selectedTrackForPlayer: MusicTrack?
    @State private var selectedAlbum: AlbumSummary?
    @State private var selectedArtist: ArtistSummary?

    private let sampleGenres = [
        "Electronic", "Soundtrack", "Ambient", "Classical", "Synthwave", "Rock"
    ]

    private let sampleArtists: [ArtistSummary] = [
        ArtistSummary(id: "art-1", name: "Hans Zimmer"),
        ArtistSummary(id: "art-2", name: "Daft Punk"),
        ArtistSummary(id: "art-3", name: "Ludwig Göransson"),
        ArtistSummary(id: "art-4", name: "Trent Reznor"),
        ArtistSummary(id: "art-5", name: "Max Richter"),
        ArtistSummary(id: "art-6", name: "M83")
    ]

    public init() {}

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KhyloSpacing.lg) {
                    // Header Title & Tab Picker
                    headerSection
                        .padding(.horizontal, KhyloSpacing.lg)
                        .padding(.top, KhyloSpacing.md)

                    switch selectedTab {
                    case .listenNow:
                        listenNowContent
                    case .albums:
                        albumsContent
                    case .artists:
                        artistsContent
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedTrackForPlayer) { track in
            MusicPlayerView(
                track: track,
                queue: sampleTracks.filter { $0.id != track.id },
                onDismiss: { selectedTrackForPlayer = nil }
            )
        }
        .navigationDestination(item: $selectedAlbum) { album in
            AlbumView(
                albumId: album.id,
                albumTitle: album.title,
                artistName: "Electronic Mastermind",
                releaseYear: album.year,
                artworkURL: album.imageURL
            )
        }
        .navigationDestination(item: $selectedArtist) { artist in
            ArtistView(artistId: artist.id, artistName: artist.name)
        }
    }

    // MARK: - Header & Tab Picker

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Music")
                    .font(KhyloTypography.largeTitle)
                    .foregroundColor(KhyloColors.textPrimary)

                Text("Hi-Fi streaming and curated collections")
                    .font(KhyloTypography.body)
                    .foregroundColor(KhyloColors.textSecondary)
            }

            Picker("Music View", selection: $selectedTab) {
                ForEach(MusicHomeTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Listen Now Content

    private var listenNowContent: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xl) {
            // Hero Billboard Banner
            heroBanner
                .padding(.horizontal, KhyloSpacing.lg)

            // Recently Played
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                Text("Recently Played")
                    .font(KhyloTypography.title3)
                    .foregroundColor(KhyloColors.textPrimary)
                    .padding(.horizontal, KhyloSpacing.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: KhyloSpacing.md) {
                        ForEach(sampleTracks) { track in
                            recentTrackCard(track: track)
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                }
            }

            // Artist Explorer (Circular Avatars)
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                Text("Artist Explorer")
                    .font(KhyloTypography.title3)
                    .foregroundColor(KhyloColors.textPrimary)
                    .padding(.horizontal, KhyloSpacing.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 20) {
                        ForEach(sampleArtists) { artist in
                            Button {
                                selectedArtist = artist
                            } label: {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(KhyloColors.accent.opacity(0.2))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "person.crop.circle.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(KhyloColors.accent)
                                        )
                                        .overlay(Circle().stroke(KhyloColors.border, lineWidth: 1))

                                    Text(artist.name)
                                        .font(KhyloTypography.captionMedium)
                                        .foregroundColor(KhyloColors.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 88)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                }
            }

            // Browse by Genre
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                Text("Browse Genres")
                    .font(KhyloTypography.title3)
                    .foregroundColor(KhyloColors.textPrimary)
                    .padding(.horizontal, KhyloSpacing.lg)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: KhyloSpacing.sm),
                        GridItem(.flexible(), spacing: KhyloSpacing.sm)
                    ],
                    spacing: KhyloSpacing.sm
                ) {
                    ForEach(sampleGenres, id: \.self) { genre in
                        MusicGenreCard(genre: genre)
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)
            }
        }
    }

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: KhyloRadius.lg)
                .fill(
                    LinearGradient(
                        colors: [KhyloColors.accent.opacity(0.7), KhyloColors.surfaceElevated],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 190)

            VStack(alignment: .leading, spacing: 6) {
                Text("FEATURED RELEASE")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(4)

                Text("Solaris Reverie")
                    .font(KhyloTypography.title1)
                    .foregroundColor(.white)

                Text("Hans Zimmer • High-Resolution Lossless")
                    .font(KhyloTypography.caption)
                    .foregroundColor(Color.white.opacity(0.8))

                Button {
                    if let first = sampleTracks.first {
                        selectedTrackForPlayer = first
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Play Album")
                            .font(KhyloTypography.captionBold)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            .padding(18)
        }
    }

    private func recentTrackCard(track: MusicTrack) -> some View {
        Button {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            selectedTrackForPlayer = track
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    KhyloColors.surfaceElevated
                    Image(systemName: "music.note")
                        .font(.system(size: 32))
                        .foregroundColor(KhyloColors.accent)
                }
                .frame(width: 140, height: 140)
                .cornerRadius(KhyloRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: KhyloRadius.sm)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

                Text(track.title)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)

                Text(track.artist)
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 140)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Albums Tab Content

    private var albumsContent: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: KhyloSpacing.md),
                GridItem(.flexible(), spacing: KhyloSpacing.md)
            ],
            spacing: KhyloSpacing.md
        ) {
            ForEach(sampleAlbums) { album in
                Button {
                    selectedAlbum = album
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack {
                            KhyloColors.surfaceElevated
                            Image(systemName: "music.note.list")
                                .font(.system(size: 36))
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .cornerRadius(KhyloRadius.md)

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
        .padding(.horizontal, KhyloSpacing.lg)
    }

    // MARK: - Artists Tab Content

    private var artistsContent: some View {
        VStack(spacing: KhyloSpacing.sm) {
            ForEach(sampleArtists) { artist in
                Button {
                    selectedArtist = artist
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(KhyloColors.accent.opacity(0.2))
                            .frame(width: 52, height: 52)
                            .overlay(
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(KhyloColors.accent)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist.name)
                                .font(KhyloTypography.headline)
                                .foregroundColor(KhyloColors.textPrimary)

                            Text("Artist")
                                .font(KhyloTypography.caption)
                                .foregroundColor(KhyloColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(KhyloColors.textTertiary)
                    }
                    .padding(KhyloSpacing.md)
                    .background(KhyloColors.surface)
                    .cornerRadius(KhyloRadius.sm)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
    }

    // MARK: - Sample Data

    private var sampleTracks: [MusicTrack] {
        [
            MusicTrack(id: "mh-1", title: "Solaris Reverie", artist: "Hans Zimmer", album: "Dune Soundtrack", durationSeconds: 218),
            MusicTrack(id: "mh-2", title: "Midnight Synthesis", artist: "Daft Punk", album: "Random Access Memories", durationSeconds: 230),
            MusicTrack(id: "mh-3", title: "Echoes in the Starlight", artist: "Ludwig Göransson", album: "Oppenheimer", durationSeconds: 195),
            MusicTrack(id: "mh-4", title: "Astral Drift", artist: "Trent Reznor", album: "The Social Network", durationSeconds: 278)
        ]
    }

    private var sampleAlbums: [AlbumSummary] {
        [
            AlbumSummary(id: "alb-h1", title: "Dune: Part Two OST", year: 2024, trackCount: 16),
            AlbumSummary(id: "alb-h2", title: "Random Access Memories", year: 2013, trackCount: 13),
            AlbumSummary(id: "alb-h3", title: "Oppenheimer OST", year: 2023, trackCount: 24),
            AlbumSummary(id: "alb-h4", title: "Tron: Legacy Reconfigured", year: 2011, trackCount: 15),
            AlbumSummary(id: "alb-h5", title: "Interstellar Soundtrack", year: 2014, trackCount: 16),
            AlbumSummary(id: "alb-h6", title: "Blade Runner 2049 OST", year: 2017, trackCount: 24)
        ]
    }
}

// MARK: - Music Genre Card

private struct MusicGenreCard: View {
    let genre: String

    private var color: Color {
        GenreColors.color(for: genre)
    }

    var body: some View {
        Button {} label: {
            HStack {
                Text(genre)
                    .font(KhyloTypography.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(KhyloSpacing.md)
            .frame(height: 64)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(KhyloRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
