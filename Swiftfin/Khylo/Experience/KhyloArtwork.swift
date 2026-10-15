//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import NukeUI
import SwiftUI

/// Picks the right artwork for an item and builds a sized image URL for it.
enum KhyloArtwork {

    enum Style {
        /// 2:3 cover art (movies, shows, books).
        case poster
        /// 16:9 still (continue watching, episodes).
        case landscape
        /// Wide background art for heroes and headers.
        case backdrop
        /// Transparent title treatment.
        case logo
        /// 1:1 art (albums, artists, channels).
        case square
    }

    static func url(for item: BaseItemDto, style: Style, width: CGFloat) -> URL? {
        guard let (itemID, type, tag) = source(for: item, style: style) else { return nil }
        return url(itemID: itemID, type: type, tag: tag, width: width)
    }

    static func url(itemID: String, type: ImageType, tag: String?, width: CGFloat) -> URL? {
        guard let client = KhyloAPI.session?.client else { return nil }
        let scale = UIScreen.main.scale
        let parameters = Paths.GetItemImageParameters(
            maxWidth: Int(width * scale),
            quality: 90,
            tag: tag,
            format: type == .logo ? .png : nil
        )
        return client.url(with: Paths.getItemImage(itemID: itemID, imageType: type.rawValue, parameters: parameters))
    }

    private static func source(for item: BaseItemDto, style: Style) -> (String, ImageType, String?)? {
        guard let id = item.id else { return nil }
        let tags = item.imageTags ?? [:]

        func own(_ type: ImageType) -> (String, ImageType, String?)? {
            tags[type.rawValue].map { (id, type, $0) }
        }

        func backdrop() -> (String, ImageType, String?)? {
            if let tag = item.backdropImageTags?.first { return (id, .backdrop, tag) }
            if let parent = item.parentBackdropItemID, let tag = item.parentBackdropImageTags?.first {
                return (parent, .backdrop, tag)
            }
            return nil
        }

        func thumb() -> (String, ImageType, String?)? {
            if let own = own(.thumb) { return own }
            if let parent = item.parentThumbItemID, let tag = item.parentThumbImageTag {
                return (parent, .thumb, tag)
            }
            return nil
        }

        switch style {
        case .poster:
            if item.type == .episode, let series = item.seriesID, let tag = item.seriesPrimaryImageTag {
                return (series, .primary, tag)
            }
            if item.type == .season, own(.primary) == nil, let series = item.seriesID, let tag = item.seriesPrimaryImageTag {
                return (series, .primary, tag)
            }
            return own(.primary)
        case .landscape:
            if item.type == .episode {
                return own(.primary) ?? thumb() ?? backdrop()
            }
            // Backdrops are clean art; thumbs often have the title printed on them.
            return backdrop() ?? thumb() ?? own(.primary)
        case .backdrop:
            return backdrop() ?? thumb() ?? own(.primary)
        case .logo:
            if let own = own(.logo) { return own }
            if let parent = item.parentLogoItemID, let tag = item.parentLogoImageTag {
                return (parent, .logo, tag)
            }
            return nil
        case .square:
            if let own = own(.primary) { return own }
            if let album = item.albumID, let tag = item.albumPrimaryImageTag {
                return (album, .primary, tag)
            }
            if let channel = item.channelID, let tag = item.channelPrimaryImageTag {
                return (channel, .primary, tag)
            }
            return nil
        }
    }
}

/// Async image with a quiet placeholder and a soft fade-in.
struct KhyloImage: View {

    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSymbol: String? = nil
    /// Off for transparent art such as title logos.
    var showsPlaceholder: Bool = true

    var body: some View {
        // The rectangle takes exactly the proposed size; the image is drawn in an
        // overlay so its own pixel size can never widen the surrounding layout.
        Rectangle()
            .fill(showsPlaceholder ? KhyloStyle.placeholder : Color.clear)
            .overlay {
                if showsPlaceholder, let placeholderSymbol {
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.18))
                }
            }
            .overlay {
                if let url {
                    LazyImage(url: url, transaction: .init(animation: .easeOut(duration: 0.25))) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                        }
                    }
                }
            }
            .clipped()
    }
}
