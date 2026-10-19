//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Pulse

final class UserSession {

    let server: ServerState
    let user: UserState

    /// Built with the token on first use. If the token couldn't be read then
    /// (phone locked), it's built again as soon as the token can be read, so
    /// requests and stream links never carry an empty token.
    var client: JellyfinClient {
        clientLock.withLock {
            if let existing = _client, existing.accessToken?.isEmpty == false {
                return existing
            }
            let token = user.accessToken
            if let existing = _client, token.isEmpty {
                return existing
            }
            let client = JellyfinClient(
                configuration: .swiftfinConfiguration(
                    url: server.effectiveServerURL,
                    accessToken: token
                ),
                sessionConfiguration: .swiftfin,
                sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
            )
            _client = client
            return client
        }
    }

    private var _client: JellyfinClient?
    private let clientLock = NSLock()

    @MainActor
    lazy var serverConnectionManager = ServerConnectionManager()

    lazy var serverSocketManager = ServerSocketManager()

    @MainActor
    private lazy var services: [any UserSessionService] = [
        serverConnectionManager,
        serverSocketManager,
    ]

    init(
        server: ServerState,
        user: UserState
    ) {
        self.server = server
        self.user = user
    }

    @MainActor
    func willStart() async {
        for service in services {
            await service.willStart(userSession: self)
        }
    }

    @MainActor
    func didStart() {
        for service in services {
            service.didStart(userSession: self)
        }
    }

    @MainActor
    func willStop() {
        for service in services.reversed() {
            service.willStop(userSession: self)
        }
    }
}
