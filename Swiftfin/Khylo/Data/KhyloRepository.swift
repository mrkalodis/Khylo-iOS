//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Foundation

// MARK: - Khylo Media Item Model

public struct KhyloMediaItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: String // Movie, Episode, Series, Channel
    public let overview: String?
    public let seriesName: String?
    public let seriesId: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let productionYear: Int?
    public let officialRating: String?
    public let communityRating: Double?
    public let runTimeTicks: Int64?
    public let playbackPositionTicks: Int64?
    public let genres: [String]
    public let backdropImageTag: String?
    public let primaryImageTag: String?
    public let logoImageTag: String?
    public let isPlayed: Bool
    public let isFavorite: Bool
    public let serverUrl: URL?

    public init(
        id: String,
        name: String,
        type: String,
        overview: String? = nil,
        seriesName: String? = nil,
        seriesId: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        productionYear: Int? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        runTimeTicks: Int64? = nil,
        playbackPositionTicks: Int64? = nil,
        genres: [String] = [],
        backdropImageTag: String? = nil,
        primaryImageTag: String? = nil,
        logoImageTag: String? = nil,
        isPlayed: Bool = false,
        isFavorite: Bool = false,
        serverUrl: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.overview = overview
        self.seriesName = seriesName
        self.seriesId = seriesId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.productionYear = productionYear
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.runTimeTicks = runTimeTicks
        self.playbackPositionTicks = playbackPositionTicks
        self.genres = genres
        self.backdropImageTag = backdropImageTag
        self.primaryImageTag = primaryImageTag
        self.logoImageTag = logoImageTag
        self.isPlayed = isPlayed
        self.isFavorite = isFavorite
        self.serverUrl = serverUrl
    }

    // MARK: - Computed Properties

    public var title: String { name }
    public var subtitle: String? { displaySubtitle.isEmpty ? nil : displaySubtitle }
    public var isUnplayed: Bool { !isPlayed }
    public var imageURL: URL? {
        if type == "Episode" {
            return backdropURL() ?? posterURL()
        } else {
            return posterURL() ?? backdropURL()
        }
    }

    public var progress: Double {
        guard let runTime = runTimeTicks, runTime > 0,
              let pos = playbackPositionTicks, pos > 0 else {
            return 0.0
        }
        return min(max(Double(pos) / Double(runTime), 0.0), 1.0)
    }

    public var durationString: String {
        guard let runTime = runTimeTicks, runTime > 0 else { return "" }
        let totalSeconds = Int(runTime / 10_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    public var formattedEpisodeSubtitle: String? {
        if let s = seasonNumber, let e = episodeNumber {
            return "S\(s):E\(e)"
        }
        return nil
    }

    public var displaySubtitle: String {
        if type == "Episode" {
            var parts: [String] = []
            if let s = seasonNumber, let e = episodeNumber {
                parts.append("S\(s):E\(e)")
            }
            if let seriesName {
                parts.append(seriesName)
            }
            return parts.joined(separator: " • ")
        } else {
            var parts: [String] = []
            if let year = productionYear {
                parts.append("\(year)")
            }
            if let rating = officialRating, !rating.isEmpty {
                parts.append(rating)
            }
            if !durationString.isEmpty {
                parts.append(durationString)
            }
            return parts.joined(separator: " • ")
        }
    }

    // MARK: - Image URLs

    public func backdropURL(width: Int = 1280) -> URL? {
        guard let server = serverUrl else { return nil }
        var targetId = id
        var tag = backdropImageTag
        if tag == nil, let seriesId {
            targetId = seriesId
        }
        var comp = URLComponents(url: server.appendingPathComponent("Items/\(targetId)/Images/Backdrop"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "quality", value: "90")
        ]
        if let tag {
            comp?.queryItems?.append(URLQueryItem(name: "tag", value: tag))
        }
        return comp?.url
    }

    public func posterURL(width: Int = 600) -> URL? {
        guard let server = serverUrl else { return nil }
        var targetId = id
        // For episodes, primary image might belong to series or season
        if type == "Episode", primaryImageTag == nil, let seriesId {
            targetId = seriesId
        }
        var comp = URLComponents(url: server.appendingPathComponent("Items/\(targetId)/Images/Primary"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "quality", value: "90")
        ]
        if let primaryImageTag {
            comp?.queryItems?.append(URLQueryItem(name: "tag", value: primaryImageTag))
        }
        return comp?.url
    }

    public func logoURL(width: Int = 600) -> URL? {
        guard let server = serverUrl else { return nil }
        var targetId = id
        if let seriesId {
            targetId = seriesId
        }
        var comp = URLComponents(url: server.appendingPathComponent("Items/\(targetId)/Images/Logo"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "quality", value: "90")
        ]
        if let logoImageTag {
            comp?.queryItems?.append(URLQueryItem(name: "tag", value: logoImageTag))
        }
        return comp?.url
    }
}

// MARK: - Library Model

public struct KhyloMediaLibrary: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let collectionType: String
    public let itemCount: Int?
    public let primaryImageTag: String?
    public let serverUrl: URL?

    public init(
        id: String,
        name: String,
        collectionType: String,
        itemCount: Int? = nil,
        primaryImageTag: String? = nil,
        serverUrl: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
        self.itemCount = itemCount
        self.primaryImageTag = primaryImageTag
        self.serverUrl = serverUrl
    }

    public var systemIconName: String {
        switch collectionType.lowercased() {
        case "movies": return "film.stack"
        case "tvshows": return "tv"
        case "music": return "music.note.list"
        case "books": return "book.closed"
        case "audiobooks": return "headphones"
        case "boxsets": return "square.stack.3d.up"
        case "playlists": return "music.quarternote.3"
        case "homevideos", "photos": return "photo.on.rectangle"
        default: return "folder.fill"
        }
    }
}

