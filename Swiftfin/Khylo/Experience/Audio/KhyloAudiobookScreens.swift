//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Helpers

enum KhyloAudiobook {

    /// "22 Hope to Die" → ("Hope to Die", 22). Leading numbers are series order.
    static func cleanTitle(_ raw: String) -> (title: String, number: Int?) {
        let pattern = #"^\s*(\d{1,3})[\s._-]+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let numberRange = Range(match.range(at: 1), in: raw),
              let titleRange = Range(match.range(at: 2), in: raw)
        else { return (raw, nil) }
        return (String(raw[titleRange]), Int(raw[numberRange]))
    }

    /// Where Play should start: the part in progress, else the first unfinished part.
    static func resumeIndex(in parts: [BaseItemDto]) -> Int {
        if let inProgress = parts.lastIndex(where: { ($0.userData?.playbackPositionTicks ?? 0) > 0 && !$0.khyloIsPlayed }) {
            return inProgress
        }
        return parts.firstIndex(where: { !$0.khyloIsPlayed }) ?? 0
    }

    static func artworkURL(book: BaseItemDto, parts: [BaseItemDto]) -> URL? {
        KhyloArtwork.url(for: book, style: .square, width: 600)
            ?? parts.lazy.compactMap { KhyloArtwork.url(for: $0, style: .square, width: 600) }.first
    }

    /// Plays a book's parts from the resume point.
    @MainActor
    static func play(book: BaseItemDto, parts: [BaseItemDto], startAt index: Int? = nil) {
        let start = index ?? resumeIndex(in: parts)
        KhyloAudioPlayer.shared.play(
            parts,
            startAt: start,
            kind: .audiobook,
            collectionTitle: cleanTitle(book.name ?? "").title,
            artworkURL: artworkURL(book: book, parts: parts),
            startTicks: parts[start].khyloIsPlayed ? 0 : nil
        )
    }

    static func parts(of folderID: String) async throws -> [BaseItemDto] {
        try await KhyloAPI.items(
            parentID: folderID,
            types: [.audioBook, .audio],
            sortBy: [.parentIndexNumber, .indexNumber, .sortName],
            recursive: true,
            limit: 500
        ).items
    }
}

// MARK: - Folder screen

/// Opens a folder: a book's parts become an audiobook page, anything else a grid.
struct KhyloFolderScreen: View {

    let folder: BaseItemDto

