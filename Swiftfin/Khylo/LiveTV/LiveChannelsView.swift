//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import SwiftUI

// MARK: - Live Channels Guide View

public struct LiveChannelsView: View {

    @EnvironmentObject private var navigator: KhyloNavigator
    @StateObject private var repository = KhyloRepository.shared
    @State private var channels: [LiveChannel] = []
    @State private var isLoading: Bool = true
    @State private var selectedChannel: LiveChannel?
    @State private var selectedProgram: LiveChannelProgram?
    @State private var currentTime: Date = Date()
    @State private var isTuning: Bool = false
    @State private var tuningError: String?
    @State private var timerSubscription: AnyCancellable?

    private let timelineIntervalMinutes: Int = 30
    private let minuteWidth: CGFloat = 3.6
    private let channelColumnWidth: CGFloat = 120
    private let rowHeight: CGFloat = 72

    public init() {}

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            if isLoading {
                VStack(spacing: KhyloSpacing.md) {
                    ProgressView()
                        .tint(KhyloColors.accent)
                        .scaleEffect(1.2)
                    Text("Loading 24/7 Programmed Channels...")
                        .font(KhyloTypography.subheadline)
                        .foregroundColor(KhyloColors.textSecondary)
                }
            } else if channels.isEmpty {
                emptyChannelsView
            } else {
                VStack(spacing: 0) {
                    // Preview Header Area
                    if let channel = activeChannel, let program = activeProgram {
                        channelPreviewHeader(channel: channel, program: program)
                    }

                    Divider()
                        .background(KhyloColors.border.opacity(0.4))

                    // Synchronized Timeline Grid
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Timeline Time Header
                            timelineHeaderView

                            Divider()
                                .background(KhyloColors.border.opacity(0.6))

                            // Channel Rows
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(channels) { channel in
                                    channelRowView(for: channel)
                                    Divider()
                                        .background(KhyloColors.border.opacity(0.2))
                                }
                            }
                        }
                    }
                }
            }

            if isTuning {
                ZStack {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()

                    VStack(spacing: KhyloSpacing.md) {
                        ProgressView()
                            .tint(KhyloColors.accent)
                            .scaleEffect(1.4)
                        Text("Tuning Live Stream...")
                            .font(KhyloTypography.headline)
                            .foregroundColor(.white)
                    }
                    .padding(KhyloSpacing.xl)
                    .background(KhyloColors.surfaceElevated)
                    .cornerRadius(KhyloRadius.lg)
                }
            }
        }
        .task {
            await loadChannels()
            startClock()
        }
        .onDisappear {
            timerSubscription?.cancel()
        }
    }

    // MARK: - Active Selection Helpers

    private var activeChannel: LiveChannel? {
        selectedChannel ?? channels.first
    }

    private var activeProgram: LiveChannelProgram? {
        if let prog = selectedProgram { return prog }
        if let ch = activeChannel {
            return ch.currentProgram(at: currentTime) ?? ch.programs.first
        }
        return nil
    }

    // MARK: - Preview Header

    private func channelPreviewHeader(channel: LiveChannel, program: LiveChannelProgram) -> some View {
        let isNow = program.isAiring(at: currentTime)
        let progProgress = program.progress(at: currentTime)

        return ZStack(alignment: .bottomLeading) {
            // Subtle backdrop glow
            LinearGradient(
                colors: [
                    KhyloColors.surfaceElevated,
                    KhyloColors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
                HStack(spacing: KhyloSpacing.sm) {
                    if isNow {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                            Text("ON NOW")
                                .font(KhyloTypography.caption2Medium)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.16))
                        .cornerRadius(KhyloRadius.xs)
                    }

                    Text("CH \(channel.number) • \(channel.name.uppercased())")
                        .font(KhyloTypography.captionMedium)
                        .foregroundColor(KhyloColors.accent)

                    Spacer()

                    if let err = tuningError {
                        Text(err)
                            .font(KhyloTypography.caption)
                            .foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.35))
                    }
                }

                Text(program.title)
                    .font(KhyloTypography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)

                if let detail = program.detail {
                    Text(detail)
                        .font(KhyloTypography.subheadline)
                        .foregroundColor(KhyloColors.textSecondary)
                }

                if let ov = program.overview, !ov.isEmpty {
                    Text(ov)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textTertiary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                if isNow {
                    // Live airing progress bar
                    VStack(alignment: .leading, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(KhyloColors.accent)
                                    .frame(width: geo.size.width * CGFloat(progProgress), height: 4)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text(formatTime(program.start))
                                .font(KhyloTypography.caption2)
                                .foregroundColor(KhyloColors.textTertiary)
                            Spacer()
                            Text(formatTime(program.end))
                                .font(KhyloTypography.caption2)
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                    }
                    .padding(.top, 4)
                }

                // Action buttons
                HStack(spacing: KhyloSpacing.md) {
                    Button {
                        tuneIn(to: channel, program: program)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(isNow ? "Tune In Mid-Program" : "Watch From Beginning")
                                .font(KhyloTypography.subheadlineMedium)
                        }
                        .padding(.horizontal, KhyloSpacing.md)
                        .padding(.vertical, 8)
                        .background(KhyloColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(KhyloRadius.sm)
                    }

                    Button {
                        navigator.push(.multiView(channelIds: [channel.id]))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 12))
                            Text("Multi View")
                                .font(KhyloTypography.captionMedium)
                        }
                        .padding(.horizontal, KhyloSpacing.md)
                        .padding(.vertical, 8)
                        .background(KhyloColors.surfaceElevated)
                        .foregroundColor(KhyloColors.textPrimary)
                        .cornerRadius(KhyloRadius.sm)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.vertical, KhyloSpacing.md)
        }
        .frame(height: 200)
    }

    // MARK: - Timeline Time Header

    private var timelineHeaderView: some View {
        HStack(alignment: .center, spacing: 0) {
            // Channel Column Spacer
            HStack {
                Text("Channels")
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(KhyloColors.textSecondary)
                Spacer()
            }
            .frame(width: channelColumnWidth)
            .padding(.leading, KhyloSpacing.sm)
            .background(KhyloColors.surface)

            // Timeline slots for 6 hours
            ForEach(0..<12, id: \.self) { slotIndex in
                timelineSlotView(slotIndex: slotIndex)
            }
        }
        .background(KhyloColors.surface)
    }

    // MARK: - Channel Row

    private func channelRowView(for channel: LiveChannel) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // Left sticky channel info column
            Button {
                selectedChannel = channel
                selectedProgram = channel.currentProgram(at: currentTime)
            } label: {
                HStack(spacing: KhyloSpacing.xs) {
                    Text("\(channel.number)")
                        .font(KhyloTypography.captionBold)
                        .foregroundColor(KhyloColors.accent)
                        .frame(width: 30, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name)
                            .font(KhyloTypography.captionMedium)
                            .foregroundColor(KhyloColors.textPrimary)
                            .lineLimit(1)

                        Text(channel.category)
                            .font(KhyloTypography.caption2)
                            .foregroundColor(KhyloColors.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, KhyloSpacing.xs)
                .frame(width: channelColumnWidth, height: rowHeight)
                .background(selectedChannel?.id == channel.id ? KhyloColors.surfaceElevated : KhyloColors.surface)
            }

            // Programs track along the timeline
            let startOfTimeline = timelineStart
            HStack(spacing: 2) {
                ForEach(channel.programs) { program in
                    ProgramCellView(
                        program: program,
                        currentTime: currentTime,
                        isSelected: selectedProgram?.id == program.id,
                        minuteWidth: minuteWidth,
                        rowHeight: rowHeight,
                        onSelect: {
                            selectedChannel = channel
                            selectedProgram = program
                        }
                    )
                }
            }
            .frame(height: rowHeight)
            .padding(.leading, max(CGFloat(channel.programs.first?.start.timeIntervalSince(startOfTimeline) ?? 0) / 60.0 * minuteWidth, 0))
        }
    }

    // MARK: - Empty State

    private var emptyChannelsView: some View {
        VStack(spacing: KhyloSpacing.md) {
            Image(systemName: "tv.slash")
                .font(.system(size: 48))
                .foregroundColor(KhyloColors.textTertiary)

            Text("No Live Channels Configured")
                .font(KhyloTypography.headline)
                .foregroundColor(KhyloColors.textPrimary)

            Text("Live channels are automatically programmed 24/7 streams generated from your library media.")
                .font(KhyloTypography.caption)
                .foregroundColor(KhyloColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, KhyloSpacing.xl)

            Button {
                Task { await loadChannels() }
            } label: {
                Text("Refresh Guide")
                    .font(KhyloTypography.subheadlineMedium)
                    .foregroundColor(KhyloColors.accent)
            }
        }
        .padding(KhyloSpacing.xl)
    }

    // MARK: - Tuning & Timeline Calculations

    private var timelineStart: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: currentTime)
        let min = (comps.minute ?? 0) < 30 ? 0 : 30
        var newComps = comps
        newComps.minute = min
        newComps.second = 0
        let base = cal.date(from: newComps) ?? currentTime
        return base.addingTimeInterval(-30 * 60) // Show 30 mins prior
    }

    private func tuneIn(to channel: LiveChannel, program: LiveChannelProgram) {
        guard !isTuning else { return }
        isTuning = true
        tuningError = nil

        Task {
            do {
                let tune = try await LiveChannelsAPI.shared.tune(channelId: channel.id)
                await MainActor.run {
                    self.isTuning = false
                    // Start playback at tune offset without writing to playback watch history
                    self.navigator.play(
                        itemId: program.itemId,
                        resumePositionTicks: tune.startPositionTicks,
                        title: "\(channel.number) · \(channel.name) (\(program.title))"
                    )
                }
            } catch {
                await MainActor.run {
                    self.isTuning = false
                    self.tuningError = "Failed to tune channel \(channel.number)."
                }
            }
        }
    }

    private func loadChannels() async {
        isLoading = true
        let list = await LiveChannelsAPI.shared.fetchGuide(hours: 6)
        await MainActor.run {
            self.channels = list
            self.selectedChannel = list.first
            self.selectedProgram = list.first?.currentProgram(at: self.currentTime) ?? list.first?.programs.first
            self.isLoading = false
        }
    }

    private func startClock() {
        timerSubscription = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [self] date in
                self.currentTime = date
            }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func timelineSlotView(slotIndex: Int) -> some View {
        let slotDate = timelineStart.addingTimeInterval(Double(slotIndex * timelineIntervalMinutes * 60))
        return HStack {
            Text(formatTime(slotDate))
                .font(KhyloTypography.caption2Medium)
                .foregroundColor(KhyloColors.textSecondary)
                .padding(.leading, 6)
            Spacer()
        }
        .frame(width: CGFloat(timelineIntervalMinutes) * minuteWidth, height: 36)
        .border(KhyloColors.border.opacity(0.3), width: 0.5)
    }
}

