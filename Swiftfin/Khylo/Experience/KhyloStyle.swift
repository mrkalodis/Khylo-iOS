//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Tokens

/// Visual language for the main app: near-black canvas, white type with
/// restrained greys, the brand orange used only for progress and primary actions.
enum KhyloStyle {
    static let canvas = Color(hex: "#08090A")
    static let raised = Color(hex: "#141518")
    static let placeholder = Color(hex: "#1A1B1F")
    static let hairline = Color.white.opacity(0.08)
    static let accent = KhyloColors.accent

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.4)

    static let cardRadius: CGFloat = 10
    static let gutter: CGFloat = 20

    static func title(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .bold) }
}

// MARK: - Item helpers

extension BaseItemDto {

    /// 0...1 watch progress, nil when not started.
    var khyloProgress: Double? {
        guard let position = userData?.playbackPositionTicks, position > 0,
              let total = runTimeTicks, total > 0
        else { return nil }
        return min(1, Double(position) / Double(total))
    }

    var khyloRemaining: String? {
        guard let position = userData?.playbackPositionTicks, position > 0,
              let total = runTimeTicks, total > position
        else { return nil }
        let minutes = (total - position) / 600_000_000
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(max(minutes, 1))m left"
    }

    var khyloRuntime: String? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        let minutes = ticks / 600_000_000
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// "S2 · E5" for episodes.
    var khyloEpisodeLabel: String? {
        guard type == .episode else { return nil }
        let season = parentIndexNumber.map { "S\($0)" }
        let episode = indexNumber.map { "E\($0)" }
        let parts = [season, episode].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Main line on a card: the show name for episodes, otherwise the title.
    var khyloCardTitle: String {
        if type == .episode, let seriesName { return seriesName }
        return name ?? ""
    }

    /// Secondary line on a card.
    var khyloCardSubtitle: String? {
        switch type {
        case .episode:
            let label = khyloEpisodeLabel
            if let label, let name { return "\(label)  \(name)" }
            return label ?? name
        case .series:
            if let year = productionYear {
                return status == "Continuing" ? "\(year) – Present" : "\(year)"
            }
            return nil
        case .musicAlbum:
            return albumArtist ?? artists?.first
        case .audio:
            return artists?.joined(separator: ", ") ?? album
        default:
            return productionYear.map(String.init)
        }
    }

    var khyloIsPlayed: Bool { userData?.isPlayed ?? false }
    var khyloIsFavorite: Bool { userData?.isFavorite ?? false }
}

// MARK: - Progress

struct KhyloProgressLine: View {

    let progress: Double

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.25))
            .frame(height: 3)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(KhyloStyle.accent)
                        .frame(width: max(4, proxy.size.width * progress))
                }
            }
    }
}

// MARK: - Cards

/// 2:3 cover with title below.
struct KhyloCoverCard: View {

    let item: BaseItemDto
    var width: CGFloat = 124
    var showsTitle: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = KhyloArtwork.url(for: item, style: .poster, width: width) {
                        KhyloImage(url: url, placeholderSymbol: placeholderSymbol)
                    } else if item.type == .book || item.type == .audioBook {
                        KhyloGeneratedCover(name: item.name ?? "", width: width)
                    } else {
                        KhyloImage(url: nil, placeholderSymbol: placeholderSymbol)
                    }
                }
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: KhyloStyle.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KhyloStyle.cardRadius, style: .continuous)
                        .strokeBorder(KhyloStyle.hairline, lineWidth: 0.5)
                )

                if item.khyloIsPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, KhyloStyle.accent)
                        .padding(6)
                } else if let unplayed = item.userData?.unplayedItemCount, unplayed > 0, item.type == .series {
                    Text("\(unplayed)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(KhyloStyle.accent))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = item.khyloProgress {
                    KhyloProgressLine(progress: progress)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }

            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(KhyloStyle.primaryText)
                        .lineLimit(1)
                    if let subtitle = item.khyloCardSubtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(KhyloStyle.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
    }

    private var placeholderSymbol: String {
        switch item.type {
        case .book: "book.closed"
        case .audioBook: "headphones"
        case .series, .season, .episode: "tv"
        default: "film"
        }
    }
}

/// 16:9 still with progress and two lines of text.
struct KhyloLandscapeCard: View {

    let item: BaseItemDto
    var width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            KhyloImage(
                url: KhyloArtwork.url(for: item, style: .landscape, width: width),
                placeholderSymbol: "play.rectangle"
            )
            .frame(width: width, height: width * 9 / 16)
            .overlay {
                if let progress = item.khyloProgress {
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        KhyloProgressLine(progress: progress)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: KhyloStyle.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KhyloStyle.cardRadius, style: .continuous)
                    .strokeBorder(KhyloStyle.hairline, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.khyloCardTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KhyloStyle.primaryText)
                    .lineLimit(1)
                Text(item.khyloRemaining ?? item.khyloCardSubtitle ?? item.khyloRuntime ?? " ")
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

/// 1:1 art for albums, artists and channels.
struct KhyloTileCard: View {

    let item: BaseItemDto
    var width: CGFloat = 150
    var isCircular: Bool = false

    var body: some View {
        VStack(alignment: isCircular ? .center : .leading, spacing: 8) {
            KhyloImage(
                url: KhyloArtwork.url(for: item, style: .square, width: width),
                placeholderSymbol: isCircular ? "music.mic" : "music.note"
            )
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: isCircular ? width / 2 : KhyloStyle.cardRadius, style: .continuous))

            VStack(alignment: isCircular ? .center : .leading, spacing: 2) {
                Text(item.name ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(KhyloStyle.primaryText)
                    .lineLimit(1)
                if !isCircular, let subtitle = item.khyloCardSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: isCircular ? .center : .leading)
        }
    }
}

// MARK: - Shelf

/// Titled horizontal row.
struct KhyloShelf<Content: View>: View {

