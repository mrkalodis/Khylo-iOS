//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

/// Khylo TV: always-on channels built from your own library. Tune in and the
/// show picks up mid-way, like real TV.
struct KhyloTVScreen: View {

    @State private var channels: [KhyloAPI.TVChannel] = []
    @State private var category = "All"
    @State private var featuredID: String?
    @State private var now = Date()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tuningID: String?
    @Router private var router

    private static let categoryOrder = ["TV", "Movies", "Networks", "Collections"]

    private var categories: [String] {
        let present = Set(channels.map(\.category))
        return ["All"] + Self.categoryOrder.filter(present.contains)
    }

    private var visible: [KhyloAPI.TVChannel] {
        category == "All" ? channels : channels.filter { $0.category == category }
    }

    private var featured: KhyloAPI.TVChannel? {
        visible.first { $0.id == featuredID } ?? visible.first { $0.current(at: now) != nil }
    }

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            if isLoading {
                KhyloLoadingState()
            } else if channels.isEmpty {
                KhyloEmptyState(
                    systemImage: "play.tv",
                    title: "No channels yet",
                    message: errorMessage ?? "Channels are built from your movie and TV libraries. Add more titles and they'll appear here.",
                    actionTitle: "Try Again"
                ) {
                    Task { await load() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if let featured, let program = featured.current(at: now) {
                            hero(featured, program)
                        }

                        if categories.count > 2 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                KhyloSegmentTabs(tabs: categories.map { ($0, $0) }, selection: $category)
                                    .padding(.horizontal, KhyloStyle.gutter)
                            }
                            .scrollClipDisabled()
                        }

                        LazyVStack(spacing: 4) {
                            ForEach(visible) { channel in
                                KhyloTVChannelRow(
                                    channel: channel,
                                    now: now,
                                    isFeatured: channel.id == featured?.id,
                                    isTuning: tuningID == channel.id
                                ) {
                                    tune(channel)
                                } onSelect: {
                                    withAnimation(.easeInOut(duration: 0.25)) { featuredID = channel.id }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .refreshable { await load() }
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await load() }
        .task {
            // Keep "on now" and progress current; refetch the guide every few minutes.
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
                ticks += 1
                if ticks % 10 == 0 { await load() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .khyloPlaybackDidEnd)) { _ in
            playbackEnded()
        }
        .alert("Couldn't tune in", isPresented: Binding(get: { errorMessage != nil && !channels.isEmpty }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Khylo TV")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Text("\(channels.count) channels · Always on")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(KhyloStyle.tertiaryText)
            }
            Spacer()
            KhyloProfileButton()
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.top, 8)
    }

    private func hero(_ channel: KhyloAPI.TVChannel, _ program: KhyloAPI.TVProgram) -> some View {
        Button {
            tune(channel)
        } label: {
            ZStack(alignment: .bottomLeading) {
                KhyloImage(url: KhyloTVArt.backdrop(program, width: 900))
                    .aspectRatio(16 / 9, contentMode: .fit)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.25), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.9), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        KhyloLiveBadge()
                        Text("CH \(channel.number) · \(channel.name.uppercased())")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Text(program.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !program.subtitle.isEmpty {
                        Text(program.subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        KhyloTVProgress(value: program.progress(at: now))
                            .frame(maxWidth: 140)
                        Text("Ends \(program.end.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        HStack(spacing: 6) {
                            if tuningID == channel.id {
                                ProgressView().tint(.black).controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Watch")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.white))
                    }
                    .padding(.top, 2)
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .padding(.horizontal, KhyloStyle.gutter)
        .id(channel.id)
        .transition(.opacity)
    }

    // MARK: Actions

    private func load() async {
        do {
            let guide = try await KhyloAPI.khyloTVGuide(from: Date(), hours: 6)
            channels = guide.sorted { $0.number < $1.number }
            errorMessage = nil
        } catch {
            if channels.isEmpty { errorMessage = error.localizedDescription }
        }
        now = Date()
        isLoading = false
    }

    private func tune(_ channel: KhyloAPI.TVChannel) {
        guard tuningID == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        tuningID = channel.id
        Task {
            defer { tuningID = nil }
            do {
                let result = try await KhyloAPI.tuneKhyloTV(channelID: channel.id)
                guard let current = result.current else {
                    errorMessage = "Nothing is on \(channel.name) right now."
                    return
                }
                var item = try await KhyloAPI.item(current.itemID)
                // Join the broadcast where it is now, not where you last stopped.
                if item.userData == nil { item.userData = UserItemDataDto(itemID: item.id, key: item.id ?? "") }
                item.userData?.playbackPositionTicks = result.startPositionTicks
                KhyloTVSession.shared.start(channelID: channel.id, program: current)
                try KhyloPlayback.play(prepared: item, router: router)
            } catch {
                errorMessage = "Couldn't tune in to \(channel.name). Try again in a moment."
            }
        }
    }

    /// When a program plays to its end, carry on with the channel; otherwise
    /// the viewer left, so tell the server.
    private func playbackEnded() {
        let session = KhyloTVSession.shared
        guard let channelID = session.channelID else { return }
        if let end = session.programEnd, Date() >= end.addingTimeInterval(-45),
           let channel = channels.first(where: { $0.id == channelID }) {
            session.stop(notifyServer: false)
            tune(channel)
        } else {
            session.stop(notifyServer: true)
        }
    }
}

// MARK: - Session

/// The channel this device is watching, so a finished program can roll into the next.
@MainActor
final class KhyloTVSession {
    static let shared = KhyloTVSession()

    private(set) var channelID: String?
    private(set) var programEnd: Date?

    func start(channelID: String, program: KhyloAPI.TVProgram) {
        self.channelID = channelID
        programEnd = program.end
    }

    func stop(notifyServer: Bool) {
        channelID = nil
        programEnd = nil
        if notifyServer {
            Task { await KhyloAPI.leaveKhyloTV() }
        }
    }
}

// MARK: - Artwork

enum KhyloTVArt {
    /// The show's (or movie's) backdrop.
    static func backdrop(_ program: KhyloAPI.TVProgram, width: CGFloat) -> URL? {
        KhyloArtwork.url(itemID: program.seriesID ?? program.itemID, type: .backdrop, tag: nil, width: width)
    }

    /// The episode still for episodes, the backdrop for movies.
    static func thumb(_ program: KhyloAPI.TVProgram, width: CGFloat) -> URL? {
        program.seriesID != nil
            ? KhyloArtwork.url(itemID: program.itemID, type: .primary, tag: nil, width: width)
            : KhyloArtwork.url(itemID: program.itemID, type: .backdrop, tag: nil, width: width)
    }
}

// MARK: - Row

private struct KhyloTVChannelRow: View {

    let channel: KhyloAPI.TVChannel
    let now: Date
    let isFeatured: Bool
    let isTuning: Bool
    let onWatch: () -> Void
    let onSelect: () -> Void

    var body: some View {
        let current = channel.current(at: now)
        let next = channel.next(after: now)

        Button(action: onWatch) {
            HStack(spacing: 12) {
                KhyloChannelEmblem(number: channel.number, name: channel.name, category: channel.category)

                ZStack(alignment: .bottom) {
                    if let current {
                        KhyloImage(url: KhyloTVArt.thumb(current, width: 240), placeholderSymbol: "play.tv")
                    } else {
                        Rectangle().fill(KhyloStyle.placeholder)
                    }
                    if let current {
                        KhyloTVProgress(value: current.progress(at: now))
                            .padding(.horizontal, 6)
                            .padding(.bottom, 5)
                    }
                    if isTuning {
                        Color.black.opacity(0.5)
                        ProgressView().tint(.white).frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(current?.title ?? "Off air")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let subtitle = current?.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(KhyloStyle.secondaryText)
                            .lineLimit(1)
                    }
                    if let next {
                        Text("\(next.start.formatted(date: .omitted, time: .shortened)) · \(next.title)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(KhyloStyle.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFeatured ? Color.white.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .padding(.horizontal, KhyloStyle.gutter - 12)
        .contextMenu {
            Button {
                onWatch()
            } label: {
                Label("Watch", systemImage: "play.fill")
            }
            Button {
                onSelect()
            } label: {
                Label("Feature at Top", systemImage: "rectangle.topthird.inset.filled")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Channel \(channel.number), \(channel.name), now \(current?.title ?? "off air")")
    }
}

/// Channel number and name on a colour picked from the channel, like a network bug.
private struct KhyloChannelEmblem: View {
    let number: Int
    let name: String
    let category: String

    private static let palette = ["#C2410C", "#7C3AED", "#0E7490", "#BE123C", "#15803D", "#1D4ED8", "#A16207", "#9D174D"]

    var body: some View {
        let hex = Self.palette[abs(name.hashValue_stable) % Self.palette.count]
        VStack(spacing: 1) {
            Text("\(number)")
                .font(.system(size: 18, weight: .heavy).monospacedDigit())
            Text(name)
                .font(.system(size: 8, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .foregroundColor(.white)
        .padding(4)
        .frame(width: 54, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: hex), Color(hex: hex).opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private extension String {
    /// A hash that stays the same between launches (unlike `hashValue`).
    var hashValue_stable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}

struct KhyloLiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.white).frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(Color(hex: "#E5484D")))
    }
}

private struct KhyloTVProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(KhyloStyle.accent).frame(width: max(3, proxy.size.width * value))
            }
        }
        .frame(height: 3)
    }
}
