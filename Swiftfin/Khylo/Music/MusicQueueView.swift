//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Music Track Model

public struct MusicTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let durationSeconds: Double
    public let imageURL: URL?
    public let audioURL: URL?

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Double = 210,
        imageURL: URL? = nil,
        audioURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.imageURL = imageURL
        self.audioURL = audioURL
    }

    public var durationString: String {
        let total = Int(durationSeconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Music Queue View

public struct MusicQueueView: View {
    public let currentTrack: MusicTrack?
    @Binding public var queue: [MusicTrack]
    public let onSelectTrack: (MusicTrack) -> Void
    public let onClearQueue: () -> Void
    public let onDismiss: () -> Void

    public init(
        currentTrack: MusicTrack?,
        queue: Binding<[MusicTrack]>,
        onSelectTrack: @escaping (MusicTrack) -> Void,
        onClearQueue: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentTrack = currentTrack
        self._queue = queue
        self.onSelectTrack = onSelectTrack
        self.onClearQueue = onClearQueue
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                KhyloColors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Now Playing Header Card
                    if let track = currentTrack {
                        nowPlayingSection(track: track)
                            .padding(.horizontal, KhyloSpacing.lg)
                            .padding(.top, KhyloSpacing.md)
                            .padding(.bottom, KhyloSpacing.sm)
                    }

                    // Queue List
                    if queue.isEmpty {
                        emptyQueueView
                    } else {
                        List {
                            Section {
                                ForEach(queue) { track in
                                    queueRow(track: track)
                                }
                                .onMove(perform: moveTrack)
                                .onDelete(perform: deleteTrack)
                                .listRowBackground(KhyloColors.surface)
                                .listRowSeparatorTint(KhyloColors.border)
                            } header: {
                                HStack {
                                    Text("UP NEXT (\(queue.count))")
                                        .font(KhyloTypography.captionBold)
                                        .foregroundColor(KhyloColors.textTertiary)

                                    Spacer()

                                    Button("Clear Queue") {
                                        #if os(iOS)
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        #endif
                                        onClearQueue()
                                    }
                                    .font(KhyloTypography.captionMedium)
                                    .foregroundColor(KhyloColors.accent)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Play Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(KhyloColors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .foregroundColor(KhyloColors.accent)
                }
            }
        }
    }

    // MARK: - Sections & Rows

    private func nowPlayingSection(track: MusicTrack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOW PLAYING")
                .font(KhyloTypography.captionBold)
                .foregroundColor(KhyloColors.textTertiary)

            HStack(spacing: 12) {
                // Album Art
                trackArtView(url: track.imageURL, size: 48)

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

                EqualizerBarsView(isPlaying: true, maxHeight: 18)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                    .fill(KhyloColors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: KhyloRadius.sm)
                            .strokeBorder(KhyloColors.accent.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    private func queueRow(track: MusicTrack) -> some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelectTrack(track)
        }) {
            HStack(spacing: 12) {
                trackArtView(url: track.imageURL, size: 42)

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

                Text(track.durationString)
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(KhyloColors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func trackArtView(url: URL?, size: CGFloat) -> some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    default:
                        fallbackArtIcon
                    }
                }
            } else {
                fallbackArtIcon
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(KhyloRadius.xs)
    }

    private var fallbackArtIcon: some View {
        ZStack {
            KhyloColors.surfaceElevated
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .foregroundColor(KhyloColors.textTertiary)
        }
    }

    private var emptyQueueView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(KhyloColors.textTertiary)
            Text("Queue is Empty")
                .font(KhyloTypography.headline)
                .foregroundColor(KhyloColors.textPrimary)
            Text("Select songs from an album or artist to build your queue.")
                .font(KhyloTypography.caption)
                .foregroundColor(KhyloColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func moveTrack(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteTrack(at offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
    }
}
