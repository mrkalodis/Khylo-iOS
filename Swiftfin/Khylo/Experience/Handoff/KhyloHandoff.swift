//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import FactoryKit
import Get
import JellyfinAPI
import SwiftUI

/// One of the person's other devices that can take over playback.
struct KhyloHandoffDevice: Decodable, Identifiable, Equatable {

    let sessionID: String
    let deviceName: String
    let client: String?
    let isPlaying: Bool
    let itemID: String?
    let itemName: String?
    let seriesName: String?
    let positionTicks: Int?
    let runTimeTicks: Int?

    var id: String { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID = "SessionId"
        case deviceName = "DeviceName"
        case client = "Client"
        case isPlaying = "IsPlaying"
        case itemID = "NowPlayingItemId"
        case itemName = "NowPlayingName"
        case seriesName = "NowPlayingSeriesName"
        case positionTicks = "PositionTicks"
        case runTimeTicks = "RunTimeTicks"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        let name = try values.decodeIfPresent(String.self, forKey: .deviceName)
        client = try values.decodeIfPresent(String.self, forKey: .client)
        deviceName = name ?? client ?? "Another device"
        isPlaying = try values.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false
        itemID = try values.decodeIfPresent(String.self, forKey: .itemID)
        itemName = try values.decodeIfPresent(String.self, forKey: .itemName)
        seriesName = try values.decodeIfPresent(String.self, forKey: .seriesName)
        positionTicks = try values.decodeIfPresent(Int.self, forKey: .positionTicks)
        runTimeTicks = try values.decodeIfPresent(Int.self, forKey: .runTimeTicks)
    }

    /// "Some Show · Pilot", or just the title.
    var title: String {
        [seriesName, itemName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var minutesLeft: Int? {
        guard let runTimeTicks, let positionTicks, runTimeTicks > positionTicks else { return nil }
        return max(1, (runTimeTicks - positionTicks) / 600_000_000)
    }

    var timeLeftText: String? {
        guard let minutes = minutesLeft else { return nil }
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours) hr left" : "\(hours) hr \(rest) min left"
        }
        return "\(minutes) min left"
    }
}

/// Moves playback between a person's own devices: take over what another device
/// is playing, or hand over what is playing here.
@MainActor
final class KhyloHandoff: ObservableObject {

    static let shared = KhyloHandoff()

    /// Marks a scheduled Khylo TV program, which can't be handed off.
    static let scheduledMarker = "khylo-scheduled"

    @Published private(set) var devices: [KhyloHandoffDevice] = []
    /// A short plain message shown over the app.
    @Published private(set) var notice: String?

    private weak var manager: MediaPlayerManager?
    private var cancellables = Set<AnyCancellable>()
    private var noticeTask: Task<Void, Never>?

    private init() {
        Container.shared.mediaPlayerManagerPublisher()
            .sink { [weak self] manager in
                Task { @MainActor in self?.manager = manager }
            }
            .store(in: &cancellables)
    }

    /// Other devices that are playing something right now.
    var playingElsewhere: [KhyloHandoffDevice] {
        devices.filter { $0.isPlaying && $0.itemID != nil }
    }

    // MARK: - What's playing here

    struct Playing {
        let title: String
        let positionTicks: Int
        let audioStreamIndex: Int?
        let subtitleStreamIndex: Int?
    }

    private var videoManager: MediaPlayerManager? {
        guard let manager, manager.state != .stopped, manager.state != .error else { return nil }
        return manager
    }

    /// What this device is playing, if it can be handed over. Scheduled Khylo TV
    /// programs and live channels can't.
    func nowPlaying() -> Playing? {
        if let manager = videoManager {
            let item = manager.item
            guard !item.isLiveStream, item.tags?.contains(Self.scheduledMarker) != true else { return nil }
            return Playing(
                title: item.displayTitle,
                positionTicks: Int(manager.seconds.microseconds * 10),
                audioStreamIndex: manager.playbackItem?.selectedAudioStreamIndex,
                subtitleStreamIndex: manager.playbackItem?.selectedSubtitleStreamIndex
            )
        }
        let player = KhyloAudioPlayer.shared
        if let current = player.current {
            return Playing(
                title: current.name ?? "",
                positionTicks: Int(player.currentTime * 10_000_000),
                audioStreamIndex: nil,
                subtitleStreamIndex: nil
            )
        }
        return nil
    }

    var canSend: Bool { nowPlaying() != nil }

    /// Lets go of whatever is playing here once another device has taken it.
    func endLocalPlayback() {
        if let manager = videoManager {
            manager.stop()
        } else {
            _ = stopAudioIfPlaying()
        }
    }

    /// A stop from the server while music or an audiobook is playing here.
    @discardableResult
    func stopAudioIfPlaying() -> Bool {
        let player = KhyloAudioPlayer.shared
        guard videoManager == nil, player.isActive else { return false }
        player.isNowPlayingRequested = false
        player.stop()
        return true
    }

    // MARK: - Devices

    func refresh() async {
        guard let session = KhyloAPI.session else {
            devices = []
            return
        }
        let request = Request<[KhyloHandoffDevice]>(path: "/Khylo/Handoff/Devices")
        if let list = try? await session.client.send(request).value {
            devices = list
        }
    }

    func clear() {
        devices = []
    }

    // MARK: - Sending and bringing

