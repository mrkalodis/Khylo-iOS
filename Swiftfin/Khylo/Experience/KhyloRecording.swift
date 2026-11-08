//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//


import JellyfinAPI
import SwiftUI

/// Recording Live TV: the program on now, one in the guide, or every episode of a show.
enum KhyloRecording {

    /// Only people whose account can manage Live TV can record.
    static var canRecord: Bool {
        KhyloAPI.session?.user.data.policy?.enableLiveTvManagement == true
    }

    private static func requireSession() throws -> UserSession {
        guard let session = KhyloAPI.session else { throw KhyloAPI.APIError.notSignedIn }
        return session
    }

    /// The program on now for a channel, with whether it is already set to record.
    static func currentProgram(channelID: String) async -> BaseItemDto? {
        guard let session = KhyloAPI.session else { return nil }
        let request = Paths.getChannel(channelID: channelID, userID: session.user.id)
        return (try? await session.client.send(request).value)?.currentProgram
    }

    /// Sets a program to record, and returns the new recording's id.
    @discardableResult
    static func record(programID: String) async throws -> String? {
        let session = try requireSession()
        let defaults = try await session.client.send(Paths.getDefaultTimer(programID: programID)).value
        var timer = TimerInfoDto()
        timer.type = defaults.type
        timer.serverID = defaults.serverID
        timer.externalID = defaults.externalID
        timer.channelID = defaults.channelID
        timer.externalChannelID = defaults.externalChannelID
        timer.channelName = defaults.channelName
        timer.programID = defaults.programID
        timer.externalProgramID = defaults.externalProgramID
        timer.name = defaults.name
        timer.overview = defaults.overview
        timer.startDate = defaults.startDate
        timer.endDate = defaults.endDate
        timer.serviceName = defaults.serviceName
        timer.priority = defaults.priority
        timer.prePaddingSeconds = defaults.prePaddingSeconds
        timer.postPaddingSeconds = defaults.postPaddingSeconds
        timer.isPrePaddingRequired = defaults.isPrePaddingRequired
        timer.isPostPaddingRequired = defaults.isPostPaddingRequired
        timer.keepUntil = defaults.keepUntil
        _ = try await session.client.send(Paths.createTimer(timer))
        return await timerID(forProgram: programID)
    }

    static func cancel(timerID: String) async throws {
        let session = try requireSession()
        _ = try await session.client.send(Paths.cancelTimer(timerID: timerID))
    }

    /// Every episode of a show.
    @discardableResult
    static func recordSeries(programID: String) async throws -> String? {
        let session = try requireSession()
        let defaults = try await session.client.send(Paths.getDefaultTimer(programID: programID)).value
        _ = try await session.client.send(Paths.createSeriesTimer(defaults))
        return await programTimers(programID: programID).series
    }

    static func cancelSeries(id: String) async throws {
        let session = try requireSession()
        _ = try await session.client.send(Paths.cancelSeriesTimer(timerID: id))
    }

    static func timerID(forProgram programID: String) async -> String? {
        guard let session = KhyloAPI.session else { return nil }
        let timers = (try? await session.client.send(Paths.getTimers()).value)?.items ?? []
        return timers.first { $0.programID == programID }?.id
    }

    /// The program as the server now has it, so its recording state is current.
    static func programTimers(programID: String) async -> (timer: String?, series: String?) {
        guard let session = KhyloAPI.session,
              let program = try? await session.client.send(Paths.getProgram(programID: programID, userID: session.user.id)).value
        else { return (nil, nil) }
        return (program.timerID, program.seriesTimerID)
    }

    static let noGuideMessage = "There's no guide information for this channel to record."
}

// MARK: - Record button in the live player

/// A red dot in the live player: records the program on now; press again to cancel.
struct KhyloRecordButton: View {

    let channelID: String

    @State private var program: BaseItemDto?
    @State private var isBusy = false
    @State private var message: String?

    private var isRecording: Bool { program?.timerID != nil }

