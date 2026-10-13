//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Album Details View

public struct AlbumView: View {
    public let albumId: String
    public let albumTitle: String
    public let artistName: String
    public let releaseYear: Int?
    public let artworkURL: URL?

    @EnvironmentObject private var navigator: KhyloNavigator
    @State private var tracks: [MusicTrack] = []
    @State private var isFavorite: Bool = false
    @State private var selectedTrackForPlayback: MusicTrack?

    public init(
        albumId: String,
        albumTitle: String,
        artistName: String,
        releaseYear: Int? = 2024,
        artworkURL: URL? = nil
    ) {
        self.albumId = albumId
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.releaseYear = releaseYear
        self.artworkURL = artworkURL
    }

    private var totalDurationString: String {
        let totalSecs = tracks.reduce(0) { $0 + $1.durationSeconds }
        let mins = Int(totalSecs) / 60
        return "\(mins) mins"
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: KhyloSpacing.lg) {
                    // Album Header Artwork & Details
                    albumHeader
                        .padding(.top, KhyloSpacing.md)

                    // Action Buttons (Play All & Shuffle)
                    actionButtonsRow
                        .padding(.horizontal, KhyloSpacing.lg)

                    // Tracklist
                    tracklistSection
                        .padding(.horizontal, KhyloSpacing.lg)
                }
                .padding(.bottom, 100)
            }
        }
        .navigationTitle(albumTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedTrackForPlayback) { track in
            let queue = tracks.filter { $0.id != track.id }
            MusicPlayerView(
                track: track,
                queue: queue,
                onDismiss: {
                    selectedTrackForPlayback = nil
                }
            )
        }
        .onAppear {
            loadSampleTracks()
        }
    }

    // MARK: - Album Header

    private var albumHeader: some View {
        VStack(spacing: KhyloSpacing.md) {
            // Square Cover Art
            ZStack {
                if let url = artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(1, contentMode: .fill)
                        default:
                            fallbackCover
                        }
                    }
                } else {
                    fallbackCover
                }
            }
            .frame(width: 220, height: 220)
            .cornerRadius(KhyloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.md)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 18, x: 0, y: 10)

            // Metadata Titles
            VStack(spacing: 4) {
                Text(albumTitle)
                    .font(KhyloTypography.title2)
                    .foregroundColor(KhyloColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(artistName)
                    .font(KhyloTypography.headline)
                    .foregroundColor(KhyloColors.accent)

                HStack(spacing: 6) {
                    if let year = releaseYear {
                        Text("\(year)")
                    }
                    Text("•")
                    Text("\(tracks.count) Songs")
                    Text("•")
                    Text(totalDurationString)
                }
                .font(KhyloTypography.caption)
                .foregroundColor(KhyloColors.textSecondary)
            }
        }
    }

    private var fallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: [KhyloColors.surfaceElevated, KhyloColors.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundColor(KhyloColors.accent.opacity(0.8))
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsRow: some View {
        HStack(spacing: 14) {
            // Play All
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                if let first = tracks.first {
                    selectedTrackForPlayback = first
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Play All")
                        .font(KhyloTypography.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(KhyloColors.accent)
                .cornerRadius(KhyloRadius.sm)
                .shadow(color: KhyloColors.accent.opacity(0.35), radius: 8)
            }
            .buttonStyle(PlainButtonStyle())

            // Shuffle
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                if let random = tracks.randomElement() {
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
                .overlay(
                    RoundedRectangle(cornerRadius: KhyloRadius.sm)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Tracklist Section

    private var tracklistSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRACKS")
                .font(KhyloTypography.captionBold)
                .foregroundColor(KhyloColors.textTertiary)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button(action: {
                        #if os(iOS)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        selectedTrackForPlayback = track
                    }) {
                        HStack(spacing: 14) {
                            // Track Number
                            Text("\(index + 1)")
                                .font(KhyloTypography.bodyMedium)
                                .foregroundColor(KhyloColors.textTertiary)
                                .frame(width: 24, alignment: .trailing)

                            // Track Title
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(KhyloTypography.bodyMedium)
                                    .foregroundColor(KhyloColors.textPrimary)
                                    .lineLimit(1)

                                Text(track.artist)
                                    .font(KhyloTypography.caption)
                                    .foregroundColor(KhyloColors.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Track Duration
                            Text(track.durationString)
                                .font(KhyloTypography.captionMedium)
                                .foregroundColor(KhyloColors.textTertiary)

                            // Context menu
                            Menu {
                                Button("Play Next") {}
                                Button("Add to Queue") {}
                                Button("Add to Playlist") {}
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14))
                                    .foregroundColor(KhyloColors.textTertiary)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    if index < tracks.count - 1 {
                        Divider().background(KhyloColors.border.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.sm)
        }
    }

    private func loadSampleTracks() {
        tracks = [
            MusicTrack(id: "\(albumId)-t1", title: "Solaris Reverie", artist: artistName, album: albumTitle, durationSeconds: 218),
            MusicTrack(id: "\(albumId)-t2", title: "Neon Horizon", artist: artistName, album: albumTitle, durationSeconds: 254),
            MusicTrack(id: "\(albumId)-t3", title: "Echoes in the Starlight", artist: artistName, album: albumTitle, durationSeconds: 195),
            MusicTrack(id: "\(albumId)-t4", title: "Astral Drift", artist: artistName, album: albumTitle, durationSeconds: 278),
            MusicTrack(id: "\(albumId)-t5", title: "Midnight Synthesis", artist: artistName, album: albumTitle, durationSeconds: 230),
            MusicTrack(id: "\(albumId)-t6", title: "Velocity", artist: artistName, album: albumTitle, durationSeconds: 184),
            MusicTrack(id: "\(albumId)-t7", title: "Cosmic Resonance", artist: artistName, album: albumTitle, durationSeconds: 312),
            MusicTrack(id: "\(albumId)-t8", title: "Silent Orbit", artist: artistName, album: albumTitle, durationSeconds: 240)
        ]
    }
}
