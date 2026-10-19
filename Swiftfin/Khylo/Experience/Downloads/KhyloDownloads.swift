//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI
import Network
import UIKit

// MARK: - Settings

/// How big a downloaded copy is.
enum KhyloDownloadQuality: String, CaseIterable, Identifiable, Codable {
    case original
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Original"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Data Saver"
        }
    }

    var detail: String {
        switch self {
        case .original: "Exactly as it is on your server"
        case .high: "1080p video · 320 kbps music"
        case .medium: "720p video · 256 kbps music"
        case .low: "480p video · 128 kbps music"
        }
    }

    var videoBitrate: Int {
        switch self {
        case .original, .high: 8_000_000
        case .medium: 4_000_000
        case .low: 1_500_000
        }
    }

    var maxWidth: Int {
        switch self {
        case .original, .high: 1920
        case .medium: 1280
        case .low: 854
        }
    }

    /// Music and audiobooks.
    var audioBitrate: Int {
        switch self {
        case .original, .high: 320_000
        case .medium: 256_000
        case .low: 128_000
        }
    }

    /// The sound in a smaller video copy.
    var videoAudioBitrate: Int {
        switch self {
        case .original, .high: 192_000
        case .medium: 160_000
        case .low: 128_000
        }
    }
}

enum KhyloDownloadSettings {
    static let qualityKey = "khylo.downloads.quality"
    static let wifiOnlyKey = "khylo.downloads.wifiOnly"
    static let autoNextKey = "khylo.downloads.autoNextEpisodes"

    static var quality: KhyloDownloadQuality {
        UserDefaults.standard.string(forKey: qualityKey).flatMap(KhyloDownloadQuality.init) ?? .original
    }

    static var wifiOnly: Bool {
        UserDefaults.standard.object(forKey: wifiOnlyKey) as? Bool ?? true
    }

    static var autoNextEpisodes: Bool {
        UserDefaults.standard.object(forKey: autoNextKey) as? Bool ?? true
    }
}

// MARK: - Network

/// Whether the phone has a connection, and whether it's Wi-Fi (not cellular or a hotspot).
@MainActor
final class KhyloNetwork: ObservableObject {

    static let shared = KhyloNetwork()

    @Published private(set) var isOnline = true
    @Published private(set) var isOnWiFi = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            let wifi = online && !path.isExpensive
            Task { @MainActor in
                let network = KhyloNetwork.shared
                let cameOnline = online && !network.isOnline
                if network.isOnline != online { network.isOnline = online }
                if network.isOnWiFi != wifi { network.isOnWiFi = wifi }
                if cameOnline {
                    // Back online: send the progress made while offline.
                    await KhyloDownloads.shared.syncProgress()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "org.khylo.network"))
    }
}

// MARK: - Model

/// One downloaded (or downloading) movie, episode, song, audiobook part or book.
struct KhyloDownload: Codable, Identifiable {

    enum Kind: String, Codable {
        case video
        case music
        case audiobook
        case book
    }

    enum State: String, Codable {
        case queued
        case downloading
        case done
        case failed
    }

    let id: String
    var item: BaseItemDto
    let kind: Kind
    let quality: KhyloDownloadQuality
    var state: State
    var fileName: String?
    var bytes: Int64 = 0
    var expectedBytes: Int64
    /// Shows, albums, playlists and audiobooks this belongs to.
    var groupIDs: [String]
    var message: String?
    var attempts = 0
    let addedAt: Date
}

/// A show, album, playlist or audiobook with downloaded members.
struct KhyloDownloadGroup: Codable, Identifiable {
    let id: String
    var item: BaseItemDto
    let kind: KhyloDownload.Kind
    /// Members in the order they play.
    var memberIDs: [String]
    let addedAt: Date
}

/// Where you got to in a downloaded title, kept on the phone and sent to the
/// server when there's a connection.
struct KhyloOfflinePosition: Codable {
    var ticks: Int
    var isPlayed: Bool
    var updated: Date
    var needsSync: Bool
}

/// What a download button shows.
enum KhyloDownloadStatus: Equatable {
    case none
    case downloading
    case done
    case failed
}

