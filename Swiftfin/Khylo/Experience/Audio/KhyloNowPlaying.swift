//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

private extension KhyloAudioPlayer {

    var displayTitle: String {
        guard let item = current else { return "" }
        return kind == .audiobook ? (collectionTitle ?? item.name ?? "") : (item.name ?? "")
    }

    var displaySubtitle: String {
        guard let item = current else { return "" }
        switch kind {
        case .audiobook:
            return item.name ?? ""
        case .music:
            return item.artists?.joined(separator: ", ") ?? item.albumArtist ?? item.album ?? ""
        }
    }

    var displayArtwork: URL? {
        artworkURL ?? current.flatMap { KhyloArtwork.url(for: $0, style: .square, width: 600) }
    }
}

// MARK: - Mini player

/// Frosted bar above the tab bar while something is playing.
struct KhyloMiniPlayer: View {

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @State private var isShowingNowPlaying = false

    var body: some View {
        if player.isActive {
            Button {
                isShowingNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    KhyloImage(url: player.displayArtwork, placeholderSymbol: player.kind == .audiobook ? "headphones" : "music.note")
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(player.displaySubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(KhyloStyle.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.kind == .audiobook ? player.skip(by: 30) : player.next()
                    } label: {
                        Image(systemName: player.kind == .audiobook ? "goforward.30" : "forward.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(height: 56)
                .overlay(alignment: .bottom) {
                    if player.duration > 0 {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(KhyloStyle.accent)
                                .frame(width: proxy.size.width * min(1, player.currentTime / player.duration), height: 2)
                        }
                        .frame(height: 2)
                        .padding(.horizontal, 18)
                    }
                }
                .backport
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(KhyloScaleButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .fullScreenCover(isPresented: $isShowingNowPlaying) {
                KhyloNowPlayingScreen()
            }
        }
    }
}

// MARK: - Now playing

struct KhyloNowPlayingScreen: View {

    @ObservedObject private var player = KhyloAudioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double?
    @State private var isShowingQueue = false

    private let speeds: [Float] = [0.75, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                    .onTapGesture { dismiss() }

                Spacer(minLength: 24)

                KhyloImage(url: player.displayArtwork, placeholderSymbol: player.kind == .audiobook ? "headphones" : "music.note")
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
                    .scaleEffect(player.isPlaying ? 1 : 0.88)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: player.isPlaying)
                    .padding(.horizontal, 32)

                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(player.displayTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(player.displaySubtitle)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                scrubber
                    .padding(.horizontal, 28)
                    .padding(.top, 22)

                transport
                    .padding(.top, 18)

                extras
                    .padding(.horizontal, 32)
                    .padding(.top, 26)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 120 { dismiss() }
            }
        )
        .sheet(isPresented: $isShowingQueue) { queueSheet }
        .onChange(of: player.isActive) { _, isActive in
            if !isActive { dismiss() }
        }
    }

    private var background: some View {
        ZStack {
            KhyloStyle.canvas
            KhyloImage(url: player.displayArtwork, showsPlaceholder: false)
                .scaleEffect(1.6)
                .blur(radius: 70)
                .opacity(0.75)
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { scrubValue ?? player.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0 ... max(player.duration, 1)
            ) { editing in
                if !editing, let value = scrubValue {
                    player.seek(to: value)
                    scrubValue = nil
                }
            }
            .tint(.white)

            HStack {
                Text(Self.format(scrubValue ?? player.currentTime))
                Spacer()
                Text("-" + Self.format(max(0, player.duration - (scrubValue ?? player.currentTime))))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundColor(.white.opacity(0.55))
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer()
            if player.kind == .audiobook {
                transportButton("gobackward.15", size: 30) { player.skip(by: -15) }
            } else {
                transportButton("backward.fill", size: 30) { player.previous() }
            }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    if player.isBuffering && player.isPlaying {
                        ProgressView().tint(.white).scaleEffect(1.4)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .foregroundColor(.white)
                .frame(width: 80, height: 80)
            }
            .buttonStyle(KhyloScaleButtonStyle())
            Spacer()
            if player.kind == .audiobook {
                transportButton("goforward.30", size: 30) { player.skip(by: 30) }
            } else {
                transportButton("forward.fill", size: 30) { player.next() }
            }
            Spacer()
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private var extras: some View {
        HStack {
            if player.kind == .audiobook {
                Menu {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            player.rate = speed
                        } label: {
                            if speed == player.rate {
                                Label(Self.formatSpeed(speed), systemImage: "checkmark")
                            } else {
                                Text(Self.formatSpeed(speed))
                            }
                        }
                    }
                } label: {
                    Text(Self.formatSpeed(player.rate))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 56, height: 36)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }

                Spacer()

                Menu {
                    Button("Off") { player.setSleepTimer(minutes: nil) }
                    Button("End of Part") { player.setSleepTimer(minutes: 0) }
                    ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) Minutes") { player.setSleepTimer(minutes: minutes) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz")
                        if let end = player.sleepTimerEnd {
                            Text(end, style: .timer).monospacedDigit()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(player.sleepTimerEnd == nil ? .white.opacity(0.85) : KhyloStyle.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }

                Spacer()
            } else {
                Spacer()
            }

            Button {
                isShowingQueue = true
            } label: {
                Image(systemName: player.kind == .audiobook ? "list.bullet" : "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 44, height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel(player.kind == .audiobook ? "Parts" : "Up Next")
        }
    }

    private var queueSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { offset, item in
                    Button {
                        player.jump(to: offset)
                        isShowingQueue = false
                    } label: {
                        HStack(spacing: 12) {
                            if offset == player.index {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(KhyloStyle.accent)
                                    .frame(width: 22)
                            } else {
                                Text("\(offset + 1)")
                                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "")
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let runtime = item.khyloRuntime {
                                    Text(runtime).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(player.kind == .audiobook ? "Parts" : "Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isShowingQueue = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func formatSpeed(_ speed: Float) -> String {
        let text = speed == speed.rounded() ? String(format: "%.0f", speed) : String(format: "%g", speed)
        return text + "×"
    }
}
