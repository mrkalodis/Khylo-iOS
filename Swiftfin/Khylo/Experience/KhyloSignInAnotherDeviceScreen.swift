//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import CoreImage.CIFilterBuiltins
import Get
import SwiftUI

/// Shows a QR code that signs another phone in as you: on the new phone, tap
/// Scan to Sign In and point it here. The code works once, for a few minutes.
struct KhyloSignInAnotherDeviceScreen: View {

    private enum Stage: Equatable {
        case loading
        case showing(String, UIImage, expires: Date)
        case signedIn(device: String?)
        case expired
        case failed(String)

        static func == (lhs: Stage, rhs: Stage) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.expired, .expired): true
            case let (.showing(a, _, _), .showing(b, _, _)): a == b
            case let (.signedIn(a), .signedIn(b)): a == b
            case let (.failed(a), .failed(b)): a == b
            default: false
            }
        }
    }

    @State private var stage: Stage = .loading
    @State private var code: String?
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("On the new phone, open Khylo and tap **Scan to Sign In**, then point it at this code. It signs that phone in as you.")
                    .font(.system(size: 15))
                    .foregroundColor(KhyloStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                content
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.25), value: stage)
            }
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .navigationTitle("Sign In Another Device")
        .navigationBarTitleDisplayMode(.inline)
        .task { await makeCode() }
        .task(id: code) { await watch() }
        .onDisappear {
            // Nobody scanned it: it shouldn't stay usable.
            if let code, case .showing = stage {
                Task { await KhyloAPI.cancelSignInCode(code) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .loading:
            ProgressView().tint(.white).frame(height: 300)

        case let .showing(_, image, expires):
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                Text(remaining(until: expires))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundColor(KhyloStyle.tertiaryText)
            }

        case let .signedIn(device):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(KhyloStyle.accent)
                Text(device.map { "Signed in on \($0)" } ?? "Signed in")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Button("Sign In Another") { Task { await makeCode() } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KhyloStyle.accent)
                    .padding(.top, 4)
            }
            .frame(height: 300)

        case .expired:
            VStack(spacing: 12) {
                Text("This code ran out.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Button("New Code") { Task { await makeCode() } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KhyloStyle.accent)
            }
            .frame(height: 300)

        case let .failed(message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(KhyloStyle.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await makeCode() } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KhyloStyle.accent)
            }
            .frame(height: 300)
        }
    }

    private func remaining(until expires: Date) -> String {
        let seconds = max(0, Int(expires.timeIntervalSince(now)))
        return String(format: "Works for %d:%02d", seconds / 60, seconds % 60)
    }

    private func makeCode() async {
        if let old = code, case .showing = stage { await KhyloAPI.cancelSignInCode(old) }
        stage = .loading
        code = nil
        do {
            let made = try await KhyloAPI.makeSignInCode()
            guard let image = Self.qrImage(made.qrURL) else {
                stage = .failed("Couldn't draw the code. Try again.")
                return
            }
            let expires = made.expiresAt ?? Date().addingTimeInterval(TimeInterval(made.expiresInSeconds ?? 300))
            code = made.code
            now = Date()
            stage = .showing(made.code, image, expires: expires)
        } catch {
            if case let .unacceptableStatusCode(status) = error as? APIError, status == 404 {
                stage = .failed("Your server needs an update before it can sign in another device this way. You can still sign in with Quick Connect or a password.")
            } else {
                stage = .failed("Couldn't make a code. Check your connection and try again.")
            }
        }
    }

    /// Counts down, and checks every 2 seconds whether the code was used.
    private func watch() async {
        guard let code else { return }
        var tick = 0
        while !Task.isCancelled, case let .showing(_, _, expires) = stage {
            try? await Task.sleep(for: .seconds(1))
            now = Date()
            if now >= expires {
                stage = .expired
                return
            }
            tick += 1
            guard tick % 2 == 0, let status = try? await KhyloAPI.signInCodeStatus(code) else { continue }
            if status.used {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                stage = .signedIn(device: status.deviceName)
                return
            }
            if status.expired {
                stage = .expired
                return
            }
        }
    }

    private static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
