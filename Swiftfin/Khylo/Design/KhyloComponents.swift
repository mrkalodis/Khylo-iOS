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

// MARK: - Button Style

public struct KhyloScaleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Primary Button

public struct KhyloPrimaryButton: View {
    public let title: String
    public let icon: String?
    public let isLoading: Bool
    public let isEnabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: KhyloSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(KhyloColors.textPrimary)
                        .scaleEffect(0.9)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(title)
                        .font(KhyloTypography.headline)
                }
            }
            .foregroundColor(KhyloColors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.md, style: .continuous)
                    .fill(isEnabled ? KhyloColors.accent : KhyloColors.accentDim.opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled || isLoading)
        .buttonStyle(KhyloScaleButtonStyle())
    }
}

// MARK: - Secondary Button

public struct KhyloSecondaryButton: View {
    public let title: String
    public let icon: String?
    public let isEnabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: KhyloSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(KhyloTypography.headline)
            }
            .foregroundColor(isEnabled ? KhyloColors.textPrimary : KhyloColors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.md, style: .continuous)
                    .fill(KhyloColors.surfaceElevated.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.md, style: .continuous)
                    .stroke(KhyloColors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .buttonStyle(KhyloScaleButtonStyle())
    }
}

// MARK: - Badge

public struct KhyloBadge: View {
    public enum Style {
        case standard
        case accent
        case outline
    }

    public let text: String
    public let style: Style

    public init(_ text: String, style: Style = .standard) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text.uppercased())
            .font(KhyloTypography.badge)
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.xs, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.xs, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var textColor: Color {
        switch style {
        case .standard: return KhyloColors.textSecondary
        case .accent: return KhyloColors.textPrimary
        case .outline: return KhyloColors.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard: return KhyloColors.surfaceElevated.opacity(0.9)
        case .accent: return KhyloColors.accent
        case .outline: return Color.clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard: return KhyloColors.border.opacity(0.6)
        case .accent: return Color.clear
        case .outline: return KhyloColors.textTertiary
        }
    }
}

// MARK: - Progress Bar

public struct KhyloProgressBar: View {
    public let progress: Double
    public let height: CGFloat
    public let trackColor: Color
    public let fillColor: Color

    public init(
        progress: Double,
        height: CGFloat = 3,
        trackColor: Color = Color.white.opacity(0.18),
        fillColor: Color = KhyloColors.accent
    ) {
        self.progress = max(0, min(1, progress))
        self.height = height
        self.trackColor = trackColor
        self.fillColor = fillColor
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(height: height)

                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, proxy.size.width * CGFloat(progress)), height: height)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Loading View

public struct KhyloLoadingView: View {
    public let message: String?

    public init(_ message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: KhyloSpacing.md) {
            ProgressView()
                .tint(KhyloColors.accent)
                .scaleEffect(1.2)

            if let message {
                Text(message)
                    .font(KhyloTypography.subheadline)
                    .foregroundColor(KhyloColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Toast Modifier

public struct KhyloToastModifier: ViewModifier {
    @Binding public var isPresented: Bool
    public let message: String
    public let icon: String?
    public let duration: TimeInterval

    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if isPresented {
                VStack {
                    HStack(spacing: KhyloSpacing.sm) {
                        if let icon {
                            Image(systemName: icon)
                                .foregroundColor(KhyloColors.accent)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Text(message)
                            .font(KhyloTypography.bodyMedium)
                            .foregroundColor(KhyloColors.textPrimary)
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.vertical, KhyloSpacing.md)
                    .background(
                        Capsule()
                            .fill(KhyloColors.surfaceElevated)
                            .overlay(
                                Capsule()
                                    .stroke(KhyloColors.border, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
                    )
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                    }

                    Spacer()
                }
                .zIndex(999)
                .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }
}

public extension View {
    func khyloToast(
        isPresented: Binding<Bool>,
        message: String,
        icon: String? = nil,
        duration: TimeInterval = 2.5
    ) -> some View {
        modifier(KhyloToastModifier(
            isPresented: isPresented,
            message: message,
            icon: icon,
            duration: duration
        ))
    }
}

// MARK: - Gradient Overlay

public struct KhyloGradientOverlay: View {
    public let height: CGFloat?
    public let baseColor: Color

    public init(
        height: CGFloat? = nil,
        baseColor: Color = KhyloColors.background
    ) {
        self.height = height
        self.baseColor = baseColor
    }

    public var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                baseColor.opacity(0.0),
                baseColor.opacity(0.4),
                baseColor.opacity(0.85),
                baseColor
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxHeight: height == nil ? .infinity : nil)
        .allowsHitTesting(false)
    }
}
