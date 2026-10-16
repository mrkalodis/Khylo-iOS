//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import FactoryKit
import Foundation
import Get
import JellyfinAPI
import os

/// Thin async wrapper over the signed-in user's server client.
///
/// Watch progress lives on the server: the player reports position as you watch
/// (see `MediaProgressObserver`), and `resume`/`nextUp` read it back, which is what
/// lets playback pick up where you left off on any device.
enum KhyloAPI {

    enum APIError: LocalizedError {
        case notSignedIn

        var errorDescription: String? {
            "You're not signed in."
        }
    }

    static var session: UserSession? {
        Container.shared.currentUserSession()
    }

    private static func requireSession() throws -> UserSession {
        guard let session else { throw APIError.notSignedIn }
        return session
    }

    /// Fields needed to render cards and detail headers.
    static let cardFields: [ItemFields] = [
        .overview,
        .genres,
        .primaryImageAspectRatio,
        .childCount,
        .mediaSourceCount,
        .parentID,
    ]

    static let imageTypes: [ImageType] = [.primary, .backdrop, .thumb, .logo]

    // MARK: - Home

    static func resume(limit: Int = 20, mediaTypes: [MediaType] = [.video]) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetResumeItemsParameters()
        parameters.userID = session.user.id
        parameters.limit = limit
        parameters.fields = cardFields
        parameters.mediaTypes = mediaTypes
        parameters.enableUserData = true
        parameters.enableImageTypes = imageTypes
        parameters.imageTypeLimit = 1
        return try await send(session, Paths.getResumeItems(parameters: parameters)).items ?? []
    }

    static func nextUp(limit: Int = 20, seriesID: String? = nil) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetNextUpParameters()
        parameters.userID = session.user.id
        parameters.limit = limit
        parameters.seriesID = seriesID
        parameters.fields = cardFields
        parameters.enableUserData = true
        parameters.enableImageTypes = imageTypes
        parameters.imageTypeLimit = 1
        parameters.enableResumable = false
        return try await send(session, Paths.getNextUp(parameters: parameters)).items ?? []
    }

    static func libraries() async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetUserViewsParameters()
        parameters.userID = session.user.id
        return try await send(session, Paths.getUserViews(parameters: parameters)).items ?? []
    }

    static func latest(in parentID: String, limit: Int = 20) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetLatestMediaParameters()
        parameters.userID = session.user.id
        parameters.parentID = parentID
        parameters.limit = limit
        parameters.fields = cardFields
        parameters.enableUserData = true
        parameters.enableImageTypes = imageTypes
        parameters.imageTypeLimit = 1
        parameters.isGroupItems = true
        return try await send(session, Paths.getLatestMedia(parameters: parameters))
    }

    // MARK: - Browsing

    struct Page {
        let items: [BaseItemDto]
        let total: Int
    }

    static func items(
        parentID: String? = nil,
        types: [BaseItemKind]? = nil,
        sortBy: [ItemSortBy] = [.sortName],
        sortOrder: JellyfinAPI.SortOrder = .ascending,
        filters: [JellyfinAPI.ItemFilter]? = nil,
        isFavorite: Bool? = nil,
        genres: [String]? = nil,
        artistIDs: [String]? = nil,
        albumArtistIDs: [String]? = nil,
        albumIDs: [String]? = nil,
        searchTerm: String? = nil,
        recursive: Bool = true,
        startIndex: Int = 0,
        limit: Int = 60,
        extraFields: [ItemFields] = [],
        requiredImages: [ImageType]? = nil
    ) async throws -> Page {
        let session = try requireSession()
        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.parentID = parentID
        parameters.includeItemTypes = types
        parameters.sortBy = sortBy
        parameters.sortOrder = [sortOrder]
        parameters.filters = filters
        parameters.isFavorite = isFavorite
        parameters.genres = genres
        parameters.artistIDs = artistIDs
        parameters.albumArtistIDs = albumArtistIDs
        parameters.albumIDs = albumIDs
        parameters.searchTerm = searchTerm
        parameters.isRecursive = recursive
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.fields = cardFields + extraFields
        parameters.imageTypes = requiredImages
        parameters.enableUserData = true
        parameters.enableImageTypes = imageTypes
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = true
        let result = try await send(session, Paths.getItems(parameters: parameters))
        return Page(items: result.items ?? [], total: result.totalRecordCount ?? 0)
    }

    static func item(_ id: String) async throws -> BaseItemDto {
        let session = try requireSession()
        return try await send(session, Paths.getItem(itemID: id, userID: session.user.id))
    }

    static func seasons(seriesID: String) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetSeasonsParameters()
        parameters.userID = session.user.id
        parameters.enableUserData = true
        parameters.enableImageTypes = imageTypes
        return try await send(session, Paths.getSeasons(seriesID: seriesID, parameters: parameters)).items ?? []
    }

    static func episodes(seriesID: String, seasonID: String) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetEpisodesParameters()
        parameters.userID = session.user.id
        parameters.seasonID = seasonID
        parameters.fields = [.overview, .primaryImageAspectRatio]
        parameters.enableUserData = true
        parameters.enableImageTypes = imageTypes
        return try await send(session, Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).items ?? []
    }

    static func similar(to id: String, limit: Int = 12) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetSimilarItemsParameters()
        parameters.userID = session.user.id
        parameters.limit = limit
        parameters.fields = cardFields
        return try await send(session, Paths.getSimilarItems(itemID: id, parameters: parameters)).items ?? []
    }

    /// Searches each kind separately so a flood of one kind (e.g. songs)
    /// can't crowd out the rest.
    static func search(_ term: String) async throws -> [BaseItemDto] {
        let groups: [([BaseItemKind], Int)] = [
            ([.movie], 20),
            ([.series], 20),
            ([.episode], 12),
            ([.book], 20),
            ([.audioBook], 12),
            ([.musicAlbum], 15),
            ([.musicArtist], 10),
            ([.audio], 12),
            ([.tvChannel], 10),
        ]
        return try await withThrowingTaskGroup(of: (Int, [BaseItemDto]).self) { group in
            for (index, entry) in groups.enumerated() {
                group.addTask {
                    let items = (try? await items(types: entry.0, sortBy: [.sortName], searchTerm: term, limit: entry.1).items) ?? []
                    return (index, items)
                }
            }
            var results: [(Int, [BaseItemDto])] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    /// A large, lightweight sample of titles (genres and artwork only), most
    /// popular first, used to build search categories from real genre metadata.
    static func genreSample(types: [BaseItemKind], sortBy: [ItemSortBy], limit: Int = 1500) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.includeItemTypes = types
        parameters.isRecursive = true
        parameters.sortBy = sortBy
        parameters.sortOrder = [.descending]
        parameters.limit = limit
        parameters.fields = [.genres]
        parameters.enableUserData = false
        parameters.enableImageTypes = [.primary, .backdrop]
        parameters.imageTypeLimit = 1
        return try await send(session, Paths.getItems(parameters: parameters)).items ?? []
    }

    /// Movie and show genres, for browsing.
    static func genres(parentID: String? = nil, types: [BaseItemKind] = [.movie, .series]) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetGenresParameters()
        parameters.userID = session.user.id
        parameters.parentID = parentID
        parameters.includeItemTypes = types
        parameters.sortBy = [.sortName]
        parameters.enableImages = false
        return try await send(session, Paths.getGenres(parameters: parameters)).items ?? []
    }

    // MARK: - Music

    static func albumArtists(parentID: String?, searchTerm: String? = nil, startIndex: Int = 0, limit: Int = 60) async throws -> Page {
        let session = try requireSession()
        var parameters = Paths.GetAlbumArtistsParameters()
        parameters.userID = session.user.id
        parameters.parentID = parentID
        parameters.searchTerm = searchTerm
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.sortBy = [.sortName]
        parameters.fields = [.primaryImageAspectRatio, .childCount, .overview, .genres]
        parameters.enableImages = true
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = true
        let result = try await send(session, Paths.getAlbumArtists(parameters: parameters))
        return Page(items: result.items ?? [], total: result.totalRecordCount ?? 0)
    }

    static func tracks(albumID: String) async throws -> [BaseItemDto] {
        try await items(
            parentID: albumID,
            types: [.audio],
            sortBy: [.parentIndexNumber, .indexNumber, .sortName],
            limit: 500,
            extraFields: [.mediaStreams]
        ).items
    }

    /// A mix of songs in the style of an artist, album, song or genre.
    static func instantMix(from itemID: String, limit: Int = 80) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetInstantMixFromItemParameters()
        parameters.userID = session.user.id
        parameters.limit = limit
        parameters.fields = cardFields
        parameters.enableUserData = true
        return try await send(session, Paths.getInstantMixFromItem(itemID: itemID, parameters: parameters)).items ?? []
    }

    static func similarArtists(to artistID: String, limit: Int = 12) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetSimilarArtistsParameters()
        parameters.userID = session.user.id
        parameters.limit = limit
        parameters.fields = [.primaryImageAspectRatio, .genres]
        return try await send(session, Paths.getSimilarArtists(itemID: artistID, parameters: parameters)).items ?? []
    }

    // MARK: - Live TV

    static func channels(limit: Int = 500) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetLiveTvChannelsParameters()
        parameters.userID = session.user.id
        parameters.isAddCurrentProgram = true
        parameters.enableImages = true
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        parameters.limit = limit
        return try await send(session, Paths.getLiveTvChannels(parameters: parameters)).items ?? []
    }

    /// Programs airing now, with artwork, for the Live TV hero row.
    static func onNow(limit: Int = 20) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetRecommendedProgramsParameters()
        parameters.userID = session.user.id
        parameters.isAiring = true
        parameters.limit = limit
        parameters.enableImages = true
        parameters.imageTypeLimit = 1
        parameters.fields = [.channelInfo, .primaryImageAspectRatio]
        return try await send(session, Paths.getRecommendedPrograms(parameters: parameters)).items ?? []
    }

    /// Upcoming programs on a set of channels, for the guide.
    static func programs(channelIDs: [String], hours: Double = 6) async throws -> [BaseItemDto] {
        let session = try requireSession()
        var parameters = Paths.GetLiveTvProgramsParameters()
        parameters.userID = session.user.id
        parameters.channelIDs = channelIDs
        parameters.minEndDate = Date()
        parameters.maxStartDate = Date().addingTimeInterval(hours * 3600)
        parameters.sortBy = [.startDate]
        parameters.enableImages = false
        parameters.limit = 2000
        return try await send(session, Paths.getLiveTvPrograms(parameters: parameters)).items ?? []
    }

    // MARK: - User data

    @discardableResult
    static func setFavorite(_ isFavorite: Bool, itemID: String) async throws -> UserItemDataDto {
        let session = try requireSession()
        let request = isFavorite
            ? Paths.markFavoriteItem(itemID: itemID, userID: session.user.id)
            : Paths.unmarkFavoriteItem(itemID: itemID, userID: session.user.id)
        return try await session.client.send(request).value
    }

    @discardableResult
    static func setPlayed(_ isPlayed: Bool, itemID: String) async throws -> UserItemDataDto {
        let session = try requireSession()
        let request = isPlayed
            ? Paths.markPlayedItem(itemID: itemID, userID: session.user.id)
            : Paths.markUnplayedItem(itemID: itemID, userID: session.user.id)
        return try await session.client.send(request).value
    }

    /// Takes an item out of Continue Watching by clearing its saved position.
    /// It stays unwatched and is still in its library.
    static func removeFromResume(itemID: String) async throws {
        let session = try requireSession()
        var body = UpdateUserItemDataDto()
        body.playbackPositionTicks = 0
        _ = try await session.client.send(Paths.updateItemUserData(itemID: itemID, userID: session.user.id, body))
    }

    // MARK: - Lenient decoding

    /// Library types this app knows how to present beyond the SDK's list,
    /// e.g. the Khylo server's "audiobooks" and "podcasts" libraries.
    enum ExtendedCollectionType: String {
        case audiobooks
        case podcasts
    }

    private static let extendedTypes = OSAllocatedUnfairLock(initialState: [String: String]())

    /// The server's own collection type for a library the SDK reports as unknown.
    static func extendedCollectionType(for item: BaseItemDto) -> ExtendedCollectionType? {
        guard let id = item.id else { return nil }
        return extendedTypes.withLock { $0[id] }.flatMap(ExtendedCollectionType.init(rawValue:))
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(string)"))
            }
            return date
        }
        return decoder
    }()

    /// Server dates look like `2024-05-01T12:34:56.1234567Z`, sometimes without
    /// fraction or zone; trim the fraction to milliseconds for `ISO8601DateFormatter`.
    private static func parseDate(_ string: String) -> Date? {
        var value = string
        if let dot = value.firstIndex(of: ".") {
            let fractionEnd = value[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) ?? value.endIndex
            let digits = value[value.index(after: dot) ..< fractionEnd].prefix(3)
            value = String(value[..<dot]) + "." + digits.padding(toLength: 3, withPad: "0", startingAt: 0) + value[fractionEnd...]
        }
        if !value.hasSuffix("Z"), value.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) == nil {
            value += "Z"
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static let knownCollectionTypes = Set(CollectionType.allCases.map(\.rawValue))

    /// Sends a request and decodes it, replacing enum values the SDK doesn't know
    /// (which would otherwise fail the whole response) and remembering them.
    private static func send<T: Decodable>(_ session: UserSession, _ request: Request<T>) async throws -> T {
        let data = try await session.client.data(for: request).value
        do {
            return try decoder.decode(T.self, from: data)
        } catch is DecodingError {
            let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let cleaned = try JSONSerialization.data(withJSONObject: sanitize(json), options: [.fragmentsAllowed])
            return try decoder.decode(T.self, from: cleaned)
        }
    }

    private static func sanitize(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            if let raw = object["CollectionType"] as? String, !knownCollectionTypes.contains(raw) {
                if let id = object["Id"] as? String {
                    extendedTypes.withLock { $0[id] = raw }
                }
                object["CollectionType"] = CollectionType.unknown.rawValue
            }
            for (key, child) in object where child is [Any] || child is [String: Any] {
                object[key] = sanitize(child)
            }
            return object
        }
        if let array = value as? [Any] {
            return array.map(sanitize)
        }
        return value
    }

    // MARK: - URLs

    /// Authenticated download URL for an item's original file (used for books).
    static func downloadURL(itemID: String) -> URL? {
        guard let session else { return nil }
        return session.client.url(with: Paths.getDownload(itemID: itemID))
    }

    static var accessToken: String? {
        session?.user.accessToken
    }
}

