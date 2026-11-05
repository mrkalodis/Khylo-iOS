//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI
import UIKit

/// How this app introduces itself to the server. Khylo Music has its own name and
/// device id, so each Khylo app shows up as its own device with its own sign-in.
enum KhyloDeviceIdentity {

    static var client: String {
        KhyloVariant.isMusic ? "Khylo Music \(UIDevice.platform)" : "Khylo \(UIDevice.platform)"
    }

    static var deviceName: String {
        UIDevice.current.name
            .folding(options: .diacriticInsensitive, locale: .current)
            .unicodeScalars
            .filter { CharacterSet.urlQueryAllowed.contains($0) }
            .description
    }

    static var deviceID: String {
        let base = "\(UIDevice.platform)_\(UIDevice.vendorUUIDString)"
        return KhyloVariant.isMusic ? base + "-music" : base
    }

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.1"
    }
}

extension JellyfinClient.Configuration {

    static func swiftfinConfiguration(
        url: URL,
        accessToken: String? = nil
    ) -> Self {

        let client = KhyloDeviceIdentity.client
        let deviceName = KhyloDeviceIdentity.deviceName
        let deviceID = KhyloDeviceIdentity.deviceID
        let version = KhyloDeviceIdentity.version

        return .init(
            url: url,
            accessToken: accessToken,
            client: client,
            deviceName: deviceName,
            deviceID: deviceID,
            version: version
        )
    }
}
