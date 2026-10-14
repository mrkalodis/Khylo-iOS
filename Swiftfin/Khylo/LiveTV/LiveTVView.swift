//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import SwiftUI

// MARK: - IPTV Channel Model

public struct IPTVChannel: Identifiable, Hashable, Sendable {
    public let id: String
    public let number: String
    public let name: String
    public let category: String
    public let currentProgram: String
    public let nextProgram: String
    public let currentStart: Date
    public let currentEnd: Date
    public var isFavorite: Bool

    public init(
        id: String,
        number: String,
        name: String,
        category: String,
        currentProgram: String,
        nextProgram: String,
        currentStart: Date,
        currentEnd: Date,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.category = category
        self.currentProgram = currentProgram
        self.nextProgram = nextProgram
        self.currentStart = currentStart
        self.currentEnd = currentEnd
        self.isFavorite = isFavorite
    }

    public var progress: Double {
        let now = Date()
        let total = currentEnd.timeIntervalSince(currentStart)
        guard total > 0 else { return 0.5 }
        let elapsed = now.timeIntervalSince(currentStart)
        return min(max(elapsed / total, 0.0), 1.0)
    }
}

// MARK: - Live TV Mode

public enum LiveTVMode: String, CaseIterable, Identifiable {
    case liveTV = "Live TV"
    case programmed = "Live Channels"

    public var id: String { rawValue }
}

// MARK: - Live TV View

public struct LiveTVView: View {

    @EnvironmentObject private var navigator: KhyloNavigator
    @StateObject private var repository = KhyloRepository.shared

    @State private var selectedMode: LiveTVMode = .liveTV
    @State private var channels: [IPTVChannel] = []
    @State private var selectedChannel: IPTVChannel?
    @State private var showOnlyFavorites: Bool = false
    @State private var selectedCategory: String = "All"
    @State private var isMultiSelectMode: Bool = false
    @State private var multiSelectChannelIds: Set<String> = []
    @State private var searchQuery: String = ""

    private let categories = ["All", "Favorites", "News", "Sports", "Entertainment", "Movies", "Kids"]

    public init() {}

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header & Segmented Picker
                headerBar

