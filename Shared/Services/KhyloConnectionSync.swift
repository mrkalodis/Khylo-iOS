//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation
import Logging

/// Learns a Khylo server's home and web addresses from the server itself, so the
/// phone uses the home address on your home network and the web address away.
enum KhyloConnectionSync {

    private struct Answer: Decodable {
        let serverID: String
        let homeAddresses: [String]
        let webAddress: String?

        enum CodingKeys: String, CodingKey {
            case serverID = "ServerId"
            case homeAddresses = "HomeAddresses"
            case webAddress = "WebAddress"
        }
    }

    /// Addresses the server gave are named like this, so a later refresh can replace
    /// them without touching addresses added by hand.
    private static let providedPrefix = "khylo-provided-"
    private static let homeName = "Home"
    private static let webName = "Internet"

    private static let logger = Logger.swiftfin()

    static func isProvided(_ connection: ServerConnection) -> Bool {
        connection.id.hasPrefix(providedPrefix)
    }

    static func isHome(_ connection: ServerConnection) -> Bool {
        connection.id.hasPrefix(providedPrefix + "home-")
    }

    /// Asks the server (on the address that works now) for its addresses and updates the list.
    /// Returns true when the list changed.
    @discardableResult
    static func refresh(for server: ServerState) async -> Bool {
        let base = server.effectiveServerURL
        var request = URLRequest(url: base.appendingPathComponent("Khylo/Connection"))
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(Answer.self, from: data),
              answer.serverID == server.id
        else {
            // An older server (or no answer): keep what's there.
            return false
        }

        func normalized(_ text: String?) -> URL? {
            guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme != nil, url.host != nil else {
                return nil
            }
            return url.normalizedServerConnectionURL ?? url
        }

        var provided: [ServerConnection] = []
        for address in answer.homeAddresses {
            guard let url = normalized(address) else { continue }
            provided.append(ServerConnection(
                id: providedPrefix + "home-" + url.absoluteString,
                name: homeName,
                url: url,
                interface: .wifi,
                priority: provided.count
            ))
        }
        if let web = normalized(answer.webAddress) {
            provided.append(ServerConnection(
                id: providedPrefix + "web",
                name: webName,
                url: web,
                interface: .any,
                priority: provided.count
            ))
        }
        guard !provided.isEmpty else { return false }

        // What the person added by hand stays, after the server's own addresses,
        // unless it is the same address.
        let providedURLs = Set(provided.map(\.url))
        let manual = server.serverConnections.filter { connection in
            !isProvided(connection) && !providedURLs.contains(connection.url)
        }

        let merged = ServerConnection.ordered(provided + manual, preservingOrder: true)
        let existing = server.serverConnections
        let changed = merged.map(\.id) != existing.map(\.id) || merged.map(\.url) != existing.map(\.url)
        guard changed else { return false }

        server.serverConnections = merged
        logger.info("Server addresses updated", metadata: ["count": "\(merged.count)"])
        return true
    }
}
