//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//


import Combine
import Foundation
import Get
import JellyfinAPI
import SwiftUI

/// One screen that follows another.
struct KhyloMirrorTarget: Decodable, Identifiable, Equatable {
    let sessionID: String
    let deviceName: String?
    let client: String?
    var id: String { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID = "SessionId"
        case deviceName = "DeviceName"
        case client = "Client"
    }
}

/// A running mirror: the followed device and the devices following it.
struct KhyloMirrorInfo: Decodable {
    let sourceSessionID: String
    let sourceName: String?
    let nowPlayingName: String?
    let targets: [KhyloMirrorTarget]

    enum CodingKeys: String, CodingKey {
        case sourceSessionID = "SourceSessionId"
        case sourceName = "SourceName"
        case nowPlayingName = "NowPlayingName"
        case targets = "Targets"
    }
}

private struct KhyloMirrorReference: Decodable {
    let itemID: String?
    let positionTicks: Int?
    let isPaused: Bool?

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
    }
}

/// Mirror: play the same thing on several of a person's devices at once. This device
/// can be followed (and starts a mirror from the player), and it follows by keeping
/// its position within a fraction of a second of the followed device.
@MainActor
final class KhyloMirror: ObservableObject {

    static let shared = KhyloMirror()

    /// The message that asks a follower to tune to a Khylo TV channel.
    static let channelPrefix = "khylo-tv-channel:"

    @Published private(set) var mirrors: [KhyloMirrorInfo] = []
    /// A short plain message about a mirror that couldn't be started.
    @Published private(set) var failure: String?

    private var loop: Task<Void, Never>?
    /// Playback speed this device had before a correction nudged it.
    private var restoreRate: Float?
    private var announcedChannel: String?
    private var lastChannelPost = Date.distantPast

    private init() {}

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - The devices following this one

    /// Devices following this one. The device list leaves this device out, so a mirror
    /// whose source is not in it is the one this device is leading.
    func followers(knownDevices: [KhyloHandoffDevice]) -> [String] {
        let others = Set(knownDevices.map(\.sessionID))
        return mirrors.filter { !others.contains($0.sourceSessionID) }.flatMap { $0.targets.map(\.sessionID) }
    }

    func refresh() async {
        guard let session = KhyloAPI.session else {
            mirrors = []
            return
        }
        if let list = try? await session.client.send(Request<[KhyloMirrorInfo]>(path: "/Khylo/Mirror")).value {
            mirrors = list
        }
    }

    private struct StartBody: Encodable {
        var targets: [String]
        enum CodingKeys: String, CodingKey { case targets = "TargetSessionIds" }
    }

    /// Starts following this device on `device`, or takes it out if it already follows.
    func toggle(_ device: KhyloHandoffDevice, isFollowing: Bool) async -> Bool {
        guard let session = KhyloAPI.session else { return false }
        failure = nil
        do {
            if isFollowing {
                _ = try await session.client.send(Request<Void>(
                    path: "/Khylo/Mirror",
                    method: "DELETE",
                    query: [("sessionId", device.sessionID)]
                ))
            } else {
                _ = try await session.client.send(Request<Void>(
                    path: "/Khylo/Mirror",
                    method: "POST",
                    body: StartBody(targets: [device.sessionID])
                ))
            }
            await refresh()
            return true
        } catch {
            if case let .unacceptableStatusCode(code) = error as? APIError, code == 404, !isFollowing {
                failure = "Your Khylo Server needs updating to use Mirror."
            } else {
                failure = "That didn't work. Make sure the other device is open and signed in as you."
            }
            return false
        }
    }

    // MARK: - Each second

