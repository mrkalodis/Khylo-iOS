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
    enum ScannedCode: Equatable {
        /// "Sign in another device" on a signed-in device: server address and a one-time code.
        case signIn(server: String, code: String)
        /// A Quick Connect code, which is for approving a device, not signing in with.
        case quickConnect
        case unknown

        init(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let hash = trimmed.firstIndex(of: "#") else {
                self = .unknown
                return
            }
            let server = String(trimmed[..<hash]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let route = URLComponents(string: String(trimmed[trimmed.index(after: hash)...]))
            let path = route?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let code = route?.queryItems?.first { $0.name.lowercased() == "code" }?.value
            if path == "quickconnect" {
                self = .quickConnect
            } else if path == "signin", let code, !code.isEmpty, !server.isEmpty {
                self = .signIn(server: server, code: code)
            } else {
                self = .unknown
            }
        }
    }

    /// Signs in with a QR code from "Sign in another device": finds the server it
    /// names, then trades the one-time code for a sign-in.
    func signIn(scanned text: String, authenticationAction: LocalUserAuthenticationAction?) {
        guard !isSigningIn else { return }
        errorMessage = nil

        switch ScannedCode(text) {
        case .quickConnect:
            errorMessage = "That code is for approving a device. On the device that's signed in, open Sign in another device and scan the code it shows."
            return
        case .unknown:
            errorMessage = "That isn't a Khylo sign-in code. On the device that's signed in, open Sign in another device and scan the code it shows."
            return
        case let .signIn(address, code):
            isSigningIn = true
            isCodeSignIn = true
            self.authenticationAction = authenticationAction
            Task {
                let discovered: DiscoveredServer
                do {
                    discovered = try await KhyloServerDiscovery().pingServer(urlString: address)
                } catch {
                    isSigningIn = false
                    isCodeSignIn = false
                    errorMessage = "Couldn't reach the server in that code. Check your connection and try again."
                    return
                }
                do {
                    let server = try await storedServer(for: discovered)
                    let viewModel = makeViewModel(for: server)
                    await viewModel.signInWithCode(code: code)
                } catch {
                    fail(error)
                }
            }
        }
    }

    /// The sign-in under way came from a scanned code, which has its own messages.
    private var isCodeSignIn = false

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
            errorMessage = Self.codeMessage(for: error)
            return
        }
        let message = error?.localizedDescription ?? ""
        if message.localizedCaseInsensitiveContains("401") || message.localizedCaseInsensitiveContains("unauthorized") {
            errorMessage = "That username or password isn't right. Try again."
        } else if message.isEmpty {
            errorMessage = "Something went wrong signing in. Try again."
        } else {
            errorMessage = message
        }
    }

    private static func codeMessage(for error: Error?) -> String {
        var status: Int? = if case let .unacceptableStatusCode(code) = error as? APIError { code } else { nil }
        if status == nil, let text = error?.localizedDescription {
            // The error can arrive wrapped, keeping only its description ("…unacceptable: 404.").
            status = [404, 403, 429].first { text.contains(": \($0)") }
        }
        switch status {
        case 404:
            return "That code has run out or was already used. Make a new one on the other device and scan it again."
        case 403:
            return "This account can't sign in right now. Ask the person who runs your server."
        case 429:
            return "Too many tries. Wait a minute, then scan a new code."
        default:
            return "Couldn't sign in with that code. Make a new one on the other device and try again."
        }
    }
}
