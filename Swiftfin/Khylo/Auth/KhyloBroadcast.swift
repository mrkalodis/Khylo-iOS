//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Darwin
import Foundation

/// Finds Khylo servers on the home network: one short broadcast that Khylo
/// servers answer with their name and address. Nothing else answers it.
enum KhyloBroadcast {

    struct Reply {
        let address: String
        let id: String
        let name: String
    }

    private static let port: UInt16 = 7360
    private static let message = "who is KhyloServer?"
    private static let listenSeconds = 2.5

    /// Broadcasts once and collects replies for a couple of seconds.
    static func discover() async -> [Reply] {
        await Task.detached(priority: .userInitiated) { run() }.value
    }

    private static func run() -> [Reply] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }

        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let payload = Array(message.utf8)
        for address in broadcastAddresses() {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = port.bigEndian
            target.sin_addr.s_addr = address
            _ = withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    sendto(descriptor, payload, payload.count, 0, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var replies: [Reply] = []
        var seen = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let end = Date().addingTimeInterval(listenSeconds)
        while Date() < end {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: Data(buffer[0 ..< count])) as? [String: Any],
                  let address = json["Address"] as? String,
                  let id = json["Id"] as? String,
                  seen.insert(id).inserted
            else { continue }
            replies.append(Reply(address: address, id: id, name: json["Name"] as? String ?? "Khylo"))
        }
        return replies
    }

    /// 255.255.255.255 and the broadcast address of each active network (network byte order).
    private static func broadcastAddresses() -> [UInt32] {
        var result: [UInt32] = [UInt32(0xFFFF_FFFF).bigEndian]
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return result }
        defer { freeifaddrs(pointer) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let destination = interface.ifa_dstaddr, destination.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            let value = destination.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            if !result.contains(value) { result.append(value) }
        }
        return result
    }
}
