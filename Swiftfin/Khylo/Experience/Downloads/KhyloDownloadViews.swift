//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Download button

/// Download, progress, and remove, for a title or a whole show, season, album,
/// playlist or audiobook. Hidden when the server doesn't allow downloads.
struct KhyloDownloadButton: View {

    enum Style {
        /// Round icon with a label under it (detail pages).
        case labeled
        /// Icon only, sized for a header row (albums, playlists).
        case icon
        /// Small icon for list rows (episodes).
        case compact
    }

    let item: BaseItemDto
    var style: Style = .labeled
    /// An audiobook's parts, when the screen already has them.
    var audiobookParts: [BaseItemDto]? = nil

    @ObservedObject private var downloads = KhyloDownloads.shared
    @ObservedObject private var live = KhyloDownloadProgress.shared
    @ObservedObject private var network = KhyloNetwork.shared
    @State private var isConfirming = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    private var status: KhyloDownloadStatus {
        isStarting ? .downloading : downloads.status(for: item)
    }

    private var progress: Double {
        downloads.progress(for: item, live: live.fractions)
    }

    private var isGroup: Bool {
        [.series, .season, .musicAlbum, .playlist, .folder].contains(item.type) || (audiobookParts?.count ?? 0) > 1
    }

    var body: some View {
        if KhyloDownloads.isAllowed {
            Button(action: tap) { label }
                .buttonStyle(KhyloScaleButtonStyle())
                .accessibilityLabel(title)
                .confirmationDialog(
                    status == .done ? "Remove this download?" : "Stop downloading?",
                    isPresented: $isConfirming,
                    titleVisibility: .visible
                ) {
                    if status == .done, isGroup {
                        Button("Download Anything Missing") { start() }
                    }
                    Button(status == .done ? "Remove Download" : "Stop Download", role: .destructive) {
                        downloads.delete(item)
                    }
                } message: {
                    Text(status == .done
                        ? "It'll stream instead, and you can download it again any time."
                        : "What's downloaded so far will be removed.")
                }
                .alert("Can't Download", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                    Button("OK") { errorMessage = nil }
                } message: { message in
                    Text(message)
                }
        }
    }

    private var title: String {
        switch status {
        case .none: "Download"
        case .downloading:
            if KhyloDownloadSettings.wifiOnly, !network.isOnWiFi { "Waiting for Wi-Fi" }
            else if progress > 0 { "\(Int(progress * 100))%" }
            else { "Downloading" }
        case .done: "Downloaded"
        case .failed: "Try Again"
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .labeled:
            VStack(spacing: 6) {
                KhyloDownloadGlyph(status: status, progress: progress, size: 19)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(KhyloStyle.secondaryText)
                    .lineLimit(1)
            }
        case .icon:
            KhyloDownloadGlyph(status: status, progress: progress, size: 22)
                .frame(width: 30, height: 30)
        case .compact:
            KhyloDownloadGlyph(status: status, progress: progress, size: 18)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
    }

    private func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch status {
        case .none, .failed: start()
        case .downloading, .done: isConfirming = true
        }
    }

    private func start() {
        isStarting = true
        Task {
            do {
                if let parts = audiobookParts {
                    try await downloads.downloadAudiobook(book: item, parts: parts)
                } else {
                    try await downloads.download(item)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isStarting = false
        }
    }
}

/// The download icon: an arrow, a filling ring while downloading, a filled
/// arrow when it's on the phone.
struct KhyloDownloadGlyph: View {

    let status: KhyloDownloadStatus
    let progress: Double
    let size: CGFloat

    var body: some View {
        switch status {
        case .none:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        case .downloading:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(progress, 0.03))
                    .stroke(KhyloStyle.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: progress)
                Image(systemName: "stop.fill")
                    .font(.system(size: size * 0.32))
                    .foregroundColor(.white)
            }
            .frame(width: size * 1.05, height: size * 1.05)
        case .done:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: size, weight: .medium))
                .foregroundColor(KhyloStyle.accent)
        case .failed:
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

// MARK: - Downloads page

/// Everything on the phone: what's downloading, movies, shows, music,
/// audiobooks and books, with the space they use.
struct KhyloDownloadsScreen<Header: View>: View {

    @ViewBuilder let header: () -> Header

    @ObservedObject private var downloads = KhyloDownloads.shared
    @ObservedObject private var network = KhyloNetwork.shared
    @Router private var router
    @State private var isConfirmingDeleteAll = false
    @State private var playError: String?

    private var finished: [KhyloDownload] {
        downloads.downloads.values.filter { $0.state == .done }
    }