// MARK: - Khylo TV

/// Khylo TV: always-on channels the server builds from your own libraries.
/// The server keeps the schedule; tuning in returns what's on and how far in.
extension KhyloAPI {

    struct TVProgram: Decodable, Hashable {
        let itemID: String
        let type: String?
        let name: String
        let seriesName: String?
        let seriesID: String?
        let seasonNumber: Int?
        let episodeNumber: Int?
        let productionYear: Int?
        let officialRating: String?
        let overview: String?
        let start: Date
        let end: Date

        enum CodingKeys: String, CodingKey {
            case itemID = "ItemId"
            case type = "Type"
            case name = "Name"
            case seriesName = "SeriesName"
            case seriesID = "SeriesId"
            case seasonNumber = "SeasonNumber"
            case episodeNumber = "EpisodeNumber"
            case productionYear = "ProductionYear"
            case officialRating = "OfficialRating"
            case overview = "Overview"
            case start = "StartUtc"
            case end = "EndUtc"
        }

        /// The show for episodes, otherwise the title.
        var title: String { seriesName ?? name }

        /// "S2 · E5 · Episode name" for episodes, the year for movies.
        var subtitle: String {
            guard seriesName != nil else { return productionYear.map(String.init) ?? "" }
            var parts: [String] = []
            if let seasonNumber { parts.append("S\(seasonNumber)") }
            if let episodeNumber { parts.append("E\(episodeNumber)") }
            parts.append(name)
            return parts.joined(separator: " · ")
        }

