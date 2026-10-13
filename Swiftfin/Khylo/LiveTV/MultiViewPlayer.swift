//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import SwiftUI

// MARK: - Multi View Layout Mode

public enum MultiViewLayout: String, CaseIterable, Identifiable {
    case single = "Single"
    case dual = "Dual"
    case triple = "Triple"
    case quad = "Quad"
    case spotlight = "Spotlight"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .single: return "rectangle.fill"
        case .dual: return "rectangle.split.2x1.fill"
        case .triple: return "rectangle.split.3x1.fill"
        case .quad: return "square.grid.2x2.fill"
        case .spotlight: return "sidebar.right"
        }
    }
}

// MARK: - Stream Tile State

public struct StreamTile: Identifiable, Hashable {
    public let id: String
    public var channelId: String
    public var channelName: String
    public var channelNumber: String
    public var programTitle: String
    public var isMuted: Bool

    public init(
        id: String = UUID().uuidString,
        channelId: String,
        channelName: String,
        channelNumber: String,
        programTitle: String,
        isMuted: Bool = true
    ) {
        self.id = id
        self.channelId = channelId
        self.channelName = channelName
        self.channelNumber = channelNumber
        self.programTitle = programTitle
        self.isMuted = isMuted
    }
}

// MARK: - Multi View Player

public struct MultiViewPlayer: View {

    @EnvironmentObject private var navigator: KhyloNavigator
    @State private var activeLayout: MultiViewLayout = .quad
    @State private var tiles: [StreamTile] = []
    @State private var audioActiveTileId: String?
    @State private var showSwapSheet: Bool = false
    @State private var tileToSwap: StreamTile?
    @State private var showControls: Bool = true
    @State private var controlsTimer: AnyCancellable?

    private let availableChannels: [(id: String, num: String, name: String, prog: String)] = [
        ("ch-1", "04.1", "NBC Premier", "Today in America Live"),
        ("ch-2", "07.1", "ABC Prime", "World News Tonight"),
        ("ch-3", "11.1", "CBS Showcase", "60 Minutes Investigative"),
        ("ch-4", "28.1", "PBS North", "Nova: Wonders of the Cosmos"),
        ("ch-5", "32.1", "FOX Sports Live", "European Football"),
        ("ch-6", "44.1", "Cinema HD 1", "Dune: Part Two"),
        ("ch-7", "101", "Sci-Fi 24/7", "The Expanse"),
        ("ch-8", "102", "Cinema Classics", "Casablanca")
    ]

    public init(initialChannelIds: [String] = []) {
        // Will initialize in onAppear
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Video Grid Layout
            GeometryReader { geo in
                layoutContent(in: geo.size)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showControls.toggle()
                }
                resetControlsTimer()
            }

            // Top Overlay Control Bar
            if showControls {
                VStack {
                    topControlBar
                    Spacer()
                    bottomHintBar
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSwapSheet) {
            channelSwapSheet
        }
        .onAppear {
            setupInitialTiles()
            resetControlsTimer()
        }
        .onDisappear {
            controlsTimer?.cancel()
        }
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: KhyloSpacing.md) {
            // Close / Exit Button
            Button(action: {
                navigator.pop()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            Text("Multi View (\(tiles.count) Streams)")
                .font(KhyloTypography.headline)
                .foregroundColor(.white)

            Spacer()

            // Layout Mode Switcher
            HStack(spacing: 4) {
                ForEach(MultiViewLayout.allCases) { layout in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            activeLayout = layout
                            enforceTileCount(for: layout)
                        }
                    }) {
                        Image(systemName: layout.systemIcon)
                            .font(.system(size: 14))
                            .foregroundColor(activeLayout == layout ? KhyloColors.accent : .white)
                            .frame(width: 34, height: 32)
                            .background(activeLayout == layout ? Color.white.opacity(0.18) : Color.clear)
                            .cornerRadius(KhyloRadius.xs)
                    }
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.6))
            .cornerRadius(KhyloRadius.sm)

