//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI

import JellyfinAPI
import SwiftUI

extension Notification.Name {
    /// A playlist was made, changed or deleted.
    static let khyloPlaylistsChanged = Notification.Name("khylo.playlistsChanged")
}

/// Pick a playlist for some songs, or start a new one with them.
struct KhyloAddToPlaylistSheet: View {

    let songs: [BaseItemDto]

    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var isNaming = false
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newName = ""
                        isNaming = true
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                            .foregroundColor(KhyloStyle.accent)
                    }
                }
                Section {
                    if isLoading {
                        ProgressView()
                    }
                    ForEach(playlists, id: \.id) { playlist in
                        Button {
                            add(to: playlist)
                        } label: {
                            HStack(spacing: 12) {
                                KhyloImage(url: KhyloArtwork.url(for: playlist, style: .square, width: 90), placeholderSymbol: "music.note.list")
                                    .frame(width: 42, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                Text(playlist.name ?? "")
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KhyloStyle.canvas)
            .navigationTitle(songs.count == 1 ? "Add to Playlist" : "Add \(songs.count) Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $isNaming) {
                TextField("Name", text: $newName)
                Button("Create") { create() }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                playlists = (try? await KhyloAPI.musicPlaylists()) ?? []
                isLoading = false
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func add(to playlist: BaseItemDto) {
        guard let id = playlist.id else { return }
        Task {
            do {
                try await KhyloAPI.addToPlaylist(id, songIDs: songs.compactMap(\.id))
                NotificationCenter.default.post(name: .khyloPlaylistsChanged, object: nil)
                dismiss()
            } catch {
                message = "That didn't work. Check your connection and try again."
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                try await KhyloAPI.createPlaylist(name: name, songIDs: songs.compactMap(\.id))
                NotificationCenter.default.post(name: .khyloPlaylistsChanged, object: nil)
                dismiss()
            } catch {
                message = "The playlist couldn't be made. Check your connection and try again."
            }
        }
    }
}