        func isOn(at date: Date) -> Bool { start <= date && end > date }

        func progress(at date: Date) -> Double {
            let length = end.timeIntervalSince(start)
            guard length > 0 else { return 0 }
            return min(1, max(0, date.timeIntervalSince(start) / length))
        }
    }

    struct TVChannel: Decodable, Identifiable, Hashable {
        let id: String
        let key: String?
        let number: Int
        let name: String
        /// TV, Movies, Networks or Collections.
        let category: String
        let description: String?
        let programs: [TVProgram]

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case key = "Key"
            case number = "Number"
            case name = "Name"
            case category = "Category"
            case description = "Description"
            case programs = "Programs"
        }

        func current(at date: Date) -> TVProgram? { programs.first { $0.isOn(at: date) } }

        func next(after date: Date) -> TVProgram? { programs.first { $0.start > date } }
    }

    struct TVTuneResult: Decodable {
        let channel: TVChannel
        let current: TVProgram?
        let startPositionTicks: Int
        let upNext: [TVProgram]
        let serverTime: Date

        enum CodingKeys: String, CodingKey {
            case channel = "Channel"
            case current = "Current"
            case startPositionTicks = "StartPositionTicks"
            case upNext = "UpNext"
            case serverTime = "ServerTimeUtc"
        }
    }

    private struct TVStatus: Decodable {
        let enabled: Bool

        enum CodingKeys: String, CodingKey {
            case enabled = "Enabled"
        }
    }

    static func khyloTVEnabled() async throws -> Bool {
        let session = try requireSession()
        return try await send(session, Request<TVStatus>(path: "/LiveChannels/Status")).enabled
    }

    static func khyloTVGuide(from start: Date = Date(), hours: Int = 6) async throws -> [TVChannel] {
        let session = try requireSession()
        let formatter = ISO8601DateFormatter()
        let request = Request<[TVChannel]>(
            path: "/LiveChannels/Guide",
            query: [("startTime", formatter.string(from: start)), ("hours", String(hours))]
        )
        return try await send(session, request)
    }

    static func tuneKhyloTV(channelID: String) async throws -> TVTuneResult {
        let session = try requireSession()
        return try await send(session, Request<TVTuneResult>(path: "/LiveChannels/\(channelID)/Tune", method: "POST"))
    }

    /// Tells the server this device stopped watching channels.
    static func leaveKhyloTV() async {
        guard let session else { return }
        _ = try? await session.client.send(Request<Void>(path: "/LiveChannels/Leave", method: "POST"))
    }
}
