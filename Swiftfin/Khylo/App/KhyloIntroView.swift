//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import AVFoundation
import AVKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct KhyloIntroView: View {
    public let onComplete: () -> Void

    @State private var player: AVPlayer?
    @State private var opacity: Double = 0.0
    @State private var isFinished: Bool = false
    @State private var playerObserver: Any?

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let player {
                KhyloIntroPlayerRepresentable(player: player)
                    .ignoresSafeArea()
            }
        }
        .opacity(opacity)
        .contentShape(Rectangle())
        .onTapGesture {
            finishIntro()
        }
        .onAppear {
            setupPlayerAndStart()
        }
        .onDisappear {
            cleanup()
        }
    }

    private func setupPlayerAndStart() {
        guard let url = Bundle.main.url(forResource: "khylo_intro", withExtension: "mp4") else {
            // Video asset not found in bundle — fade in briefly, wait 0.5s, then complete
            withAnimation(.easeInOut(duration: 0.3)) {
                opacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                finishIntro()
            }
            return
        }

        let avPlayer = AVPlayer(url: url)
        avPlayer.actionAtItemEnd = .none
        self.player = avPlayer

        // Listen for video playback completion
        if let currentItem = avPlayer.currentItem {
            playerObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: currentItem,
                queue: .main
            ) { _ in
                finishIntro()
            }
        }

        // Fade in from black over 0.3s on appear
        withAnimation(.easeInOut(duration: 0.3)) {
            opacity = 1.0
        }

        avPlayer.play()
    }

    private func finishIntro() {
        guard !isFinished else { return }
        isFinished = true

        player?.pause()

        // Fade out to black over 0.3s before calling onComplete
        withAnimation(.easeInOut(duration: 0.3)) {
            opacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            cleanup()
            onComplete()
        }
    }

    private func cleanup() {
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }
        player?.pause()
        player = nil
    }
}

// MARK: - Native Player Representable

#if canImport(UIKit)
private struct KhyloIntroPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
#else
private struct KhyloIntroPlayerRepresentable: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
    }
}
#endif
