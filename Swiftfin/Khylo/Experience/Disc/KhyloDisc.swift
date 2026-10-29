//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Get
import JellyfinAPI
import SwiftUI

// MARK: - What the server knows about a disc

/// A DVD (ISO image or DVD folder): its titles, scenes and tracks, read from the disc itself.
struct KhyloDisc: Decodable {

    struct Chapter: Decodable, Identifiable {
        let number: Int
        let startSeconds: Double?
        let startPositionTicks: Int?
        var id: Int { number }
    }

    struct Track: Decodable, Identifiable {
        let index: Int
        let codec: String?
        let channels: Int?
        let language: String?
        let languageName: String?
        let note: String?
        var id: Int { index }

        /// "English · Dolby Digital 5.1"
        var title: String {
            var parts: [String] = []
            parts.append(languageName ?? language.map { $0.uppercased() } ?? "Track \(index + 1)")
            if let kind = Self.codecName(codec) {
                let layout = channels.map { Self.layout($0) }.flatMap { $0 }
                parts.append([kind, layout].compactMap { $0 }.joined(separator: " "))
            }
            if let note, !note.isEmpty { parts.append(note) }
            return parts.joined(separator: " · ")
        }

        private static func codecName(_ codec: String?) -> String? {
            switch codec?.lowercased() {
            case "ac3": "Dolby Digital"
            case "dts": "DTS"
            case "mp2", "mp2a": "MPEG Audio"
            case "pcm_dvd", "lpcm": "PCM"
            case "dvd_subtitle", "dvdsub": nil
            case let other?: other.uppercased()
            case nil: nil
            }
        }

        private static func layout(_ channels: Int) -> String? {
            switch channels {
            case 1: "Mono"
            case 2: "Stereo"
            case 6: "5.1"
            case 8: "7.1"
            default: nil
            }
        }
    }

    struct Title: Decodable, Identifiable {
        let number: Int
        let isMain: Bool?
        let mediaSourceId: String?
        let seconds: Double?
        let runTimeTicks: Int?
        let chapters: [Chapter]?
        let audio: [Track]?
        let subtitles: [Track]?
        var id: Int { number }

        var length: Double { seconds ?? Double(runTimeTicks ?? 0) / 10_000_000 }
    }

    let isScrambled: Bool?
    let hasMenuImage: Bool?
    let mainTitle: Int?
    let titles: [Title]?

    var main: Title? {
        titles?.first { $0.number == mainTitle } ?? titles?.first { $0.isMain == true } ?? titles?.first
    }

    var extras: [Title] {
        (titles ?? []).filter { $0.number != main?.number }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // The server writes PascalCase ("MediaSourceId"); the fields here are camelCase.
        decoder.keyDecodingStrategy = .custom { keys in
            let key = keys.last!.stringValue
            return AnyKey(stringValue: key.prefix(1).lowercased() + key.dropFirst()) ?? keys.last!
        }
        return decoder
    }()

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Whether an item is a DVD (an ISO image or a DVD folder). Blu-ray images play without a menu.
    static func isDisc(_ item: BaseItemDto) -> Bool {
        (item.videoType == .iso && item.isoType == .dvd) || item.videoType == .dvd
    }
}

extension KhyloAPI {

    static func disc(_ itemID: String) async throws -> KhyloDisc {
        guard let session else { throw APIError.notSignedIn }
        let data = try await session.client.data(for: Request<Void>(path: "/Khylo/Disc/\(itemID)")).value
        return try KhyloDisc.decoder.decode(KhyloDisc.self, from: data)
    }

    /// A picture from a disc: its menu, or a frame of a title.
    static func discImageURL(_ itemID: String, menu: Bool = false, title: Int? = nil, seconds: Double? = nil) -> URL? {
        guard let session, let token = accessToken else { return nil }
        var query: [(String, String?)] = []
        if menu { query.append(("menu", "true")) }
        if let title { query.append(("title", String(title))) }
        if let seconds { query.append(("seconds", String(Int(seconds)))) }
        query.append(("api_key", token))
        return session.client.url(with: Request<Void>(path: "/Khylo/Disc/\(itemID)/Image", query: query))
    }
}

