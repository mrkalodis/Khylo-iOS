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
    @State private var pulseAnimation: Bool = false

    public let onSelectServer: (DiscoveredServer) -> Void

    public init(onSelectServer: @escaping (DiscoveredServer) -> Void) {
        self.onSelectServer = onSelectServer
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: KhyloSpacing.xl) {
                    // Header Brand
                    VStack(spacing: KhyloSpacing.sm) {
                        #if canImport(UIKit)
                        if let logo = loadBrandImage(named: "khylo_logo") {
                            Image(uiImage: logo)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                        }
                        #endif

                        Text("Connect to Server")
                            .font(KhyloTypography.title1)
                            .foregroundColor(KhyloColors.textPrimary)

                        Text("Choose a media server on your local network or enter an address.")
                            .font(KhyloTypography.body)
                            .foregroundColor(KhyloColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, KhyloSpacing.lg)
                    }
                    .padding(.top, KhyloSpacing.xl)

                    // Error Alert Banner
                    if let errorMessage {
                        HStack(spacing: KhyloSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(KhyloTypography.subheadline)
                                .foregroundColor(KhyloColors.textPrimary)
                            Spacer()
                            Button(action: { self.errorMessage = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(KhyloColors.textSecondary)
                            }
                        }
                        .padding(KhyloSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                .fill(Color.red.opacity(0.18))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.horizontal, KhyloSpacing.lg)
                    }

                    // Discovered Servers Section
                    VStack(alignment: .leading, spacing: KhyloSpacing.md) {
                        HStack {
                            Text("Discovered Servers")
                                .font(KhyloTypography.headline)
                                .foregroundColor(KhyloColors.textPrimary)

                            Spacer()

                            if discovery.isScanning {
                                HStack(spacing: KhyloSpacing.xs) {
                                    Circle()
                                        .fill(KhyloColors.accent)
                                        .frame(width: 8, height: 8)
                                        .scaleEffect(pulseAnimation ? 1.4 : 0.8)
                                        .opacity(pulseAnimation ? 1.0 : 0.4)
                                    Text("Scanning...")
                                        .font(KhyloTypography.caption)
                                        .foregroundColor(KhyloColors.textSecondary)
                                }
                            } else {
                                Button(action: { discovery.startScanning() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Rescan")
                                    }
                                    .font(KhyloTypography.captionBold)
                                    .foregroundColor(KhyloColors.accent)
                                }
                            }
                        }

                        if discovery.discoveredServers.isEmpty {
                            VStack(spacing: KhyloSpacing.sm) {
                                Image(systemName: "network")
                                    .font(.system(size: 32))
                                    .foregroundColor(KhyloColors.textTertiary)
                                Text(discovery.isScanning ? "Looking for nearby Khylo servers..." : "No servers discovered automatically")
                                    .font(KhyloTypography.subheadline)
                                    .foregroundColor(KhyloColors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, KhyloSpacing.xl)
                            .background(
                                RoundedRectangle(cornerRadius: KhyloRadius.md)
                                    .fill(KhyloColors.surfaceElevated.opacity(0.5))
                            )
                        } else {
                            VStack(spacing: KhyloSpacing.sm) {
                                ForEach(discovery.discoveredServers) { server in
                                    serverRow(server)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)

                    // Manual Connection Section
                    VStack(alignment: .leading, spacing: KhyloSpacing.md) {
                        Text("Connect Manually")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)

                        VStack(spacing: KhyloSpacing.sm) {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(KhyloColors.textTertiary)
                                TextField("http://192.168.1.100:8096", text: $manualHost)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .font(KhyloTypography.body)
                                    .foregroundColor(KhyloColors.textPrimary)
                            }
                            .padding(KhyloSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: KhyloRadius.md)
                                    .fill(KhyloColors.surfaceElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: KhyloRadius.md)
                                    .stroke(KhyloColors.border, lineWidth: 1)
                            )

                            KhyloPrimaryButton(
                                "Connect",
                                icon: "arrow.right",
                                isLoading: isConnectingManual,
                                isEnabled: !manualHost.trimmingCharacters(in: .whitespaces).isEmpty
                            ) {
                                connectManual()
                            }
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)

                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            discovery.startScanning()
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .onDisappear {
            discovery.stopScanning()
        }
    }

    private func serverRow(_ server: DiscoveredServer) -> some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onSelectServer(server)
        }) {
            HStack(spacing: KhyloSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: KhyloRadius.sm)
                        .fill(server.isKhyloServer ? KhyloColors.accent.opacity(0.18) : KhyloColors.surfaceElevated)
                        .frame(width: 44, height: 44)

                    Image(systemName: server.isKhyloServer ? "sparkles.tv" : "server.rack")
                        .font(.system(size: 20))
                        .foregroundColor(server.isKhyloServer ? KhyloColors.accent : KhyloColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)

                        if server.isKhyloServer {
                            KhyloBadge("Khylo", style: .accent)
                        } else {
                            KhyloBadge("Media Server", style: .standard)
                        }
                    }

                    Text(server.address.absoluteString)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(KhyloColors.textTertiary)
            }
            .padding(KhyloSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.md)
                    .fill(KhyloColors.surfaceElevated.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.md)
                    .stroke(server.isKhyloServer ? KhyloColors.accentDim.opacity(0.5) : KhyloColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private func connectManual() {
        guard !manualHost.isEmpty else { return }
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
                self.errorMessage = "Unable to connect to server at \(manualHost). Check host address and network."
            }
            isConnectingManual = false
        }
    }

    #if canImport(UIKit)
    private func loadBrandImage(named: String) -> UIImage? {
        if let path = Bundle.main.path(forResource: named, ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }
    #endif
}
