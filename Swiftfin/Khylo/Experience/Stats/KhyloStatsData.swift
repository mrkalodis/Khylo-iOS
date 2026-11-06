//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//


import Foundation
import Get
import JellyfinAPI

// MARK: - Models

/// Decodes a value if it is there and the right shape; otherwise leaves it out
/// instead of failing the whole page.
struct KhyloLossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct KhyloStatArtist: Decodable, Identifiable {
    let artistId: String?
    let name: String?
    let seconds: Double?
    let plays: Int?
    var id: String { artistId ?? name ?? UUID().uuidString }
}

struct KhyloStatSong: Decodable, Identifiable {
    let songKey: String?
    let itemId: String?
    let title: String?
    let artist: String?
    let plays: Int?
    let seconds: Double?
    var id: String { songKey ?? itemId ?? title ?? UUID().uuidString }
}

struct KhyloStatAlbum: Decodable, Identifiable {
    let albumId: String?
    let name: String?
    let artist: String?
    let seconds: Double?
    let plays: Int?
    var id: String { albumId ?? name ?? UUID().uuidString }
}

struct KhyloStatGenre: Decodable, Identifiable {
    let name: String?
    let seconds: Double?
    var id: String { name ?? UUID().uuidString }
}

struct KhyloStatDay: Decodable, Identifiable {
    let date: String
    let seconds: Double?
    let plays: Int?
    var id: String { date }
}

struct KhyloStatBusiestDay: Decodable {
    let date: String?
    let seconds: Double?
    let topArtist: String?
}

struct KhyloStatPrevious: Decodable {
    let totalSeconds: Double?
    let plays: Int?
}

struct KhyloStatSongRef: Decodable {
    let title: String?
    let artist: String?
}

struct KhyloStatMonth: Decodable, Identifiable {
    let month: Int
    let seconds: Double?
    let topArtist: String?
    var id: Int { month }
}

struct KhyloStatWeekday: Decodable, Identifiable {
    let weekday: Int
    let seconds: Double?
    var id: Int { weekday }
}

struct KhyloStatHour: Decodable, Identifiable {
    let hour: Int
    let seconds: Double?
    var id: Int { hour }
}

/// Any range of days: the weekly page.
struct KhyloStatSummary: Decodable {
    let totalSeconds: Double?
    let plays: Int?
    let distinctSongs: Int?
    let distinctArtists: Int?
    let distinctAlbums: Int?
    let days: [KhyloStatDay]?
    let topArtists: [KhyloStatArtist]?
    let topSongs: [KhyloStatSong]?
    let topAlbums: [KhyloStatAlbum]?
    let topGenres: [KhyloStatGenre]?
    let newArtists: [KhyloStatArtist]?
    let busiestDay: KhyloStatBusiestDay?
    let previous: KhyloStatPrevious?
}

/// A quarterly review or the yearly Wrapped.
struct KhyloStatReview: Decodable {
    let available: Bool?
    let availableFrom: String?
    let year: Int?
    let quarter: Int?
    let totalSeconds: Double?
    let plays: Int?
    let distinctSongs: Int?
    let distinctArtists: Int?
    let distinctAlbums: Int?
    let distinctGenres: Int?
    let topArtists: [KhyloStatArtist]?
    let topSongs: [KhyloStatSong]?
    let topAlbums: [KhyloStatAlbum]?
    let topGenres: [KhyloStatGenre]?
    let topArtist: KhyloStatArtist?
    let busiestDay: KhyloStatBusiestDay?
    let longestStreakDays: Int?
    let byMonth: [KhyloStatMonth]?
    let byWeekday: [KhyloStatWeekday]?
    let byHour: [KhyloStatHour]?
    let timeOfDay: String?
    let newArtists: KhyloLossy<Int>?
    let firstSong: KhyloLossy<KhyloStatSongRef>?
    let lastSong: KhyloLossy<KhyloStatSongRef>?
    let previous: KhyloLossy<KhyloStatPrevious>?
    let changePercent: KhyloLossy<Double>?
    let topChanged: KhyloLossy<Bool>?
    let climbers: KhyloLossy<[KhyloStatArtist]>?
}

struct KhyloStatQuarter: Decodable, Identifiable {
    let year: Int
    let quarter: Int
    let available: Bool?
    let availableFrom: String?
    var id: String { "\(year)-\(quarter)" }

    var title: String { "Q\(quarter) \(year)" }
    var months: String {
        ["January – March", "April – June", "July – September", "October – December"][max(0, min(3, quarter - 1))]
    }
}

