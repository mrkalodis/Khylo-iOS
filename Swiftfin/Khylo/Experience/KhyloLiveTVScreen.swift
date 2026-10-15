//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

@MainActor
final class KhyloLiveTVModel: ObservableObject {

    @Published private(set) var channels: [BaseItemDto] = []
    @Published private(set) var onNow: [BaseItemDto] = []
    @Published private(set) var programs: [String: [BaseItemDto]] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    func load() async {
        errorMessage = nil
        do {
            async let channelList = KhyloAPI.channels()
            async let airing = KhyloAPI.onNow(limit: 24)
            channels = try await channelList
            onNow = (try? await airing) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadGuide() async {
        let ids = channels.compactMap(\.id)
        guard !ids.isEmpty, programs.isEmpty else { return }
        let list = (try? await KhyloAPI.programs(channelIDs: ids)) ?? []
        programs = Dictionary(grouping: list) { $0.channelID ?? "" }
    }

    /// Whether the server has program info; without it only channels are shown.
    var hasGuide: Bool {
        !onNow.isEmpty || channels.contains { $0.currentProgram != nil }
    }

    func channel(for program: BaseItemDto) -> BaseItemDto? {
        channels.first { $0.id == program.channelID }
    }
}

struct KhyloLiveTVScreen: View {

    enum Section: String, CaseIterable {
        case onNow = "On Now"
        case channels = "Channels"
        case guide = "Guide"
    }

    @StateObject private var model = KhyloLiveTVModel()
    @State private var section: Section = .onNow
    @State private var playError: String?
    @Router private var router

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            if model.isLoading {
                KhyloLoadingState()
            } else if model.channels.isEmpty {
                VStack(spacing: 0) {
                    header
                    KhyloEmptyState(
                        systemImage: "antenna.radiowaves.left.and.right",
                        title: "No channels",
                        message: model.errorMessage ?? "Set up a tuner or IPTV source on your server to watch live TV.",
                        actionTitle: "Try Again"
                    ) {
                        Task { await model.load() }
                    }
                }
            } else if !model.hasGuide {
                channelGrid
            } else {
                switch section {
                case .onNow: onNowView
                case .channels: channelsView
                case .guide: guideView
                }
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            if model.channels.isEmpty { await model.load() }
        }
        .alert("Can't Play", isPresented: .constant(playError != nil), presenting: playError) { _ in
            Button("OK") { playError = nil }
        } message: { Text($0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 10) {
                    Text("Live TV")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: "#E5484D")))
                }
                Spacer()
                KhyloProfileButton()
            }
            .padding(.horizontal, KhyloStyle.gutter)

            if model.hasGuide {
            HStack(spacing: 8) {
                ForEach(Section.allCases, id: \.self) { option in
                    KhyloPill(title: option.rawValue, isSelected: section == option) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) { section = option }
                    }
                }
            }
            .padding(.horizontal, KhyloStyle.gutter)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Channel grid (no guide data)

    private var channelGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14, alignment: .top),
                        GridItem(.flexible(), spacing: 14, alignment: .top),
                    ],
                    spacing: 18
                ) {
                    ForEach(model.channels, id: \.id) { channel in
                        Button {
                            watch(channel)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    if let url = KhyloArtwork.url(for: channel, style: .square, width: 240) {
                                        KhyloImage(url: url, contentMode: .fit, showsPlaceholder: false)
                                            .padding(22)
                                    } else {
                                        Text(channel.name ?? "")
                                            .font(.system(size: 17, weight: .heavy))
                                            .foregroundColor(.white.opacity(0.85))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.7)
                                            .padding(16)
                                    }
                                }
                                .aspectRatio(16 / 10, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(KhyloStyle.hairline, lineWidth: 0.5)
                                )
                                .overlay(alignment: .topLeading) {
                                    HStack(spacing: 5) {
                                        Circle().fill(Color(hex: "#E5484D")).frame(width: 6, height: 6)
                                        Text("LIVE").font(.system(size: 10, weight: .heavy)).tracking(0.8)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.black.opacity(0.5)))
                                    .padding(8)
                                }

                                Text(channel.name ?? "")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }

    // MARK: - On Now

    private var onNowView: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - KhyloStyle.gutter * 2
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    let programs = model.onNow.isEmpty
                        ? model.channels.compactMap(\.currentProgram)
                        : model.onNow

                    LazyVStack(spacing: 22) {
                        ForEach(Array(programs.enumerated()), id: \.offset) { _, program in
                            Button {
                                if let channel = model.channel(for: program) { watch(channel) }
                            } label: {
                                KhyloProgramCard(program: program, channel: model.channel(for: program), width: width)
                            }
                            .buttonStyle(KhyloScaleButtonStyle())
                        }
                    }
                    .padding(.horizontal, KhyloStyle.gutter)
                }
                .padding(.bottom, 32)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: - Channels

    private var channelsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVStack(spacing: 0) {
                    ForEach(model.channels, id: \.id) { channel in
                        Button {
                            watch(channel)
                        } label: {
                            KhyloChannelRow(channel: channel)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(KhyloStyle.hairline).padding(.leading, KhyloStyle.gutter + 76)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }

    // MARK: - Guide

    private let hourWidth: CGFloat = 320
    private let rowHeight: CGFloat = 64
    private let channelColumn: CGFloat = 76

    private var guideStart: Date {
        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        return calendar.date(byAdding: .minute, value: -(minute % 30), to: now)?
            .addingTimeInterval(-Double(calendar.component(.second, from: now))) ?? now
    }

    private var guideView: some View {
        let start = guideStart
        let hours = 6.0

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                header

                HStack(alignment: .top, spacing: 0) {
                    // Channel logos stay put while the schedule scrolls sideways.
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 30)
                        ForEach(model.channels, id: \.id) { channel in
                            KhyloChannelLogo(channel: channel, size: 44)
                                .frame(width: channelColumn, height: rowHeight)
                                .onTapGesture { watch(channel) }
                        }
                    }
                    .background(KhyloStyle.canvas)
                    .zIndex(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            timeRuler(start: start, hours: hours)
                            ForEach(model.channels, id: \.id) { channel in
                                guideRow(for: channel, start: start, hours: hours)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            // "Now" line.
                            Rectangle()
                                .fill(KhyloStyle.accent)
                                .frame(width: 2)
                                .offset(x: CGFloat(Date().timeIntervalSince(start) / 3600) * hourWidth)
                                .padding(.top, 26)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .task { await model.loadGuide() }
    }

    private func timeRuler(start: Date, hours: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(0 ..< Int(hours * 2), id: \.self) { slot in
                Text(start.addingTimeInterval(Double(slot) * 1800), format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .frame(width: hourWidth / 2, alignment: .leading)
            }
        }
        .frame(height: 30)
    }

    private func guideRow(for channel: BaseItemDto, start: Date, hours: Double) -> some View {
        let end = start.addingTimeInterval(hours * 3600)
        let shows = (model.programs[channel.id ?? ""] ?? [])
            .filter { ($0.endDate ?? .distantPast) > start && ($0.startDate ?? .distantFuture) < end }

        return ZStack(alignment: .leading) {
            Color.clear.frame(width: hourWidth * hours, height: rowHeight)
            ForEach(Array(shows.enumerated()), id: \.offset) { _, show in
                let showStart = max(show.startDate ?? start, start)
                let showEnd = min(show.endDate ?? end, end)
                let x = CGFloat(showStart.timeIntervalSince(start) / 3600) * hourWidth
                let width = max(CGFloat(showEnd.timeIntervalSince(showStart) / 3600) * hourWidth - 4, 20)
                let isAiring = (show.startDate ?? .distantFuture) <= Date() && (show.endDate ?? .distantPast) > Date()

                Button {
                    if isAiring { watch(channel) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show.name ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let startDate = show.startDate {
                            Text(startDate, format: .dateTime.hour().minute())
                                .font(.system(size: 11))
                                .foregroundColor(KhyloStyle.tertiaryText)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(width: width, height: rowHeight - 6, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isAiring ? Color.white.opacity(0.13) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isAiring ? KhyloStyle.accent.opacity(0.45) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .offset(x: x)
            }
        }
        .frame(height: rowHeight)
    }

    // MARK: - Playback

    private func watch(_ channel: BaseItemDto) {
        Task {
            do {
                try await KhyloPlayback.play(channel, router: router)
            } catch {
                playError = error.localizedDescription
            }
        }
    }
}

// MARK: - Components

struct KhyloChannelLogo: View {
    let channel: BaseItemDto
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
            if let url = KhyloArtwork.url(for: channel, style: .square, width: size * 2) {
                KhyloImage(url: url, contentMode: .fit, showsPlaceholder: false)
                    .padding(6)
            } else {
                Text(channel.channelNumber ?? String((channel.name ?? "?").prefix(3)))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(KhyloStyle.secondaryText)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct KhyloChannelRow: View {
    let channel: BaseItemDto

    var body: some View {
        HStack(spacing: 14) {
            KhyloChannelLogo(channel: channel)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Short numbers are real channel numbers; long ones are internal IDs.
                    if let number = channel.channelNumber, number.count <= 4 {
                        Text(number)
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    Text(channel.name ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(KhyloStyle.secondaryText)
                        .lineLimit(1)
                }
                if let program = channel.currentProgram?.name {
                    Text(program)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                if let program = channel.currentProgram, let progress = program.khyloAiringProgress {
                    KhyloProgressLine(progress: progress)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "play.circle.fill")
                .font(.system(size: 26))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.white.opacity(0.12))
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Wide card for a program on air now.
private struct KhyloProgramCard: View {
    let program: BaseItemDto
    let channel: BaseItemDto?
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                KhyloImage(
                    url: KhyloArtwork.url(for: program, style: .landscape, width: width)
                        ?? KhyloArtwork.url(for: program, style: .poster, width: width),
                    placeholderSymbol: "tv"
                )
                .frame(width: width, height: width * 9 / 16)
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                        if let progress = program.khyloAiringProgress {
                            KhyloProgressLine(progress: progress)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "#E5484D")).frame(width: 7, height: 7)
                    Text("LIVE").font(.system(size: 11, weight: .heavy)).tracking(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(KhyloStyle.hairline, lineWidth: 0.5)
            )

            HStack(spacing: 12) {
                if let channel {
                    KhyloChannelLogo(channel: channel, size: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let name = channel?.name ?? program.channelName { parts.append(name) }
        if let end = program.endDate {
            let minutes = max(0, Int(end.timeIntervalSinceNow / 60))
            parts.append(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left")
        }
        return parts.joined(separator: " · ")
    }
}

extension BaseItemDto {
    /// 0...1 through a program's air time, nil if not airing.
    var khyloAiringProgress: Double? {
        guard let start = startDate, let end = endDate, end > start else { return nil }
        let value = Date().timeIntervalSince(start) / end.timeIntervalSince(start)
        return (0 ... 1).contains(value) ? value : nil
    }
}

/// Opening a channel from search shows its page with a Watch button.
struct KhyloChannelRedirect: View {
    let channel: BaseItemDto
    @Router private var router

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                KhyloChannelLogo(channel: channel, size: 120)
                Text(channel.name ?? "")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                if let program = channel.currentProgram?.name {
                    Text("Now: \(program)")
                        .font(.system(size: 15))
                        .foregroundColor(KhyloStyle.secondaryText)
                }
                KhyloPlayButton(title: "Watch Live") {
                    Task { try? await KhyloPlayback.play(channel, router: router) }
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