// MARK: - Person Model

public struct KhyloPerson: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let role: String?
    public let type: String?
    public let primaryImageTag: String?
    public let overview: String?
    public let serverUrl: URL?

    public init(
        id: String,
        name: String,
        role: String? = nil,
        type: String? = nil,
        primaryImageTag: String? = nil,
        overview: String? = nil,
        serverUrl: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.primaryImageTag = primaryImageTag
        self.overview = overview
        self.serverUrl = serverUrl
    }

    public func imageURL(width: Int = 400) -> URL? {
        guard let server = serverUrl else { return nil }
        var comp = URLComponents(url: server.appendingPathComponent("Items/\(id)/Images/Primary"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "quality", value: "90")
        ]
        if let primaryImageTag {
            comp?.queryItems?.append(URLQueryItem(name: "tag", value: primaryImageTag))
        }
        return comp?.url
    }
}

// MARK: - Season Model

public struct KhyloSeason: Identifiable, Hashable, Sendable {
    public let id: String
    public let seriesId: String
    public let name: String
    public let seasonNumber: Int
    public let episodeCount: Int
    public var episodes: [KhyloMediaItem]

    public init(
        id: String,
        seriesId: String,
        name: String,
        seasonNumber: Int,
        episodeCount: Int = 0,
        episodes: [KhyloMediaItem] = []
    ) {
        self.id = id
        self.seriesId = seriesId
        self.name = name
        self.seasonNumber = seasonNumber
        self.episodeCount = episodeCount
        self.episodes = episodes
    }
}

// MARK: - Technical Specs Model

public struct TechnicalSpecs: Hashable, Sendable {
    public let container: String?
    public let videoCodec: String?
    public let resolution: String?
    public let bitrate: Int?
    public let audioStreams: [String]
    public let subtitleStreams: [String]

    public init(
        container: String? = nil,
        videoCodec: String? = nil,
        resolution: String? = nil,
        bitrate: Int? = nil,
        audioStreams: [String] = [],
        subtitleStreams: [String] = []
    ) {
        self.container = container
        self.videoCodec = videoCodec
        self.resolution = resolution
        self.bitrate = bitrate
        self.audioStreams = audioStreams
        self.subtitleStreams = subtitleStreams
    }

    public var formattedBitrate: String? {
        guard let bitrate, bitrate > 0 else { return nil }
        let mbps = Double(bitrate) / 1_000_000.0
        return String(format: "%.1f Mbps", mbps)
    }
}

// MARK: - Media Segment Model

public enum SegmentType: String, Sendable, Codable, CaseIterable {
    case intro = "Intro"
    case recap = "Recap"
    case credits = "Outro"
    case preview = "Preview"
    case commercial = "Commercial"

    public var title: String {
        switch self {
        case .intro: return "Skip Intro"
        case .recap: return "Skip Recap"
        case .credits: return "Skip Credits"
        case .preview: return "Skip Preview"
        case .commercial: return "Skip Ad"
        }
    }

    public var iconName: String {
        switch self {
        case .intro, .recap, .credits, .preview:
            return "forward.fill"
        case .commercial:
            return "xmark.circle"
        }
    }
}

public struct KhyloSegment: Identifiable, Hashable, Sendable {
    public let id: String
    public let itemId: String
    public let type: SegmentType
    public let startTicks: Int64
    public let endTicks: Int64

    public init(
        id: String,
        itemId: String,
        type: SegmentType,
        startTicks: Int64,
        endTicks: Int64
    ) {
        self.id = id
        self.itemId = itemId
        self.type = type
        self.startTicks = startTicks
        self.endTicks = endTicks
    }

    public var startSeconds: Double {
        Double(startTicks) / 10_000_000.0
    }

    public var endSeconds: Double {
        Double(endTicks) / 10_000_000.0
    }
}

// MARK: - Khylo Repository

@MainActor
public final class KhyloRepository: ObservableObject {

    public static let shared = KhyloRepository()

