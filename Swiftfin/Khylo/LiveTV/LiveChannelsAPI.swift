//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Foundation

// MARK: - Live Channel Program

public struct LiveChannelProgram: Identifiable, Hashable, Codable, Sendable {
    public let itemId: String
    public let name: String
    public let seriesName: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let productionYear: Int?
    public let overview: String?
    public let startUtc: String
    public let endUtc: String

    public var id: String { "\(itemId)_\(startUtc)" }

    public init(
        itemId: String,
        name: String,
        seriesName: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        productionYear: Int? = nil,
        overview: String? = nil,
        startUtc: String,
        endUtc: String
    ) {
        self.itemId = itemId
        self.name = name
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.productionYear = productionYear
        self.overview = overview
        self.startUtc = startUtc
        self.endUtc = endUtc
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case name = "Name"
        case seriesName = "SeriesName"
        case seasonNumber = "SeasonNumber"
        case episodeNumber = "EpisodeNumber"
        case productionYear = "ProductionYear"
        case overview = "Overview"
        case startUtc = "StartUtc"
        case endUtc = "EndUtc"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemId = try container.decodeIfPresent(String.self, forKey: .itemId) ?? UUID().uuidString
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.seriesName = try container.decodeIfPresent(String.self, forKey: .seriesName)
        self.seasonNumber = try container.decodeIfPresent(Int.self, forKey: .seasonNumber)
        self.episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
        self.productionYear = try container.decodeIfPresent(Int.self, forKey: .productionYear)
        self.overview = try container.decodeIfPresent(String.self, forKey: .overview)
        self.startUtc = try container.decodeIfPresent(String.self, forKey: .startUtc) ?? ""
        self.endUtc = try container.decodeIfPresent(String.self, forKey: .endUtc) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(seriesName, forKey: .seriesName)
        try container.encodeIfPresent(seasonNumber, forKey: .seasonNumber)
        try container.encodeIfPresent(episodeNumber, forKey: .episodeNumber)
        try container.encodeIfPresent(productionYear, forKey: .productionYear)
        try container.encodeIfPresent(overview, forKey: .overview)
        try container.encode(startUtc, forKey: .startUtc)
        try container.encode(endUtc, forKey: .endUtc)
    }

    public var start: Date {
        LiveChannelsAPI.parseUtc(startUtc)
    }

    public var end: Date {
        LiveChannelsAPI.parseUtc(endUtc)
    }

    /// "Series · S2 E4 · Episode" or "Movie (1999)"
    public var title: String {
        seriesName ?? name
    }

    public var detail: String? {
        if seriesName != nil {
            var parts: [String] = []
            if let s = seasonNumber, let e = episodeNumber {
                parts.append("S\(s) E\(e)")
            }
            if !name.isEmpty, name != seriesName {
                parts.append(name)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        } else if let year = productionYear {
            return "\(year)"
        }
        return nil
    }

    public func isAiring(at date: Date = Date()) -> Bool {
        return date >= start && date < end
    }

    public func progress(at date: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0.0 }
        let elapsed = date.timeIntervalSince(start)
        return min(max(elapsed / total, 0.0), 1.0)
    }

    public var durationMinutes: Int {
        let seconds = end.timeIntervalSince(start)
        return max(Int(seconds / 60), 1)
    }
}

// MARK: - Live Channel

public struct LiveChannel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let number: Int
    public let name: String
    public let category: String
    public let description: String
    public let programs: [LiveChannelProgram]

    public init(
        id: String,
        number: Int,
        name: String,
        category: String = "",
        description: String = "",
        programs: [LiveChannelProgram] = []
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.category = category
        self.description = description
        self.programs = programs
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case number = "Number"
        case name = "Name"
        case category = "Category"
        case description = "Description"
        case programs = "Programs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.programs = try container.decodeIfPresent([LiveChannelProgram].self, forKey: .programs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(description, forKey: .description)
        try container.encode(programs, forKey: .programs)
    }

    public func currentProgram(at date: Date = Date()) -> LiveChannelProgram? {
        programs.first { $0.isAiring(at: date) }
    }

    public func nextProgram(at date: Date = Date()) -> LiveChannelProgram? {
        programs.first { $0.start >= date }
    }
}

// MARK: - Live Channel Tune

public struct LiveChannelTune: Codable, Sendable {
    public let current: LiveChannelProgram?
    public let startPositionTicks: Int64

    public init(current: LiveChannelProgram?, startPositionTicks: Int64 = 0) {
        self.current = current
        self.startPositionTicks = startPositionTicks
    }

    enum CodingKeys: String, CodingKey {
        case current = "Current"
        case startPositionTicks = "StartPositionTicks"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.current = try container.decodeIfPresent(LiveChannelProgram.self, forKey: .current)
        self.startPositionTicks = try container.decodeIfPresent(Int64.self, forKey: .startPositionTicks) ?? 0
    }
}

// MARK: - Live Channel Status

public struct LiveChannelStatus: Codable, Sendable {
    public let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case enabled = "Enabled"
    }

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }
}

