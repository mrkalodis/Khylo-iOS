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

// MARK: - Unplayed Badge

public struct KhyloUnplayedBadge: View {
    public let size: CGFloat

    public init(size: CGFloat = 8) {
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(KhyloColors.accent)
            .frame(width: size, height: size)
            .shadow(color: KhyloColors.accent.opacity(0.6), radius: 3, x: 0, y: 0)
    }
}

// MARK: - Card Media Artwork

private struct CardMediaArtwork: View {
    let url: URL?
    let aspectRatio: CGFloat
    let placeholderSystemImage: String
    let progress: Double?
    let isUnplayed: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            placeholderView
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        case .failure:
                            placeholderView
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }

                // Progress Bar at bottom if progress > 0
                if let progress, progress > 0.0 {
                    KhyloProgressBar(
                        progress: progress,
                        height: 3.5,
                        trackColor: Color.black.opacity(0.55),
                        fillColor: KhyloColors.accent
                    )
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }

                // Unplayed badge at top right
                if isUnplayed {
                    VStack {
                        HStack {
                            Spacer()
                            KhyloUnplayedBadge(size: 8)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(KhyloColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: KhyloRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KhyloRadius.md, style: .continuous)
                .stroke(KhyloColors.border.opacity(0.6), lineWidth: 1)
        )
    }

    private var placeholderView: some View {
        ZStack {
            KhyloColors.surfaceElevated
            Image(systemName: placeholderSystemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(KhyloColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Poster Card (2:3)

public struct KhyloPosterCard: View {
    public let imageURL: URL?
    public let title: String
    public let subtitle: String?
    public let progress: Double?
    public let isUnplayed: Bool
    public let width: CGFloat?
    public let onTap: (() -> Void)?
    public let onLongPress: (() -> Void)?

    public init(
        imageURL: URL?,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        isUnplayed: Bool = false,
        width: CGFloat? = 140,
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.isUnplayed = isUnplayed
        self.width = width
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
            CardMediaArtwork(
                url: imageURL,
                aspectRatio: 2.0 / 3.0,
                placeholderSystemImage: "film",
                progress: progress,
                isUnplayed: isUnplayed
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onLongPress?()
        }
    }
}

// MARK: - Wide Card (16:9)

public struct KhyloWideCard: View {
    public let imageURL: URL?
    public let title: String
    public let subtitle: String?
    public let progress: Double?
    public let isUnplayed: Bool
    public let width: CGFloat?
    public let onTap: (() -> Void)?
    public let onLongPress: (() -> Void)?

    public init(
        imageURL: URL?,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        isUnplayed: Bool = false,
        width: CGFloat? = 260,
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.isUnplayed = isUnplayed
        self.width = width
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
            CardMediaArtwork(
                url: imageURL,
                aspectRatio: 16.0 / 9.0,
                placeholderSystemImage: "tv",
                progress: progress,
                isUnplayed: isUnplayed
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onLongPress?()
        }
    }
}

// MARK: - Square Card (1:1)

public struct KhyloSquareCard: View {
    public let imageURL: URL?
    public let title: String
    public let subtitle: String?
    public let progress: Double?
    public let isUnplayed: Bool
    public let width: CGFloat?
    public let onTap: (() -> Void)?
    public let onLongPress: (() -> Void)?

    public init(
        imageURL: URL?,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        isUnplayed: Bool = false,
        width: CGFloat? = 150,
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.isUnplayed = isUnplayed
        self.width = width
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
            CardMediaArtwork(
                url: imageURL,
                aspectRatio: 1.0,
                placeholderSystemImage: "music.note",
                progress: progress,
                isUnplayed: isUnplayed
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onLongPress?()
        }
    }
}
