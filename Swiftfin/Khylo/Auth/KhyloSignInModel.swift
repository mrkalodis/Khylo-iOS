//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI

/// Drives the Khylo sign-in screen using the app's real session pipeline:
/// stores the server, authenticates through `UserSignInViewModel`, saves the user
/// (token in the keychain) and activates the session in `UserSessionManager`.
/// `KhyloRootView` observes the session manager and moves into the app once signed in.
@MainActor
final class KhyloSignInModel: ObservableObject {

    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    private var viewModel: UserSignInViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var authenticationAction: LocalUserAuthenticationAction?

    func signIn(
        server discovered: DiscoveredServer,
        username: String,
        password: String,
        authenticationAction: LocalUserAuthenticationAction?
    ) {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        self.authenticationAction = authenticationAction

        Task {
            do {
                let server = try await storedServer(for: discovered)
                let viewModel = makeViewModel(for: server)
                await viewModel.signIn(username: username, password: password)
            } catch {
                fail(error)
            }
        }
    }

    // MARK: - Server

    /// Returns the saved server with this id, or saves a new one.
    private func storedServer(for discovered: DiscoveredServer) async throws -> ServerState {
        if let existing = StoredValues[.Server.servers].first(where: { $0.id == discovered.id }) {
            return existing
        }

        let server = ServerState(
            urls: [discovered.address],
            currentURL: discovered.address,
            name: discovered.name,
            id: discovered.id,
            userIDs: []
        )

        let publicInfo = try await server.getPublicSystemInfo()
        StoredValues[.Server.servers] = StoredValues[.Server.servers].appending(server)
        StoredValues[.Server.publicInfo(id: server.id)] = publicInfo
        return server
    }

    // MARK: - Sign-in pipeline

    private func makeViewModel(for server: ServerState) -> UserSignInViewModel {
        cancellables.removeAll()

        let viewModel = UserSignInViewModel(server: server)
        self.viewModel = viewModel

        viewModel.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.fail(error)
            }
            .store(in: &cancellables)

        return viewModel
    }

    private func handle(_ event: UserSignInViewModel._Event) {
        guard let viewModel else { return }

        guard let authenticationAction else {
            fail(nil)
            return
        }

        let policy: LocalUserAccessPolicy = .none

        switch event {
        case let .connected(user):
            viewModel.save(
                user: user,
                authenticationAction: (authenticationAction, policy, nil),
                evaluatedPolicyMap: .init(action: { $0 })
            )
        case let .existingUser(user):
            // Already signed in on this device before: refresh the stored token.
            viewModel.saveExisting(
                user: user,
                replaceForAccessToken: true,
                authenticationAction: (authenticationAction, policy, nil),
                evaluatedPolicyMap: .init(action: { $0 })
            )
        case let .saved(user):
            Task {
                do {
                    try await userSessionManager.signIn(userID: user.id)
                    isSigningIn = false
                } catch {
                    fail(error)
                }
            }
        }
    }

    private func fail(_ error: Error?) {
        isSigningIn = false
        let message = error?.localizedDescription ?? ""
        if message.localizedCaseInsensitiveContains("401") || message.localizedCaseInsensitiveContains("unauthorized") {
            errorMessage = "That username or password isn't right. Try again."
        } else if message.isEmpty {
            errorMessage = "Something went wrong signing in. Try again."
        } else {
            errorMessage = message
        }
    }
}