    let title: String
    var action: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(KhyloStyle.primaryText)
                if let action {
                    Button(action: action) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, KhyloStyle.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    content()
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Buttons

/// Large white action button, as used for Play on detail pages.
struct KhyloPlayButton: View {

    let title: String
    var systemImage: String = "play.fill"
    var progress: Double? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if let progress {
                    Capsule()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 44, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.black).frame(width: 44 * progress, height: 4)
                        }
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }
}

/// Round icon button with a caption, for secondary actions.
struct KhyloIconAction: View {

    let title: String
    let systemImage: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(isActive ? KhyloStyle.accent : .white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(KhyloStyle.secondaryText)
            }
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }
}

// MARK: - States

struct KhyloLoadingState: View {
    var body: some View {
        ProgressView()
            .tint(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct KhyloEmptyState: View {

    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .foregroundColor(KhyloStyle.tertiaryText)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(KhyloStyle.primaryText)
            if let message {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(KhyloStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KhyloStyle.accent)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Generated book cover

/// A typeset cover for books without artwork: a deep color picked from the
/// title, the title in a serif face and the author beneath a fine rule.
struct KhyloGeneratedCover: View {

    let name: String
    let width: CGFloat

    private static let palettes: [(String, String)] = [
        ("#1F3A5F", "#0F1C2E"), ("#5B2333", "#2B0F18"), ("#2F4F3A", "#14251A"),
        ("#4A3B2A", "#211A12"), ("#3B2F5C", "#1A142B"), ("#5E3A1A", "#2A190B"),
        ("#20434A", "#0E1F22"), ("#4B2E39", "#22141A"), ("#383838", "#161616"),
    ]

    private var parts: (title: String, author: String?) { Self.parse(name) }

    /// "Title - Author" or "Title by Author" → parts. Filenames often use "_" for ":".
    static func parse(_ name: String) -> (title: String, author: String?) {
        func tidy(_ text: Substring) -> String {
            text.replacingOccurrences(of: "_ ", with: ": ")
                .replacingOccurrences(of: "_", with: ": ")
                .trimmingCharacters(in: .whitespaces)
        }
        for separator in [" - ", " by ", " – "] {
            if let range = name.range(of: separator, options: .caseInsensitive) {
                let title = tidy(name[..<range.lowerBound])
                let author = tidy(name[range.upperBound...])
                if !title.isEmpty, !author.isEmpty { return (title, author) }
            }
        }
        return (tidy(name[...]), nil)
    }

    private var palette: (String, String) {
        // Stable across launches (unlike hashValue).
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return Self.palettes[sum % Self.palettes.count]
    }

    var body: some View {
        let scale = width / 120
        ZStack {
            LinearGradient(
                colors: [Color(hex: palette.0), Color(hex: palette.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            // Spine shading on the left edge.
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 8 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8 * scale) {
                Spacer(minLength: 0)
                Text(parts.title)
                    .font(.system(size: 15 * scale, weight: .semibold, design: .serif))
                    .foregroundColor(Color(hex: "#F3E9D6"))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.6)
                Rectangle()
                    .fill(Color(hex: "#C9A86A").opacity(0.8))
                    .frame(width: 24 * scale, height: 1)
                if let author = parts.author {
                    Text(author.uppercased())
                        .font(.system(size: 8 * scale, weight: .semibold))
                        .tracking(1.2 * scale)
                        .foregroundColor(Color(hex: "#C9A86A"))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 16 * scale)
        }
    }
}

// MARK: - Continue card

/// Streaming-service style card for Continue Watching and Up Next: the still
/// with the title art laid over it, a hairline progress bar flush along the
/// bottom edge, and a single quiet caption underneath.
struct KhyloContinueCard: View {

    let item: BaseItemDto
    var width: CGFloat = 272
    var showsProgress = true

    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                KhyloImage(
                    url: KhyloArtwork.url(for: item, style: .landscape, width: width),
                    placeholderSymbol: "play.rectangle"
                )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.75), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                titleArt
                    .padding(.horizontal, 12)
                    .padding(.bottom, showsProgress && item.khyloProgress != nil ? 13 : 10)

                if showsProgress, let progress = item.khyloProgress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.22))
                            Rectangle().fill(KhyloStyle.accent).frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )

            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(KhyloStyle.secondaryText)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }

    @ViewBuilder
    private var titleArt: some View {
        if let logo = KhyloArtwork.url(for: item, style: .logo, width: width * 0.55) {
            KhyloImage(url: logo, contentMode: .fit, showsPlaceholder: false)
                .frame(width: width * 0.5, height: height * 0.3, alignment: .bottomLeading)
        } else {
            Text(item.khyloCardTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        }
    }

    private var caption: String {
        var parts: [String] = []
        if let episode = item.khyloEpisodeLabel {
            parts.append(episode)
        }
        if showsProgress, let remaining = item.khyloRemaining {
            parts.append(remaining)
        } else if item.type == .episode, let name = item.name {
            parts.append(name)
        } else if let runtime = item.khyloRuntime {
            parts.append(runtime)
        }
        return parts.joined(separator: " · ")
    }
}
