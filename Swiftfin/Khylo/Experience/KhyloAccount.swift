//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation

/// Keeps one account's music, downloads and cached pages away from the next
/// account signed in on this phone, even on another server.
@MainActor
enum KhyloAccount {

    /// "server|user" for the signed-in account, nil when signed out.
    static var currentKey: String? {
        KhyloAPI.session.map { key(serverID: $0.server.id, userID: $0.user.id) }
    }

    static var currentServerID: String? {
        KhyloAPI.session?.server.id
    }

    static func key(serverID: String, userID: String) -> String {
        "\(serverID)|\(userID)"
    }

    private static var lastKey: String?
    private static var hasStarted = false

    /// Called when an account signs in (pass its key) and when it signs out (nil).
    static func didChange(to key: String?) {
        guard !hasStarted || key != lastKey else { return }
        let isFirst = !hasStarted
        hasStarted = true
        lastKey = key

        // What was playing belongs to the account that played it. On launch the
        // saved song is checked against the account instead (see restoreSession).
        if !isFirst {
            KhyloAudioPlayer.shared.stop()
            KhyloSongCache.shared.clear()
            KhyloTVSession.shared.stop(notifyServer: false)
        }
        KhyloCategoryCache.shared.reset()
        KhyloArtistArt.shared.reset()
        KhyloDownloads.shared.showCurrentAccount()
    }
}