enum KhyloDownloadError: LocalizedError {
    case notAllowed
    case nothingToDownload
    case notEnoughSpace(needed: Int64)

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            "Downloads are turned off for your account. Ask the person who runs your server to allow them."
        case .nothingToDownload:
            "There's nothing here to download."
        case let .notEnoughSpace(needed):
            "There isn't enough space on your iPhone. This needs about \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file))."
        }
    }
}

/// Live download progress, kept apart so lists don't redraw on every byte.
@MainActor
final class KhyloDownloadProgress: ObservableObject {
    static let shared = KhyloDownloadProgress()
    @Published var fractions: [String: Double] = [:]
}

// MARK: - Manager

/// Downloads titles to the phone for offline playback. Downloads run in a
/// background session, so they carry on while Khylo is closed.
@MainActor
final class KhyloDownloads: NSObject, ObservableObject {

    static let shared = KhyloDownloads()

    @Published private(set) var downloads: [String: KhyloDownload] = [:]
    @Published private(set) var groups: [String: KhyloDownloadGroup] = [:]
    private var positions: [String: KhyloOfflinePosition] = [:]

    /// Handed over by the system when it wakes Khylo for finished background downloads.
    var backgroundCompletion: (() -> Void)?

    private var session: URLSession!
    private var lastProgressPublish: [String: Date] = [:]
    private var isSyncing = false
    private var cancellables: Set<AnyCancellable> = []

    nonisolated static let sessionIdentifier = "org.khylo.app.downloads"