    @Published public private(set) var heroBillboardItems: [KhyloMediaItem] = []
    @Published public private(set) var continueWatchingItems: [KhyloMediaItem] = []
    @Published public private(set) var nextUpItems: [KhyloMediaItem] = []
    @Published public private(set) var recentlyAddedItems: [KhyloMediaItem] = []
    @Published public private(set) var recommendedItems: [KhyloMediaItem] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    public private(set) var serverUrl: URL?
    public private(set) var userId: String?
    public private(set) var accessToken: String?

    public init(
        serverUrl: URL? = nil,
        userId: String? = nil,
        accessToken: String? = nil
    ) {
        self.serverUrl = serverUrl
        self.userId = userId
        self.accessToken = accessToken
    }

    public func configure(serverUrl: URL?, userId: String?, accessToken: String?) {
        self.serverUrl = serverUrl
        self.userId = userId
        self.accessToken = accessToken
        UpNextManager.shared.configure(userId: userId, serverUrl: serverUrl)
    }

    public var currentServerUrl: URL? { serverUrl }
    public var currentUserId: String? { userId }
    public var currentAccessToken: String? { accessToken }

    // MARK: - Main Refresh

    public func refreshAll() async {
        isLoading = true
        errorMessage = nil

        async let hero = fetchHeroBillboard()
        async let resume = fetchContinueWatching()
        async let nextUp = fetchNextUp()
        async let recent = fetchRecentlyAdded(itemType: nil)
        async let recommended = fetchRecommendations()

        let (h, r, n, rec, recom) = await (hero, resume, nextUp, recent, recommended)

        self.heroBillboardItems = h
        self.continueWatchingItems = r
        self.nextUpItems = n
        self.recentlyAddedItems = rec
        self.recommendedItems = recom
        self.isLoading = false
    }

    // MARK: - Fetchers

    public func fetchHeroBillboard() async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else {
            return sampleHeroItems
        }

        var comp = URLComponents(url: server.appendingPathComponent("Users/\(uId)/Items"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series"),
            URLQueryItem(name: "SortBy", value: "DateCreated,PremiereDate"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Limit", value: "6"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,MediaSources,Taglines")
        ]

        guard let url = comp?.url else { return sampleHeroItems }
        if let items = await fetchItems(from: url), !items.isEmpty {
            return items
        }
        return sampleHeroItems
    }

    public func fetchContinueWatching() async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else {
            return sampleContinueWatching
        }

        var comp = URLComponents(url: server.appendingPathComponent("Users/\(uId)/Items/Resume"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "Limit", value: "15"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,SeriesId,SeriesName,SeasonNumber,IndexNumber")
        ]

        guard let url = comp?.url else { return sampleContinueWatching }
        guard let items = await fetchItems(from: url), !items.isEmpty else {
            return sampleContinueWatching
        }

        // Deduplicate 1 episode per show:
        var seenSeries = Set<String>()
        var deduplicated: [KhyloMediaItem] = []
        for item in items {
            if let seriesId = item.seriesId {
                if !seenSeries.contains(seriesId) {
                    seenSeries.insert(seriesId)
                    deduplicated.append(item)
                }
            } else {
                deduplicated.append(item)
            }
        }
        return deduplicated
    }

    public func fetchNextUp() async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else {
            return UpNextManager.shared.filter(items: sampleNextUp, seriesIdProvider: { $0.seriesId })
        }

        var comp = URLComponents(url: server.appendingPathComponent("Shows/NextUp"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "UserId", value: uId),
            URLQueryItem(name: "Limit", value: "24"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,SeriesId,SeriesName,SeasonNumber,IndexNumber")
        ]

        guard let url = comp?.url else {
            return UpNextManager.shared.filter(items: sampleNextUp, seriesIdProvider: { $0.seriesId })
        }

        guard let items = await fetchItems(from: url), !items.isEmpty else {
            return UpNextManager.shared.filter(items: sampleNextUp, seriesIdProvider: { $0.seriesId })
        }

        // Filter hidden series using UpNextManager
        return UpNextManager.shared.filter(items: items, seriesIdProvider: { $0.seriesId })
    }

    public func fetchRecentlyAdded(itemType: String?) async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else {
            return sampleRecentlyAdded
        }

        var comp = URLComponents(url: server.appendingPathComponent("Users/\(uId)/Items/Latest"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "Limit", value: "20"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,ProductionYear")
        ]
        if let itemType, !itemType.isEmpty {
            comp?.queryItems?.append(URLQueryItem(name: "IncludeItemTypes", value: itemType))
        }

        guard let url = comp?.url else { return sampleRecentlyAdded }
        if let items = await fetchItems(from: url), !items.isEmpty {
            return items
        }
        return sampleRecentlyAdded
    }

    public func fetchRecommendations() async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else {
            return sampleRecommendations
        }

        var comp = URLComponents(url: server.appendingPathComponent("Users/\(uId)/Suggestions"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "Limit", value: "16"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,ProductionYear")
        ]

        guard let url = comp?.url else { return sampleRecommendations }
        if let items = await fetchItems(from: url), !items.isEmpty {
            return items
        }
        return sampleRecommendations
    }

