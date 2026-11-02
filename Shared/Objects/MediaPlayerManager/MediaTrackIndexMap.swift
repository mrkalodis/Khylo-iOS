//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CryptoKit
import Foundation
import JellyfinAPI

struct MediaTrackIndexMap {

    private var playerIndexesByServerIndex: [Int: Int]

    init(_ playerIndexesByServerIndex: [Int: Int] = [:]) {
        self.playerIndexesByServerIndex = playerIndexesByServerIndex
    }

    func playerIndex(for serverIndex: Int?) -> Int? {
        guard let serverIndex, serverIndex != -1 else { return -1 }
        return playerIndexesByServerIndex[serverIndex]
    }

    mutating func setPlayerIndex(_ playerIndex: Int, for serverIndex: Int) {
        playerIndexesByServerIndex[serverIndex] = playerIndex
    }

    /// Maps Khylo stream indexes to positions in each player track array.
    /// Embedded tracks keep their order; transcoding exposes only the selected audio track.
    /// Sidecar subtitles are resolved after loading.
    static func build(
        from mediaStreams: [MediaStream],
        for playMethod: PlayMethod,
        selectedAudioStreamIndex: Int
    ) -> MediaTrackIndexMap {
        var indexMap = MediaTrackIndexMap()

        if playMethod == .transcode {
            let audioStreams = mediaStreams.filter { $0.type == .audio && $0.isExternal != true }

            if let serverIndex = audioStreams.first(where: { $0.index == selectedAudioStreamIndex })?.index {
                indexMap.setPlayerIndex(0, for: serverIndex)
            }
        } else {
            let embeddedAudioStreams = mediaStreams.filter { $0.type == .audio && $0.isExternal != true }
            let embeddedSubtitleStreams = mediaStreams.filter { $0.type == .subtitle && $0.isExternal != true }

            for (playerIndex, stream) in embeddedAudioStreams.enumerated() {
                guard let serverIndex = stream.index else { continue }
                indexMap.setPlayerIndex(playerIndex, for: serverIndex)
            }

            for (playerIndex, stream) in embeddedSubtitleStreams.enumerated() {
                guard let serverIndex = stream.index else { continue }
                indexMap.setPlayerIndex(playerIndex, for: serverIndex)
            }
        }

        return indexMap
    }

    /// Maps each sidecar to its loaded subtitle track.
    func resolvingSidecarSubtitles(
        _ sidecars: [(serverIndex: Int, url: URL)],
        subtitleTracks: [(playerIndex: Int, id: String)]
    ) -> MediaTrackIndexMap {
        var resolvedMap = self

        for subtitle in sidecars {
            // Match libVLC's MD5(full URL)/spu/... track IDs in SwiftVLC 1.0.0.
            // https://github.com/videolan/vlc/blob/c833c4be0/src/input/input.c#L2742-L2765
            let urlHash = Insecure.MD5.hash(data: Data(subtitle.url.absoluteString.utf8))
                .map { String(format: "%02x", $0) }.joined()
            resolvedMap.playerIndexesByServerIndex[subtitle.serverIndex] = subtitleTracks.first {
                $0.playerIndex >= 0 && $0.id.hasPrefix("\(urlHash)/spu/")
            }?.playerIndex
        }

        return resolvedMap
    }
}
