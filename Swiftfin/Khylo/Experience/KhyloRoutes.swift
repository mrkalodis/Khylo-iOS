//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Routes

extension NavigationRoute {

    static func khyloItem(_ item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "khylo-item-\(item.id ?? UUID().uuidString)") {
            KhyloDestination(item: item)
        }
    }

    static func khyloLibrary(_ library: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "khylo-library-\(library.id ?? UUID().uuidString)") {
            KhyloLibraryScreen(library: library)
        }
    }

    static func khyloCollection(
        title: String,
        id: String,
        loader: @escaping (Int, Int) async throws -> KhyloAPI.Page
    ) -> NavigationRoute {
        NavigationRoute(id: "khylo-collection-\(id)") {
            KhyloGridScreen(title: title, loader: loader)
        }
    }

    static func khyloProfile() -> NavigationRoute {
        NavigationRoute(id: "khylo-profile", style: .sheet) {
            KhyloProfileScreen()
        }
    }
}

/// Sends each kind of item to the screen that suits it.
struct KhyloDestination: View {

    let item: BaseItemDto

    var body: some View {
        switch item.type {
        case .collectionFolder, .userView:
            KhyloLibraryScreen(library: item)
        case .folder:
            KhyloFolderScreen(folder: item)
        case .book:
            KhyloBookScreen(book: item)
        case .audioBook:
            KhyloAudiobookPartRedirect(part: item)
        case .musicAlbum, .playlist:
            KhyloAlbumScreen(album: item)
        case .musicArtist:
            KhyloArtistScreen(artist: item)
        case .audio:
            KhyloTrackRedirect(track: item)
        case .tvChannel:
            KhyloChannelRedirect(channel: item)
        default:
            KhyloDetailScreen(item: item)
        }
    }
}

// MARK: - Playback

/// Starts playback through the app's media player, which reports progress to the
/// server as you watch so Continue Watching stays in sync across devices.
@MainActor
enum KhyloPlayback {

    enum StartPoint {
        /// Continue from the server's saved position.
        case resume
        case beginning
    }

    /// Plays a movie, episode or video. For a series or season, plays the next episode.
    static func play(
        _ item: BaseItemDto,
        from start: StartPoint = .resume,
        router: Router.Wrapper
    ) async throws {
        var playable = try await playableItem(for: item)

        if start == .beginning {
            playable.userData?.playbackPositionTicks = 0
        }

        guard let provider = playable.getPlaybackItemProvider(userSession: KhyloAPI.session) else {
            throw PlaybackError.unavailable
        }

        let queue: (any MediaPlayerQueue)? = playable.type == .episode
            ? EpisodeMediaPlayerQueue(episode: playable)
            : nil

        router.route(to: .videoPlayer(provider: provider, queue: queue))
    }

    /// Plays an item exactly as given (already fetched, start position set), with no episode queue.
    static func play(prepared item: BaseItemDto, router: Router.Wrapper) throws {
        guard let provider = item.getPlaybackItemProvider(userSession: KhyloAPI.session) else {
            throw PlaybackError.unavailable
        }
        router.route(to: .videoPlayer(provider: provider, queue: nil))
    }

    /// Resolves what Play should actually start, with full media source info.
    private static func playableItem(for item: BaseItemDto) async throws -> BaseItemDto {
        switch item.type {
        case .series:
            guard let id = item.id else { throw PlaybackError.unavailable }
            if let next = try await KhyloAPI.nextUp(limit: 1, seriesID: id).first?.id {
                return try await KhyloAPI.item(next)
            }
            // Nothing in progress: start from the first episode.
            let seasons = try await KhyloAPI.seasons(seriesID: id)
            guard let season = seasons.first(where: { ($0.indexNumber ?? 0) > 0 }) ?? seasons.first,
                  let seasonID = season.id,
                  let first = try await KhyloAPI.episodes(seriesID: id, seasonID: seasonID).first?.id
            else { throw PlaybackError.unavailable }
            return try await KhyloAPI.item(first)
        case .season:
            guard let seriesID = item.seriesID, let seasonID = item.id else { throw PlaybackError.unavailable }
            let episodes = try await KhyloAPI.episodes(seriesID: seriesID, seasonID: seasonID)
            guard let next = episodes.first(where: { !$0.khyloIsPlayed })?.id ?? episodes.first?.id
            else { throw PlaybackError.unavailable }
            return try await KhyloAPI.item(next)
        default:
            guard let id = item.id else { throw PlaybackError.unavailable }
            return try await KhyloAPI.item(id)
        }
    }

    enum PlaybackError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "This title can't be played right now."
        }
    }
}

/// Opening a single audiobook part shows its whole book.
struct KhyloAudiobookPartRedirect: View {
    let part: BaseItemDto
    @State private var folder: BaseItemDto?

    var body: some View {
        Group {
            if let folder {
                KhyloAudiobookScreen(book: folder)
            } else {
                KhyloLoadingState().background(KhyloStyle.canvas.ignoresSafeArea())
            }
        }
        .task {
            if let parentID = part.parentID, let parent = try? await KhyloAPI.item(parentID) {
                folder = parent
            } else {
                folder = part
            }
        }
    }
}
