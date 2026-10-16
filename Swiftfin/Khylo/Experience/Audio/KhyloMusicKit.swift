//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import CoreImage
import CoreImage.CIFilterBuiltins
import JellyfinAPI
import Nuke
import SwiftUI

// Shared pieces for the music screens: artwork colours, artist images and
// the round artist avatar.

// MARK: - Artwork colour

/// The dominant colour of a piece of artwork, darkened enough for white text,
/// used to tint album, artist and Now Playing backgrounds.
@MainActor
enum KhyloArtColor {

    private static var cache: [URL: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func color(for url: URL?) async -> Color? {
        guard let url else { return nil }
        if let cached = cache[url] { return cached }
        guard let image = try? await ImagePipeline.shared.image(for: url),
              let input = CIImage(image: image)
        else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let color = Color(
            hue: hue,
            saturation: min(0.75, saturation * 1.3 + 0.08),
            brightness: min(0.5, max(0.26, brightness * 0.8))
        )
        cache[url] = color
        return color
    }
}

/// A colour wash from the top of the screen into the canvas.
struct KhyloTintedBackdrop: View {
    let color: Color?
    var height: CGFloat = 520

    var body: some View {
        ZStack(alignment: .top) {
            KhyloStyle.canvas
            LinearGradient(
                colors: [(color ?? Color.white.opacity(0.08)), KhyloStyle.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: color)
    }
}

// MARK: - Artist images

/// Finds the best image for an artist: their own photo or backdrop when the
/// server has one, otherwise the cover of their newest album.
@MainActor
final class KhyloArtistArt {

    static let shared = KhyloArtistArt()

    private var cache: [String: URL?] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]

    /// Synchronous answer when the artist carries its own image (no request needed).
    static func ownImage(for artist: BaseItemDto, width: CGFloat) -> URL? {
        guard let id = artist.id else { return nil }
        if let tag = artist.imageTags?["Primary"] {
            return KhyloArtwork.url(itemID: id, type: .primary, tag: tag, width: width)
        }
        if let tag = artist.backdropImageTags?.first {
            return KhyloArtwork.url(itemID: id, type: .backdrop, tag: tag, width: width)
        }
        return nil
    }

    func image(for artist: BaseItemDto, width: CGFloat) async -> URL? {
        if let own = Self.ownImage(for: artist, width: width) { return own }
        guard let id = artist.id else { return nil }
        if let cached = cache[id] { return cached }
        if let task = inFlight[id] { return await task.value }

        let task = Task<URL?, Never> {
            let albums = try? await KhyloAPI.items(
                types: [.musicAlbum],
                sortBy: [.productionYear, .sortName],
                sortOrder: .descending,
                albumArtistIDs: [id],
                limit: 6
            )
            let withArt = albums?.items.first { $0.imageTags?["Primary"] != nil }
            return withArt.flatMap { KhyloArtwork.url(for: $0, style: .square, width: width) }
        }
        inFlight[id] = task
        let url = await task.value
        inFlight[id] = nil
        cache[id] = url
        return url
    }
}

/// Round artist image, filled in from their albums when there's no photo.
struct KhyloArtistAvatar: View {
    let artist: BaseItemDto
    var size: CGFloat = 120

    @State private var url: URL?

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
            )
            if let url {
                KhyloImage(url: url, showsPlaceholder: false)
                    .clipShape(Circle())
                    .transition(.opacity)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: artist.id) {
            url = KhyloArtistArt.ownImage(for: artist, width: size * 2)
            if url == nil {
                let found = await KhyloArtistArt.shared.image(for: artist, width: size * 2)
                withAnimation(.easeOut(duration: 0.25)) { url = found }
            }
        }
    }

    private var initials: String {
        let words = (artist.name ?? "").split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Artist cell for grids and shelves: round image with the name centred under it.
struct KhyloArtistCell: View {
    let artist: BaseItemDto
    var size: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            KhyloArtistAvatar(artist: artist, size: size)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            Text(artist.name ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: size)
            Text("Artist")
                .font(.system(size: 12))
                .foregroundColor(KhyloStyle.tertiaryText)
        }
    }
}

// MARK: - Formatting

extension BaseItemDto {
    /// "Album · 2019", "Single · 2021", "EP · 2020"
    var khyloAlbumKind: String {
        let tracks = childCount ?? 0
        let kind = tracks > 0 && tracks <= 2 ? "Single" : (tracks > 2 && tracks <= 6 ? "EP" : "Album")
        return [kind, productionYear.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    var khyloIsSingleOrEP: Bool {
        let tracks = childCount ?? 0
        return tracks > 0 && tracks <= 6
    }

    var khyloArtistLine: String {
        if let artists = albumArtists?.compactMap(\.name), !artists.isEmpty { return artists.joined(separator: ", ") }
        if let artists, !artists.isEmpty { return artists.joined(separator: ", ") }
        return albumArtist ?? ""
    }
}