    private var movies: [KhyloDownload] {
        finished.filter { $0.kind == .video && $0.item.type != .episode }.sorted { name($0.item) < name($1.item) }
    }

    private func groups(_ kind: KhyloDownload.Kind) -> [KhyloDownloadGroup] {
        downloads.groups.values
            .filter { group in group.kind == kind && downloads.members(of: group.id).contains { $0.state == .done } }
            .sorted { name($0.item) < name($1.item) }
    }

    private func loose(_ kind: KhyloDownload.Kind) -> [KhyloDownload] {
        finished.filter { $0.kind == kind && $0.groupIDs.isEmpty && !($0.kind == .video) }
            .sorted { name($0.item) < name($1.item) }
    }

    private func name(_ item: BaseItemDto) -> String {
        (item.sortName ?? item.name ?? "").lowercased()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header()

                if !network.isOnline {
                    offlineBanner
                }

                storageCard

                if downloads.downloads.isEmpty {
                    KhyloEmptyState(
                        systemImage: "arrow.down.circle",
                        title: "No downloads yet",
                        message: "Tap the download button on a movie, show, album, playlist, audiobook or book to keep it on your iPhone and play it anywhere, even without a connection."
                    )
                    .frame(height: 320)
                } else {
                    sections
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .alert("Can't Play", isPresented: .constant(playError != nil), presenting: playError) { _ in
            Button("OK") { playError = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog("Delete all downloads?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All Downloads", role: .destructive) { downloads.deleteAll() }
        } message: {
            Text("Everything downloaded to this iPhone will be removed. Your progress is kept.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sections: some View {
        let active = downloads.active
        if !active.isEmpty {
            section("Downloading") {
                ForEach(active) { download in
                    KhyloActiveDownloadRow(download: download)
                }
            }
        }

        if !movies.isEmpty {
            section("Movies") {
                ForEach(movies) { download in
                    KhyloDownloadRow(
                        artwork: downloads.artworkURL(for: download.id),
                        shape: .poster,
                        title: download.item.name ?? "",
                        subtitle: subtitle(download.item, bytes: download.bytes, quality: download.quality),
                        progress: download.item.khyloProgress,
                        onDelete: { downloads.delete(itemID: download.id) }
                    ) {
                        play(download.item)
                    }
                }
            }
        }

        let shows = groups(.video)
        if !shows.isEmpty {
            section("TV Shows") {
                ForEach(shows) { group in
                    let count = downloads.members(of: group.id).filter { $0.state == .done }.count
                    KhyloDownloadRow(
                        artwork: downloads.groupArtworkURL(group.id),
                        shape: .poster,
                        title: group.item.name ?? "",
                        subtitle: "\(count) episode\(count == 1 ? "" : "s") · \(size(downloads.bytes(of: group)))",
                        showsChevron: true,
                        onDelete: { downloads.deleteGroup(group.id) }
                    ) {
                        router.route(to: NavigationRoute(id: "khylo-downloads-show-\(group.id)") {
                            KhyloDownloadedShowScreen(groupID: group.id)
                        })
                    }
                }
            }
        }

        let music = groups(.music)
        let songs = loose(.music)
        if !music.isEmpty || !songs.isEmpty {
            section("Music") {
                ForEach(music) { group in
                    let count = downloads.members(of: group.id).filter { $0.state == .done }.count
                    KhyloDownloadRow(
                        artwork: downloads.groupArtworkURL(group.id),
                        shape: .square,
                        title: group.item.name ?? "",
                        subtitle: [group.item.type == .playlist ? "Playlist" : group.item.khyloArtistLine,
                                   "\(count) song\(count == 1 ? "" : "s")", size(downloads.bytes(of: group))]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                        showsChevron: true,
                        onDelete: { downloads.deleteGroup(group.id) }
                    ) {
                        router.route(to: NavigationRoute(id: "khylo-downloads-album-\(group.id)") {
                            KhyloDownloadedAlbumScreen(groupID: group.id)
                        })
                    }
                }
                ForEach(songs) { download in
                    KhyloDownloadRow(
                        artwork: downloads.artworkURL(for: download.id),
                        shape: .square,
                        title: download.item.name ?? "",
                        subtitle: [download.item.khyloArtistLine, size(download.bytes)].compactMap { $0 }.joined(separator: " · "),
                        onDelete: { downloads.delete(itemID: download.id) }
                    ) {
                        KhyloAudioPlayer.shared.play([download.item], kind: .music, startTicks: 0)
                    }
                }
            }
        }

        let audiobooks = groups(.audiobook)
        let singleAudiobooks = loose(.audiobook)
        if !audiobooks.isEmpty || !singleAudiobooks.isEmpty {
            section("Audiobooks") {
                ForEach(audiobooks) { group in
                    KhyloDownloadRow(
                        artwork: downloads.groupArtworkURL(group.id),
                        shape: .square,
                        title: KhyloAudiobook.cleanTitle(group.item.name ?? "").title,
                        subtitle: size(downloads.bytes(of: group)),
                        onDelete: { downloads.deleteGroup(group.id) }
                    ) {
                        let parts = downloads.withLocalProgress(
                            downloads.members(of: group.id).filter { $0.state == .done }.map(\.item)
                        )
                        guard !parts.isEmpty else { return }
                        KhyloAudiobook.play(book: group.item, parts: parts)
                    }
                }
                ForEach(singleAudiobooks) { download in
                    KhyloDownloadRow(
                        artwork: downloads.artworkURL(for: download.id),
                        shape: .square,
                        title: KhyloAudiobook.cleanTitle(download.item.name ?? "").title,
                        subtitle: size(download.bytes),
                        progress: download.item.khyloProgress,
                        onDelete: { downloads.delete(itemID: download.id) }
                    ) {
                        KhyloAudiobook.play(book: download.item, parts: downloads.withLocalProgress([download.item]))
                    }
                }
            }
        }

        let books = loose(.book)
        if !books.isEmpty {
            section("Books") {
                ForEach(books) { download in
                    KhyloDownloadRow(
                        artwork: downloads.artworkURL(for: download.id),
                        shape: .poster,
                        title: KhyloGeneratedCover.parse(download.item.name ?? "").title,
                        subtitle: [KhyloGeneratedCover.parse(download.item.name ?? "").author, size(download.bytes)]
                            .compactMap { $0 }.joined(separator: " · "),
                        onDelete: { downloads.delete(itemID: download.id) }
                    ) {
                        router.route(to: .khyloReader(download.item))
                    }
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(KhyloStyle.title(21))
                .foregroundColor(.white)
                .padding(.horizontal, KhyloStyle.gutter)
            VStack(spacing: 2) {
                content()
            }
        }
    }

    // MARK: Pieces

    private var offlineBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(KhyloStyle.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("Your downloads are ready to play. Progress syncs when you're back online.")
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KhyloStyle.raised))
        .padding(.horizontal, KhyloStyle.gutter)
    }

    private var storageCard: some View {
        let used = downloads.usedBytes
        let free = downloads.freeBytes
        let total = max(used + free, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Storage")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if downloads.hasDownloads {
                    Menu {
                        Button("Delete All Downloads", systemImage: "trash", role: .destructive) {
                            isConfirmingDeleteAll = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(KhyloStyle.secondaryText)
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(KhyloStyle.accent)
                        .frame(width: max(used > 0 ? 6 : 0, geometry.size.width * CGFloat(Double(used) / Double(total))))
                }
            }
            .frame(height: 8)

            HStack {
                Label("Khylo \(size(used))", systemImage: "circle.fill")
                    .labelStyle(KhyloDotLabelStyle(color: KhyloStyle.accent))
                Spacer()
                Text("\(size(free)) free")
            }
            .font(.system(size: 13))
            .foregroundColor(KhyloStyle.secondaryText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KhyloStyle.raised))
        .padding(.horizontal, KhyloStyle.gutter)
    }

    private func subtitle(_ item: BaseItemDto, bytes: Int64, quality: KhyloDownloadQuality) -> String {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        if let runtime = item.khyloRuntime { parts.append(runtime) }
        parts.append(size(bytes))
        if quality != .original { parts.append(quality.title) }
        return parts.joined(separator: " · ")
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func play(_ item: BaseItemDto) {
        Task {
            do {
                try await KhyloPlayback.play(item, router: router)
            } catch {
                playError = error.localizedDescription
            }
        }
    }
}

private struct KhyloDotLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

// MARK: - Rows

/// A downloaded title: artwork, name, details, and a menu to remove it.
struct KhyloDownloadRow: View {

    enum Shape {
        case poster
        case square
        case landscape

        var size: CGSize {
            switch self {
            case .poster: CGSize(width: 52, height: 78)
            case .square: CGSize(width: 64, height: 64)
            case .landscape: CGSize(width: 112, height: 63)
            }
        }
    }

    let artwork: URL?
    let shape: Shape
    let title: String
    let subtitle: String
    var progress: Double? = nil
    var isPlayed = false
    var showsChevron = false
    let onDelete: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                KhyloImage(url: artwork, placeholderSymbol: placeholder)
                    .frame(width: shape.size.width, height: shape.size.height)
                    .overlay(alignment: .bottom) {
                        if let progress {
                            KhyloProgressLine(progress: progress)
                                .padding(.horizontal, 5)
                                .padding(.bottom, 5)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: shape == .square ? 6 : 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if isPlayed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(KhyloStyle.accent)
                        }
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.tertiaryText)
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(KhyloStyle.tertiaryText)
                }

                Menu {
                    Button("Remove Download", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.leading, KhyloStyle.gutter)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Download", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var placeholder: String {
        switch shape {
        case .poster: "film"
        case .square: "music.note"
        case .landscape: "play.rectangle"
        }
    }
}

/// A download that's on its way, waiting, or stopped with a problem.
private struct KhyloActiveDownloadRow: View {

    let download: KhyloDownload

    @ObservedObject private var live = KhyloDownloadProgress.shared
    @ObservedObject private var network = KhyloNetwork.shared
    private var downloads: KhyloDownloads { .shared }

    private var fraction: Double { live.fractions[download.id] ?? 0 }

    private var status: String {
        if download.state == .failed { return download.message ?? "Didn't finish" }
        if KhyloDownloadSettings.wifiOnly, !network.isOnWiFi { return "Waiting for Wi-Fi" }
        if !network.isOnline { return "Waiting for a connection" }
        if fraction <= 0 { return "Waiting" }
        let expected = ByteCountFormatter.string(fromByteCount: download.expectedBytes, countStyle: .file)
        return "\(Int(fraction * 100))% of \(expected)"
    }

    var body: some View {
        HStack(spacing: 14) {
            KhyloImage(url: downloads.artworkURL(for: download.id), placeholderSymbol: "arrow.down")
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if download.state != .failed {
                    KhyloProgressLine(progress: fraction)
                }
                Text(status)
                    .font(.system(size: 12))
                    .foregroundColor(download.state == .failed ? .orange.opacity(0.9) : KhyloStyle.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if download.state == .failed {
                Button {
                    downloads.retry(download.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .accessibilityLabel("Try again")
            }

            Button {
                downloads.delete(itemID: download.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(KhyloStyle.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel("Cancel download")
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.vertical, 6)
    }

    private var title: String {
        let item = download.item
        if item.type == .episode, let series = item.seriesName {
            return "\(series) · \(item.khyloEpisodeLabel ?? item.name ?? "")"
        }
        return item.name ?? ""
    }
}

// MARK: - Downloaded show

/// A show's downloaded episodes, by season. Works offline.
struct KhyloDownloadedShowScreen: View {

    let groupID: String

    @ObservedObject private var downloads = KhyloDownloads.shared
    @Router private var router
    @Environment(\.dismiss) private var dismiss
    @State private var playError: String?

    private var group: KhyloDownloadGroup? { downloads.groups[groupID] }

    private var episodes: [BaseItemDto] {
        downloads.withLocalProgress(downloads.members(of: groupID).filter { $0.state == .done }.map(\.item))
    }

    private var seasons: [(Int, [BaseItemDto])] {
        let grouped = Dictionary(grouping: episodes) { $0.parentIndexNumber ?? 0 }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 16) {
                    KhyloImage(url: downloads.groupArtworkURL(groupID), placeholderSymbol: "tv")
                        .frame(width: 96, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group?.item.name ?? "")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(3)
                        Text("\(episodes.count) downloaded episode\(episodes.count == 1 ? "" : "s")")
                            .font(.system(size: 14))
                            .foregroundColor(KhyloStyle.secondaryText)
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
                .padding(.top, 12)

                ForEach(seasons, id: \.0) { season, seasonEpisodes in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(season == 0 ? "Specials" : "Season \(season)")
                            .font(KhyloStyle.title(19))
                            .foregroundColor(.white)
                            .padding(.horizontal, KhyloStyle.gutter)
                        ForEach(seasonEpisodes, id: \.id) { episode in
                            KhyloDownloadRow(
                                artwork: downloads.artworkURL(for: episode.id),
                                shape: .landscape,
                                title: episode.indexNumber.map { "\($0). \(episode.name ?? "")" } ?? episode.name ?? "",
                                subtitle: [episode.khyloRemaining ?? episode.khyloRuntime,
                                           downloads.downloads[episode.id ?? ""].map {
                                               ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file)
                                           }].compactMap { $0 }.joined(separator: " · "),
                                progress: episode.khyloProgress,
                                isPlayed: episode.khyloIsPlayed,
                                onDelete: { downloads.delete(itemID: episode.id ?? "") }
                            ) {
                                play(episode)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 48)
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Remove Show", systemImage: "trash", role: .destructive) {
                        downloads.deleteGroup(groupID)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Can't Play", isPresented: .constant(playError != nil), presenting: playError) { _ in
            Button("OK") { playError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func play(_ episode: BaseItemDto) {
        Task {
            do {
                try await KhyloPlayback.play(episode, router: router)
            } catch {
                playError = error.localizedDescription
            }
        }
    }
}

// MARK: - Downloaded album or playlist

/// A downloaded album or playlist's songs. Works offline.
struct KhyloDownloadedAlbumScreen: View {

    let groupID: String

    @ObservedObject private var downloads = KhyloDownloads.shared
    @ObservedObject private var player = KhyloAudioPlayer.shared
    @Environment(\.dismiss) private var dismiss

    private var group: KhyloDownloadGroup? { downloads.groups[groupID] }

    private var tracks: [BaseItemDto] {
        downloads.members(of: groupID).filter { $0.state == .done }.map(\.item)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                KhyloImage(url: downloads.groupArtworkURL(groupID), placeholderSymbol: "music.note")
                    .frame(width: 230, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                    .padding(.top, 12)

                VStack(spacing: 4) {
                    Text(group?.item.name ?? "")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if let artist = group?.item.khyloArtistLine, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(KhyloStyle.secondaryText)
                    }
                    Text("\(tracks.count) downloaded song\(tracks.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.tertiaryText)
                }
                .padding(.horizontal, 30)

                HStack(spacing: 12) {
                    KhyloPlayButton(title: "Play") {
                        player.play(tracks, kind: .music, collectionTitle: group?.item.name, startTicks: 0)
                    }
                    Button {
                        player.play(tracks.shuffled(), kind: .music, collectionTitle: group?.item.name, startTicks: 0)
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(KhyloScaleButtonStyle())
                    .accessibilityLabel("Shuffle")
                }
                .padding(.horizontal, KhyloStyle.gutter)
                .disabled(tracks.isEmpty)

                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        trackRow(track, number: index + 1) {
                            player.play(tracks, startAt: index, kind: .music, collectionTitle: group?.item.name, startTicks: 0)
                        }
                    }
                }
            }
            .padding(.bottom, 48)
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Remove Download", systemImage: "trash", role: .destructive) {
                        downloads.deleteGroup(groupID)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func trackRow(_ track: BaseItemDto, number: Int, action: @escaping () -> Void) -> some View {
        let isCurrent = player.current?.id == track.id
        return Button(action: action) {
            HStack(spacing: 14) {
                Text("\(number)")
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name ?? "")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isCurrent ? KhyloStyle.accent : .white)
                        .lineLimit(1)
                    Text(track.khyloArtistLine)
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(track.khyloRuntimeClock ?? "")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(KhyloStyle.tertiaryText)
                Menu {
                    Button("Remove Download", systemImage: "trash", role: .destructive) {
                        downloads.delete(itemID: track.id ?? "")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .frame(width: 30, height: 40)
                        .contentShape(Rectangle())
                }
            }
            .padding(.leading, KhyloStyle.gutter)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

/// The Downloads part of the Account sheet.
struct KhyloDownloadSettingsSection: View {

    let openDownloads: () -> Void

    @AppStorage(KhyloDownloadSettings.qualityKey) private var quality: KhyloDownloadQuality = .original
    @AppStorage(KhyloDownloadSettings.wifiOnlyKey) private var wifiOnly = true
    @AppStorage(KhyloDownloadSettings.autoNextKey) private var autoNext = true
    @ObservedObject private var downloads = KhyloDownloads.shared

    var body: some View {
        Section {
            Button(action: openDownloads) {
                HStack {
                    Label("Your Downloads", systemImage: "arrow.down.circle")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: downloads.usedBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.white)

            if KhyloDownloads.isAllowed {
                Picker("Quality", selection: $quality) {
                    ForEach(KhyloDownloadQuality.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Toggle("Download on Wi-Fi Only", isOn: $wifiOnly)
                    .onChange(of: wifiOnly) { _, _ in downloads.restartPending() }
                Toggle("Download Next Episodes", isOn: $autoNext)
            }
        } header: {
            Text("Downloads")
        } footer: {
            if KhyloDownloads.isAllowed {
                Text("\(quality.title): \(quality.detail.lowercased()). With Download Next Episodes on, the next two episodes of a show you've downloaded are ready by the time you need them.")
            } else {
                Text("Downloads are turned off for your account.")
            }
        }
    }
}