    private func tick() async {
        guard let session = KhyloAPI.session else {
            announcedChannel = nil
            return
        }

        let handoff = KhyloHandoff.shared
        let video = handoff.activeVideoManager
        let audio = KhyloAudioPlayer.shared
        let audioPlaying = video == nil && audio.isActive && audio.isPlaying
        let videoPlaying = video != nil

        await announceChannel(session: session, watching: videoPlaying)

        guard videoPlaying || audioPlaying else {
            if restoreRate != nil { resetRate(video: nil) }
            return
        }

        // Where the followed device is right now, if this device is following one.
        let sent = Date()
        guard let reference = try? await session.client.send(Request<KhyloMirrorReference>(path: "/Khylo/Mirror/Reference")).value else {
            resetRate(video: video)
            return
        }
        let roundTrip = Date().timeIntervalSince(sent)

        let id = (video?.item.id ?? audio.current?.id ?? "").replacingOccurrences(of: "-", with: "").lowercased()
        let wantedID = (reference.itemID ?? "").replacingOccurrences(of: "-", with: "").lowercased()
        guard reference.isPaused != true, !wantedID.isEmpty, wantedID == id, let ticks = reference.positionTicks else {
            resetRate(video: video)
            return
        }

        let wanted = Double(ticks) / 10_000_000 + roundTrip / 2
        let here: Double
        if let video {
            here = Double(video.seconds.microseconds) / 1_000_000
        } else {
            here = audio.clock.currentTime
        }
        let difference = here - wanted // positive: ahead

        if abs(difference) > 1.5 {
            seek(to: wanted + 0.3, video: video)
            resetRate(video: video)
        } else if abs(difference) > 0.12 {
            setRate(difference > 0 ? 0.94 : 1.06, video: video)
        } else {
            resetRate(video: video)
        }
    }

    private func seek(to seconds: Double, video: MediaPlayerManager?) {
        if let video {
            video.proxy?.setSeconds(.seconds(seconds))
        } else {
            KhyloAudioPlayer.shared.seek(to: seconds)
        }
    }

    private func setRate(_ rate: Float, video: MediaPlayerManager?) {
        if let video {
            if restoreRate == nil { restoreRate = video.rate }
            video.proxy?.setRate(rate)
        } else {
            let audio = KhyloAudioPlayer.shared
            if restoreRate == nil { restoreRate = audio.rate }
            audio.rate = rate
        }
    }

    private func resetRate(video: MediaPlayerManager?) {
        guard let rate = restoreRate else { return }
        restoreRate = nil
        if let video {
            video.proxy?.setRate(rate)
        } else {
            KhyloAudioPlayer.shared.rate = rate
        }
    }

    // MARK: - Khylo TV

    private struct ChannelBody: Encodable {
        var channelID: String?
        enum CodingKeys: String, CodingKey { case channelID = "ChannelId" }
    }

    /// While this device watches a Khylo TV channel, tell the server which one (every
    /// ten seconds), so devices following this one can tune to it too.
    private func announceChannel(session: UserSession, watching: Bool) async {
        let channel = watching ? KhyloTVSession.shared.channelID : nil
        if let channel {
            if announcedChannel != channel || Date().timeIntervalSince(lastChannelPost) >= 10 {
                announcedChannel = channel
                lastChannelPost = Date()
                _ = try? await session.client.send(Request<Void>(
                    path: "/Khylo/Mirror/Channel",
                    method: "POST",
                    body: ChannelBody(channelID: channel)
                ))
            }
        } else if announcedChannel != nil {
            announcedChannel = nil
            _ = try? await session.client.send(Request<Void>(
                path: "/Khylo/Mirror/Channel",
                method: "POST",
                body: ChannelBody(channelID: nil)
            ))
        }
    }

    /// A device this one follows moved to a Khylo TV channel: tune to it here too.
    func tuneChannel(_ channelID: String) {
        Task { @MainActor in
            guard let result = try? await KhyloAPI.tuneKhyloTV(channelID: channelID),
                  let current = result.current,
                  let item = try? await KhyloAPI.item(current.itemID)
            else { return }
            let airedAt = Date().addingTimeInterval(-Double(result.startPositionTicks) / 10_000_000)
            KhyloTVSession.shared.start(channelID: channelID, program: current, itemID: current.itemID, airedAt: airedAt)
            guard let provider = KhyloPlayback.liveProvider(item, airedAt: airedAt) else { return }
            KhyloAudioPlayer.shared.isNowPlayingRequested = false
            if let manager = KhyloHandoff.shared.activeVideoManager {
                await manager.playNewItem(provider: provider)
            } else {
                KhyloPageRelay.shared.open(.videoPlayer(provider: provider, queue: nil))
            }
        }
    }
}