    var body: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(Color(hex: "#E5484D"))
                .opacity(isBusy ? 0.5 : 1)
        }
        .accessibilityLabel(isRecording ? "Recording" : "Record")
        .task(id: channelID) { await load() }
        .alert("Recording", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func load() async {
        program = await KhyloRecording.currentProgram(channelID: channelID)
    }

    private func toggle() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            // The program changes through the evening; look at what is on now.
            await load()
            guard let current = program, let programID = current.id else {
                message = KhyloRecording.noGuideMessage
                return
            }
            do {
                if let timerID = current.timerID {
                    try await KhyloRecording.cancel(timerID: timerID)
                } else {
                    try await KhyloRecording.record(programID: programID)
                }
                await load()
            } catch {
                message = "That didn't work. Check your connection and try again."
            }
        }
    }
}

// MARK: - Guide options

/// What can be done with a program in the guide.
struct KhyloProgramOptions: View {

    let program: BaseItemDto
    let channel: BaseItemDto?
    let onWatch: () -> Void
    let onChanged: (BaseItemDto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current: BaseItemDto
    @State private var isBusy = false
    @State private var message: String?

    init(program: BaseItemDto, channel: BaseItemDto?, onWatch: @escaping () -> Void, onChanged: @escaping (BaseItemDto) -> Void) {
        self.program = program
        self.channel = channel
        self.onWatch = onWatch
        self.onChanged = onChanged
        _current = State(initialValue: program)
    }

    private var isAiring: Bool {
        (current.startDate ?? .distantFuture) <= Date() && (current.endDate ?? .distantPast) > Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(current.khyloProgramName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text([channel?.name ?? current.channelName, timeText].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14))
                    .foregroundColor(KhyloStyle.secondaryText)
                if let overview = current.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 14))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .lineLimit(4)
                        .padding(.top, 4)
                }
            }

            VStack(spacing: 10) {
                if isAiring {
                    optionButton("Watch now", symbol: "play.fill", prominent: true) {
                        dismiss()
                        onWatch()
                    }
                }
                if KhyloRecording.canRecord {
                    optionButton(
                        current.timerID == nil ? "Record this" : "Cancel recording",
                        symbol: current.timerID == nil ? "record.circle" : "xmark.circle",
                        tint: Color(hex: "#E5484D")
                    ) { toggleSingle() }
                    if current.isSeries == true {
                        optionButton(
                            current.seriesTimerID == nil ? "Record every episode" : "Cancel series recording",
                            symbol: "rectangle.stack",
                            tint: Color(hex: "#E5484D")
                        ) { toggleSeries() }
                    }
                }
            }
            if let message {
                Text(message).font(.system(size: 13)).foregroundColor(KhyloStyle.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(KhyloStyle.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var timeText: String? {
        guard let start = current.startDate, let end = current.endDate else { return nil }
        return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func optionButton(_ title: String, symbol: String, prominent: Bool = false, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                Text(title)
                Spacer()
                if isBusy && !prominent { ProgressView().tint(.white) }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(prominent ? .black : tint)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(prominent ? Color.white : Color.white.opacity(0.08)))
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .disabled(isBusy)
    }

    private func refresh() async {
        guard let id = current.id else { return }
        let timers = await KhyloRecording.programTimers(programID: id)
        current.timerID = timers.timer
        current.seriesTimerID = timers.series
        onChanged(current)
    }

    private func toggleSingle() {
        guard let id = current.id else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if let timer = current.timerID {
                    try await KhyloRecording.cancel(timerID: timer)
                } else {
                    try await KhyloRecording.record(programID: id)
                }
                await refresh()
            } catch {
                message = "That didn't work. Check your connection and try again."
            }
        }
    }

    private func toggleSeries() {
        guard let id = current.id else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if let series = current.seriesTimerID {
                    try await KhyloRecording.cancelSeries(id: series)
                } else {
                    try await KhyloRecording.recordSeries(programID: id)
                }
                await refresh()
            } catch {
                message = "That didn't work. Check your connection and try again."
            }
        }
    }
}
