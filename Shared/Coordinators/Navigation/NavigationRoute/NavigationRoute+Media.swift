//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import PreferencesView
import SwiftUI
import Transmission

extension NavigationRoute {

    @MainActor
    static var liveGuide: NavigationRoute {
        NavigationRoute(
            id: "liveGuide"
        ) {
            EPGView()
        }
    }

    @MainActor
    static var liveTV: NavigationRoute {
        NavigationRoute(
            id: "liveTV",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            ContentGroupView(provider: LiveTVGroupProvider())
        }
    }

    static func mediaSourceInfo(source: MediaSourceInfo) -> NavigationRoute {
        NavigationRoute(
            id: "mediaSourceInfo",
            style: .sheet
        ) {
            MediaSourceInfoView(source: source)
        }
    }

    static func mediaStreamInfo(mediaStream: MediaStream) -> NavigationRoute {
        NavigationRoute(id: "mediaStreamInfo") {
            MediaStreamInfoView(mediaStream: mediaStream)
        }
    }

    @MainActor
    static func videoPlayer(
        provider: MediaPlayerItemProvider,
        queue: (any MediaPlayerQueue)? = nil
    ) -> NavigationRoute {
        let manager = MediaPlayerManager(
            provider: provider,
            queue: queue
        )

        return Self.videoPlayer(manager: manager)
    }

    @MainActor
    static func videoPlayer(manager: MediaPlayerManager) -> NavigationRoute {

        Container.shared.mediaPlayerManager.register {
            manager
        }

        Container.shared.mediaPlayerManagerPublisher()
            .send(manager)

        return NavigationRoute(
            id: "videoPlayer",
            style: .fullscreen
        ) {
            VideoPlayerViewShim(manager: manager)
        }
    }
}

// TODO: shim until native vs swiftfin player is replace with vlc vs av layers
//       - when removed, ensure same behavior with safe area
//       - may just need to make a VC wrapper to capture them

struct VideoPlayerViewShim: View {

    @State
    private var safeAreaInsets: EdgeInsets = .init()

    let manager: MediaPlayerManager

    var body: some View {
        Group {
            switch Defaults[.VideoPlayer.videoPlayerType] {
            case .native:
                NativeVideoPlayer()
            case .vlc, .mpv:
                VideoPlayer()
            }
        }
        .colorScheme(.dark) // use over `preferredColorScheme(.dark)` to not have destination change
        .environment(\.safeAreaInsets, safeAreaInsets)
        .supportedOrientations(.allButUpsideDown)
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onSceneDidEnterBackground {
            if Defaults[.VideoPlayer.Transition.pauseOnBackground] {
                manager.setPlaybackRequestStatus(status: .paused)
            }
        }
        .onFrameChanged { _, safeArea in
            self.safeAreaInsets = safeArea.max(EdgeInsets.edgePadding)
        }
        .onAppear {
            // Phones turn to landscape for video, like other media apps.
            Self.requestOrientation(.landscapeRight)
        }
        .onDisappear {
            Self.requestOrientation(.portrait)
            // Lets browse screens refresh Continue Watching with the new position.
            NotificationCenter.default.post(name: .khyloPlaybackDidEnd, object: nil)
        }
    }
}

extension VideoPlayerViewShim {

    static func requestOrientation(_ orientation: UIInterfaceOrientationMask) {
        guard !UIDevice.isPad,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        // Give the presentation a beat so the new supported orientations are in place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scene.windows.first { $0.isKeyWindow }?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
    }
}

extension Notification.Name {
    /// Posted when the video player closes.
    static let khyloPlaybackDidEnd = Notification.Name("khyloPlaybackDidEnd")
}
