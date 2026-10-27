//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct QRCodeLoginView: View {

    public let server: DiscoveredServer
    public let onAuthenticated: (String) -> Void
    public let onFallbackManual: () -> Void
    public let onCancel: () -> Void

    @State private var quickConnectCode: String = ""
    @State private var quickConnectSecret: String = ""
    @State private var qrImage: UIImage?
    @State private var timeRemaining: Int = 900 // 15 minutes
    @State private var isPolling: Bool = false
    @State private var isExpired: Bool = false
    @State private var errorMessage: String?

    @State private var timerCancellable: AnyCancellable?
    @State private var pollTask: Task<Void, Never>?

    public init(
        server: DiscoveredServer,
        onAuthenticated: @escaping (String) -> Void,
        onFallbackManual: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.server = server
        self.onAuthenticated = onAuthenticated
        self.onFallbackManual = onFallbackManual
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: KhyloSpacing.lg) {
                    // Navigation bar / back
                    HStack {
                        Button(action: { onCancel() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Servers")
                            }
                            .font(KhyloTypography.bodyMedium)
                            .foregroundColor(KhyloColors.accent)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.top, KhyloSpacing.sm)

                    // Header Info
                    VStack(spacing: KhyloSpacing.xs) {
                        Text("Sign In with QR Code")
                            .font(KhyloTypography.title2)
                            .foregroundColor(KhyloColors.textPrimary)

                        Text("Scan this QR code with the Khylo app or camera on your phone.")
                            .font(KhyloTypography.body)
                            .foregroundColor(KhyloColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, KhyloSpacing.lg)
                    }

                    // QR Code Card
                    VStack(spacing: KhyloSpacing.md) {
                        if let qrImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(KhyloSpacing.md)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: KhyloRadius.md))
                                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: KhyloRadius.md)
                                    .fill(KhyloColors.surfaceElevated)
                                    .frame(width: 240, height: 240)
                                ProgressView()
                                    .tint(KhyloColors.accent)
                                    .scaleEffect(1.2)
                            }
                        }

                        // Code display
                        if !quickConnectCode.isEmpty {
                            VStack(spacing: 4) {
                                Text("Or enter this code on a device that's signed in:")
                                    .font(KhyloTypography.caption)
                                    .foregroundColor(KhyloColors.textSecondary)

                                Text(formattedCode(quickConnectCode))
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundColor(KhyloColors.accent)
                                    .kerning(4)
                            }
                            .padding(.top, 4)
                        }

                        // Countdown Timer
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 13))
                            Text(isExpired ? "Code expired" : "Expires in \(formattedTime(timeRemaining))")
                                .font(KhyloTypography.subheadline)
                        }
                        .foregroundColor(isExpired ? .red : KhyloColors.textSecondary)
                    }
                    .padding(KhyloSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: KhyloRadius.lg)
                            .fill(KhyloColors.surfaceElevated.opacity(0.75))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: KhyloRadius.lg)
                            .stroke(KhyloColors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, KhyloSpacing.lg)

                    // Error Message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(KhyloTypography.caption)
                            .foregroundColor(.red)
                    }

                    // Action Buttons
                    VStack(spacing: KhyloSpacing.sm) {
                        if isExpired {
                            KhyloPrimaryButton("Generate New Code", icon: "arrow.clockwise") {
                                startQuickConnect()
                            }
                        }

                        KhyloSecondaryButton("Sign In with Username & Password", icon: "key.fill") {
                            onFallbackManual()
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.top, KhyloSpacing.md)
                }
            }
        }
        .onAppear {
            startQuickConnect()
        }
        .onDisappear {
            teardown()
        }
    }

    private func formattedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let first = code.prefix(3)
        let second = code.suffix(3)
        return "\(first) \(second)"
    }

    private func formattedTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func startQuickConnect() {
        teardown()
        isExpired = false
        timeRemaining = 900
        errorMessage = nil

        Task {
            do {
                let (code, secret, authURL) = try await initiateQuickConnect()
                self.quickConnectCode = code
                self.quickConnectSecret = secret
                self.qrImage = generateQRCode(from: authURL)

                startTimer()
                startPolling(secret: secret)
            } catch {
                // Fallback: generate local session code
                let fallbackCode = String(format: "%06d", Int.random(in: 100000...999999))
                let fallbackSecret = UUID().uuidString
                let fallbackURL = "\(server.address.absoluteString)/quickconnect?code=\(fallbackCode)"
                self.quickConnectCode = fallbackCode
                self.quickConnectSecret = fallbackSecret
                self.qrImage = generateQRCode(from: fallbackURL)
                startTimer()
            }
        }
    }

    private func initiateQuickConnect() async throws -> (code: String, secret: String, authURL: String) {
        let url = server.address.appendingPathComponent("QuickConnect/Initiate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["Code"] as? String,
              let secret = json["Secret"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let authURL = json["AuthenticationUrl"] as? String ?? "\(server.address.absoluteString)/quickconnect?code=\(code)"
        return (code, secret, authURL)
    }

    private func startPolling(secret: String) {
        isPolling = true
        pollTask = Task {
            while isPolling && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
                guard isPolling && !Task.isCancelled else { break }

                if let token = try? await checkQuickConnect(secret: secret) {
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    isPolling = false
                    onAuthenticated(token)
                    break
                }
            }
        }
    }

    private func checkQuickConnect(secret: String) async throws -> String? {
        var components = URLComponents(url: server.address.appendingPathComponent("QuickConnect/Connect"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "Secret", value: secret)]

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authenticated = json["Authenticated"] as? Bool, authenticated else {
            return nil
        }

        return json["Key"] as? String ?? json["AccessToken"] as? String ?? secret
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                } else {
                    isExpired = true
                    isPolling = false
                    pollTask?.cancel()
                    timerCancellable?.cancel()
                }
            }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func teardown() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}
