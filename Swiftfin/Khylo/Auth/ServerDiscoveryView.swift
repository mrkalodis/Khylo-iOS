//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct ServerDiscoveryView: View {

    @StateObject private var discovery = KhyloServerDiscovery()
    @State private var manualHost: String = ""
    @State private var isConnectingManual: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isAddressFocused: Bool

    public let onSelectServer: (DiscoveredServer) -> Void
    /// Opens the camera to sign in with a code from a device that's already signed in.
    public let onScanToSignIn: (() -> Void)?

    public init(onSelectServer: @escaping (DiscoveredServer) -> Void, onScanToSignIn: (() -> Void)? = nil) {
        self.onSelectServer = onSelectServer
        self.onScanToSignIn = onScanToSignIn
    }

    private var canConnect: Bool {
        !manualHost.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var body: some View {
        KhyloAuthScaffold {
            Spacer(minLength: 56)

            KhyloAuthLogo(width: 240)
                .padding(.bottom, 44)

            KhyloAuthHeader(
                title: "Connect to your server",
                subtitle: "Enter your Khylo server address to start watching."
            )
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 12) {
                KhyloAuthField(
                    label: "Server address",
                    text: $manualHost,
                    kind: .url,
                    isFocused: isAddressFocused,
                    hasError: errorMessage != nil,
                    onSubmit: connectManual
                )
                .focused($isAddressFocused)
                .onChange(of: manualHost) { _, _ in
                    if errorMessage != nil {
                        withAnimation { errorMessage = nil }
                    }
                }

                if let errorMessage {
                    KhyloAuthError(message: errorMessage)
                } else {
                    Text("For example khylo.example.com or 192.168.1.20:8096")
                        .font(.system(size: 13))
                        .foregroundColor(KhyloColors.textTertiary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.bottom, 24)

            KhyloAuthPrimaryButton(
                title: "Continue",
                isLoading: isConnectingManual,
                isEnabled: canConnect,
                action: connectManual
            )

            if let onScanToSignIn {
                KhyloAuthTextButton(title: "Scan to Sign In", systemImage: "qrcode.viewfinder", action: onScanToSignIn)
                    .padding(.top, 16)
            }

            nearbyServers
                .padding(.top, 40)

            Spacer(minLength: 32)
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
        .animation(.easeInOut(duration: 0.25), value: discovery.discoveredServers)
        .onAppear {
            discovery.startScanning()
        }
        .onDisappear {
            discovery.stopScanning()
        }
    }

    // MARK: - Nearby Servers

    @ViewBuilder
    private var nearbyServers: some View {
        if !discovery.discoveredServers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("ON YOUR NETWORK")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(KhyloColors.textTertiary)
                    .padding(.horizontal, 4)

                VStack(spacing: 10) {
                    ForEach(discovery.discoveredServers) { server in
                        serverRow(server)
                    }
                }
            }
            .transition(.opacity)
        } else if discovery.isScanning {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(KhyloColors.textTertiary)
                Text("Looking for servers on your network…")
                    .font(.system(size: 14))
                    .foregroundColor(KhyloColors.textTertiary)
            }
            .transition(.opacity)
        } else {
            KhyloAuthTextButton(title: "Search my network again", systemImage: "arrow.clockwise") {
                discovery.startScanning()
            }
            .transition(.opacity)
        }
    }

    private func serverRow(_ server: DiscoveredServer) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onSelectServer(server)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KhyloColors.accent.opacity(0.16))
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(KhyloColors.accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(KhyloColors.textPrimary)
                        .lineLimit(1)

                    Text(server.address.host() ?? server.address.absoluteString)
                        .font(.system(size: 13))
                        .foregroundColor(KhyloColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(KhyloColors.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    // MARK: - Actions

    private func connectManual() {
        guard canConnect, !isConnectingManual else { return }
        isAddressFocused = false
        isConnectingManual = true
        errorMessage = nil

        Task {
            do {
                let server = try await discovery.pingServer(urlString: manualHost)
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                onSelectServer(server)
            } catch {
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                #endif
                self.errorMessage = "We couldn't reach that server. Check the address and your connection, then try again."
            }
            isConnectingManual = false
        }
    }
}
