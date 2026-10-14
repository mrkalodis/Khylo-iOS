//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Reader Settings Bar Sheet

public struct ReaderSettingsBar: View {
    @Binding public var theme: ReadingTheme
    @Binding public var fontSize: ReadingFontSize
    @Binding public var isSerif: Bool
    public let onDismiss: () -> Void

    public init(
        theme: Binding<ReadingTheme>,
        fontSize: Binding<ReadingFontSize>,
        isSerif: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) {
        self._theme = theme
        self._fontSize = fontSize
        self._isSerif = isSerif
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Reader Settings")
                    .font(KhyloTypography.headline)
                    .foregroundColor(theme.textColor)

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .font(KhyloTypography.subheadlineBold)
                .foregroundColor(KhyloColors.accent)
            }

            // Theme Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("THEME")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(theme.secondaryTextColor)

                HStack(spacing: 12) {
                    ForEach(ReadingTheme.allCases) { t in
                        ThemeSelectorButton(
                            themeOption: t,
                            currentTheme: theme,
                            onSelect: { theme = t }
                        )
                    }
                }
            }

            // Font Size Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("TEXT SIZE")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(theme.secondaryTextColor)

                HStack(spacing: 8) {
                    ForEach(ReadingFontSize.allCases) { size in
                        FontSizeSelectorButton(
                            size: size,
                            currentSize: fontSize,
                            theme: theme,
                            onSelect: { fontSize = size }
                        )
                    }
                }
            }

            // Font Family Toggle (Serif vs Sans)
            VStack(alignment: .leading, spacing: 8) {
                Text("TYPOGRAPHY")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(theme.secondaryTextColor)

                HStack(spacing: 12) {
                    Button(action: {
                        isSerif = true
                    }) {
                        Text("Serif (Georgia)")
                            .font(.system(size: 15, weight: isSerif ? .bold : .regular, design: .serif))
                            .foregroundColor(isSerif ? .white : theme.textColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                    .fill(isSerif ? KhyloColors.accent : Color.gray.opacity(0.18))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        isSerif = false
                    }) {
                        Text("Sans (System)")
                            .font(.system(size: 15, weight: !isSerif ? .bold : .regular, design: .default))
                            .foregroundColor(!isSerif ? .white : theme.textColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                    .fill(!isSerif ? KhyloColors.accent : Color.gray.opacity(0.18))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: KhyloRadius.lg)
                .fill(theme.backgroundColor)
                .shadow(color: Color.black.opacity(0.5), radius: 24, x: 0, y: -6)
        )
    }
}

// MARK: - Subviews

private struct ThemeSelectorButton: View {
    let themeOption: ReadingTheme
    let currentTheme: ReadingTheme
    let onSelect: () -> Void

    private var isSelected: Bool {
        currentTheme == themeOption
    }

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(themeOption.backgroundColor)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))

                Text(themeOption.rawValue)
                    .font(isSelected ? KhyloTypography.subheadlineBold : KhyloTypography.subheadline)
                    .foregroundColor(currentTheme == .night ? .white : Color.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                    .fill(themeOption.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: KhyloRadius.sm)
                            .strokeBorder(isSelected ? KhyloColors.accent : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct FontSizeSelectorButton: View {
    let size: ReadingFontSize
    let currentSize: ReadingFontSize
    let theme: ReadingTheme
    let onSelect: () -> Void

    private var isSelected: Bool {
        currentSize == size
    }

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            Text(size.label)
                .font(.system(size: size.pointSize * 0.8, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : theme.textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: KhyloRadius.xs)
                        .fill(isSelected ? KhyloColors.accent : Color.gray.opacity(0.18))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
