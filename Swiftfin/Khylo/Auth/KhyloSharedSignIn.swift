//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation
import Security

/// Lets the Khylo apps on one iPhone sign each other in.
///
/// When you sign in to one Khylo app, it leaves a small record in a keychain area
/// shared by Khylo apps. Another Khylo app that isn't signed in reads it, asks the
/// server for a one-time sign-in code as that account (the same code "Scan to Sign In"
/// uses), and signs itself in with the code. Each app ends up with its own sign-in on
/// the server, so signing out of one doesn't sign out the others.
enum KhyloSharedSignIn {

    struct Record: Codable, Equatable {
        var serverID: String
        var serverName: String
        var addresses: [String]
        var token: String
        var userName: String
        var isAdministrator: Bool
        /// How the app that saved this introduced itself; the server expects the same
        /// introduction with this token.
        var client: String
        var deviceName: String
        var deviceID: String
        var version: String
    }

    /// A code made by one app for another to sign in with.
    struct Bootstrap {
        let serverID: String
        let serverName: String
        let address: URL
        let code: String
    }

    private static let service = "org.khylo.shared"
    private static let account = "signin"
    private static let signedOutKey = "khylo.signedOutHere"

    /// Set when you sign out of this app yourself, so it doesn't sign straight back in.
    private static var signedOutHere: Bool {
        get { UserDefaults.standard.bool(forKey: signedOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: signedOutKey) }
    }

    // MARK: Saving

    /// Called whenever this app is signed in.
    static func publish(
        serverID: String,
        serverName: String,
        addresses: [URL],
        token: String,
        userName: String,
        isAdministrator: Bool
    ) {
        signedOutHere = false
        guard !token.isEmpty else { return }
        var list: [String] = []
        for address in addresses where !list.contains(address.absoluteString) {
            list.append(address.absoluteString)
        }
        write(Record(
            serverID: serverID,
            serverName: serverName,
            addresses: list,
            token: token,
            userName: userName,
            isAdministrator: isAdministrator,
            client: KhyloDeviceIdentity.client,
            deviceName: KhyloDeviceIdentity.deviceName,
            deviceID: KhyloDeviceIdentity.deviceID,
            version: KhyloDeviceIdentity.version
        ))
    }

    /// You signed out of this app. It stays signed out until you sign in again.
    static func userSignedOutHere(token: String?) {
        signedOutHere = true
        if let token, let record = read(), record.token == token {
            remove()
        }
    }

    // MARK: Signing in from another Khylo app

    /// Asks the server, as the account another Khylo app is signed in with, for a
    /// one-time code this app can sign in with. Nil when there is nothing to sign in with.
    static func bootstrap() async -> Bootstrap? {
        guard !signedOutHere, let record = read() else { return nil }
        guard let base = await firstReachable(record) else { return nil }

        var request = URLRequest(url: base.appendingPathComponent("Khylo/SignInCodes"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(authorization(for: record), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        if http.statusCode == 401 {
            // The account that saved this has signed out for good.
            remove()
            return nil
        }
        guard (200 ..< 300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["Code"] as? String, !code.isEmpty
        else { return nil }

        return Bootstrap(serverID: record.serverID, serverName: record.serverName, address: base, code: code)
    }

    private static func authorization(for record: Record) -> String {
        "MediaBrowser Client=\"\(record.client)\", Device=\"\(record.deviceName)\", DeviceId=\"\(record.deviceID)\", "
            + "Version=\"\(record.version)\", Token=\"\(record.token)\""
    }

    /// Checks the saved addresses at once (home first) and returns one that answers as that server.
    private static func firstReachable(_ record: Record) async -> URL? {
        let urls = record.addresses.compactMap(URL.init(string:))
        let results = await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    var request = URLRequest(url: url.appendingPathComponent("System/Info/Public"))
                    request.timeoutInterval = 2
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { return (index, false) }
                    return (index, (json["Id"] as? String) == record.serverID)
                }
            }
            var all: [(Int, Bool)] = []
            for await item in group { all.append(item) }
            return all
        }
        guard let best = results.filter(\.1).map(\.0).min() else { return nil }
        return urls[best]
    }

    // MARK: Shared keychain

    /// `<team>.org.khylo.shared`, filled in by the build.
    private static var group: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KhyloKeychainGroup") as? String,
              !value.isEmpty, !value.contains("$(")
        else { return nil }
        return value
    }

    private static func query() -> [String: Any]? {
        guard let group else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
        ]
    }

    static func read() -> Record? {
        guard var query = query() else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func write(_ record: Record) {
        guard let query = query(), let data = try? JSONEncoder().encode(record) else { return }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func remove() {
        guard let query = query() else { return }
        SecItemDelete(query as CFDictionary)
    }
}