struct KhyloStatHistoryRow: Decodable, Identifiable {
    let startedAt: String
    let secondsListened: Double?
    let itemId: String?
    let title: String?
    let album: String?
    let albumId: String?
    let albumArtist: String?
    let artists: [String]?
    var id: String { startedAt + (itemId ?? title ?? "") }

    var date: Date? { KhyloStatsAPI.parseDate(startedAt) }
    var artistLine: String {
        let names = (artists ?? []).filter { !$0.isEmpty }
        return names.isEmpty ? (albumArtist ?? "") : names.joined(separator: ", ")
    }
}

struct KhyloStatHistoryPage: Decodable {
    let items: [KhyloStatHistoryRow]?
    let next: String?
}

// MARK: - Server calls

/// The person's own listening statistics. The server answers for the signed-in
/// person only; nothing here is ever made up.
enum KhyloStatsAPI {

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // The server writes PascalCase.
        decoder.keyDecodingStrategy = .custom { keys in
            let key = keys.last!.stringValue
            guard let first = key.first else { return keys.last! }
            return AnyKey(stringValue: first.lowercased() + key.dropFirst())
        }
        return decoder
    }()

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    static var timeZone: String { TimeZone.current.identifier }

    /// An administrator can open the reviews early (on a Dev server) to try them out.
    /// It is still their own data.
    static var opensReviewsEarly: Bool {
        KhyloAPI.session?.user.data.policy?.isAdministrator == true
    }

    private static func fetch<T: Decodable>(_ path: String, query: [(String, String?)] = []) async throws -> T {
        guard let session = KhyloAPI.session else { throw KhyloAPI.APIError.notSignedIn }
        let request = Request<Void>(path: path, method: "GET", query: query)
        let data = try await session.client.data(for: request).value
        return try decoder.decode(T.self, from: data)
    }

    static func summary(from: String, to: String) async throws -> KhyloStatSummary {
        try await fetch("/Khylo/Listening/Summary", query: [("from", from), ("to", to), ("tz", timeZone), ("kind", "music")])
    }

    static func quarters() async throws -> [KhyloStatQuarter] {
        try await fetch("/Khylo/Listening/Quarters", query: [("kind", "music"), ("tz", timeZone)])
    }

    static func quarter(year: Int, quarter: Int) async throws -> KhyloStatReview {
        var query: [(String, String?)] = [("year", "\(year)"), ("quarter", "\(quarter)"), ("kind", "music"), ("tz", timeZone)]
        if opensReviewsEarly { query.append(("preview", "true")) }
        return try await fetch("/Khylo/Listening/Quarter", query: query)
    }

    static func wrapped(year: Int) async throws -> KhyloStatReview {
        var query: [(String, String?)] = [("year", "\(year)"), ("kind", "music"), ("tz", timeZone)]
        if opensReviewsEarly { query.append(("preview", "true")) }
        return try await fetch("/Khylo/Listening/Wrapped", query: query)
    }

    static func history(before: String?, limit: Int = 50) async throws -> KhyloStatHistoryPage {
        var query: [(String, String?)] = [("limit", "\(limit)"), ("kind", "music")]
        if let before { query.append(("before", before)) }
        return try await fetch("/Khylo/Listening/History", query: query)
    }

    private struct SettingsBody: Codable {
        var enabled: Bool
        enum CodingKeys: String, CodingKey { case enabled = "Enabled" }
    }

    static func isRecording() async throws -> Bool {
        let settings: SettingsBody = try await fetch("/Khylo/Listening/Settings")
        return settings.enabled
    }

    static func setRecording(_ enabled: Bool) async throws {
        guard let session = KhyloAPI.session else { throw KhyloAPI.APIError.notSignedIn }
        _ = try await session.client.send(Request<Void>(path: "/Khylo/Listening/Settings", method: "POST", body: SettingsBody(enabled: enabled)))
    }

    static func deleteAll() async throws {
        guard let session = KhyloAPI.session else { throw KhyloAPI.APIError.notSignedIn }
        _ = try await session.client.send(Request<Void>(path: "/Khylo/Listening", method: "DELETE"))
    }

    // MARK: Formatting

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func day(_ string: String?) -> Date? { string.flatMap { dayFormatter.date(from: String($0.prefix(10))) } }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        // The server may leave off the zone; that time is UTC.
        let bare = DateFormatter()
        bare.locale = Locale(identifier: "en_US_POSIX")
        bare.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            bare.dateFormat = format
            if let date = bare.date(from: string) { return date }
        }
        return nil
    }

    /// "3 h 20 min", "45 min", "12 min".
    static func duration(_ seconds: Double?) -> String {
        let total = Int((seconds ?? 0).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min" }
        return "\(max(minutes, total > 0 ? 1 : 0)) min"
    }
}
