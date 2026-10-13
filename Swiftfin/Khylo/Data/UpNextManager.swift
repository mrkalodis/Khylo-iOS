//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Foundation

// MARK: - UpNext Manager (Swift Port of Android TV UpNextHidden.kt)

@MainActor
public final class UpNextManager: ObservableObject {

    public static let shared = UpNextManager()

    private static let displayPreferencesId = "khylo"
    private static let clientIdentifier = "khylo"
    private static let preferenceKey = "upNextHidden"
    private static let localCacheKey = "khylo_upNextHidden_seriesIds"

    @Published public private(set) var hiddenSeriesIds: Set<String> = []

    private var activeUserId: String?
    private var activeServerUrl: URL?
    private var isSyncing: Bool = false

    public init() {
        loadFromLocalCache()
    }

    // MARK: - Configuration

    public func configure(userId: String?, serverUrl: URL?) {
        self.activeUserId = userId
        self.activeServerUrl = serverUrl
        loadFromLocalCache()
        Task {
            await fetchServerHiddenList()
        }
    }

    // MARK: - Query

    public func isHidden(seriesId: String) -> Bool {
        hiddenSeriesIds.contains(seriesId)
    }

    public func filter<T>(items: [T], seriesIdProvider: (T) -> String?) -> [T] {
        items.filter { item in
            guard let sId = seriesIdProvider(item) else { return true }
            return !hiddenSeriesIds.contains(sId)
        }
    }

    // MARK: - Mutation

    /// Hides a series from the Up Next row and persists both locally and server-side.
    public func hide(seriesId: String) {
        guard !seriesId.isEmpty else { return }
        hiddenSeriesIds.insert(seriesId)
        saveToLocalCache()
        Task {
            await pushServerHiddenList()
        }
    }

    /// Unhides a series (called when user watches another episode of this show).
    public func unhide(seriesId: String) {
        guard hiddenSeriesIds.contains(seriesId) else { return }
        hiddenSeriesIds.remove(seriesId)
        saveToLocalCache()
        Task {
            await pushServerHiddenList()
        }
    }

    /// Clears all hidden entries.
    public func clearAll() {
        hiddenSeriesIds.removeAll()
        saveToLocalCache()
        Task {
            await pushServerHiddenList()
        }
    }

    // MARK: - Local Cache

    private func loadFromLocalCache() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.localCacheKey) ?? []
        self.hiddenSeriesIds = Set(stored)
    }

    private func saveToLocalCache() {
        UserDefaults.standard.set(Array(hiddenSeriesIds), forKey: Self.localCacheKey)
    }

    // MARK: - Server Sync (Jellyfin DisplayPreferences API)

    public func fetchServerHiddenList() async {
        guard let serverUrl = activeServerUrl, let userId = activeUserId else { return }

        guard var components = URLComponents(url: serverUrl.appendingPathComponent("DisplayPreferences/\(Self.displayPreferencesId)"), resolvingAgainstBaseURL: false) else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "client", value: Self.clientIdentifier)
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let customPrefs = json["CustomPrefs"] as? [String: String],
               let rawHidden = customPrefs[Self.preferenceKey] {
                let ids = rawHidden
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                self.hiddenSeriesIds = Set(ids)
                saveToLocalCache()
            }
        } catch {
            // Offline or network error - retain local cache
        }
    }

    private func pushServerHiddenList() async {
        guard let serverUrl = activeServerUrl, let userId = activeUserId else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard var components = URLComponents(url: serverUrl.appendingPathComponent("DisplayPreferences/\(Self.displayPreferencesId)"), resolvingAgainstBaseURL: false) else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "client", value: Self.clientIdentifier)
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let csv = hiddenSeriesIds.joined(separator: ",")
        let payload: [String: Any] = [
            "Id": Self.displayPreferencesId,
            "CustomPrefs": [
                Self.preferenceKey: csv
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = bodyData

        do {
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            // Network failure will retry on next sync
        }
    }
}
