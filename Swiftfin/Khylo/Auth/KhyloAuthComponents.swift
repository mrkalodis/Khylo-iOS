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

// Shared building blocks for the sign-in flow (connect, sign in, quick connect),
// so every onboarding screen has the same backdrop, logo, fields and buttons.

// MARK: - Backdrop

/// Dark backdrop with a soft brand glow, used behind all auth screens.
struct KhyloAuthBackground: View {

    var body: some View {
        ZStack {
            KhyloColors.background

            RadialGradient(
                colors: [KhyloColors.accent.opacity(0.22), .clear],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 520
            )

            RadialGradient(
                colors: [KhyloColors.accentDim.opacity(0.10), .clear],
                center: UnitPoint(x: 1.1, y: 1.0),
                startRadius: 0,
                endRadius: 420
            )

            LinearGradient(
                colors: [.clear, KhyloColors.background.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Logo

/// The Khylo wordmark, loaded from the bundled `khylo_logo.png`.
struct KhyloAuthLogo: View {

    var width: CGFloat = 220

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let path = Bundle.main.path(forResource: "khylo_logo", ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .frame(width: width)
        .accessibilityLabel("Khylo")
    }

    private var fallback: some View {
        Text("KHYLO")
            .font(.system(size: width * 0.2, weight: .heavy))
            .tracking(4)
            .foregroundColor(KhyloColors.textPrimary)
    }
}

// MARK: - Header

/// Large title with a muted supporting line.
struct KhyloAuthHeader: View {

    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(KhyloColors.textPrimary)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(KhyloColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Text Field

/// Tall rounded input with a floating label, focus glow and optional secure entry.
struct KhyloAuthField: View {

    enum Kind {
        case url
        case username
        case password
    }

    let label: String
    @Binding var text: String
    var kind: Kind = .username
    var isFocused: Bool = false
    var hasError: Bool = false
    var onSubmit: () -> Void = {}

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if !text.isEmpty {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isFocused ? KhyloColors.accent : KhyloColors.textSecondary)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                field
                    .font(.system(size: 17))
                    .foregroundColor(KhyloColors.textPrimary)
                    .tint(KhyloColors.accent)
                    .submitLabel(kind == .password ? .go : (kind == .url ? .go : .next))
                    .onSubmit(onSubmit)
            }
            .animation(.easeOut(duration: 0.15), value: text.isEmpty)

            if kind == .password {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(KhyloColors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            } else if !text.isEmpty, isFocused {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(KhyloColors.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused || hasError ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var borderColor: Color {
        if hasError { return Color.red.opacity(0.7) }
        return isFocused ? KhyloColors.accent : Color.white.opacity(0.08)
    }

    private var placeholder: Text {
        Text(label).foregroundColor(KhyloColors.textSecondary.opacity(0.8))
    }

    @ViewBuilder
    private var field: some View {
        switch kind {
        case .url:
            TextField("", text: $text, prompt: placeholder)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .username:
            TextField("", text: $text, prompt: placeholder)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .password:
            if isRevealed {
                TextField("", text: $text, prompt: placeholder)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField("", text: $text, prompt: placeholder)
                    .textContentType(.password)
            }
        }
    }
}

// MARK: - Inline Error

struct KhyloAuthError: View {

    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(Color(hex: "#FF6B5E"))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Buttons

/// Full-width, high-emphasis brand button.
struct KhyloAuthPrimaryButton: View {

    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        } label: {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#E8873F"), KhyloColors.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .shadow(color: KhyloColors.accent.opacity(isEnabled ? 0.35 : 0), radius: 18, y: 8)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .disabled(!isEnabled || isLoading)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

/// Low-emphasis text button for secondary actions.
struct KhyloAuthTextButton: View {

    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(KhyloColors.textSecondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Circular back button for the top-left corner.
struct KhyloAuthBackButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(KhyloColors.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .accessibilityLabel("Back")
    }
}

// MARK: - Layout

/// Centers auth content in a readable column, scrolls when the keyboard is up.
struct KhyloAuthScaffold<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            KhyloAuthBackground()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        content()
                    }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}