    nonisolated static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KhyloDownloads", isDirectory: true)
    }

    nonisolated static func itemFolder(_ id: String) -> URL {
        root.appendingPathComponent("items", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    nonisolated static func groupFolder(_ id: String) -> URL {
        root.appendingPathComponent("groups", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    private static var indexFile: URL { root.appendingPathComponent("downloads.json") }
    private static var positionsFile: URL { root.appendingPathComponent("progress.json") }

    private struct Index: Codable {
        var downloads: [String: KhyloDownload]
        var groups: [String: KhyloDownloadGroup]
    }

    override private init() {
        super.init()
        prepareFolder()
        loadIndex()

        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // Few at a time, so downloads don't crowd out what you're streaming.
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 120
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        reconnect()

        NotificationCenter.default.publisher(for: .khyloOfflineProgress)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let info = note.userInfo,
                      let id = info["itemID"] as? String,
                      let ticks = info["ticks"] as? Int
                else { return }
                self?.record(itemID: id, ticks: ticks, isFinal: info["final"] as? Bool ?? false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { _ in Task { await KhyloDownloads.shared.syncProgress() } }
            .store(in: &cancellables)
    }

    // MARK: Permission

    /// The server lets this account download (the "Allow media downloading" permission).
    static var isAllowed: Bool {
        KhyloAPI.session?.user.data.policy?.enableContentDownloading == true
    }

    // MARK: Lookups

    var hasDownloads: Bool { !downloads.isEmpty }

    var active: [KhyloDownload] {
        downloads.values
            .filter { $0.state == .queued || $0.state == .downloading || $0.state == .failed }
            .sorted { $0.addedAt < $1.addedAt }
    }

    /// The finished file for a title, if it's on the phone.
    func fileURL(for itemID: String) -> URL? {
        guard let download = downloads[itemID], download.state == .done, let name = download.fileName else { return nil }
        let url = Self.itemFolder(itemID).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(_ itemID: String?) -> Bool {
        guard let itemID else { return false }
        return fileURL(for: itemID) != nil
    }

    /// The finished file for a title, for code that can't wait on the main thread.
    nonisolated static func storedFile(itemID: String) -> URL? {
        let folder = itemFolder(itemID)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.lastPathComponent.hasPrefix("media.") }
    }

    /// Saved artwork for a title, or for the show or album it belongs to.
    func artworkURL(for itemID: String?) -> URL? {
        guard let itemID else { return nil }
        let own = Self.itemFolder(itemID).appendingPathComponent("art.jpg")
        if FileManager.default.fileExists(atPath: own.path) { return own }
        if let groupID = downloads[itemID]?.groupIDs.first {
            return groupArtworkURL(groupID)
        }
        return groupArtworkURL(itemID)
    }

    func groupArtworkURL(_ groupID: String) -> URL? {
        let url = Self.groupFolder(groupID).appendingPathComponent("art.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func backdropURL(for itemID: String) -> URL? {
        let url = Self.itemFolder(itemID).appendingPathComponent("backdrop.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Members of a show, album, playlist or audiobook, in play order.
    func members(of groupID: String) -> [KhyloDownload] {
        guard let group = groups[groupID] else { return [] }
        return group.memberIDs.compactMap { downloads[$0] }
    }

    /// Downloads that belong to an item shown with a download button.
    private func related(to item: BaseItemDto) -> [KhyloDownload] {
        guard let id = item.id else { return [] }
        switch item.type {
        case .season:
            return downloads.values.filter { $0.item.seasonID == id }
        case .series, .musicAlbum, .playlist, .folder:
            if groups[id] != nil { return members(of: id) }
            return downloads[id].map { [$0] } ?? []
        default:
            if let single = downloads[id] { return [single] }
            return groups[id] != nil ? members(of: id) : []
        }
    }

    func status(for item: BaseItemDto) -> KhyloDownloadStatus {
        let related = related(to: item)
        guard !related.isEmpty else { return .none }
        if related.contains(where: { $0.state == .queued || $0.state == .downloading }) { return .downloading }
        if related.contains(where: { $0.state == .failed }) { return .failed }
        return .done
    }

    func progress(for item: BaseItemDto, live: [String: Double]) -> Double {
        let related = related(to: item)
        guard !related.isEmpty else { return 0 }
        let total = related.reduce(0.0) { sum, download in
            sum + (download.state == .done ? 1 : (live[download.id] ?? fraction(download)))
        }
        return total / Double(related.count)
    }

    private func fraction(_ download: KhyloDownload) -> Double {
        guard download.expectedBytes > 0 else { return 0 }
        return min(Double(download.bytes) / Double(download.expectedBytes), 0.99)
    }

    // MARK: Storage

    var usedBytes: Int64 {
        downloads.values.reduce(0) { $0 + ($1.state == .done ? $1.bytes : 0) }
    }

    var freeBytes: Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func bytes(of group: KhyloDownloadGroup) -> Int64 {
        members(of: group.id).reduce(0) { $0 + ($1.state == .done ? $1.bytes : $1.expectedBytes) }
    }

    // MARK: Starting downloads

    /// Downloads a title, or everything in a show, season, album, playlist or audiobook.
    func download(_ item: BaseItemDto) async throws {
        guard Self.isAllowed else { throw KhyloDownloadError.notAllowed }
        guard let id = item.id else { throw KhyloDownloadError.nothingToDownload }

        switch item.type {
        case .series:
            let episodes = try await KhyloAPI.items(
                parentID: id, types: [.episode], sortBy: [.parentIndexNumber, .indexNumber],
                limit: 2000, extraFields: [.mediaSources]
            ).items
            try enqueue(episodes, kind: .video, group: item)
        case .season:
            let episodes = try await KhyloAPI.items(
                parentID: id, types: [.episode], sortBy: [.parentIndexNumber, .indexNumber],
                limit: 500, extraFields: [.mediaSources]
            ).items
            let series = try await item.seriesID.asyncMap { try await KhyloAPI.item($0) }
            try enqueue(episodes, kind: .video, group: series)
        case .episode:
            let full = try await KhyloAPI.item(id)
            let series = try? await full.seriesID.asyncMap { try await KhyloAPI.item($0) }
            try enqueue([full], kind: .video, group: series ?? nil)
        case .musicAlbum, .playlist:
            let tracks = try await KhyloAPI.items(
                parentID: id, types: [.audio],
                sortBy: [.parentIndexNumber, .indexNumber, .sortName],
                recursive: true, limit: 2000, extraFields: [.mediaSources, .mediaStreams]
            ).items
            try enqueue(tracks, kind: .music, group: item)
        case .audio:
            try enqueue([try await KhyloAPI.item(id)], kind: .music, group: nil)
        case .book:
            try enqueue([try await KhyloAPI.item(id)], kind: .book, group: nil)
        case .audioBook:
            try enqueue([try await KhyloAPI.item(id)], kind: .audiobook, group: nil)
        default:
            try enqueue([try await KhyloAPI.item(id)], kind: .video, group: nil)
        }
    }

    /// Downloads an audiobook's parts (the screen already has them).
    func downloadAudiobook(book: BaseItemDto, parts: [BaseItemDto]) async throws {
        guard Self.isAllowed else { throw KhyloDownloadError.notAllowed }
        if parts.count == 1, parts[0].id == book.id {
            try await download(parts[0])
            return
        }
        let full = (try? await KhyloAudiobook.parts(of: book.id ?? "")) ?? parts
        try enqueue(full.isEmpty ? parts : full, kind: .audiobook, group: book)
    }

    private func enqueue(_ items: [BaseItemDto], kind: KhyloDownload.Kind, group: BaseItemDto?) throws {
        let fresh = items.filter { item in
            guard let id = item.id else { return false }
            return downloads[id] == nil || downloads[id]?.state == .failed
        }
        guard !fresh.isEmpty || group != nil else { throw KhyloDownloadError.nothingToDownload }
        let quality = kind == .book ? .original : KhyloDownloadSettings.quality

        let needed = fresh.reduce(Int64(0)) { $0 + Self.estimatedBytes(for: $1, kind: kind, quality: quality) }
        if needed > freeBytes - 500_000_000 { throw KhyloDownloadError.notEnoughSpace(needed: needed) }

        if let group, let groupID = group.id {
            var record = groups[groupID] ?? KhyloDownloadGroup(id: groupID, item: group, kind: kind, memberIDs: [], addedAt: Date())
            record.item = group
            for item in items {
                if let id = item.id, !record.memberIDs.contains(id) { record.memberIDs.append(id) }
            }
            if kind == .video {
                // Episodes stay in season and episode order however they were added.
                record.memberIDs.sort { lhs, rhs in
                    let a = downloads[lhs]?.item ?? items.first { $0.id == lhs }
                    let b = downloads[rhs]?.item ?? items.first { $0.id == rhs }
                    return ((a?.parentIndexNumber ?? 0), (a?.indexNumber ?? 0)) < ((b?.parentIndexNumber ?? 0), (b?.indexNumber ?? 0))
                }
            }
            groups[groupID] = record
            saveArtwork(for: group, into: Self.groupFolder(groupID), style: kind == .video ? .poster : .square)
        }

        for item in items {
            guard let id = item.id else { continue }
            if var existing = downloads[id] {
                if let groupID = group?.id, !existing.groupIDs.contains(groupID) {
                    existing.groupIDs.append(groupID)
                    downloads[id] = existing
                }
                guard existing.state == .failed else { continue }
            }
            downloads[id] = KhyloDownload(
                id: id,
                item: item,
                kind: kind,
                quality: quality,
                state: .queued,
                expectedBytes: Self.estimatedBytes(for: item, kind: kind, quality: quality),
                groupIDs: Array(Set((downloads[id]?.groupIDs ?? []) + (group?.id.map { [$0] } ?? []))),
                addedAt: Date()
            )
            if group == nil || kind == .video {
                saveArtwork(for: item, into: Self.itemFolder(id), style: kind == .video && item.type == .episode ? .landscape : (kind == .music ? .square : .poster))
            }
            if kind == .video, item.type != .episode {
                saveArtwork(for: item, into: Self.itemFolder(id), style: .backdrop, name: "backdrop.jpg")
            }
            start(id)
        }

        save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func estimatedBytes(for item: BaseItemDto, kind: KhyloDownload.Kind, quality: KhyloDownloadQuality) -> Int64 {
        let seconds = Double(item.runTimeTicks ?? 0) / 10_000_000
        if quality == .original || kind == .book {
            if let size = item.mediaSources?.first?.size, size > 0 { return Int64(size) }
        }
        switch kind {
        case .video:
            return Int64(seconds * Double(quality.videoBitrate + quality.videoAudioBitrate) / 8)
        case .music, .audiobook:
            return Int64(seconds * Double(quality.audioBitrate) / 8)
        case .book:
            return 20_000_000
        }
    }

    // MARK: Transfers

    private func start(_ id: String) {
        guard var download = downloads[id] else { return }
        guard let (url, ext) = sourceURL(for: download) else {
            // Not signed in yet (Khylo is still starting): wait in the queue.
            guard KhyloAPI.session == nil else {
                download.state = .failed
                download.message = "Sign in again to download."
                downloads[id] = download
                return
            }
            download.state = .queued
            downloads[id] = download
            return
        }
        var request = URLRequest(url: url)
        let wifiOnly = KhyloDownloadSettings.wifiOnly
        request.allowsCellularAccess = !wifiOnly
        request.allowsExpensiveNetworkAccess = !wifiOnly
        let task = session.downloadTask(with: request)
        task.taskDescription = "\(id)|\(ext)"
        if download.expectedBytes > 0 { task.countOfBytesClientExpectsToReceive = download.expectedBytes }
        task.resume()

        download.state = .downloading
        download.message = nil
        download.attempts += 1
        downloads[id] = download
    }

    /// The link for a download: the original file, or a smaller copy made by the server.
    private func sourceURL(for download: KhyloDownload) -> (URL, String)? {
        guard let client = KhyloAPI.session?.client, let token = KhyloAPI.accessToken else { return nil }
        let id = download.id
        let item = download.item

        func make(_ path: String, _ query: [String: String]) -> URL? {
            guard let base = client.url(path: path),
                  var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            else { return nil }
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "ApiKey", value: token)]
            return components.url
        }

        if download.quality == .original || download.kind == .book {
            return make("/Items/\(id)/Download", [:]).map { ($0, Self.originalExtension(for: item, kind: download.kind)) }
        }

        let quality = download.quality
        let device = UIDevice.current.identifierForVendor?.uuidString ?? "khylo-ios"
        switch download.kind {
        case .video:
            let query = [
                "container": "mp4",
                "videoCodec": "h264",
                "audioCodec": "aac",
                "videoBitRate": String(quality.videoBitrate),
                "audioBitRate": String(quality.videoAudioBitrate),
                "maxWidth": String(quality.maxWidth),
                "audioChannels": "2",
                "mediaSourceId": item.mediaSources?.first?.id ?? id,
                "static": "false",
                "deviceId": device,
                "playSessionId": UUID().uuidString,
            ]
            return make("/Videos/\(id)/stream.mp4", query).map { ($0, "mp4") }
        case .music, .audiobook:
            let query = [
                "container": "mp3",
                "audioCodec": "mp3",
                "audioBitRate": String(quality.audioBitrate),
                "static": "false",
                "deviceId": device,
            ]
            return make("/Audio/\(id)/stream.mp3", query).map { ($0, "mp3") }
        case .book:
            return nil
        }
    }

    private static func originalExtension(for item: BaseItemDto, kind: KhyloDownload.Kind) -> String {
        let path = item.mediaSources?.first?.path ?? item.path ?? ""
        let fromPath = (path as NSString).pathExtension.lowercased()
        if !fromPath.isEmpty, fromPath.count <= 5 { return fromPath }
        if let container = item.mediaSources?.first?.container?.split(separator: ",").first {
            return String(container)
        }
        return kind == .book ? "book" : "media"
    }

    /// Picks up downloads that were running when Khylo was closed, and starts
    /// any that were waiting for sign-in.
    func reconnect() {
        session.getAllTasks { tasks in
            let running = Set(tasks.compactMap { $0.taskDescription?.components(separatedBy: "|").first })
            Task { @MainActor in
                let downloads = KhyloDownloads.shared
                for (id, download) in downloads.downloads where download.state == .queued || download.state == .downloading {
                    if !running.contains(id) { downloads.start(id) }
                }
                downloads.save()
            }
        }
    }

    /// Starts unfinished downloads again (for example after Wi-Fi only is turned off).
    func restartPending() {
        session.getAllTasks { tasks in
            for task in tasks { task.cancel() }
            Task { @MainActor in
                let downloads = KhyloDownloads.shared
                for (id, download) in downloads.downloads where download.state != .done {
                    downloads.downloads[id]?.attempts = 0
                    downloads.start(id)
                }
                downloads.save()
            }
        }
    }

    func retry(_ id: String) {
        downloads[id]?.attempts = 0
        start(id)
        save()
    }

    fileprivate func didProgress(_ id: String, written: Int64, expected: Int64) {
        // Only the progress publisher changes as bytes arrive, so lists stay still.
        guard let download = downloads[id] else { return }
        let total = expected > 0 ? expected : download.expectedBytes
        let now = Date()
        if now.timeIntervalSince(lastProgressPublish[id] ?? .distantPast) > 0.4 {
            lastProgressPublish[id] = now
            KhyloDownloadProgress.shared.fractions[id] = total > 0 ? min(Double(written) / Double(total), 0.99) : 0
        }
    }

    fileprivate func didFinish(_ id: String, fileName: String, size: Int64) {
        guard var download = downloads[id] else {
            // Deleted while it finished.
            try? FileManager.default.removeItem(at: Self.itemFolder(id))
            return
        }
        download.state = .done
        download.fileName = fileName
        download.bytes = size
        download.expectedBytes = size
        download.message = nil
        downloads[id] = download
        KhyloDownloadProgress.shared.fractions[id] = nil
        save()
    }

    fileprivate func didFail(_ id: String, message: String, retryable: Bool) {
        guard var download = downloads[id], download.state != .done else { return }
        KhyloDownloadProgress.shared.fractions[id] = nil
        if retryable, download.attempts < 3 {
            // A dropped connection or a refused link: try again with a fresh link.
            downloads[id] = download
            let wait = Double(download.attempts) * 5
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(wait))
                guard KhyloDownloads.shared.downloads[id]?.state == .downloading else { return }
                KhyloDownloads.shared.start(id)
            }
            return
        }
        download.state = .failed
        download.message = message
        downloads[id] = download
        save()
    }

    // MARK: Deleting

    func delete(itemID id: String) {
        cancelTask(for: id)
        try? FileManager.default.removeItem(at: Self.itemFolder(id))
        downloads[id] = nil
        KhyloDownloadProgress.shared.fractions[id] = nil
        for (groupID, var group) in groups where group.memberIDs.contains(id) {
            group.memberIDs.removeAll { $0 == id }
            if group.memberIDs.isEmpty {
                groups[groupID] = nil
                try? FileManager.default.removeItem(at: Self.groupFolder(groupID))
            } else {
                groups[groupID] = group
            }
        }
        save()
    }

    /// Removes the downloads behind a download button (a title, or a whole show, season, album…).
    func delete(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        if item.type == .season {
            for download in related(to: item) { delete(itemID: download.id) }
        } else if groups[id] != nil {
            deleteGroup(id)
        } else {
            delete(itemID: id)
        }
    }

    /// Removes a show, album, playlist or audiobook. Songs that are also in
    /// another downloaded album or playlist stay.
    func deleteGroup(_ groupID: String) {
        guard let group = groups[groupID] else { return }
        for memberID in group.memberIDs {
            guard var download = downloads[memberID] else { continue }
            download.groupIDs.removeAll { $0 == groupID }
            if download.groupIDs.isEmpty {
                delete(itemID: memberID)
            } else {
                downloads[memberID] = download
            }
        }
        groups[groupID] = nil
        try? FileManager.default.removeItem(at: Self.groupFolder(groupID))
        save()
    }

    func deleteAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        downloads = [:]
        groups = [:]
        KhyloDownloadProgress.shared.fractions = [:]
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent("items"))
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent("groups"))
        save()
    }

    private func cancelTask(for id: String) {
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription?.hasPrefix("\(id)|") == true }.forEach { $0.cancel() }
        }
    }

    // MARK: Offline progress

    /// Saves where you are in a downloaded title. Sent to the server when online.
    func record(itemID: String, ticks: Int, isFinal: Bool) {
        let runtime = downloads[itemID]?.item.runTimeTicks ?? 0
        let isPlayed = runtime > 0 && Double(ticks) >= Double(runtime) * 0.9
        positions[itemID] = KhyloOfflinePosition(
            ticks: isPlayed ? 0 : ticks,
            isPlayed: isPlayed,
            updated: Date(),
            needsSync: true
        )
        if var download = downloads[itemID] {
            if download.item.userData == nil { download.item.userData = UserItemDataDto(itemID: itemID, key: itemID) }
            download.item.userData?.playbackPositionTicks = isPlayed ? 0 : ticks
            if isPlayed { download.item.userData?.isPlayed = true }
            download.item.userData?.lastPlayedDate = Date()
            downloads[itemID] = download
        }
        if isFinal {
            savePositions()
            save()
            Task { await syncProgress() }
        }
    }

    /// Where to start a title: your offline progress if it hasn't reached the
    /// server yet, otherwise the server's.
    func resumeTicks(for item: BaseItemDto) -> Int? {
        if let id = item.id, let local = positions[id], local.needsSync {
            return local.ticks
        }
        return item.userData?.playbackPositionTicks
    }

    /// Copies of items with your offline progress applied (for resume points and checkmarks).
    func withLocalProgress(_ items: [BaseItemDto]) -> [BaseItemDto] {
        items.map { item in
            guard let id = item.id, let local = positions[id], local.needsSync else { return item }
            var copy = item
            if copy.userData == nil { copy.userData = UserItemDataDto(itemID: id, key: id) }
            copy.userData?.playbackPositionTicks = local.ticks
            if local.isPlayed { copy.userData?.isPlayed = true }
            return copy
        }
    }

    /// Sends progress made offline to the server, as normal playback reports.
    func syncProgress() async {
        guard !isSyncing, KhyloNetwork.shared.isOnline, let client = KhyloAPI.session?.client, KhyloAPI.accessToken != nil else { return }
        let pending = positions.filter(\.value.needsSync)
        guard !pending.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        for (itemID, position) in pending.sorted(by: { $0.value.updated < $1.value.updated }) {
            let playSession = UUID().uuidString
            var start = PlaybackStateInfo()
            start.itemID = itemID
            start.playSessionID = playSession
            start.playMethod = .directPlay
            start.positionTicks = position.ticks
            var stop = PlaybackStopInfo()
            stop.itemID = itemID
            stop.playSessionID = playSession
            let runtime = downloads[itemID]?.item.runTimeTicks
            stop.positionTicks = position.isPlayed ? (runtime ?? position.ticks) : position.ticks
            do {
                _ = try await client.send(Paths.reportPlaybackStart(start))
                _ = try await client.send(Paths.reportPlaybackStopped(stop))
                if position.isPlayed {
                    _ = try? await KhyloAPI.setPlayed(true, itemID: itemID)
                }
                positions[itemID]?.needsSync = false
                if let episode = downloads[itemID]?.item, episode.type == .episode, position.isPlayed {
                    await prepareNextEpisodes(after: episode)
                }
            } catch {
                break
            }
        }
        savePositions()
        NotificationCenter.default.post(name: .khyloProgressDidChange, object: nil)
    }

    // MARK: Next episodes

    /// With auto-download on, keeps the next two episodes of a downloaded show ready.
    func prepareNextEpisodes(after episode: BaseItemDto) async {
        guard KhyloDownloadSettings.autoNextEpisodes, Self.isAllowed, KhyloNetwork.shared.isOnline,
              episode.type == .episode, let seriesID = episode.seriesID, groups[seriesID] != nil
        else { return }
        guard let episodes = try? await KhyloAPI.items(
            parentID: seriesID, types: [.episode], sortBy: [.parentIndexNumber, .indexNumber],
            limit: 2000, extraFields: [.mediaSources]
        ).items,
            let index = episodes.firstIndex(where: { $0.id == episode.id })
        else { return }
        let next = episodes.dropFirst(index + 1)
            .filter { ($0.parentIndexNumber ?? 1) > 0 && downloads[$0.id ?? ""] == nil }
            .prefix(2)
        guard !next.isEmpty, let series = groups[seriesID]?.item else { return }
        try? enqueue(Array(next), kind: .video, group: series)
    }

    /// The episode to play from a downloaded show when there's no connection.
    func nextDownloadedEpisode(in item: BaseItemDto) -> BaseItemDto? {
        let episodes: [KhyloDownload]
        switch item.type {
        case .series: episodes = members(of: item.id ?? "")
        case .season: episodes = downloads.values.filter { $0.item.seasonID == item.id }
            .sorted { ($0.item.indexNumber ?? 0) < ($1.item.indexNumber ?? 0) }
        default: return nil
        }
        let ready = withLocalProgress(episodes.filter { $0.state == .done }.map(\.item))
        return ready.first { !$0.khyloIsPlayed } ?? ready.first
    }

    // MARK: Saving

    private func prepareFolder() {
        var root = Self.root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Downloads can be fetched again, so they don't go into iCloud backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    private func loadIndex() {
        if let data = try? Data(contentsOf: Self.indexFile),
           let index = try? JSONDecoder().decode(Index.self, from: data) {
            downloads = index.downloads
            groups = index.groups
        }
        if let data = try? Data(contentsOf: Self.positionsFile),
           let saved = try? JSONDecoder().decode([String: KhyloOfflinePosition].self, from: data) {
            positions = saved
        }
    }

    private func save() {
        let index = Index(downloads: downloads, groups: groups)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: Self.indexFile, options: .atomic)
    }

    private func savePositions() {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        try? data.write(to: Self.positionsFile, options: .atomic)
    }

    /// Keeps a copy of the artwork so downloads look right offline.
    private func saveArtwork(for item: BaseItemDto, into folder: URL, style: KhyloArtwork.Style, name: String = "art.jpg") {
        let destination = folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path),
              let url = KhyloArtwork.url(for: item, style: style, width: style == .backdrop ? 1200 : 600)
        else { return }
        Task.detached {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: destination, options: .atomic)
        }
    }
}

