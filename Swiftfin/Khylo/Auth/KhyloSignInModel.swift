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
import Get
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

    // MARK: - Scanning a code from a signed-in device

    /// What a scanned QR code holds.
    struct ScannedCode: Equatable {
        let code: String
        /// The server named in the link, when it's a link and not a bare code.
        let host: String?

        /// A link from "Sign In Another Device" (`…/#/signin?code=…`) or a bare code.
        init?(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let hash = trimmed.firstIndex(of: "#") else {
                // A bare code: no address, no spaces.
                guard !trimmed.contains("://"), !trimmed.contains(" "), !trimmed.contains("/") else { return nil }
                code = trimmed
                host = nil
                return
            }
            let route = URLComponents(string: String(trimmed[trimmed.index(after: hash)...]))
            guard route?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "signin",
                  let value = route?.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value,
                  !value.isEmpty
            else { return nil }
            code = value
            host = URL(string: String(trimmed[..<hash]))?.host()?.lowercased()
        }
    }

    /// Signs in on the chosen server with a code scanned from "Sign In Another Device".
    func signIn(scanned text: String, server discovered: DiscoveredServer, authenticationAction: LocalUserAuthenticationAction?) {
        guard !isSigningIn else { return }
        errorMessage = nil

        guard let scanned = ScannedCode(text) else {
            errorMessage = "That isn't a Khylo sign-in code. On the device that's signed in, open Sign In Another Device and scan the code it shows."
            return
        }
        isSigningIn = true
        isCodeSignIn = true
        // A link to another address can still be this server (home and web addresses differ).
        codeIsFromOtherAddress = scanned.host.map { $0 != discovered.address.host()?.lowercased() } ?? false
        self.authenticationAction = authenticationAction
        Task {
            do {
                let server = try await storedServer(for: discovered)
                let viewModel = makeViewModel(for: server)
                await viewModel.signInWithCode(code: scanned.code)
            } catch {
                fail(error)
            }
        }
    }

    /// The sign-in under way came from a scanned code, which has its own messages.
    private var isCodeSignIn = false
    private var codeIsFromOtherAddress = false

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
                    isCodeSignIn = false
                } catch {
                    fail(error)
                }
            }
        }
    }

    private func fail(_ error: Error?) {
        isSigningIn = false
        if isCodeSignIn {
            isCodeSignIn = false
            errorMessage = codeMessage(for: error)
            return
        }
        let message = error?.localizedDescription ?? ""
        if Self.status(of: error) == 429 {
            errorMessage = "Too many sign-in attempts. Try again in a few minutes."
        } else if message.localizedCaseInsensitiveContains("401") || message.localizedCaseInsensitiveContains("unauthorized") {
            errorMessage = "That username or password isn't right. Try again."
        } else if message.isEmpty {
            errorMessage = "Something went wrong signing in. Try again."
        } else {
            errorMessage = message
        }
    }

    private func codeMessage(for error: Error?) -> String {
        switch Self.status(of: error) {
        case 404:
            codeIsFromOtherAddress
                ? "That code is from a different server."
                : "That code has run out. Make a new one on the other device."
        case 403:
            "This account can't sign in right now."
        case 429:
            "Too many tries. Wait a minute and try again."
        default:
            "Couldn't reach your server. Try again."
        }
    }

    /// The server's answer, also when the error arrives wrapped with only its description.
    private static func status(of error: Error?) -> Int? {
        if case let .unacceptableStatusCode(code) = error as? APIError { return code }
        guard let text = error?.localizedDescription else { return nil }
        return [404, 403, 429].first { text.contains(": \($0)") }
    }
}
