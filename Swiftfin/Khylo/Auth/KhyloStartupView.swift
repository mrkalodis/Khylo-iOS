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
    case qrCode(DiscoveredServer)
    case manualLogin(DiscoveredServer)
    case kidsSetup(DiscoveredServer)
}

// MARK: - Khylo Startup View Coordinator

public struct KhyloStartupView: View {

    @State private var currentStep: StartupStep = .serverDiscovery
    @State private var activeServer: DiscoveredServer?
    @State private var manualUsername: String = ""
    @State private var manualPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var authErrorMessage: String?

    public let onAuthenticated: () -> Void

    public init(
        initialServer: DiscoveredServer? = nil,
        onAuthenticated: @escaping () -> Void
    ) {
        self._activeServer = State(initialValue: initialServer)
        if let initialServer {
            self._currentStep = State(initialValue: .profiles(initialServer))
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
                        currentStep = .profiles(selectedServer)
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

            case .qrCode(let server):
                QRCodeLoginView(
                    server: server,
                    onAuthenticated: { _ in
                        onAuthenticated()
                    },
                    onFallbackManual: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentStep = .manualLogin(server)
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
    }

    // MARK: - Manual Login View

    @ViewBuilder
    private func manualLoginView(server: DiscoveredServer) -> some View {
        ScrollView {
            VStack(spacing: KhyloSpacing.xl) {
                // Top Bar
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentStep = .profiles(server)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(KhyloTypography.bodyMedium)
                        .foregroundColor(KhyloColors.textPrimary)
                    }

                    Spacer()
                }
                .padding(.horizontal, KhyloSpacing.lg)
                .padding(.top, KhyloSpacing.md)

                // Header
                VStack(spacing: KhyloSpacing.xs) {
                    Text("Sign In")
                        .font(KhyloTypography.largeTitle)
                        .foregroundColor(KhyloColors.textPrimary)

                    Text(server.name)
                        .font(KhyloTypography.headline)
                        .foregroundColor(KhyloColors.accent)

                    Text(server.address.absoluteString)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textSecondary)
                }

                // Error Message
                if let authErrorMessage {
                    HStack(spacing: KhyloSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(authErrorMessage)
                            .font(KhyloTypography.subheadline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Spacer()
                    }
                    .padding(KhyloSpacing.md)
                    .background(Color.red.opacity(0.18))
                    .cornerRadius(KhyloRadius.sm)
                    .padding(.horizontal, KhyloSpacing.lg)
                }

                // Form Fields
                VStack(spacing: KhyloSpacing.md) {
                    VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
                        Text("Username")
                            .font(KhyloTypography.captionMedium)
                            .foregroundColor(KhyloColors.textSecondary)

                        TextField("Enter your username", text: $manualUsername)
                            .padding(.horizontal, KhyloSpacing.md)
                            .frame(height: 52)
                            .background(KhyloColors.surface)
                            .cornerRadius(KhyloRadius.sm)
                            .foregroundColor(KhyloColors.textPrimary)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
                        Text("Password")
                            .font(KhyloTypography.captionMedium)
                            .foregroundColor(KhyloColors.textSecondary)

                        HStack {
                            if showPassword {
                                TextField("Enter your password", text: $manualPassword)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("Enter your password", text: $manualPassword)
                            }

                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundColor(KhyloColors.textSecondary)
                            }
                        }
                        .padding(.horizontal, KhyloSpacing.md)
                        .frame(height: 52)
                        .background(KhyloColors.surface)
                        .cornerRadius(KhyloRadius.sm)
                        .foregroundColor(KhyloColors.textPrimary)
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)

                // Sign In Button
                Button(action: {
                    authenticateManually(server: server)
                }) {
                    HStack(spacing: KhyloSpacing.sm) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(KhyloColors.textPrimary)
                        }
                        Text("Sign In")
                            .font(KhyloTypography.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KhyloColors.accent)
                    .foregroundColor(KhyloColors.textPrimary)
                    .cornerRadius(KhyloRadius.sm)
                }
                .disabled(manualUsername.trimmingCharacters(in: .whitespaces).isEmpty || isAuthenticating)
                .opacity(manualUsername.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
                .padding(.horizontal, KhyloSpacing.lg)

                // Alternate Login Options
                VStack(spacing: KhyloSpacing.md) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentStep = .qrCode(server)
                        }
                    }) {
                        HStack(spacing: KhyloSpacing.xs) {
                            Image(systemName: "qrcode")
                            Text("Sign in with QR Code")
                        }
                        .font(KhyloTypography.bodyMedium)
                        .foregroundColor(KhyloColors.textSecondary)
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentStep = .serverDiscovery
                        }
                    }) {
                        Text("Connect to different server")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textTertiary)
                    }
                }
                .padding(.top, KhyloSpacing.sm)
            }
            .padding(.bottom, KhyloSpacing.xxl)
        }
    }

    // MARK: - Profile Picker Alternative Auth Bar

    @ViewBuilder
    private func profileAlternativeAuthBar(server: DiscoveredServer) -> some View {
        HStack(spacing: KhyloSpacing.lg) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.28)) {
                    currentStep = .qrCode(server)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode")
                    Text("Quick Connect")
                }
                .font(KhyloTypography.subheadlineMedium)
                .foregroundColor(KhyloColors.textSecondary)
            }

            Text("•")
                .foregroundColor(KhyloColors.textTertiary)

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
        isAuthenticating = true
        authErrorMessage = nil

        Task {
            let authUrl = server.address.appendingPathComponent("Users/AuthenticateByName")
            var request = URLRequest(url: authUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Jellyfin Authorization header
            let clientName = "Khylo iOS"
            let deviceName = "Apple Device"
            let deviceId = "khylo-ios-\(UUID().uuidString.prefix(8))"
            let version = "1.0.0"
            let authHeader = "MediaBrowser Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(version)\""
            request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")

            let payload: [String: String] = [
                "Username": manualUsername.trimmingCharacters(in: .whitespaces),
                "Pw": manualPassword
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    await MainActor.run {
                        self.isAuthenticating = false
                        self.authErrorMessage = "Invalid username or password"
                    }
                    return
                }

                // If authentication succeeded, parse token
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let _ = json["AccessToken"] as? String {
                    await MainActor.run {
                        self.isAuthenticating = false
                        self.onAuthenticated()
                    }
                } else {
                    await MainActor.run {
                        self.isAuthenticating = false
                        self.onAuthenticated()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authErrorMessage = "Unable to connect: \(error.localizedDescription)"
                }
            }
        }
    }
}