// MARK: - Background session

extension KhyloDownloads: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = Self.itemID(of: downloadTask) else { return }
        Task { @MainActor in
            KhyloDownloads.shared.didProgress(id, written: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let description = downloadTask.taskDescription else { return }
        let parts = description.components(separatedBy: "|")
        guard let id = parts.first else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            Task { @MainActor in
                KhyloDownloads.shared.didFail(
                    id,
                    message: status == 401 || status == 403
                        ? "The server turned this download down. Check that downloads are allowed for your account."
                        : "The server couldn't send this (error \(status)).",
                    retryable: status == 401 || status >= 500
                )
            }
            return
        }

        // The file has to be moved before this returns.
        let ext = parts.count > 1 ? parts[1] : "media"
        let folder = Self.itemFolder(id)
        let destination = folder.appendingPathComponent("media.\(ext)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            Task { @MainActor in
                KhyloDownloads.shared.didFinish(id, fileName: destination.lastPathComponent, size: size)
            }
        } catch {
            Task { @MainActor in
                KhyloDownloads.shared.didFail(id, message: "Couldn't save the download.", retryable: false)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = Self.itemID(of: task) else { return }
        let nsError = error as NSError
        // Cancelled on purpose (deleted, or restarted after a settings change).
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in
            KhyloDownloads.shared.didFail(id, message: "The download stopped: \(error.localizedDescription)", retryable: true)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            KhyloDownloads.shared.backgroundCompletion?()
            KhyloDownloads.shared.backgroundCompletion = nil
        }
    }

    nonisolated private static func itemID(of task: URLSessionTask) -> String? {
        task.taskDescription?.components(separatedBy: "|").first
    }
}

