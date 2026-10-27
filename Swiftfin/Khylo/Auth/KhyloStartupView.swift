//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Startup Navigation Step

public enum StartupStep: Equatable {
    case serverDiscovery
    case profiles(DiscoveredServer)
    case manualLogin(DiscoveredServer)
    case kidsSetup(DiscoveredServer)
}

// MARK: - Khylo Startup View Coordinator

public struct KhyloStartupView: View {

    @State private var currentStep: StartupStep = .serverDiscovery
    @State private var activeServer: DiscoveredServer?
    @State private var manualUsername: String = ""
    @State private var manualPassword: String = ""
    @FocusState private var focusedLoginField: LoginField?
    @StateObject private var signInModel = KhyloSignInModel()
    @State private var isScanningToSignIn = false

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    private var isAuthenticating: Bool { signInModel.isSigningIn }
    private var authErrorMessage: String? { signInModel.errorMessage }

    public let onAuthenticated: () -> Void

    public init(
        initialServer: DiscoveredServer? = nil,
        onAuthenticated: @escaping () -> Void
    ) {
        self._activeServer = State(initialValue: initialServer)
        if let initialServer {
            self._currentStep = State(initialValue: .manualLogin(initialServer))
        } else {
            self._currentStep = State(initialValue: .serverDiscovery)
        }
        self.onAuthenticated = onAuthenticated
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            switch currentStep {
            case .serverDiscovery:
                ServerDiscoveryView { selectedServer in
                    activeServer = selectedServer
                    withAnimation(.easeInOut(duration: 0.28)) {
                        currentStep = .manualLogin(selectedServer)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity
                ))

            case .profiles(let server):
                ProfilePickerView(
                    server: server,
                    onSelectProfile: { profile, pin in
                        handleProfileSelection(server: server, profile: profile, pin: pin)
                    },
                    onSwitchServer: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentStep = .serverDiscovery
                        }
                    }
                )
                .overlay(alignment: .bottom) {
                    profileAlternativeAuthBar(server: server)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity
                ))

            case .manualLogin(let server):
                manualLoginView(server: server)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))

            case .kidsSetup(let server):
                KidsSetupView(
                    server: server,
                    ownerHasPin: true,
                    onCreate: { _ in
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentStep = .profiles(server)
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentStep = .profiles(server)
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity
                ))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: currentStep)
        .sheet(isPresented: $isScanningToSignIn) {
            KhyloCodeScannerSheet(
                prompt: "Point your camera at the code on a device that's signed in.",
                deniedHint: "Turn on Camera for Khylo in Settings, or sign in with your password instead."
            ) { scanned in
                isScanningToSignIn = false
                // Scan to Sign In is only offered once a server is chosen.
                guard case let .manualLogin(server) = currentStep else { return }
                signInModel.signIn(scanned: scanned, server: server, authenticationAction: authenticationAction)
            }
        }
    }
    // MARK: - Manual Login View

    private enum LoginField: Hashable {
        case username
        case password
    }

    private var canSignIn: Bool {
        !manualUsername.trimmingCharacters(in: .whitespaces).isEmpty && !isAuthenticating
    }

    @ViewBuilder
    private func manualLoginView(server: DiscoveredServer) -> some View {
        ZStack(alignment: .topLeading) {
            KhyloAuthScaffold {
                Spacer(minLength: 72)

                KhyloAuthLogo(width: 180)
                    .padding(.bottom, 40)

                KhyloAuthHeader(title: "Sign in")
                    .padding(.bottom, 14)

                serverChip(server: server)
                    .padding(.bottom, 32)

                VStack(alignment: .leading, spacing: 14) {
                    KhyloAuthField(
                        label: "Username",
                        text: $manualUsername,
                        kind: .username,
                        isFocused: focusedLoginField == .username,
                        hasError: authErrorMessage != nil,
                        onSubmit: { focusedLoginField = .password }
                    )
                    .focused($focusedLoginField, equals: .username)

                    KhyloAuthField(
                        label: "Password",
                        text: $manualPassword,
                        kind: .password,
                        isFocused: focusedLoginField == .password,
                        hasError: authErrorMessage != nil,
                        onSubmit: {
                            if canSignIn { authenticateManually(server: server) }
                        }
                    )
                    .focused($focusedLoginField, equals: .password)

                    if let authErrorMessage {
                        KhyloAuthError(message: authErrorMessage)
                    }
                }
                .padding(.bottom, 24)

                KhyloAuthPrimaryButton(
                    title: "Sign In",
                    isLoading: isAuthenticating,
                    isEnabled: canSignIn
                ) {
                    authenticateManually(server: server)
                }

                KhyloAuthTextButton(title: "Scan to Sign In", systemImage: "qrcode.viewfinder") {
                    isScanningToSignIn = true
                }
                .padding(.top, 16)


                Spacer(minLength: 32)
            }
            .animation(.easeInOut(duration: 0.2), value: authErrorMessage)

            KhyloAuthBackButton {
                withAnimation(.easeInOut(duration: 0.28)) {
                    currentStep = .serverDiscovery
                }
            }
            .padding(.leading, 20)
            .padding(.top, 8)
        }
    }

    /// Shows which server the user is signing in to, with a way to change it.
    private func serverChip(server: DiscoveredServer) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                currentStep = .serverDiscovery
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: "#3DDC84"))
                    .frame(width: 7, height: 7)
                Text(server.address.host() ?? server.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)
                Text("Change")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(KhyloColors.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .accessibilityLabel("Server \(server.address.host() ?? server.name). Change server")
    }

    // MARK: - Profile Picker Alternative Auth Bar

    @ViewBuilder
    private func profileAlternativeAuthBar(server: DiscoveredServer) -> some View {
        HStack(spacing: KhyloSpacing.lg) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.28)) {
                    currentStep = .manualLogin(server)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Other User")
                }
                .font(KhyloTypography.subheadlineMedium)
                .foregroundColor(KhyloColors.textSecondary)
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
        .padding(.vertical, KhyloSpacing.md)
        .background(
            Capsule()
                .fill(KhyloColors.surfaceElevated.opacity(0.85))
                .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
        )
        .padding(.bottom, KhyloSpacing.lg)
    }

    // MARK: - Actions

    private func handleProfileSelection(
        server: DiscoveredServer,
        profile: KhyloProfile,
        pin: String?
    ) {
        Task {
            // Attempt to switch profile via Khylo API or Jellyfin user selection
            let switchUrl = server.address.appendingPathComponent("Khylo/HomeProfiles/\(profile.id)/Switch")
            var request = URLRequest(url: switchUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var payload: [String: Any] = [:]
            if let pin, !pin.isEmpty {
                payload["Pin"] = pin
            }

            if let body = try? JSONSerialization.data(withJSONObject: payload) {
                request.httpBody = body
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
                    await MainActor.run {
                        onAuthenticated()
                    }
                    return
                }
            } catch {
                // If custom endpoint not supported, proceed with standard authenticated callback
            }

            await MainActor.run {
                onAuthenticated()
            }
        }
    }

    private func authenticateManually(server: DiscoveredServer) {
        focusedLoginField = nil
        signInModel.signIn(
            server: server,
            username: manualUsername.trimmingCharacters(in: .whitespaces),
            password: manualPassword,
            authenticationAction: authenticationAction
        )
    }

}