// MARK: - Program Cell View

private struct ProgramCellView: View {
    let program: LiveChannelProgram
    let currentTime: Date
    let isSelected: Bool
    let minuteWidth: CGFloat
    let rowHeight: CGFloat
    let onSelect: () -> Void

    private var isNow: Bool {
        program.isAiring(at: currentTime)
    }

    private var cellWidth: CGFloat {
        max(CGFloat(program.durationMinutes) * minuteWidth - 2, 60)
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(program.title)
                        .font(KhyloTypography.captionBold)
                        .foregroundColor(isNow ? KhyloColors.accent : KhyloColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if isNow {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                    }
                }

                if let detail = program.detail {
                    Text(detail)
                        .font(KhyloTypography.caption2)
                        .foregroundColor(KhyloColors.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(formatTime(program.start)) - \(formatTime(program.end))")
                        .font(KhyloTypography.caption2)
                        .foregroundColor(KhyloColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isNow {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 2)

                            Rectangle()
                                .fill(KhyloColors.accent)
                                .frame(width: geo.size.width * CGFloat(program.progress(at: currentTime)), height: 2)
                        }
                    }
                    .frame(height: 2)
                }
            }
            .padding(6)
            .frame(width: cellWidth, height: rowHeight - 6)
            .background(
                isSelected ? KhyloColors.accent.opacity(0.25) :
                isNow ? KhyloColors.surfaceElevated : KhyloColors.surface
            )
            .cornerRadius(KhyloRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.xs)
                    .stroke(
                        isSelected ? KhyloColors.accent :
                        isNow ? KhyloColors.accent.opacity(0.6) :
                        Color.clear,
                        lineWidth: 1
                    )
            )
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