    @State private var children: [BaseItemDto]?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            if let children {
                if !children.isEmpty, children.allSatisfy({ $0.isFolder != true && ($0.type == .audioBook || $0.type == .audio) }) {
                    KhyloAudiobookScreen(book: folder, preloadedParts: children)
                } else {
                    KhyloSearchableGrid(
                        shape: .square,
                        id: folder.id ?? "",
                        placeholder: "Search \(folder.name ?? "")",
                        header: {
                            Text(folder.name ?? "")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, KhyloStyle.gutter)
                        }
                    ) { term, start, limit in
                        try await KhyloAPI.items(
                            parentID: folder.id,
                            types: term == nil ? nil : [.folder],
                            sortBy: [.isFolder, .sortName],
                            searchTerm: term,
                            recursive: term != nil,
                            startIndex: start,
                            limit: limit
                        )
                    }
                }
            } else if let errorMessage {
                KhyloEmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't open this", message: errorMessage)
            } else {
                KhyloLoadingState()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard children == nil, let id = folder.id else { return }
            do {
                children = try await KhyloAPI.items(
                    parentID: id,
                    sortBy: [.parentIndexNumber, .indexNumber, .sortName],
                    recursive: false,
                    limit: 500
                ).items
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Audiobook screen

struct KhyloAudiobookScreen: View {

    let book: BaseItemDto
    var preloadedParts: [BaseItemDto]? = nil

    @State private var parts: [BaseItemDto] = []
    @State private var isLoading = true
    @ObservedObject private var player = KhyloAudioPlayer.shared

    private var cleaned: (title: String, number: Int?) {
        KhyloAudiobook.cleanTitle(book.name ?? "")
    }

    private var author: String? {
        parts.first?.albumArtist ?? parts.first?.artists?.first
    }

    private var totalSeconds: Double {
        Double(parts.reduce(0) { $0 + ($1.runTimeTicks ?? 0) }) / 10_000_000
    }

    private var remainingSeconds: Double {
        Double(parts.reduce(0) { sum, part in
            if part.khyloIsPlayed { return sum }
            return sum + max(0, (part.runTimeTicks ?? 0) - (part.userData?.playbackPositionTicks ?? 0))
        }) / 10_000_000
    }

    private var isThisBookPlaying: Bool {
        guard let current = player.current?.id else { return false }
        return parts.contains { $0.id == current }
    }

    private var hasStarted: Bool {
        parts.contains { $0.khyloIsPlayed || ($0.userData?.playbackPositionTicks ?? 0) > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 26)

                if isLoading {
                    ProgressView().tint(.white).padding(.top, 30)
                } else {
                    partsList
                }
            }
            .padding(.bottom, 40)
        }
        .background(background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: player.isPlaying) { _, _ in
            Task { await refresh() }
        }
    }

    private var background: some View {
        ZStack {
            KhyloStyle.canvas
            KhyloImage(url: KhyloAudiobook.artworkURL(book: book, parts: parts), showsPlaceholder: false)
                .frame(height: 520)
                .scaleEffect(1.5)
                .blur(radius: 80)
                .opacity(0.55)
                .frame(maxHeight: .infinity, alignment: .top)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 620).frame(maxHeight: .infinity, alignment: .top))
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 16) {
            KhyloImage(url: KhyloAudiobook.artworkURL(book: book, parts: parts), placeholderSymbol: "headphones")
                .frame(width: 230, height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 28, y: 14)
                .padding(.top, 70)

            VStack(spacing: 6) {
                if let number = cleaned.number {
                    Text("BOOK \(number)")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(KhyloStyle.accent)
                }
                Text(cleaned.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                if let author {
                    Text(author)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(KhyloStyle.secondaryText)
                }
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 30)

            KhyloPlayButton(
                title: playTitle,
                systemImage: isThisBookPlaying && player.isPlaying ? "pause.fill" : "play.fill"
            ) {
                if isThisBookPlaying {
                    player.togglePlayPause()
                } else {
                    KhyloAudiobook.play(book: book, parts: parts)
                }
            }
            .disabled(parts.isEmpty)
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.top, 6)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if self.parts.count > 1 { parts.append("\(self.parts.count) parts") }
        if totalSeconds > 0 { parts.append(Self.duration(totalSeconds)) }
        if hasStarted, remainingSeconds > 0 { parts.append("\(Self.duration(remainingSeconds)) left") }
        return parts.joined(separator: " · ")
    }

    private var playTitle: String {
        if isThisBookPlaying { return player.isPlaying ? "Pause" : "Resume" }
        guard hasStarted, !parts.isEmpty else { return "Play" }
        let index = KhyloAudiobook.resumeIndex(in: parts)
        return parts.count > 1 ? "Resume Part \(index + 1)" : "Resume"
    }

    private var partsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Button {
                    KhyloAudiobook.play(book: book, parts: parts, startAt: index)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            if player.current?.id == part.id {
                                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                                    .foregroundColor(KhyloStyle.accent)
                            } else if part.khyloIsPlayed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(KhyloStyle.tertiaryText)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                    .foregroundColor(KhyloStyle.secondaryText)
                            }
                        }
                        .frame(width: 28)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(part.name ?? "Part \(index + 1)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(part.khyloIsPlayed ? KhyloStyle.secondaryText : .white)
                                .lineLimit(1)
                            if let progress = part.khyloProgress, !part.khyloIsPlayed {
                                KhyloProgressLine(progress: progress).frame(width: 120)
                            }
                        }

                        Spacer()

                        Text(part.khyloRemaining ?? part.khyloRuntime ?? "")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    .padding(.horizontal, KhyloStyle.gutter)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < parts.count - 1 {
                    Divider().overlay(KhyloStyle.hairline).padding(.leading, KhyloStyle.gutter + 42)
                }
            }
        }
    }

    private func load() async {
        if let preloadedParts, parts.isEmpty {
            parts = preloadedParts
            isLoading = false
        }
        await refresh()
        isLoading = false
    }

    private func refresh() async {
        guard let id = book.id, let fresh = try? await KhyloAudiobook.parts(of: id), !fresh.isEmpty else { return }
        parts = fresh
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(minutes, 1))m"
    }
}