// MARK: - Live Channels API Client

public final class LiveChannelsAPI: @unchecked Sendable {

    public static let shared = LiveChannelsAPI()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Time Parser

    public static func parseUtc(_ value: String) -> Date {
        let cleaned: String
        if value.hasSuffix("Z") || value.contains("+") {
            cleaned = value
        } else {
            cleaned = value + "Z"
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: cleaned) {
            return d
        }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: cleaned) {
            return d
        }

        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        return fallback.date(from: value) ?? Date()
    }

    // MARK: - Status

    public func isEnabled() async -> Bool {
        guard let server = KhyloRepository.shared.currentServerUrl else {
            return true // Fallback to sample programmed channels if demo mode
        }
        guard let url = URL(string: "\(server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/LiveChannels/Status") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = KhyloRepository.shared.currentAccessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            let status = try JSONDecoder().decode(LiveChannelStatus.self, data: data)
            return status.enabled
        } catch {
            return false
        }
    }

    // MARK: - Guide

    public func fetchGuide(hours: Int = 6) async -> [LiveChannel] {
        guard let server = KhyloRepository.shared.currentServerUrl else {
            return sampleChannels()
        }
        let base = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/LiveChannels/Guide?hours=\(hours)") else {
            return sampleChannels()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = KhyloRepository.shared.currentAccessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return sampleChannels()
            }
            let channels = try JSONDecoder().decode([LiveChannel].self, data: data)
            return channels.isEmpty ? sampleChannels() : channels
        } catch {
            return sampleChannels()
        }
    }

    // MARK: - Tune

    public func tune(channelId: String) async throws -> LiveChannelTune {
        guard let server = KhyloRepository.shared.currentServerUrl else {
            // Demo tune
            let channels = sampleChannels()
            let channel = channels.first { $0.id == channelId } ?? channels.first
            let cur = channel?.currentProgram() ?? channel?.programs.first
            let elapsedSec = cur != nil ? Date().timeIntervalSince(cur!.start) : 0
            let ticks = Int64(max(elapsedSec, 0) * 10_000_000)
            return LiveChannelTune(current: cur, startPositionTicks: ticks)
        }

        let base = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/LiveChannels/\(channelId)/Tune") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        if let token = KhyloRepository.shared.currentAccessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(LiveChannelTune.self, data: data)
    }

    // MARK: - Logo URL

    public func logoURL(channelId: String) -> URL? {
        guard let server = KhyloRepository.shared.currentServerUrl else { return nil }
        let base = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var urlString = "\(base)/LiveChannels/\(channelId)/Logo"
        if let token = KhyloRepository.shared.currentAccessToken {
            urlString += "?ApiKey=\(token)"
        }
        return URL(string: urlString)
    }

    // MARK: - Sample Channels (24/7 Virtual Library Programmed)

    public func sampleChannels() -> [LiveChannel] {
        let now = Date()
        let cal = Calendar.current
        let floorDate: Date = {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            let min = (comps.minute ?? 0) < 30 ? 0 : 30
            var newComps = comps
            newComps.minute = min
            newComps.second = 0
            return cal.date(from: newComps) ?? now
        }()

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        func block(_ offsetMinutes: Int, duration: Int) -> (String, String) {
            let start = floorDate.addingTimeInterval(Double(offsetMinutes) * 60)
            let end = start.addingTimeInterval(Double(duration) * 60)
            return (iso.string(from: start), iso.string(from: end))
        }

        let (b0s, b0e) = block(-30, 45)
        let (b1s, b1e) = block(15, 60)
        let (b2s, b2e) = block(75, 45)
        let (b3s, b3e) = block(120, 60)

        let ch1 = LiveChannel(
            id: "live-ch-101",
            number: 101,
            name: "Sci-Fi 24/7",
            category: "Entertainment",
            description: "Non-stop sci-fi sagas, space operas, and dystopian thrillers curated from your library.",
            programs: [
                LiveChannelProgram(
                    itemId: "scifi-1",
                    name: "The Expanse",
                    seriesName: "The Expanse",
                    seasonNumber: 3,
                    episodeNumber: 5,
                    productionYear: 2018,
                    overview: "Holden and the crew discover the protomolecule station deep within the ring space.",
                    startUtc: b0s,
                    endUtc: b0e
                ),
                LiveChannelProgram(
                    itemId: "scifi-2",
                    name: "Blade Runner 2049",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 2017,
                    overview: "Young Blade Runner K unearths a long-buried secret that leads him to former blade runner Rick Deckard.",
                    startUtc: b1s,
                    endUtc: b1e
                ),
                LiveChannelProgram(
                    itemId: "scifi-3",
                    name: "Severance",
                    seriesName: "Severance",
                    seasonNumber: 1,
                    episodeNumber: 8,
                    productionYear: 2022,
                    overview: "Mark and his department discover what happens when their severed consciousnesses wake up outside Lumon.",
                    startUtc: b2s,
                    endUtc: b2e
                ),
                LiveChannelProgram(
                    itemId: "scifi-4",
                    name: "Interstellar",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 2014,
                    overview: "A team of explorers travels through a wormhole in space in an attempt to ensure humanity's survival.",
                    startUtc: b3s,
                    endUtc: b3e
                )
            ]
        )

        let ch2 = LiveChannel(
            id: "live-ch-102",
            number: 102,
            name: "Cinema Classics",
            category: "Movies",
            description: "Restored timeless masterpieces and golden era cinema running around the clock.",
            programs: [
                LiveChannelProgram(
                    itemId: "classic-1",
                    name: "Casablanca",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 1942,
                    overview: "A cynical expatriate American cafe owner struggles to decide whether or not to help his former lover.",
                    startUtc: b0s,
                    endUtc: b0e
                ),
                LiveChannelProgram(
                    itemId: "classic-2",
                    name: "Rear Window",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 1954,
                    overview: "A wheelchair-bound photographer spies on his neighbors from his Greenwich Village courtyard window.",
                    startUtc: b1s,
                    endUtc: b1e
                ),
                LiveChannelProgram(
                    itemId: "classic-3",
                    name: "12 Angry Men",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 1957,
                    overview: "A jury holdout attempts to prevent a miscarriage of justice by forcing the colleagues to reconsider evidence.",
                    startUtc: b2s,
                    endUtc: b2e
                ),
                LiveChannelProgram(
                    itemId: "classic-4",
                    name: "Citizen Kane",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 1941,
                    overview: "Following the death of publishing tycoon Charles Foster Kane, reporters scramble to uncover the meaning of his final word.",
                    startUtc: b3s,
                    endUtc: b3e
                )
            ]
        )

        let ch3 = LiveChannel(
            id: "live-ch-103",
            number: 103,
            name: "Animation Station",
            category: "Kids & Family",
            description: "Anime classics, studio animation masterpieces, and Saturday morning favorites.",
            programs: [
                LiveChannelProgram(
                    itemId: "anim-1",
                    name: "Spirited Away",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 2001,
                    overview: "A young girl wanders into a world ruled by gods, witches, and spirits where humans are changed into beasts.",
                    startUtc: b0s,
                    endUtc: b0e
                ),
                LiveChannelProgram(
                    itemId: "anim-2",
                    name: "Arcane",
                    seriesName: "Arcane",
                    seasonNumber: 1,
                    episodeNumber: 3,
                    productionYear: 2021,
                    overview: "The origins of two iconic League champions-and the power that will tear them apart.",
                    startUtc: b1s,
                    endUtc: b1e
                ),
                LiveChannelProgram(
                    itemId: "anim-3",
                    name: "Spider-Man: Across the Spider-Verse",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 2023,
                    overview: "Miles Morales catapults across the Multiverse, where he encounters a team of Spider-People.",
                    startUtc: b2s,
                    endUtc: b2e
                ),
                LiveChannelProgram(
                    itemId: "anim-4",
                    name: "Cowboy Bebop",
                    seriesName: "Cowboy Bebop",
                    seasonNumber: 1,
                    episodeNumber: 5,
                    productionYear: 1998,
                    overview: "Spike Spiegel confronts his old Syndicate nemesis Vicious at a deserted cathedral.",
                    startUtc: b3s,
                    endUtc: b3e
                )
            ]
        )

        let ch4 = LiveChannel(
            id: "live-ch-104",
            number: 104,
            name: "DocuZone",
            category: "Documentary",
            description: "Nature, technology, history, and investigative exposés uninterrupted.",
            programs: [
                LiveChannelProgram(
                    itemId: "doc-1",
                    name: "Planet Earth III",
                    seriesName: "Planet Earth III",
                    seasonNumber: 1,
                    episodeNumber: 2,
                    productionYear: 2023,
                    overview: "Discover how animals survive in extreme ocean and coastal environments.",
                    startUtc: b0s,
                    endUtc: b0e
                ),
                LiveChannelProgram(
                    itemId: "doc-2",
                    name: "The Last Dance",
                    seriesName: "The Last Dance",
                    seasonNumber: 1,
                    episodeNumber: 5,
                    productionYear: 2020,
                    overview: "Michael Jordan and the 1997-98 Chicago Bulls make their final championship run.",
                    startUtc: b1s,
                    endUtc: b1e
                ),
                LiveChannelProgram(
                    itemId: "doc-3",
                    name: "Apollo 11",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 2019,
                    overview: "A look at the Apollo 11 mission to land on the moon led by commander Neil Armstrong.",
                    startUtc: b2s,
                    endUtc: b2e
                ),
                LiveChannelProgram(
                    itemId: "doc-4",
                    name: "Jiro Dreams of Sushi",
                    seriesName: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    productionYear: 2011,
                    overview: "A documentary on 85-year-old sushi master Jiro Ono, his renowned Tokyo restaurant, and his relationship with his son.",
                    startUtc: b3s,
                    endUtc: b3e
                )
            ]
        )

        return [ch1, ch2, ch3, ch4]
    }
}
