//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Foundation
import Network

// MARK: - Discovered Server Model

public struct DiscoveredServer: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let address: URL
    public let version: String
    public let isKhyloServer: Bool
    public let isOnline: Bool

    public init(
        id: String = "local-server",
        name: String = "Home Media Server",
        address: URL = URL(string: "http://localhost:8096")!,
        version: String = "10.9.0",
        isKhyloServer: Bool = true,
        isOnline: Bool = true
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.version = version
        self.isKhyloServer = isKhyloServer
        self.isOnline = isOnline
    }

    public init(name: String, address: String) {
        self.id = "local-server"
        self.name = name
        self.address = URL(string: address) ?? URL(string: "http://localhost:8096")!
        self.version = "10.9.0"
        self.isKhyloServer = true
        self.isOnline = true
    }
}

// MARK: - Server Discovery Service

@MainActor
public final class KhyloServerDiscovery: ObservableObject {

    @Published public private(set) var discoveredServers: [DiscoveredServer] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public var errorMessage: String?

    private var broadcastConnection: NWConnection?
    private var scanTask: Task<Void, Never>?
    private let discoveryPort: NWEndpoint.Port = 7359

    public init() {}

    /// Starts local network UDP discovery and subnet probe.
    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil

        scanTask = Task { [weak self] in
            await self?.performDiscoveryScan()
        }
    }

    /// Stops scanning for servers.
    public func stopScanning() {
        isScanning = false
        scanTask?.cancel()
        scanTask = nil
        broadcastConnection?.cancel()
        broadcastConnection = nil
    }

    /// Manually verifies and pings a server URL.
    /// Accepts "Khylo Server" as well as standard Jellyfin and custom versions.
    public func pingServer(urlString: String) async throws -> DiscoveredServer {
        let trimmed = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { throw URLError(.badURL) }

        // An explicit http:// or https:// is used as typed. Without a scheme, try
        // https first (remote/reverse-proxied servers) and fall back to http (LAN).
        let lowered = trimmed.lowercased()
        let candidates: [String]
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            candidates = [trimmed]
        } else {
            candidates = ["https://" + trimmed, "http://" + trimmed]
        }

        var lastError: Error = URLError(.cannotConnectToHost)
        for candidate in candidates {
            guard let baseURL = URL(string: candidate) else {
                lastError = URLError(.badURL)
                continue
            }
            do {
                return try await probeServer(baseURL: baseURL)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func probeServer(baseURL: URL) async throws -> DiscoveredServer {
        let infoURL = baseURL.appendingPathComponent("System/Info/Public")
        var request = URLRequest(url: infoURL)
        request.timeoutInterval = 8.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // If the server redirected (e.g. a reverse proxy upgrading http -> https),
        // keep the final address. Otherwise later POSTs such as login get redirected
        // too, and URLSession turns a redirected POST into a GET, which fails.
        let resolvedBaseURL = Self.baseURL(from: httpResponse.url, fallback: baseURL)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        let id = json["Id"] as? String ?? UUID().uuidString
        let serverName = json["ServerName"] as? String ?? json["Name"] as? String ?? "Media Server"
        let version = json["Version"] as? String ?? "1.0.0"
        let productName = json["ProductName"] as? String ?? ""

        // Accepts "Khylo Server", non-standard versions, or standard Jellyfin
        let isKhylo = serverName.localizedCaseInsensitiveContains("Khylo") ||
                      productName.localizedCaseInsensitiveContains("Khylo") ||
                      version.localizedCaseInsensitiveContains("khylo")

        let server = DiscoveredServer(
            id: id,
            name: serverName,
            address: resolvedBaseURL,
            version: version,
            isKhyloServer: isKhylo,
            isOnline: true
        )

        // Add to discovered list if not already present
        if !discoveredServers.contains(where: { $0.id == server.id }) {
            discoveredServers.append(server)
        }

        return server
    }

    /// Strips the `System/Info/Public` suffix from the final response URL to recover the server base URL.
    private static func baseURL(from responseURL: URL?, fallback: URL) -> URL {
        guard let responseURL,
              var components = URLComponents(url: responseURL, resolvingAgainstBaseURL: false)
        else { return fallback }

        let suffix = "/System/Info/Public"
        guard let range = components.path.range(of: suffix, options: [.caseInsensitive, .backwards]) else {
            return fallback
        }
        components.path = String(components.path[..<range.lowerBound])
        components.query = nil
        components.fragment = nil
        return components.url ?? fallback
    }

    private func performDiscoveryScan() async {
        // Send UDP discovery packet on 7359
        sendBroadcastQuery()

        // Probe common local network host addresses concurrently
        let commonAddresses = [
            "http://localhost:8096",
            "http://127.0.0.1:8096"
        ]

        for address in commonAddresses {
            guard isScanning else { break }
            if let server = try? await pingServer(urlString: address) {
                if !discoveredServers.contains(where: { $0.id == server.id }) {
                    discoveredServers.append(server)
                }
            }
        }

        // Allow background listening for broadcast responses
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if isScanning {
            isScanning = false
        }
    }

    private func sendBroadcastQuery() {
        let host = NWEndpoint.Host("255.255.255.255")
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let connection = NWConnection(host: host, port: discoveryPort, using: params)
        broadcastConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                let message = "who is JellyfinServer?".data(using: .utf8) ?? Data()
                connection.send(content: message, completion: .contentProcessed({ _ in }))
                self?.receiveBroadcastResponse(on: connection)
            }
        }

        connection.start(queue: .global(qos: .utility))
    }

    nonisolated private func receiveBroadcastResponse(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, _ in
            guard let self = self, let content = content else { return }
            if let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any],
               let addressString = json["Address"] as? String,
               let url = URL(string: addressString) {
                Task { @MainActor in
                    _ = try? await self.pingServer(urlString: url.absoluteString)
                }
            }
        }
    }
}
