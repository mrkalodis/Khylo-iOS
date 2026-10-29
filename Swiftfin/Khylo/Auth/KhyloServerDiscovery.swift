//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Foundation
import JellyfinAPI

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
        address: URL = URL(string: "http://localhost:8098")!,
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
        self.address = URL(string: address) ?? URL(string: "http://localhost:8098")!
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

    private var scanTask: Task<Void, Never>?

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
        // 1. Ask the network: Khylo servers answer a short broadcast.
        for reply in await KhyloBroadcast.discover() {
            guard isScanning else { break }
            await add(urlString: reply.address)
        }

        // 2. Some routers drop broadcasts: check each address on this Wi-Fi network directly.
        if isScanning, discoveredServers.isEmpty {
            await scanSubnet()
        }

        isScanning = false
    }

    private func add(urlString: String) async {
        guard let server = try? await pingServer(urlString: urlString) else { return }
        if !discoveredServers.contains(where: { $0.id == server.id }) {
            discoveredServers.append(server)
        }
    }

    /// Probes every host on the device's IPv4 subnet (up to a /24) on Khylo's port, 8098,
    /// and on the server's default port, 8096.
    private func scanSubnet() async {
        let hosts = Self.localSubnetHosts()
        guard !hosts.isEmpty else { return }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        await withTaskGroup(of: String?.self) { group in
            var iterator = hosts.flatMap { host in [8098, 8096].map { (host, $0) } }.makeIterator()
            func next() -> Bool {
                guard let (host, port) = iterator.next() else { return false }
                group.addTask {
                    let base = "http://\(host):\(port)"
                    guard let url = URL(string: base + "/System/Info/Public"),
                          let (_, response) = try? await session.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200
                    else { return nil }
                    return base
                }
                return true
            }
            // Keep ~32 probes in flight.
            for _ in 0 ..< 48 where next() {}
            for await found in group {
                if let found { await add(urlString: found) }
                guard isScanning else { group.cancelAll(); break }
                _ = next()
            }
        }
    }

    /// Other addresses on the Wi-Fi (en0) IPv4 network, nearest first; empty when not on Wi-Fi.
    nonisolated static func localSubnetHosts() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard String(cString: interface.ifa_name) == "en0",
                  let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let mask = interface.ifa_netmask
            else { continue }

            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            var netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            // Never scan more than a /24.
            netmask |= 0xFFFF_FF00
            let network = ip & netmask
            let broadcast = network | ~netmask

            var hosts: [UInt32] = []
            var candidate = network + 1
            while candidate < broadcast {
                if candidate != ip { hosts.append(candidate) }
                candidate += 1
            }
            hosts.sort { abs(Int64($0) - Int64(ip)) < abs(Int64($1) - Int64(ip)) }
            return hosts.map { "\($0 >> 24 & 0xFF).\($0 >> 16 & 0xFF).\($0 >> 8 & 0xFF).\($0 & 0xFF)" }
        }
        return []
    }
}