    // MARK: - Mutations

    public func markPlayed(itemId: String, isPlayed: Bool) async {
        guard let server = serverUrl, let uId = userId else { return }
        let endpoint = server.appendingPathComponent("Users/\(uId)/PlayedItems/\(itemId)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = isPlayed ? "POST" : "DELETE"
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }
        _ = try? await URLSession.shared.data(for: request)
        await refreshAll()
    }

    public func toggleFavorite(itemId: String, isFavorite: Bool) async {
        guard let server = serverUrl, let uId = userId else { return }
        let endpoint = server.appendingPathComponent("Users/\(uId)/FavoriteItems/\(itemId)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = isFavorite ? "POST" : "DELETE"
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }
        _ = try? await URLSession.shared.data(for: request)
    }

    public func dismissFromNextUp(seriesId: String) {
        UpNextManager.shared.hide(seriesId: seriesId)
        nextUpItems.removeAll { $0.seriesId == seriesId }
    }

    // MARK: - Libraries (User Views)

    public func fetchUserViews() async -> [KhyloMediaLibrary] {
        guard let server = serverUrl, let uId = userId else {
            return sampleLibraries
        }

        let url = server.appendingPathComponent("Users/\(uId)/Views")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["Items"] as? [[String: Any]] else {
                return sampleLibraries
            }

            let libraries = items.compactMap { dict -> KhyloMediaLibrary? in
                guard let id = dict["Id"] as? String,
                      let name = dict["Name"] as? String else { return nil }
                let colType = dict["CollectionType"] as? String ?? "movies"
                let imageTags = dict["ImageTags"] as? [String: String]
                let primaryTag = imageTags?["Primary"]
                return KhyloMediaLibrary(
                    id: id,
                    name: name,
                    collectionType: colType,
                    itemCount: nil,
                    primaryImageTag: primaryTag,
                    serverUrl: server
                )
            }

            return libraries.isEmpty ? sampleLibraries : libraries
        } catch {
            return sampleLibraries
        }
    }

    // MARK: - Library Items

    public func fetchLibraryItems(
        libraryId: String,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending",
        itemTypes: [String]? = nil,
        searchTerm: String? = nil,
        limit: Int = 100,
        startIndex: Int = 0
    ) async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else {
            return sampleRecentlyAdded
        }

        var comp = URLComponents(url: server.appendingPathComponent("Users/\(uId)/Items"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "ParentId", value: libraryId),
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: sortOrder),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,ProductionYear,MediaSources")
        ]

        if let itemTypes, !itemTypes.isEmpty {
            queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: itemTypes.joined(separator: ",")))
        }

        if let searchTerm, !searchTerm.isEmpty {
            queryItems.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }

        comp?.queryItems = queryItems
        guard let url = comp?.url else { return sampleRecentlyAdded }

        if let items = await fetchItems(from: url), !items.isEmpty {
            return items
        }
        return sampleRecentlyAdded
    }

    // MARK: - Item Details

    public func fetchItemDetails(itemId: String) async -> (item: KhyloMediaItem?, people: [KhyloPerson], seasons: [KhyloSeason], specs: TechnicalSpecs?, similar: [KhyloMediaItem]) {
        guard let server = serverUrl, let uId = userId else {
            return sampleDetails(for: itemId)
        }

        var comp = URLComponents(url: server.appendingPathComponent("Users/\(uId)/Items/\(itemId)"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,ProductionYear,MediaSources,People,Taglines")
        ]
        guard let url = comp?.url else { return sampleDetails(for: itemId) }

        var request = URLRequest(url: url)
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsedItem = parseItem(from: dict) else {
                return sampleDetails(for: itemId)
            }

            // Parse People
            var peopleList: [KhyloPerson] = []
            if let peopleArray = dict["People"] as? [[String: Any]] {
                peopleList = peopleArray.compactMap { pDict in
                    guard let pId = pDict["Id"] as? String,
                          let pName = pDict["Name"] as? String else { return nil }
                    let role = pDict["Role"] as? String
                    let type = pDict["Type"] as? String
                    let pTag = pDict["PrimaryImageTag"] as? String
                    return KhyloPerson(id: pId, name: pName, role: role, type: type, primaryImageTag: pTag, serverUrl: server)
                }
            }

            // Parse Media Sources / Technical Specs
            var specs: TechnicalSpecs?
            if let mediaSources = dict["MediaSources"] as? [[String: Any]], let firstSource = mediaSources.first {
                let container = firstSource["Container"] as? String
                let bitrate = firstSource["Bitrate"] as? Int
                var videoCodec: String?
                var resString: String?
                var audioList: [String] = []
                var subList: [String] = []

                if let mediaStreams = firstSource["MediaStreams"] as? [[String: Any]] {
                    for stream in mediaStreams {
                        let streamType = stream["Type"] as? String
                        let codec = stream["Codec"] as? String
                        let displayTitle = stream["DisplayTitle"] as? String ?? codec ?? "Unknown"

                        if streamType == "Video" && videoCodec == nil {
                            videoCodec = codec?.uppercased()
                            if let width = stream["Width"] as? Int, let height = stream["Height"] as? Int {
                                if width >= 3800 || height >= 2100 {
                                    resString = "4K UHD"
                                } else if width >= 1900 || height >= 1000 {
                                    resString = "1080p HD"
                                } else if width >= 1200 || height >= 700 {
                                    resString = "720p HD"
                                } else {
                                    resString = "SD"
                                }
                            }
                        } else if streamType == "Audio" {
                            audioList.append(displayTitle)
                        } else if streamType == "Subtitle" {
                            subList.append(displayTitle)
                        }
                    }
                }

                specs = TechnicalSpecs(
                    container: container?.uppercased(),
                    videoCodec: videoCodec,
                    resolution: resString,
                    bitrate: bitrate,
                    audioStreams: audioList,
                    subtitleStreams: subList
                )
            }

            // Fetch Seasons if Series
            var seasonsList: [KhyloSeason] = []
            if parsedItem.type == "Series" {
                seasonsList = await fetchSeasons(seriesId: itemId)
            }

            // Fetch Similar
            let similarItems = await fetchSimilarItems(itemId: itemId)

            return (parsedItem, peopleList, seasonsList, specs, similarItems)
        } catch {
            return sampleDetails(for: itemId)
        }
    }

    public func fetchSeasons(seriesId: String) async -> [KhyloSeason] {
        guard let server = serverUrl, let uId = userId else { return [] }
        let url = server.appendingPathComponent("Shows/\(seriesId)/Seasons?userId=\(uId)")
        var request = URLRequest(url: url)
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["Items"] as? [[String: Any]] else {
                return []
            }

            var seasons: [KhyloSeason] = []
            for sDict in items {
                guard let sId = sDict["Id"] as? String,
                      let sName = sDict["Name"] as? String else { continue }
                let sIndex = sDict["IndexNumber"] as? Int ?? 1
                let episodes = await fetchSeasonEpisodes(seriesId: seriesId, seasonId: sId)
                seasons.append(KhyloSeason(id: sId, seriesId: seriesId, name: sName, seasonNumber: sIndex, episodeCount: episodes.count, episodes: episodes))
            }
            return seasons
        } catch {
            return []
        }
    }

    public func fetchSeasonEpisodes(seriesId: String, seasonId: String) async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else { return [] }
        var comp = URLComponents(url: server.appendingPathComponent("Shows/\(seriesId)/Episodes"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "seasonId", value: seasonId),
            URLQueryItem(name: "userId", value: uId),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,PlaybackPositionTicks")
        ]
        guard let url = comp?.url else { return [] }
        return (await fetchItems(from: url)) ?? []
    }

    public func fetchSimilarItems(itemId: String) async -> [KhyloMediaItem] {
        guard let server = serverUrl, let uId = userId else { return sampleRecommendations }
        var comp = URLComponents(url: server.appendingPathComponent("Items/\(itemId)/Similar"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "userId", value: uId),
            URLQueryItem(name: "limit", value: "12")
        ]
        guard let url = comp?.url else { return sampleRecommendations }
        return (await fetchItems(from: url)) ?? sampleRecommendations
    }

    // MARK: - Person Details

    public func fetchPerson(personId: String) async -> (person: KhyloPerson?, items: [KhyloMediaItem]) {
        guard let server = serverUrl, let uId = userId else {
            return (KhyloPerson(id: personId, name: "Denis Villeneuve", role: "Director", overview: "Canadian filmmaker known for critically acclaimed sci-fi and thriller features including Dune, Blade Runner 2049, Arrival, and Sicario."), sampleRecentlyAdded)
        }

        let pUrl = server.appendingPathComponent("Persons/\(personId)?userId=\(uId)")
        var request = URLRequest(url: pUrl)
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }

        var person: KhyloPerson?
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["Name"] as? String {
            let overview = json["Overview"] as? String
            let imageTags = json["ImageTags"] as? [String: String]
            let pTag = imageTags?["Primary"]
            person = KhyloPerson(id: personId, name: name, primaryImageTag: pTag, overview: overview, serverUrl: server)
        }

        var comp = URLComponents(url: server.appendingPathComponent("Users/\(uId)/Items"), resolvingAgainstBaseURL: false)
        comp?.queryItems = [
            URLQueryItem(name: "PersonIds", value: personId),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "PremiereDate,ProductionYear"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Limit", value: "50"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,CommunityRating,OfficialRating,RunTimeTicks,ProductionYear")
        ]

        var items: [KhyloMediaItem] = []
        if let url = comp?.url, let fetched = await fetchItems(from: url) {
            items = fetched
        }

        return (person, items.isEmpty ? sampleRecentlyAdded : items)
    }

    // MARK: - Media Segments

    public func fetchMediaSegments(itemId: String) async -> [KhyloSegment] {
        guard let server = serverUrl else {
            // Return sample segments for intro & credits
            return [
                KhyloSegment(id: "seg-intro", itemId: itemId, type: .intro, startTicks: 600_000_000, endTicks: 1_450_000_000), // 60s to 145s
                KhyloSegment(id: "seg-credits", itemId: itemId, type: .credits, startTicks: 27_000_000_000, endTicks: 28_200_000_000) // credits near end
            ]
        }

        var comp = URLComponents(url: server.appendingPathComponent("Items/\(itemId)/MediaSegments"), resolvingAgainstBaseURL: false)
        guard let url = comp?.url else { return [] }

        var request = URLRequest(url: url)
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["Items"] as? [[String: Any]] else {
                return []
            }

            return items.compactMap { dict -> KhyloSegment? in
                guard let id = dict["Id"] as? String,
                      let typeRaw = dict["Type"] as? String,
                      let start = dict["StartTicks"] as? Int64,
                      let end = dict["EndTicks"] as? Int64 else { return nil }

                let segType: SegmentType
                switch typeRaw.lowercased() {
                case "intro": segType = .intro
                case "recap": segType = .recap
                case "outro", "credits": segType = .credits
                case "preview": segType = .preview
                case "commercial": segType = .commercial
                default: segType = .intro
                }

                return KhyloSegment(id: id, itemId: itemId, type: segType, startTicks: start, endTicks: end)
            }
        } catch {
            return []
        }
    }

    // MARK: - Playback Session Reporting

    public func reportPlaybackStart(itemId: String, positionTicks: Int64) async {
        await sendSessionReport(endpoint: "Sessions/Playing", itemId: itemId, positionTicks: positionTicks, isPaused: false)
    }

    public func reportPlaybackProgress(itemId: String, positionTicks: Int64, isPaused: Bool) async {
        await sendSessionReport(endpoint: "Sessions/Playing/Progress", itemId: itemId, positionTicks: positionTicks, isPaused: isPaused)
    }

    public func reportPlaybackStopped(itemId: String, positionTicks: Int64) async {
        await sendSessionReport(endpoint: "Sessions/Playing/Stopped", itemId: itemId, positionTicks: positionTicks, isPaused: false)
        await refreshAll()
    }

    private func sendSessionReport(endpoint: String, itemId: String, positionTicks: Int64, isPaused: Bool) async {
        guard let server = serverUrl else { return }
        let url = server.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }

        let payload: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "CanSeek": true,
            "PlayMethod": "DirectPlay"
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Private JSON Helper

    private func fetchItems(from url: URL) async -> [KhyloMediaItem]? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "X-Emby-Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            var rawItems: [[String: Any]] = []
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                rawItems = array
            } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let array = dict["Items"] as? [[String: Any]] {
                rawItems = array
            }

            return rawItems.compactMap { parseItem(from: $0) }
        } catch {
            return nil
        }
    }

    private func parseItem(from dict: [String: Any]) -> KhyloMediaItem? {
        guard let id = dict["Id"] as? String,
              let name = dict["Name"] as? String else {
            return nil
        }

        let type = dict["Type"] as? String ?? "Movie"
        let overview = dict["Overview"] as? String
        let seriesName = dict["SeriesName"] as? String
        let seriesId = dict["SeriesId"] as? String
        let seasonNumber = dict["SeasonNumber"] as? Int ?? dict["ParentIndexNumber"] as? Int
        let episodeNumber = dict["EpisodeNumber"] as? Int ?? dict["IndexNumber"] as? Int
        let productionYear = dict["ProductionYear"] as? Int
        let officialRating = dict["OfficialRating"] as? String
        let communityRating = dict["CommunityRating"] as? Double
        let runTimeTicks = dict["RunTimeTicks"] as? Int64

        var playbackPositionTicks: Int64?
        var isPlayed = false
        var isFavorite = false

        if let userData = dict["UserData"] as? [String: Any] {
            playbackPositionTicks = userData["PlaybackPositionTicks"] as? Int64
            isPlayed = userData["Played"] as? Bool ?? false
            isFavorite = userData["IsFavorite"] as? Bool ?? false
        }

        let genres = dict["Genres"] as? [String] ?? []

        var backdropTag: String?
        if let backdropTags = dict["BackdropImageTags"] as? [String], let first = backdropTags.first {
            backdropTag = first
        }

        var primaryTag: String?
        if let imageTags = dict["ImageTags"] as? [String: String] {
            primaryTag = imageTags["Primary"]
        }

        var logoTag: String?
        if let imageTags = dict["ImageTags"] as? [String: String] {
            logoTag = imageTags["Logo"]
        }

        return KhyloMediaItem(
            id: id,
            name: name,
            type: type,
            overview: overview,
            seriesName: seriesName,
            seriesId: seriesId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            productionYear: productionYear,
            officialRating: officialRating,
            communityRating: communityRating,
            runTimeTicks: runTimeTicks,
            playbackPositionTicks: playbackPositionTicks,
            genres: genres,
            backdropImageTag: backdropTag,
            primaryImageTag: primaryTag,
            logoImageTag: logoTag,
            isPlayed: isPlayed,
            isFavorite: isFavorite,
            serverUrl: serverUrl
        )
    }

    // MARK: - Previews & Fallback Sample Data

    private var sampleHeroItems: [KhyloMediaItem] {
        [
            KhyloMediaItem(
                id: "hero-1",
                name: "Dune: Part Two",
                type: "Movie",
                overview: "Paul Atreides unites with Chani and the Fremen while seeking revenge against the conspirators who destroyed his family.",
                productionYear: 2024,
                officialRating: "PG-13",
                communityRating: 8.6,
                runTimeTicks: 59700000000,
                genres: ["Sci-Fi", "Adventure"]
            ),
            KhyloMediaItem(
                id: "hero-2",
                name: "Severance",
                type: "Series",
                overview: "Mark leads a team of office workers whose memories have been surgically divided between their work and personal lives.",
                productionYear: 2024,
                officialRating: "TV-MA",
                communityRating: 8.7,
                genres: ["Drama", "Sci-Fi", "Thriller"]
            ),
            KhyloMediaItem(
                id: "hero-3",
                name: "Arcane",
                type: "Series",
                overview: "Set in the utopian region of Piltover and the oppressed underground of Zaun, the story follows the origins of two iconic League champions.",
                productionYear: 2024,
                officialRating: "TV-14",
                communityRating: 9.0,
                genres: ["Animation", "Action", "Fantasy"]
            )
        ]
    }

    private var sampleContinueWatching: [KhyloMediaItem] {
        [
            KhyloMediaItem(
                id: "cw-1",
                name: "Chapter 16: The Rescue",
                type: "Episode",
                overview: "The Mandalorian and his allies attempt a daring rescue mission.",
                seriesName: "The Mandalorian",
                seriesId: "mando-series",
                seasonNumber: 2,
                episodeNumber: 8,
                runTimeTicks: 28200000000,
                playbackPositionTicks: 14100000000,
                genres: ["Action", "Sci-Fi"]
            ),
            KhyloMediaItem(
                id: "cw-2",
                name: "Oppenheimer",
                type: "Movie",
                overview: "The story of American scientist J. Robert Oppenheimer and his role in the development of the atomic bomb.",
                productionYear: 2023,
                officialRating: "R",
                communityRating: 8.9,
                runTimeTicks: 64800000000,
                playbackPositionTicks: 45360000000,
                genres: ["Biography", "Drama", "History"]
            ),
            KhyloMediaItem(
                id: "cw-3",
                name: "The We We Are",
                type: "Episode",
                overview: "The severed floor employees execute an overtime contingency plan.",
                seriesName: "Severance",
                seriesId: "sev-series",
                seasonNumber: 1,
                episodeNumber: 9,
                runTimeTicks: 31200000000,
                playbackPositionTicks: 24960000000,
                genres: ["Drama", "Sci-Fi"]
            )
        ]
    }

    private var sampleNextUp: [KhyloMediaItem] {
        [
            KhyloMediaItem(
                id: "nu-1",
                name: "Point and Shoot",
                type: "Episode",
                overview: "An unexpected visitor forces Jimmy and Kim to make a desperate choice.",
                seriesName: "Better Call Saul",
                seriesId: "bcs-series",
                seasonNumber: 6,
                episodeNumber: 8,
                runTimeTicks: 30000000000,
                genres: ["Crime", "Drama"]
            ),
            KhyloMediaItem(
                id: "nu-2",
                name: "The Lord of the Tides",
                type: "Episode",
                overview: "Six years later, the Driftmark succession suddenly becomes critical when Corlys Velaryon is wounded.",
                seriesName: "House of the Dragon",
                seriesId: "hotd-series",
                seasonNumber: 1,
                episodeNumber: 8,
                runTimeTicks: 39000000000,
                genres: ["Action", "Adventure", "Drama"]
            ),
            KhyloMediaItem(
                id: "nu-3",
                name: "When You're Lost in the Darkness",
                type: "Episode",
                overview: "Twenty years after a fungal outbreak ravages the planet, survivors Joel and Tess are tasked with a mission that could change everything.",
                seriesName: "The Last of Us",
                seriesId: "tlou-series",
                seasonNumber: 1,
                episodeNumber: 1,
                runTimeTicks: 48000000000,
                genres: ["Action", "Adventure", "Drama"]
            )
        ]
    }

    private var sampleRecentlyAdded: [KhyloMediaItem] {
        [
            KhyloMediaItem(
                id: "ra-1",
                name: "Alien: Romulus",
                type: "Movie",
                overview: "While scavenging the deep ends of a derelict space station, a group of young space colonizers come face to face with the most terrifying life form in the universe.",
                productionYear: 2024,
                officialRating: "R",
                communityRating: 7.3,
                runTimeTicks: 43200000000,
                genres: ["Horror", "Sci-Fi"]
            ),
            KhyloMediaItem(
                id: "ra-2",
                name: "The Penguin",
                type: "Series",
                overview: "Following the events of The Batman, Oz Cobb strives to seize control of the criminal underworld of Gotham City.",
                productionYear: 2024,
                officialRating: "TV-MA",
                communityRating: 8.8,
                genres: ["Crime", "Drama"]
            ),
            KhyloMediaItem(
                id: "ra-3",
                name: "Deadpool & Wolverine",
                type: "Movie",
                overview: "Wolverine is recovering from his injuries when he crosses paths with the loudmouth Deadpool.",
                productionYear: 2024,
                officialRating: "R",
                communityRating: 7.7,
                runTimeTicks: 45600000000,
                genres: ["Action", "Comedy", "Sci-Fi"]
            )
        ]
    }

    private var sampleRecommendations: [KhyloMediaItem] {
        [
            KhyloMediaItem(
                id: "rec-1",
                name: "Blade Runner 2049",
                type: "Movie",
                overview: "Young Blade Runner K's discovery of a long-buried secret leads him to track down former Blade Runner Rick Deckard.",
                productionYear: 2017,
                officialRating: "R",
                communityRating: 8.0,
                runTimeTicks: 58800000000,
                genres: ["Sci-Fi", "Mystery"]
            ),
            KhyloMediaItem(
                id: "rec-2",
                name: "Interstellar",
                type: "Movie",
                overview: "When Earth becomes uninhabitable in the future, a farmer and ex-NASA pilot, Joseph Cooper, is tasked to pilot a spacecraft, along with a team of researchers, to find a new planet for humans.",
                productionYear: 2014,
                officialRating: "PG-13",
                communityRating: 8.7,
                runTimeTicks: 60600000000,
                genres: ["Adventure", "Drama", "Sci-Fi"]
            )
        ]
    }

    public var sampleLibraries: [KhyloMediaLibrary] {
        [
            KhyloMediaLibrary(id: "lib-movies", name: "Movies", collectionType: "movies", itemCount: 142),
            KhyloMediaLibrary(id: "lib-tv", name: "TV Shows", collectionType: "tvshows", itemCount: 48),
            KhyloMediaLibrary(id: "lib-music", name: "Music", collectionType: "music", itemCount: 320),
            KhyloMediaLibrary(id: "lib-collections", name: "Collections", collectionType: "boxsets", itemCount: 16),
            KhyloMediaLibrary(id: "lib-playlists", name: "Playlists", collectionType: "playlists", itemCount: 12),
            KhyloMediaLibrary(id: "lib-audiobooks", name: "Audiobooks", collectionType: "audiobooks", itemCount: 24),
            KhyloMediaLibrary(id: "lib-books", name: "Books", collectionType: "books", itemCount: 68)
        ]
    }

    public func sampleDetails(for itemId: String) -> (item: KhyloMediaItem?, people: [KhyloPerson], seasons: [KhyloSeason], specs: TechnicalSpecs?, similar: [KhyloMediaItem]) {
        let matched = (sampleHeroItems + sampleContinueWatching + sampleNextUp + sampleRecentlyAdded + sampleRecommendations).first { $0.id == itemId }
        let fallback = matched ?? sampleHeroItems[0]

        let people = [
            KhyloPerson(id: "p1", name: "Timothée Chalamet", role: "Paul Atreides", type: "Actor"),
            KhyloPerson(id: "p2", name: "Zendaya", role: "Chani", type: "Actor"),
            KhyloPerson(id: "p3", name: "Rebecca Ferguson", role: "Lady Jessica", type: "Actor"),
            KhyloPerson(id: "p4", name: "Javier Bardem", role: "Stilgar", type: "Actor"),
            KhyloPerson(id: "p5", name: "Denis Villeneuve", role: "Director & Screenplay", type: "Director"),
            KhyloPerson(id: "p6", name: "Hans Zimmer", role: "Original Score", type: "Composer")
        ]

        let seasons = [
            KhyloSeason(
                id: "s1",
                seriesId: fallback.id,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 3,
                episodes: sampleContinueWatching
            ),
            KhyloSeason(
                id: "s2",
                seriesId: fallback.id,
                name: "Season 2",
                seasonNumber: 2,
                episodeCount: 3,
                episodes: sampleNextUp
            )
        ]

        let specs = TechnicalSpecs(
            container: "MKV",
            videoCodec: "HEVC (H.265)",
            resolution: "4K UHD",
            bitrate: 28_400_000,
            audioStreams: ["English (Dolby Atmos / TrueHD 7.1)", "English Commentary", "Spanish (AC3 5.1)"],
            subtitleStreams: ["English [Forced] (SRT)", "English (SDH)", "Spanish (SRT)", "French (SRT)"]
        )

        return (fallback, people, seasons, specs, sampleRecommendations)
    }
}