// MARK: - Offline video

extension KhyloDownloads {

    /// Plays a downloaded movie or episode straight from the phone.
    func offlineProvider(for item: BaseItemDto, from start: KhyloPlayback.StartPoint) -> MediaPlayerItemProvider? {
        guard let id = item.id, let file = fileURL(for: id), let download = downloads[id], download.kind == .video else { return nil }

        var playable = download.item
        let ticks = start == .beginning ? 0 : (resumeTicks(for: item) ?? 0)
        if playable.userData == nil { playable.userData = UserItemDataDto(itemID: id, key: id) }
        playable.userData?.playbackPositionTicks = ticks
        // Chapters and preview thumbnails come from the server.
        playable.trickplay = nil

        var source = download.item.mediaSources?.first ?? MediaSourceInfo()
        source.id = source.id ?? id
        source.transcodingURL = nil
        source.isRemote = false
        if download.quality != .original {
            // The smaller copy has one picture and one sound track, and no subtitles.
            source.mediaStreams = []
            source.defaultAudioStreamIndex = nil
            source.defaultSubtitleStreamIndex = nil
        } else {
            source.mediaStreams = source.mediaStreams?.filter { $0.isExternal != true }
        }
        let mediaSource = source

        return MediaPlayerItemProvider(item: playable) { base, modify in
            var base = base
            modify?(&base)
            let resolved = base
            return await MainActor.run {
                MediaPlayerItem(
                    baseItem: resolved,
                    mediaSource: mediaSource,
                    playSessionID: UUID().uuidString,
                    url: file,
                    deviceProfile: DeviceProfile.build(
                        for: Defaults[.VideoPlayer.videoPlayerType],
                        compatibilityMode: Defaults[.VideoPlayer.Playback.compatibilityMode],
                        maxBitrate: 400_000_000
                    )
                )
            }
        }
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