    private struct Body: Encodable {
        var from: String?
        var to: String?
        var position: Int?
        var audio: Int?
        var subtitle: Int?

        enum CodingKeys: String, CodingKey {
            case from = "FromSessionId"
            case to = "ToSessionId"
            case position = "PositionTicks"
            case audio = "AudioStreamIndex"
            case subtitle = "SubtitleStreamIndex"
        }
    }

    private func post(_ body: Body) async throws {
        guard let session = KhyloAPI.session else { return }
        _ = try await session.client.send(Request<Void>(path: "/Khylo/Handoff", method: "POST", body: body))
    }

    /// Hands what is playing here to another device, at the exact moment.
    func send(to device: KhyloHandoffDevice) async -> Bool {
        guard let playing = nowPlaying() else { return false }
        do {
            try await post(Body(
                to: device.sessionID,
                position: playing.positionTicks,
                audio: playing.audioStreamIndex,
                subtitle: playing.subtitleStreamIndex
            ))
            show("Sent to \(device.deviceName)")
            return true
        } catch {
            show(message(for: error))
            return false
        }
    }

    /// Brings what another device is playing to this one.
    func bringHere(from device: KhyloHandoffDevice) async -> Bool {
        do {
            try await post(Body(from: device.sessionID))
            show("Now playing here, from \(device.deviceName)")
            return true
        } catch {
            show(message(for: error))
            return false
        }
    }

    private func message(for error: Error) -> String {
        if case let .unacceptableStatusCode(code) = error as? APIError {
            if code == 404 { return "That device is no longer online." }
            if code == 400 { return "Nothing is playing there." }
        }
        return "That didn't work. Make sure the other device is open and signed in as you."
    }

    private func show(_ text: String) {
        noticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { notice = nil }
        }
    }

    // MARK: - Receiving

    /// The server told this device to play something (another device handed it over).
    func receive(_ request: PlayRequest, session: UserSession) {
        Task { await play(request, session: session) }
    }

    private func play(_ request: PlayRequest, session: UserSession) async {
        let ids = request.itemIDs ?? []
        guard let firstID = ids[safe: request.startIndex ?? 0] ?? ids.first,
              let first = try? await KhyloAPI.item(firstID)
        else { return }

        let isSpoken = first.type == .audioBook || KhyloAPI.extendedKind(of: first) == .podcastEpisode
        if first.type == .audio || first.type == .audioBook {
            await playAudio(first, ids: ids, request: request, isSpoken: isSpoken)
        } else {
            playVideo(first, request: request, session: session)
        }
    }

    private func playVideo(_ item: BaseItemDto, request: PlayRequest, session: UserSession) {
        let source = item.mediaSources?.first { $0.id == request.mediaSourceID }
        guard var provider = item.getPlaybackItemProvider(
            userSession: session,
            mediaSource: source,
            audioStreamIndex: request.audioStreamIndex,
            subtitleStreamIndex: request.subtitleStreamIndex
        ) else { return }

        if let ticks = request.startPositionTicks {
            provider = provider.modifyingItem { item in
                if item.userData == nil {
                    item.userData = UserItemDataDto(itemID: item.id, key: item.id ?? "")
                }
                item.userData?.playbackPositionTicks = ticks
            }
        }

        // Music and audiobooks make way for the video.
        KhyloAudioPlayer.shared.isNowPlayingRequested = false

        if let manager = videoManager {
            manager.playNewItem(provider: provider)
        } else {
            let queue: (any MediaPlayerQueue)? = item.type == .episode ? EpisodeMediaPlayerQueue(episode: item) : nil
            KhyloPageRelay.shared.open(.videoPlayer(provider: provider, queue: queue))
        }
    }

    private func playAudio(_ first: BaseItemDto, ids: [String], request: PlayRequest, isSpoken: Bool) async {
        // A video closes first; the song or book takes its place.
        await videoManager?.stop()

        let player = KhyloAudioPlayer.shared
        let kind: KhyloAudioPlayer.Kind = isSpoken ? .audiobook : .music

        if ids.count > 1 {
            var items: [BaseItemDto] = []
            for id in ids {
                if let item = try? await KhyloAPI.item(id) { items.append(item) }
            }
            let start = min(request.startIndex ?? 0, max(items.count - 1, 0))
            guard !items.isEmpty else { return }
            player.play(items, startAt: start, kind: kind, startTicks: request.startPositionTicks)
        } else if isSpoken,
                  let parentID = first.parentID,
                  let book = try? await KhyloAPI.item(parentID),
                  let parts = try? await KhyloAudiobook.parts(of: parentID),
                  let index = parts.firstIndex(where: { $0.id == first.id })
        {
            player.play(
                parts,
                startAt: index,
                kind: .audiobook,
                collectionTitle: KhyloAudiobook.cleanTitle(book.name ?? "").title,
                artworkURL: KhyloAudiobook.artworkURL(book: book, parts: parts),
                startTicks: request.startPositionTicks
            )
        } else {
            player.play([first], kind: kind, startTicks: request.startPositionTicks)
        }
        player.isNowPlayingRequested = true
    }
}

// MARK: - Notice

/// The short message that appears at the top after a handoff.
struct KhyloHandoffNotice: View {

    @ObservedObject private var handoff = KhyloHandoff.shared

    var body: some View {
        Group {
            if let text = handoff.notice {
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}