                if selectedMode == .programmed {
                    LiveChannelsView()
                } else {
                    iptvGuideContent
                }
            }
        }
        .task {
            loadChannels()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: KhyloSpacing.sm) {
            HStack {
                Text("Live TV & Streams")
                    .font(KhyloTypography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(KhyloColors.textPrimary)

                Spacer()

                if selectedMode == .liveTV {
                    // Multi View Mode Toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isMultiSelectMode.toggle()
                            if !isMultiSelectMode {
                                multiSelectChannelIds.removeAll()
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 13))
                            Text(isMultiSelectMode ? "Cancel" : "Multi View")
                                .font(KhyloTypography.captionMedium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isMultiSelectMode ? KhyloColors.accent : KhyloColors.surfaceElevated)
                        .foregroundColor(isMultiSelectMode ? .white : KhyloColors.textPrimary)
                        .cornerRadius(KhyloRadius.sm)
                    }
                }
            }
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.top, KhyloSpacing.sm)

            // Segmented Picker
            Picker("Live Mode", selection: $selectedMode) {
                ForEach(LiveTVMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, KhyloSpacing.lg)
        }
        .padding(.bottom, KhyloSpacing.sm)
        .background(KhyloColors.surface.opacity(0.85))
    }

    // MARK: - IPTV Content

    private var iptvGuideContent: some View {
        VStack(spacing: 0) {
            // Selected Channel Video Preview Card
            if let active = selectedChannel ?? filteredChannels.first {
                channelPreviewCard(for: active)
            }

            // Categories & Favorites Filter Bar
            filterBar

            // Multi-Select Launch Bar
            if isMultiSelectMode {
                multiSelectBanner
            }

            // Channel List
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: KhyloSpacing.xs) {
                    ForEach(filteredChannels) { channel in
                        channelRow(channel)
                    }
                }
                .padding(.horizontal, KhyloSpacing.lg)
                .padding(.top, KhyloSpacing.sm)
                .padding(.bottom, 120)
            }
        }
    }

    // MARK: - Channel Preview Card

    private func channelPreviewCard(for channel: IPTVChannel) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // Video Preview Simulation Background
                Rectangle()
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .frame(height: 160)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "tv.fill")
                                .font(.system(size: 34))
                                .foregroundColor(KhyloColors.textTertiary.opacity(0.6))
                            Text("Live Video Feed Active")
                                .font(KhyloTypography.caption2Medium)
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                    )

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Overlay Info
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)

                            Text("LIVE")
                                .font(KhyloTypography.caption2Bold)
                                .foregroundColor(.red)

                            Text("• CH \(channel.number) · \(channel.name)")
                                .font(KhyloTypography.captionMedium)
                                .foregroundColor(.white)
                        }

                        Text(channel.currentProgram)
                            .font(KhyloTypography.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text("Next: \(channel.nextProgram)")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Watch Fullscreen Button
                    Button {
                        navigator.play(
                            itemId: channel.id,
                            resumePositionTicks: 0,
                            title: "\(channel.number) · \(channel.name)"
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                            Text("Fullscreen")
                                .font(KhyloTypography.captionBold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(KhyloColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(KhyloRadius.sm)
                    }
                }
                .padding(KhyloSpacing.md)
            }
            .frame(height: 160)
            .cornerRadius(KhyloRadius.md)
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.top, KhyloSpacing.xs)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KhyloSpacing.sm) {
                // Favorites Pill
                Button {
                    showOnlyFavorites.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showOnlyFavorites ? "star.fill" : "star")
                            .font(.system(size: 12))
                        Text("Favorites")
                            .font(KhyloTypography.captionMedium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showOnlyFavorites ? Color.yellow.opacity(0.2) : KhyloColors.surfaceElevated)
                    .foregroundColor(showOnlyFavorites ? Color.yellow : KhyloColors.textSecondary)
                    .cornerRadius(KhyloRadius.pill)
                    .overlay(
                        Capsule().stroke(showOnlyFavorites ? Color.yellow : Color.clear, lineWidth: 1)
                    )
                }

                ForEach(categories, id: \.self) { cat in
                    if cat != "Favorites" {
                        Button {
                            selectedCategory = cat
                            if showOnlyFavorites { showOnlyFavorites = false }
                        } label: {
                            Text(cat)
                                .font(KhyloTypography.captionMedium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == cat && !showOnlyFavorites ? KhyloColors.accent : KhyloColors.surfaceElevated)
                                .foregroundColor(selectedCategory == cat && !showOnlyFavorites ? .white : KhyloColors.textSecondary)
                                .cornerRadius(KhyloRadius.pill)
                        }
                    }
                }
            }
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.vertical, KhyloSpacing.sm)
        }
    }

    // MARK: - Multi-Select Launch Banner

    private var multiSelectBanner: some View {
        HStack {
            Text("Select 2 to 4 channels (\(multiSelectChannelIds.count)/4 selected)")
                .font(KhyloTypography.captionMedium)
                .foregroundColor(KhyloColors.textPrimary)

            Spacer()

            Button {
                launchMultiView()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.tv.fill")
                    Text("Start Multi View")
                        .font(KhyloTypography.captionBold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(multiSelectChannelIds.count >= 2 ? KhyloColors.accent : KhyloColors.surfaceElevated)
                .foregroundColor(multiSelectChannelIds.count >= 2 ? .white : KhyloColors.textTertiary)
                .cornerRadius(KhyloRadius.sm)
            }
            .disabled(multiSelectChannelIds.count < 2)
        }
        .padding(.horizontal, KhyloSpacing.lg)
        .padding(.vertical, 8)
        .background(KhyloColors.surface)
    }

    // MARK: - Channel Row

    private func channelRow(_ channel: IPTVChannel) -> some View {
        let isSelectedForMulti = multiSelectChannelIds.contains(channel.id)

        return Button {
            if isMultiSelectMode {
                toggleMultiSelect(for: channel)
            } else {
                selectedChannel = channel
            }
        } label: {
            HStack(spacing: KhyloSpacing.md) {
                if isMultiSelectMode {
                    Image(systemName: isSelectedForMulti ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelectedForMulti ? KhyloColors.accent : KhyloColors.textTertiary)
                }

                // Channel Number Pill
                Text(channel.number)
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.accent)
                    .frame(width: 44, height: 44)
                    .background(KhyloColors.surfaceElevated)
                    .cornerRadius(KhyloRadius.sm)

                // Channel Metadata & Now/Next
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(channel.name)
                            .font(KhyloTypography.captionBold)
                            .foregroundColor(KhyloColors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        // Star Favorite Button
                        Button {
                            toggleFavorite(channel)
                        } label: {
                            Image(systemName: channel.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 13))
                                .foregroundColor(channel.isFavorite ? Color.yellow : KhyloColors.textTertiary)
                        }
                    }

                    Text(channel.currentProgram)
                        .font(KhyloTypography.subheadlineMedium)
                        .foregroundColor(KhyloColors.accent)
                        .lineLimit(1)

                    // Now Airing Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 1)
                                .fill(KhyloColors.accent)
                                .frame(width: geo.size.width * CGFloat(channel.progress), height: 3)
                        }
                    }
                    .frame(height: 3)

                    Text("Next: \(channel.nextProgram)")
                        .font(KhyloTypography.caption2)
                        .foregroundColor(KhyloColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Quick Play Action
                if !isMultiSelectMode {
                    Button {
                        navigator.play(
                            itemId: channel.id,
                            resumePositionTicks: 0,
                            title: "\(channel.number) · \(channel.name)"
                        )
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(KhyloColors.accent)
                    }
                }
            }
            .padding(KhyloSpacing.md)
            .background(selectedChannel?.id == channel.id ? KhyloColors.surfaceElevated : KhyloColors.surface)
            .cornerRadius(KhyloRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                    .stroke(selectedChannel?.id == channel.id ? KhyloColors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var filteredChannels: [IPTVChannel] {
        channels.filter { ch in
            if showOnlyFavorites && !ch.isFavorite { return false }
            if selectedCategory != "All" && selectedCategory != "Favorites" && ch.category != selectedCategory { return false }
            if !searchQuery.isEmpty {
                return ch.name.localizedCaseInsensitiveContains(searchQuery) ||
                       ch.currentProgram.localizedCaseInsensitiveContains(searchQuery) ||
                       ch.number.contains(searchQuery)
            }
            return true
        }
    }

    private func toggleFavorite(_ channel: IPTVChannel) {
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[idx].isFavorite.toggle()
        }
    }

    private func toggleMultiSelect(for channel: IPTVChannel) {
        if multiSelectChannelIds.contains(channel.id) {
            multiSelectChannelIds.remove(channel.id)
        } else if multiSelectChannelIds.count < 4 {
            multiSelectChannelIds.insert(channel.id)
        }
    }

    private func launchMultiView() {
        let selectedIds = Array(multiSelectChannelIds)
        navigator.push(.multiView(channelIds: selectedIds))
    }

    private func loadChannels() {
        let now = Date()
        let ch1 = IPTVChannel(
            id: "iptv-1",
            number: "04.1",
            name: "NBC Premier",
            category: "Entertainment",
            currentProgram: "Today in America Live",
            nextProgram: "Midday Regional News",
            currentStart: now.addingTimeInterval(-24 * 60),
            currentEnd: now.addingTimeInterval(36 * 60),
            isFavorite: true
        )
        let ch2 = IPTVChannel(
            id: "iptv-2",
            number: "07.1",
            name: "ABC Prime",
            category: "News",
            currentProgram: "World News Tonight",
            nextProgram: "Primetime Documentary",
            currentStart: now.addingTimeInterval(-15 * 60),
            currentEnd: now.addingTimeInterval(45 * 60),
            isFavorite: false
        )
        let ch3 = IPTVChannel(
            id: "iptv-3",
            number: "11.1",
            name: "CBS Showcase",
            category: "Entertainment",
            currentProgram: "60 Minutes Investigative",
            nextProgram: "Sunday Night Football",
            currentStart: now.addingTimeInterval(-40 * 60),
            currentEnd: now.addingTimeInterval(20 * 60),
            isFavorite: true
        )
        let ch4 = IPTVChannel(
            id: "iptv-4",
            number: "28.1",
            name: "PBS North",
            category: "Documentary",
            currentProgram: "Nova: Wonders of the Cosmos",
            nextProgram: "Frontline: Global Report",
            currentStart: now.addingTimeInterval(-10 * 60),
            currentEnd: now.addingTimeInterval(50 * 60),
            isFavorite: false
        )
        let ch5 = IPTVChannel(
            id: "iptv-5",
            number: "32.1",
            name: "FOX Sports Live",
            category: "Sports",
            currentProgram: "European Football Championship",
            nextProgram: "Post-Match Analysis",
            currentStart: now.addingTimeInterval(-55 * 60),
            currentEnd: now.addingTimeInterval(35 * 60),
            isFavorite: true
        )
        let ch6 = IPTVChannel(
            id: "iptv-6",
            number: "44.1",
            name: "Cinema HD 1",
            category: "Movies",
            currentProgram: "Dune: Part Two",
            nextProgram: "Blade Runner 2049",
            currentStart: now.addingTimeInterval(-70 * 60),
            currentEnd: now.addingTimeInterval(65 * 60),
            isFavorite: false
        )
        self.channels = [ch1, ch2, ch3, ch4, ch5, ch6]
        self.selectedChannel = ch1
    }
}
