//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import AVFoundation
import SwiftUI

// MARK: - Scanner

/// The camera, looking for a QR code.
struct KhyloCodeScannerSheet: View {

    var prompt = "Point your camera at the code on a device that's signed in."
    var deniedHint = "Turn on Camera for Khylo in Settings, or sign in with your password instead."
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
