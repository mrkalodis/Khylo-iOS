//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation
import JellyfinAPI

/// Builds artist stations and mixes: the artist's songs mixed with songs by
/// artists who really sound like them.
///
/// The server matches artists on any one shared genre, so a broad tag like
/// "Rock" puts Elvis next to metalcore. Here a match needs a shared specific
/// genre (or several broad ones), and songs from a very different era stay out.
enum KhyloRadio {

    /// Tags too wide to say two artists sound alike on their own.
    private static let broad: Set<String> = [
        "rock", "pop", "alternative", "alternativerock", "indie", "indierock", "electronic",
        "hiphop", "rap", "metal", "heavymetal", "randb", "rnb", "soul", "country", "jazz",
        "classical", "soundtrack", "dance", "folk", "blues", "world", "latin", "punk",
        "christian", "gospel", "reggae", "oldies", "other", "unknown", "music", "vocal",
        "instrumental", "easylistening", "poprock", "hardrock",
    ]

    /// Most years apart two songs can be and still share a station.
    private static let eraSpan = 15

    // MARK: Matching

    /// "Post-Hardcore", "post hardcore" and "Post Hardcore" are one genre.
    static func key(_ genre: String) -> String {
        genre.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Splits tags that hold several genres ("Rock; Metalcore", "Rock/Pop").
    static func keys(_ genres: [String]?) -> Set<String> {
        Set((genres ?? []).flatMap { $0.split(whereSeparator: { ";/|,".contains($0) }) }.map { key(String($0)) }.filter { !$0.isEmpty })
    }

    /// How alike two sets of genres are: 1 for each shared specific genre, a third for each broad one.
    static func score(_ genres: Set<String>, against profile: Set<String>) -> Double {
        genres.intersection(profile).reduce(0) { $0 + (broad.contains($1) ? 1.0 / 3 : 1) }
    }

    /// The genres that describe an artist, from their own tags and their songs'.
    private struct Profile {
        let genres: Set<String>
        /// The year in the middle of their songs, when the songs have years.
        let year: Int?

        /// With only broad tags to go on, sharing one is the best that can be asked.
        var needed: Double {
            genres.contains { !KhyloRadio.broad.contains($0) } ? 1 : 1.0 / 3
        }

        init(artist: BaseItemDto, songs: [BaseItemDto]) {
            var counts: [String: Int] = [:]
            for genre in KhyloRadio.keys(artist.genres) { counts[genre, default: 0] += 3 }
            for song in songs {
                for genre in KhyloRadio.keys(song.genres) { counts[genre, default: 0] += 1 }
            }
            // A genre on one stray song out of many isn't what the artist is.
            let floor = max(1, songs.count / 10)
            genres = Set(counts.filter { $0.value >= floor }.keys)
            let years = songs.compactMap(\.productionYear).filter { $0 > 1900 }.sorted()
            year = years.isEmpty ? nil : years[years.count / 2]
        }

        func fits(_ song: BaseItemDto) -> Bool {
            if let year, let songYear = song.productionYear, songYear > 1900, abs(songYear - year) > KhyloRadio.eraSpan {
                return false
            }
            let songGenres = KhyloRadio.keys(song.genres)
            return songGenres.isEmpty || KhyloRadio.score(songGenres, against: genres) >= needed
        }
    }

    // MARK: Stations

    /// A station's queue: starts with the artist, then alternates them with close matches.
    static func songs(for artist: BaseItemDto, limit: Int = 80) async -> [BaseItemDto] {
        guard let id = artist.id else { return [] }
        let own = (try? await KhyloAPI.items(types: [.audio], sortBy: [.random], artistIDs: [id], limit: 120).items) ?? []
        let profile = Profile(artist: await details(of: artist), songs: own)
        let matches = await closeArtists(to: id, profile: profile, limit: 10)

        var others: [BaseItemDto] = []
        await withTaskGroup(of: [BaseItemDto].self) { group in
            for match in matches {
                guard let matchID = match.id else { continue }
                group.addTask {
                    (try? await KhyloAPI.items(types: [.audio], sortBy: [.random], artistIDs: [matchID], limit: 14).items) ?? []
                }
            }
            for await songs in group {
                others.append(contentsOf: songs.filter(profile.fits).prefix(8))
            }
        }
        if others.count < 10 {
            // Few close artists in the library: the server's mix, held to the same standard.
            let mix = (try? await KhyloAPI.instantMix(from: id, limit: 150)) ?? []
            let ownIDs = Set(own.compactMap(\.id))
            others += mix.filter { !ownIDs.contains($0.id ?? "") && profile.fits($0) }
        }
        return interleave(own: own, others: others.shuffled(), limit: limit)
    }

    /// Artists who sound like this one, best match first.
    static func similarArtists(to artist: BaseItemDto, limit: Int = 12) async -> [BaseItemDto] {
        guard let id = artist.id else { return [] }
        let own = (try? await KhyloAPI.items(types: [.audio], sortBy: [.random], artistIDs: [id], limit: 60).items) ?? []
        let profile = Profile(artist: await details(of: artist), songs: own)
        return await closeArtists(to: id, profile: profile, limit: limit)
    }

    private static func closeArtists(to id: String, profile: Profile, limit: Int) async -> [BaseItemDto] {
        let candidates = (try? await KhyloAPI.similarArtists(to: id, limit: 40)) ?? []
        return candidates
            .filter { $0.id != id }
            .map { ($0, score(keys($0.genres), against: profile.genres)) }
            .filter { $0.1 >= profile.needed }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Artists picked from a list (for example from play history) carry no genres.
    private static func details(of artist: BaseItemDto) async -> BaseItemDto {
        guard artist.genres == nil, let id = artist.id else { return artist }
        return (try? await KhyloAPI.item(id)) ?? artist
    }

    /// Artist, match, match, artist… with no song twice.
    private static func interleave(own: [BaseItemDto], others: [BaseItemDto], limit: Int) -> [BaseItemDto] {
        var result: [BaseItemDto] = []
        var seen = Set<String>()
        var mine = own.makeIterator()
        var theirs = others.makeIterator()
        var step = 0
        while result.count < limit {
            let next = step % 3 == 0 ? (mine.next() ?? theirs.next()) : (theirs.next() ?? mine.next())
            guard let song = next else { break }
            step += 1
            if let id = song.id, seen.insert(id).inserted { result.append(song) }
        }
        return result
    }
}
