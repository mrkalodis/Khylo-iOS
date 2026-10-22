//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation
import JellyfinAPI
import Logging
import UIKit

/// Keeps the song that's playing and the next two on the phone while you
/// listen, one at a time, so music carries on through dead spots and the next
/// song starts straight away. Nothing here is a download you manage: the cache
/// cleans itself up as you move through the queue.
@MainActor
final class KhyloSongCache {

    static let shared = KhyloSongCache()

    static let enabledKey = "khylo.music.cacheAhead"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private let folder: URL
    private let session: URLSession
    private let logger = Logger.swiftfin()

    /// Finished files by song ID.
    private var files: [String: URL] = [:]
    /// Songs to fetch, in order.
    private var wanted: [BaseItemDto] = []
    private var failures: [String: Int] = [:]
    private var task: URLSessionDownloadTask?
    private var taskItemID: String?

    /// Songs kept besides the ones around the current queue position.
    private let keepRecent = 6

    private init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KhyloSongCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 15 * 60
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration)

        // Pick up what's already on the phone; anything older than two days goes.
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let cutoff = Date().addingTimeInterval(-2 * 24 * 3600)
        for file in contents {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff || file.pathExtension == "part" {
                try? FileManager.default.removeItem(at: file)
            } else {
                files[file.deletingPathExtension().lastPathComponent] = file
            }
        }
    }

    /// The cached copy of a song, if it's finished.
    func file(for id: String?) -> URL? {
        guard let id, let file = files[id] else { return nil }
        guard FileManager.default.fileExists(atPath: file.path) else {
            files[id] = nil
            return nil
        }
        return file
    }

    /// The player says what's playing and what comes next. Songs are fetched
    /// in this order, one at a time.
    func prepare(_ items: [BaseItemDto]) {
        guard Self.isEnabled else {
            cancel()
            return
        }
        let ids = Set(items.compactMap(\.id))
        wanted = items.filter { item in
            guard let id = item.id else { return false }
            return files[id] == nil && !KhyloDownloads.shared.isDownloaded(id) && (failures[id] ?? 0) < 2
        }
        if let taskItemID, !wanted.contains(where: { $0.id == taskItemID }) {
            task?.cancel()
            task = nil
            self.taskItemID = nil
        }
        startNext()
        trim(keeping: ids)
    }

    func cancel() {
        task?.cancel()
        task = nil
        taskItemID = nil
        wanted = []
    }

    /// Empties the cache (Settings).
    func clear() {
        cancel()
        for file in files.values { try? FileManager.default.removeItem(at: file) }
        files = [:]
    }

    // MARK: Fetching

    private func startNext() {
        guard task == nil,
              let item = wanted.first(where: { files[$0.id ?? ""] == nil }),
              let id = item.id,
              let url = Self.sourceURL(for: id)
        else { return }

        taskItemID = id
        let folder = folder
        let download = session.downloadTask(with: url) { location, response, error in
            var saved: URL?
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let location, status == 200, let http = response as? HTTPURLResponse {
                // The file has to be moved before this returns.
                let destination = folder.appendingPathComponent("\(id).\(Self.fileExtension(for: http))")
                try? FileManager.default.removeItem(at: destination)
                if (try? FileManager.default.moveItem(at: location, to: destination)) != nil {
                    saved = destination
                }
            }
            let message = error?.localizedDescription ?? "status \(status)"
            Task { @MainActor in
                KhyloSongCache.shared.finished(id, file: saved, problem: saved == nil ? message : nil)
            }
        }
        task = download
        download.resume()
    }

    private func finished(_ id: String, file: URL?, problem: String?) {
        if taskItemID == id {
            task = nil
            taskItemID = nil
        }
        if let file {
            files[id] = file
            wanted.removeAll { $0.id == id }
        } else if let problem, !problem.lowercased().contains("cancel") {
            failures[id, default: 0] += 1
            logger.warning("Music: couldn't cache a song ahead", metadata: ["problem": "\(problem)"])
            if (failures[id] ?? 0) >= 2 { wanted.removeAll { $0.id == id } }
        }
        startNext()
    }

    /// Keeps the songs around the queue position and a few recent ones.
    private func trim(keeping ids: Set<String>) {
        let others = files.filter { !ids.contains($0.key) }
        guard others.count > keepRecent else { return }
        let sorted = others.sorted { lhs, rhs in
            let a = (try? lhs.value.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? rhs.value.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a > b
        }
        for (id, file) in sorted.dropFirst(keepRecent) {
            try? FileManager.default.removeItem(at: file)
            files[id] = nil
        }
    }

    /// One continuous file: the original when the server sends songs as they
    /// are, otherwise a 320 kbps MP3 it makes.
    private static func sourceURL(for id: String) -> URL? {
        guard let session = KhyloAPI.session, let token = KhyloAPI.accessToken else { return nil }
        var parameters = Paths.GetUniversalAudioStreamParameters()
        parameters.container = ["mp3", "aac", "m4a|aac", "flac", "alac", "m4a|alac", "wav"]
        parameters.userID = session.user.id
        parameters.deviceID = UIDevice.current.identifierForVendor?.uuidString
        parameters.maxStreamingBitrate = 320_000_000
        parameters.audioBitRate = 320_000
        parameters.transcodingContainer = "mp3"
        parameters.transcodingProtocol = .http
        parameters.audioCodec = "mp3"
        guard let base = session.client.url(with: Paths.getUniversalAudioStream(itemID: id, parameters: parameters)),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "api_key", value: token)]
        return components.url
    }

    /// Apple's player picks the decoder from the file's extension.
    nonisolated private static func fileExtension(for response: HTTPURLResponse) -> String {
        let type = (response.mimeType ?? "").lowercased()
        switch type {
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac-mp4": return "m4a"
        case "audio/aac", "audio/x-aac": return "aac"
        case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave": return "wav"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        default:
            let suggested = (response.suggestedFilename as NSString?)?.pathExtension.lowercased() ?? ""
            return suggested.isEmpty ? "mp3" : suggested
        }
    }
}
