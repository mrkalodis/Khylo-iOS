//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation
import os

/// While watching a scheduled channel (Khylo TV), the viewer can pause and
/// rewind but never get ahead of the broadcast. Every player backend clamps
/// its seeks through here.
enum MediaPlayerLiveEdge {

    private static let state = OSAllocatedUnfairLock<(itemID: String, airedAt: Date)?>(initialState: nil)

    /// Starts enforcing the live edge for an item that began airing at `airedAt`.
    static func begin(itemID: String, airedAt: Date) {
        state.withLock { $0 = (itemID, airedAt) }
    }

    static func end() {
        state.withLock { $0 = nil }
    }

    static var isActive: Bool {
        state.withLock { $0 != nil }
    }

    /// The furthest position the viewer may seek to right now, if limited.
    static func limit(for itemID: String?) -> Duration? {
        guard let current = state.withLock({ $0 }), current.itemID == itemID else { return nil }
        return .seconds(max(0, Date().timeIntervalSince(current.airedAt)))
    }

    static func clamp(_ seconds: Duration, itemID: String?) -> Duration {
        guard let limit = limit(for: itemID) else { return seconds }
        return min(seconds, limit)
    }
}

extension Notification.Name {
    /// Posted when the video player opens, so other audio (music) can stop.
    static let khyloVideoWillPlay = Notification.Name("khyloVideoWillPlay")
    /// Progress in a video playing from a downloaded file (userInfo: itemID, ticks, final).
    static let khyloOfflineProgress = Notification.Name("khyloOfflineProgress")
}
