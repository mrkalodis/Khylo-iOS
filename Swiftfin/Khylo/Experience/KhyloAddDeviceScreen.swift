//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import AVFoundation
import Get
import SwiftUI

/// Signs in a TV or another device: enter the code it shows, or scan its QR code,
/// and this phone approves it with your account.
struct KhyloAddDeviceScreen: View {

    private enum Stage: Equatable {
        case entering
        case approving
        case approved
    }

    @State private var code = ""
    @State private var stage: Stage = .entering
    @State private var errorMessage: String?
    @State private var isScanning = false
    @FocusState private var isFocused: Bool

    /// Quick Connect codes are six digits.
    private var isComplete: Bool { code.count == 6 }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Image(systemName: stage == .approved ? "checkmark.circle.fill" : "tv.and.mediabox")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(stage == .approved ? KhyloStyle.accent : .white.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.top, 36)

                VStack(spacing: 8) {
                    Text(stage == .approved ? "Device approved" : "Add a Device")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(stage == .approved
                        ? "It signs in as \(KhyloAPI.session?.user.username ?? "you") in a moment."
                        : "On the TV or other device, choose Sign in with a code. Then enter the code it shows, or scan its QR code.")
                        .font(.system(size: 15))
                        .foregroundColor(KhyloStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                if stage == .approved {
                    Button("Add Another Device") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            code = ""
                            stage = .entering
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KhyloStyle.accent)
                } else {
                    codeBoxes
                        .padding(.horizontal, KhyloStyle.gutter)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "#FF6B5E"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                            .transition(.opacity)
                    }

                    VStack(spacing: 12) {
                        KhyloPlayButton(title: stage == .approving ? "Approving…" : "Approve", systemImage: "checkmark") {
                            approve()
                        }
                        .disabled(!isComplete || stage == .approving)
                        .opacity(isComplete ? 1 : 0.45)

                        Button {
                            isFocused = false
                            isScanning = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                    .padding(.horizontal, KhyloStyle.gutter)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .navigationTitle("Add a Device")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
        .sheet(isPresented: $isScanning) {
            KhyloCodeScannerSheet { scanned in
                isScanning = false
                guard let found = Self.code(in: scanned) else {
                    errorMessage = "That QR code isn't a Khylo sign-in code."
                    return
                }
                code = found
                approve()
            }
        }
    }

    /// Six boxes over one hidden field, like a one-time code.
    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .foregroundColor(.clear)
                .tint(.clear)
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(6))
                    if digits != value { code = digits }
                    errorMessage = nil
                    if digits.count == 6 { approve() }
                }
            HStack(spacing: 10) {
                ForEach(0 ..< 6, id: \.self) { index in
                    let characters = Array(code)
                    let isCurrent = index == characters.count && isFocused
                    Text(index < characters.count ? String(characters[index]) : "")
                        .font(.system(size: 28, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isCurrent ? KhyloStyle.accent : Color.white.opacity(0.08), lineWidth: isCurrent ? 2 : 1)
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private func approve() {
        guard isComplete, stage != .approving else { return }
        isFocused = false
        stage = .approving
        errorMessage = nil
        let entered = code
        Task {
            do {
                try await KhyloAPI.approveDevice(code: entered)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { stage = .approved }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.easeOut(duration: 0.2)) {
                    stage = .entering
                    errorMessage = Self.message(for: error)
                }
            }
        }
    }

    private static func message(for error: Error) -> String {
        if case let .unacceptableStatusCode(status) = error as? Get.APIError {
            switch status {
            case 404: return "That code isn't valid or has run out. Check the code on the TV and try again."
            case 401, 403: return "Signing in with a code is turned off on your server, or your account can't approve devices."
            default: break
            }
        }
        return "Couldn't reach your server. Check your connection and try again."
    }

    /// The six-digit code in what a QR code holds: a link like ".../#/quickconnect?code=123456", or the bare code.
    static func code(in text: String) -> String? {
        if let range = text.range(of: #"code=(\d{6})"#, options: .regularExpression) {
            return String(text[range].suffix(6))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 6 && trimmed.allSatisfy(\.isNumber) ? trimmed : nil
    }
}

// MARK: - Scanner

/// The camera, looking for a QR code.
struct KhyloCodeScannerSheet: View {

    var prompt = "Point your camera at the QR code on the TV."
    var deniedHint = "Turn on Camera for Khylo in Settings, or type the code instead."
    let onFound: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch access {
                case .authorized:
                    KhyloQRCameraView(onFound: onFound)
                        .ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 240, height: 240)
                    VStack {
                        Spacer()
                        Text(prompt)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .padding(.bottom, 40)
                    }
                case .notDetermined:
                    ProgressView().tint(.white)
                default:
                    VStack(spacing: 14) {
                        Image(systemName: "camera")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Khylo needs your camera to scan the code.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text(deniedHint)
                            .font(.system(size: 14))
                            .foregroundColor(KhyloStyle.secondaryText)
                            .multilineTextAlignment(.center)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(KhyloStyle.accent)
                        .padding(.top, 4)
                    }
                    .padding(30)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .task {
            if access == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                access = granted ? .authorized : .denied
            }
        }
    }
}

/// A live camera preview that reports the first QR code it reads.
private struct KhyloQRCameraView: UIViewRepresentable {

    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let session = context.coordinator.session
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        let session = coordinator.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        private let onFound: (String) -> Void
        private var didFind = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didFind,
                  let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first
            else { return }
            didFind = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onFound(code)
        }
    }
}