            // Add Stream Button
            if tiles.count < 4 {
                Button(action: {
                    addNextAvailableStream()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(KhyloColors.accent)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, KhyloSpacing.lg)
        .padding(.top, KhyloSpacing.md)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Bottom Hint Bar

    private var bottomHintBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(KhyloColors.accent)
                    .font(.system(size: 12))
                Text("Tap any tile to 'Hear This' stream")
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Text("Rotate device for cinema landscape view")
                .font(KhyloTypography.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, KhyloSpacing.lg)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
    }

    // MARK: - Layout Switcher Implementation

    @ViewBuilder
    private func layoutContent(in size: CGSize) -> some View {
        switch activeLayout {
        case .single:
            if let first = tiles.first {
                tileView(first)
                    .frame(width: size.width, height: size.height)
            }

        case .dual:
            VStack(spacing: 2) {
                ForEach(tiles.prefix(2)) { tile in
                    tileView(tile)
                        .frame(width: size.width, height: (size.height - 2) / 2)
                }
            }

        case .triple:
            VStack(spacing: 2) {
                if let first = tiles.first {
                    tileView(first)
                        .frame(width: size.width, height: (size.height - 2) * 0.52)
                }
                HStack(spacing: 2) {
                    ForEach(tiles.dropFirst().prefix(2)) { tile in
                        tileView(tile)
                            .frame(width: (size.width - 2) / 2, height: (size.height - 2) * 0.48)
                    }
                }
            }

        case .quad:
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    if tiles.indices.contains(0) {
                        tileView(tiles[0])
                            .frame(width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                    }
                    if tiles.indices.contains(1) {
                        tileView(tiles[1])
                            .frame(width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                    }
                }
                HStack(spacing: 2) {
                    if tiles.indices.contains(2) {
                        tileView(tiles[2])
                            .frame(width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                    }
                    if tiles.indices.contains(3) {
                        tileView(tiles[3])
                            .frame(width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                    }
                }
            }

        case .spotlight:
            HStack(spacing: 2) {
                if let main = tiles.first {
                    tileView(main)
                        .frame(width: (size.width - 2) * 0.72, height: size.height)
                }
                VStack(spacing: 2) {
                    let sideTiles = Array(tiles.dropFirst().prefix(3))
                    let sideCount = max(sideTiles.count, 1)
                    let sideHeight = (size.height - CGFloat(sideCount - 1) * 2) / CGFloat(sideCount)
                    ForEach(sideTiles) { side in
                        tileView(side)
                            .frame(width: (size.width - 2) * 0.28, height: sideHeight)
                    }
                }
            }
        }
    }

    // MARK: - Individual Stream Tile View

    private func tileView(_ tile: StreamTile) -> some View {
        let isAudioActive = audioActiveTileId == tile.id

        return ZStack(alignment: .bottomLeading) {
            // Simulated Video Feed Texture
            Rectangle()
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "play.tv")
                            .font(.system(size: 28))
                            .foregroundColor(KhyloColors.textTertiary.opacity(0.4))
                        Text(tile.channelName)
                            .font(KhyloTypography.captionMedium)
                            .foregroundColor(.white.opacity(0.5))
                    }
                )

            // Audio Active Border Highlight
            if isAudioActive {
                Rectangle()
                    .stroke(KhyloColors.accent, lineWidth: 3)
            }

            // Top Left Audio Indicator Pill
            VStack {
                HStack {
                    if isAudioActive {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("AUDIO ACTIVE")
                                .font(KhyloTypography.caption2Bold)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(KhyloColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(KhyloRadius.xs)
                    } else {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    Spacer()

                    // Quick Action Menu (Swap, Solo, Close)
                    if showControls {
                        HStack(spacing: 4) {
                            Button(action: {
                                tileToSwap = tile
                                showSwapSheet = true
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }

                            if tiles.count > 1 {
                                Button(action: {
                                    withAnimation {
                                        removeTile(tile)
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
                }
                .padding(8)
                Spacer()
            }

            // Bottom Info Bar
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CH \(tile.channelNumber) • \(tile.channelName)")
                        .font(KhyloTypography.caption2Bold)
                        .foregroundColor(.white)

                    Text(tile.programTitle)
                        .font(KhyloTypography.caption2)
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer()

                // Tap to Hear Button
                if !isAudioActive {
                    Button(action: {
                        setAudioActive(tile.id)
                    }) {
                        Text("Hear This")
                            .font(KhyloTypography.caption2Medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(KhyloRadius.xs)
                    }
                }
            }
            .padding(8)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap any tile selects audio
            setAudioActive(tile.id)
            resetControlsTimer()
        }
    }

    // MARK: - Channel Swap Sheet

    private var channelSwapSheet: some View {
        NavigationStack {
            List(availableChannels, id: \.id) { ch in
                Button(action: {
                    if let target = tileToSwap,
                       let idx = tiles.firstIndex(where: { $0.id == target.id }) {
                        tiles[idx].channelId = ch.id
                        tiles[idx].channelNumber = ch.num
                        tiles[idx].channelName = ch.name
                        tiles[idx].programTitle = ch.prog
                    }
                    showSwapSheet = false
                }) {
                    HStack(spacing: KhyloSpacing.md) {
                        Text(ch.num)
                            .font(KhyloTypography.captionBold)
                            .foregroundColor(KhyloColors.accent)
                            .frame(width: 44, height: 44)
                            .background(KhyloColors.surfaceElevated)
                            .cornerRadius(KhyloRadius.sm)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.name)
                                .font(KhyloTypography.headline)
                                .foregroundColor(KhyloColors.textPrimary)

                            Text(ch.prog)
                                .font(KhyloTypography.caption)
                                .foregroundColor(KhyloColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle")
                            .foregroundColor(KhyloColors.accent)
                    }
                }
            }
            .navigationTitle("Swap Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSwapSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Logic & Setup

    private func setupInitialTiles() {
        var initial: [StreamTile] = []
        for (i, ch) in availableChannels.prefix(4).enumerated() {
            initial.append(
                StreamTile(
                    channelId: ch.id,
                    channelName: ch.name,
                    channelNumber: ch.num,
                    programTitle: ch.prog,
                    isMuted: i != 0 // Unmute first tile
                )
            )
        }
        self.tiles = initial
        self.audioActiveTileId = initial.first?.id
    }

    private func setAudioActive(_ id: String) {
        audioActiveTileId = id
        for i in tiles.indices {
            tiles[i].isMuted = (tiles[i].id != id)
        }
    }

    private func removeTile(_ tile: StreamTile) {
        tiles.removeAll { $0.id == tile.id }
        if audioActiveTileId == tile.id {
            audioActiveTileId = tiles.first?.id
            if let firstId = tiles.first?.id {
                setAudioActive(firstId)
            }
        }
    }

    private func addNextAvailableStream() {
        guard tiles.count < 4 else { return }
        let currentIds = Set(tiles.map { $0.channelId })
        if let next = availableChannels.first(where: { !currentIds.contains($0.id) }) {
            let newTile = StreamTile(
                channelId: next.id,
                channelName: next.name,
                channelNumber: next.num,
                programTitle: next.prog,
                isMuted: true
            )
            tiles.append(newTile)
        }
    }

    private func enforceTileCount(for layout: MultiViewLayout) {
        switch layout {
        case .single:
            if tiles.count > 1 {
                tiles = Array(tiles.prefix(1))
            }
        case .dual:
            if tiles.count < 2 {
                addNextAvailableStream()
            }
        case .triple:
            while tiles.count < 3 {
                addNextAvailableStream()
            }
        case .quad:
            while tiles.count < 4 {
                addNextAvailableStream()
            }
        case .spotlight:
            while tiles.count < 3 {
                addNextAvailableStream()
            }
        }
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Just(())
            .delay(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [self] in
                withAnimation {
                    self.showControls = false
                }
            }
    }
}
