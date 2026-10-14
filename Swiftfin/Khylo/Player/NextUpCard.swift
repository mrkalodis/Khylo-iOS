//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Next Up Card View

public struct NextUpCard: View {
    public let nextEpisode: KhyloMediaItem
    public let totalCountdownSeconds: Int
    public let onPlayNext: () -> Void
    public let onDismiss: () -> Void

    @State private var remainingSeconds: Int
    @State private var timerActive: Bool = true
    @State private var timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(
        nextEpisode: KhyloMediaItem,
        countdownSeconds: Int = 10,
        onPlayNext: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.nextEpisode = nextEpisode
        self.totalCountdownSeconds = countdownSeconds
        self._remainingSeconds = State(initialValue: countdownSeconds)
        self.onPlayNext = onPlayNext
        self.onDismiss = onDismiss
    }

    private var progress: Double {
        guard totalCountdownSeconds > 0 else { return 0 }
        return Double(totalCountdownSeconds - remainingSeconds) / Double(totalCountdownSeconds)
    }

    public var body: some View {
        HStack(spacing: 14) {
            NextUpThumbnailView(imageURL: nextEpisode.imageURL)

            NextUpEpisodeDetailsView(
                name: nextEpisode.name,
                subtitle: nextEpisode.subtitle,
                timerActive: timerActive,
                remainingSeconds: remainingSeconds
            )

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                NextUpCountdownPlayButton(progress: progress) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    timerActive = false
                    onPlayNext()
                }

                NextUpDismissButton {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    timerActive = false
                    onDismiss()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 440)
        .background(cardBackground)
        .onReceive(timer) { _ in
            guard timerActive else { return }
            if remainingSeconds > 1 {
                remainingSeconds -= 1
            } else {
                remainingSeconds = 0
                timerActive = false
                if KhyloPreferences.autoPlayNextEpisode {
                    onPlayNext()
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: KhyloRadius.md)
            .fill(KhyloColors.surface.opacity(0.92))
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.md)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Subviews

private struct NextUpThumbnailView: View {
    let imageURL: URL?

    var body: some View {
        ZStack {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } else {
                        thumbnailFallback
                    }
                }
            } else {
                thumbnailFallback
            }

            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: 1)
                )
        }
        .frame(width: 120, height: 68)
        .clipped()
        .cornerRadius(KhyloRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: KhyloRadius.sm)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var thumbnailFallback: some View {
        ZStack {
            KhyloColors.surfaceElevated
            Image(systemName: "tv")
                .font(.system(size: 20))
                .foregroundColor(KhyloColors.textTertiary)
        }
    }
}

private struct NextUpEpisodeDetailsView: View {
    let name: String
    let subtitle: String?
    let timerActive: Bool
    let remainingSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("NEXT UP")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KhyloColors.accent.opacity(0.18))
                    .cornerRadius(4)

                if timerActive {
                    Text("\(remainingSeconds)s")
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textTertiary)
                }
            }

            Text(name)
                .font(KhyloTypography.bodyMedium)
                .foregroundColor(KhyloColors.textPrimary)
                .lineLimit(1)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct NextUpCountdownPlayButton: View {
    let progress: Double
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        KhyloColors.accent,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: progress)

                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(KhyloColors.surfaceElevated)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct NextUpDismissButton: View {
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(KhyloColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(KhyloColors.surfaceElevated.opacity(0.6))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
