//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import LocalAuthentication
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shake Animation

private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}

// MARK: - PIN Entry View

public struct PINEntryView: View {

    public let title: String
    public let subtitle: String?
    public let expectedPin: String?
    public let onSuccess: (String) -> Void
    public let onCancel: () -> Void

    @State private var pin: String = ""
    @State private var shakeAttempts: CGFloat = 0
    @State private var isError: Bool = false
    @State private var biometricType: LABiometryType = .none

    public init(
        title: String = "Enter PIN",
        subtitle: String? = "Enter your 4-digit profile PIN",
        expectedPin: String? = nil,
        onSuccess: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.expectedPin = expectedPin
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            VStack(spacing: KhyloSpacing.xl) {
                // Header with cancel
                HStack {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(KhyloTypography.bodyMedium)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, KhyloSpacing.lg)
                .padding(.top, KhyloSpacing.sm)

                Spacer()

                // Titles
                VStack(spacing: KhyloSpacing.xs) {
                    Text(title)
                        .font(KhyloTypography.title2)
                        .foregroundColor(KhyloColors.textPrimary)

                    if let subtitle {
                        Text(subtitle)
                            .font(KhyloTypography.subheadline)
                            .foregroundColor(isError ? .red : KhyloColors.textSecondary)
                    }
                }

                // 4 PIN Dots
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(dotColor(at: index))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(isError ? Color.red : KhyloColors.border, lineWidth: 2)
                            )
                            .scaleEffect(index < pin.count ? 1.15 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pin.count)
                    }
                }
                .modifier(ShakeEffect(animatableData: shakeAttempts))
                .padding(.vertical, KhyloSpacing.lg)

                Spacer()

                // Numpad 3x4
                VStack(spacing: 16) {
                    numpadRow(["1", "2", "3"])
                    numpadRow(["4", "5", "6"])
                    numpadRow(["7", "8", "9"])

                    // Bottom row: Biometric / 0 / Delete
                    HStack(spacing: 32) {
                        // Biometrics
                        if biometricType != .none {
                            Button(action: triggerBiometrics) {
                                Image(systemName: biometricIcon)
                                    .font(.system(size: 26))
                                    .foregroundColor(KhyloColors.accent)
                                    .frame(width: 75, height: 75)
                            }
                        } else {
                            Color.clear
                                .frame(width: 75, height: 75)
                        }

                        // Digit 0
                        numpadButton("0")

                        // Delete
                        Button(action: deleteDigit) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(KhyloColors.textSecondary)
                                .frame(width: 75, height: 75)
                        }
                    }
                }
                .padding(.bottom, KhyloSpacing.xl)
            }
        }
        .onAppear {
            checkBiometrics()
        }
    }

    private func dotColor(at index: Int) -> Color {
        if isError {
            return Color.red.opacity(0.8)
        }
        return index < pin.count ? KhyloColors.accent : Color.clear
    }

    private func numpadRow(_ digits: [String]) -> some View {
        HStack(spacing: 32) {
            ForEach(digits, id: \.self) { digit in
                numpadButton(digit)
            }
        }
    }

    private func numpadButton(_ digit: String) -> some View {
        Button(action: { appendDigit(digit) }) {
            Text(digit)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(KhyloColors.textPrimary)
                .frame(width: 75, height: 75)
                .background(
                    Circle()
                        .fill(KhyloColors.surfaceElevated)
                )
                .overlay(
                    Circle()
                        .stroke(KhyloColors.border.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private func appendDigit(_ digit: String) {
        guard pin.count < 4 else { return }

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        isError = false
        pin.append(digit)

        if pin.count == 4 {
            validatePin()
        }
    }

    private func deleteDigit() {
        guard !pin.isEmpty else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        isError = false
        pin.removeLast()
    }

    private func validatePin() {
        if let expected = expectedPin, !expected.isEmpty {
            if pin == expected {
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                onSuccess(pin)
            } else {
                triggerError()
            }
        } else {
            // No strict local expected PIN provided -> submit PIN to caller/server
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onSuccess(pin)
        }
    }

    private func triggerError() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
        isError = true
        withAnimation(.default) {
            shakeAttempts += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            pin = ""
            isError = false
        }
    }

    private func checkBiometrics() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        }
    }

    private var biometricIcon: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }

    private func triggerBiometrics() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock profile") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif
                        onSuccess(expectedPin ?? pin)
                    }
                }
            }
        }
    }
}