// MARK: - Menu

/// The disc's own menu is a small program no app can run, so Khylo builds one from
/// the disc's data: play, scenes, sound and subtitles, and extras.
struct KhyloDiscMenuScreen: View {

    let item: BaseItemDto

    @Router private var router
    @State private var disc: KhyloDisc?
    @State private var failed = false
    @State private var audioChoice: Int?
    /// nil is the disc's default; -1 is off.
    @State private var subtitleChoice: Int?
    @State private var playError: String?
    @State private var isStarting = false

    private var itemID: String { item.id ?? "" }

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()
            backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text(item.name ?? "Disc")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, KhyloStyle.gutter)
                        .padding(.top, 70)

                    content
                }
                .padding(.bottom, 50)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            do {
                disc = try await KhyloAPI.disc(itemID)
            } catch {
                failed = true
            }
        }
        .alert("Can't Play", isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playError ?? "")
        }
    }

    // MARK: Pieces

    /// The disc's menu picture, soft and dimmed: it often has its own button
    /// labels baked in, so it's never shown sharp.
    private var backdrop: some View {
        Group {
            if disc?.hasMenuImage == true, let url = KhyloAPI.discImageURL(itemID, menu: true) {
                KhyloImage(url: url, showsPlaceholder: false)
                    .blur(radius: 40)
                    .opacity(0.35)
                    .overlay(LinearGradient(colors: [.clear, KhyloStyle.canvas], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        if failed {
            message("This disc can't be read.")
        } else if let disc {
            if disc.isScrambled == true {
                message("This disc is copy-protected. Discs copied straight from a store-bought DVD are scrambled, and Khylo can't play them. Use a copy made without the protection.")
            } else {
                playSection
                scenes(disc)
                tracks(disc)
                extras(disc)
            }
        } else {
            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(KhyloStyle.secondaryText)
            .lineSpacing(3)
            .padding(.horizontal, KhyloStyle.gutter)
    }

    private var hasProgress: Bool { (item.userData?.playbackPositionTicks ?? 0) > 0 }

    private var playSection: some View {
        VStack(spacing: 12) {
            KhyloPlayButton(title: hasProgress ? "Resume" : "Play") {
                start(.resume)
            }
            if hasProgress {
                Button {
                    start(.beginning)
                } label: {
                    Text("From the Beginning")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(KhyloStyle.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .disabled(isStarting)
    }

    // MARK: Scenes

    @ViewBuilder
    private func scenes(_ disc: KhyloDisc) -> some View {
        if let chapters = disc.main?.chapters, chapters.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Scenes")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(chapters) { chapter in
                        Button {
                            start(.scene(chapter.startPositionTicks ?? 0))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                KhyloImage(
                                    url: KhyloAPI.discImageURL(itemID, seconds: (chapter.startSeconds ?? 0) + 3),
                                    placeholderSymbol: "film"
                                )
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text("Scene \(chapter.number)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(Self.time(chapter.startSeconds ?? 0))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundColor(KhyloStyle.tertiaryText)
                            }
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
        }
    }

    // MARK: Audio and subtitles

    @ViewBuilder
    private func tracks(_ disc: KhyloDisc) -> some View {
        let audio = disc.main?.audio ?? []
        let subtitles = disc.main?.subtitles ?? []
        if audio.count > 1 || !subtitles.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("Audio & Subtitles")
                if audio.count > 1 {
                    trackGroup("Audio") {
                        ForEach(audio) { track in
                            trackRow(track.title, isSelected: (audioChoice ?? audio.first?.index) == track.index) {
                                audioChoice = track.index
                            }
                        }
                    }
                }
                if !subtitles.isEmpty {
                    trackGroup("Subtitles") {
                        trackRow("Disc default", isSelected: subtitleChoice == nil) {
                            subtitleChoice = nil
                        }
                        trackRow("Off", isSelected: subtitleChoice == -1) {
                            subtitleChoice = -1
                        }
                        ForEach(subtitles) { track in
                            trackRow(track.title, isSelected: subtitleChoice == track.index) {
                                subtitleChoice = track.index
                            }
                        }
                    }
                }
            }
        }
    }

    private func trackGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(KhyloStyle.tertiaryText)
                .textCase(.uppercase)
                .padding(.horizontal, KhyloStyle.gutter)
                .padding(.bottom, 6)
            content()
        }
    }

    private func trackRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(KhyloStyle.accent)
                }
            }
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Extras

    @ViewBuilder
    private func extras(_ disc: KhyloDisc) -> some View {
        let extras = disc.extras.filter { $0.length >= 5 }
        if !extras.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Extras")
                ForEach(extras) { extra in
                    Button {
                        start(.extra(extra))
                    } label: {
                        HStack(spacing: 14) {
                            KhyloImage(
                                url: KhyloAPI.discImageURL(itemID, title: extra.number, seconds: min(extra.length * 0.1, 30)),
                                placeholderSymbol: "film"
                            )
                            .frame(width: 112, height: 63)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Extra \(extra.number)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(Self.time(extra.length))
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundColor(KhyloStyle.tertiaryText)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, KhyloStyle.gutter)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KhyloScaleButtonStyle())
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, KhyloStyle.gutter)
    }

    // MARK: Playing

    private enum Start {
        case resume
        case beginning
        case scene(Int)
        case extra(KhyloDisc.Title)
    }

    private func start(_ start: Start) {
        guard !isStarting else { return }
        isStarting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            defer { isStarting = false }
            do {
                try await play(start)
            } catch {
                playError = error.localizedDescription
            }
        }
    }

    private func play(_ start: Start) async throws {
        // Plain play (no chosen tracks): the usual way a film starts.
        if audioChoice == nil, subtitleChoice == nil {
            switch start {
            case .resume:
                try await KhyloPlayback.play(item, from: .resume, router: router)
                return
            case .beginning:
                try await KhyloPlayback.play(item, from: .beginning, router: router)
                return
            default:
                break
            }
        }

        guard let id = item.id else { throw KhyloPlayback.PlaybackError.unavailable }
        let full = try await KhyloAPI.item(id)

        // The disc's own track i is the i-th audio (or subtitle) stream of the film.
        let streams = full.mediaSources?.first?.mediaStreams ?? []
        let audioStreams = streams.filter { $0.type == .audio }
        let subtitleStreams = streams.filter { $0.type == .subtitle }
        let audioIndex = audioChoice.flatMap { audioStreams.indices.contains($0) ? audioStreams[$0].index : nil }
        let subtitleIndex: Int? = subtitleChoice.flatMap { choice in
            if choice < 0 { return -1 }
            return subtitleStreams.indices.contains(choice) ? subtitleStreams[choice].index : nil
        }

        var source: MediaSourceInfo?
        var ticks: Int?
        switch start {
        case .resume:
            ticks = nil
        case .beginning:
            ticks = 0
        case let .scene(position):
            ticks = position
        case let .extra(title):
            source = full.mediaSources?.first { $0.id == title.mediaSourceId }
            ticks = 0
        }

        guard var provider = full.getPlaybackItemProvider(
            userSession: KhyloAPI.session,
            mediaSource: source,
            audioStreamIndex: audioIndex,
            subtitleStreamIndex: subtitleIndex
        ) else { throw KhyloPlayback.PlaybackError.unavailable }

        if let ticks {
            provider = provider.modifyingItem { item in
                if item.userData == nil {
                    item.userData = UserItemDataDto(itemID: item.id, key: item.id ?? "")
                }
                item.userData?.playbackPositionTicks = ticks
            }
        }
        router.route(to: .videoPlayer(provider: provider, queue: nil))
    }

    private static func time(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
