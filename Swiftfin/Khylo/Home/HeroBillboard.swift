//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Hero Billboard

public struct HeroBillboard: View {

    public let items: [KhyloMediaItem]
    public let onPlay: (KhyloMediaItem) -> Void
    public let onToggleList: (KhyloMediaItem) -> Void
    public let onInfo: (KhyloMediaItem) -> Void

    @State private var currentIndex: Int = 0
    @State private var timerCancellable: AnyCancellable?
    @EnvironmentObject private var ambientState: KhyloAmbientState

    public init(
        items: [KhyloMediaItem],
        onPlay: @escaping (KhyloMediaItem) -> Void,
        onToggleList: @escaping (KhyloMediaItem) -> Void,
        onInfo: @escaping (KhyloMediaItem) -> Void
    ) {
        self.items = items
        self.onPlay = onPlay
        self.onToggleList = onToggleList
        self.onInfo = onInfo
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ZStack(alignment: .bottom) {
                // Background Carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        heroSlide(for: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: 500)

                // Bottom Content & Controls Overlay
                if items.indices.contains(currentIndex) {
                    let activeItem = items[currentIndex]
                    VStack(alignment: .leading, spacing: KhyloSpacing.md) {
                        // Title or Logo
                        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
                            if let logoUrl = activeItem.logoURL() {
                                AsyncImage(url: logoUrl) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 240, maxHeight: 70, alignment: .leading)
                                    default:
                                        titleFallbackView(for: activeItem)
                                    }
                                }
                            } else {
                                titleFallbackView(for: activeItem)
                            }

                            // Metadata Badges Row
                            HStack(spacing: KhyloSpacing.sm) {
                                if let rating = activeItem.communityRating, rating > 0 {
                                    HStack(spacing: 3) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.yellow)
                                        Text(String(format: "%.1f", rating))
                                            .font(KhyloTypography.captionMedium)
                                            .foregroundColor(KhyloColors.textPrimary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(KhyloColors.surfaceElevated.opacity(0.8))
                                    .cornerRadius(KhyloRadius.xs)
                                }

                                if let year = activeItem.productionYear {
                                    Text("\(year)")
                                        .font(KhyloTypography.caption)
                                        .foregroundColor(KhyloColors.textSecondary)
                                }

                                if let officialRating = activeItem.officialRating, !officialRating.isEmpty {
                                    Text(officialRating)
                                        .font(KhyloTypography.captionMedium)
                                        .foregroundColor(KhyloColors.textPrimary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                if !activeItem.genres.isEmpty {
                                    Text(activeItem.genres.prefix(2).joined(separator: " • "))
                                        .font(KhyloTypography.caption)
                                        .foregroundColor(KhyloColors.textSecondary)
                                }
                            }

                            // Overview Description
                            if let overview = activeItem.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(KhyloTypography.caption)
                                    .foregroundColor(KhyloColors.textSecondary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: 420, alignment: .leading)
                            }
                        }

                        // Action Buttons Row
                        HStack(spacing: KhyloSpacing.md) {
                            Button(action: {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                onPlay(activeItem)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Play")
                                        .font(KhyloTypography.headline)
                                }
                                .padding(.horizontal, KhyloSpacing.lg)
                                .frame(height: 44)
                                .background(KhyloColors.accent)
                                .foregroundColor(KhyloColors.textPrimary)
                                .cornerRadius(KhyloRadius.sm)
                            }

                            Button(action: {
                                #if os(iOS)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                                onToggleList(activeItem)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: activeItem.isFavorite ? "checkmark" : "plus")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(activeItem.isFavorite ? "My List" : "Add to List")
                                        .font(KhyloTypography.bodyMedium)
                                }
                                .padding(.horizontal, KhyloSpacing.md)
                                .frame(height: 44)
                                .background(KhyloColors.surfaceElevated.opacity(0.85))
                                .foregroundColor(KhyloColors.textPrimary)
                                .cornerRadius(KhyloRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                        .stroke(KhyloColors.border.opacity(0.6), lineWidth: 1)
                                )
                            }

                            Button(action: {
                                onInfo(activeItem)
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundColor(KhyloColors.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(KhyloColors.surfaceElevated.opacity(0.85))
                                    .cornerRadius(KhyloRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: KhyloRadius.sm)
                                            .stroke(KhyloColors.border.opacity(0.6), lineWidth: 1)
                                    )
                            }

                            Spacer()

                            // Page Indicators
                            HStack(spacing: 5) {
                                ForEach(0..<items.count, id: \.self) { dotIndex in
                                    Capsule()
                                        .fill(dotIndex == currentIndex ? KhyloColors.accent : KhyloColors.textTertiary.opacity(0.4))
                                        .frame(width: dotIndex == currentIndex ? 16 : 6, height: 6)
                                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.bottom, KhyloSpacing.md)
                }
            }
            .frame(height: 500)
            .clipped()
            .onAppear {
                startAutoAdvance()
                updateAmbientColor()
            }
            .onDisappear {
                stopAutoAdvance()
            }
            .onChange(of: currentIndex) { _ in
                updateAmbientColor()
            }
        }
    }

    // MARK: - Slide View

    @ViewBuilder
    private func heroSlide(for item: KhyloMediaItem) -> some View {
        GeometryReader { proxy in
            ZStack {
                if let backdrop = item.backdropURL() {
                    AsyncImage(url: backdrop) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: 500)
                                .clipped()
                        default:
                            fallbackBackdrop()
                        }
                    }
                } else {
                    fallbackBackdrop()
                }

                // Gradients to blend into background
                LinearGradient(
                    gradient: Gradient(colors: [
                        KhyloColors.background.opacity(0.8),
                        Color.clear,
                        KhyloColors.background.opacity(0.6),
                        KhyloColors.background
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    gradient: Gradient(colors: [
                        KhyloColors.background.opacity(0.85),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private func titleFallbackView(for item: KhyloMediaItem) -> some View {
        Text(item.name)
            .font(KhyloTypography.title1)
            .fontWeight(.heavy)
            .foregroundColor(KhyloColors.textPrimary)
            .lineLimit(2)
            .shadow(color: Color.black.opacity(0.7), radius: 6, x: 0, y: 3)
    }

    private func fallbackBackdrop() -> some View {
        LinearGradient(
            colors: [KhyloColors.surfaceElevated, KhyloColors.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Ambient Color Sync

    private func updateAmbientColor() {
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        if let firstGenre = item.genres.first {
            let color = GenreColors.color(for: firstGenre)
            withAnimation(.easeInOut(duration: 0.8)) {
                ambientState.tint(color)
            }
        }
    }

    // MARK: - Auto Advance Timer

    private func startAutoAdvance() {
        guard items.count > 1 else { return }
        timerCancellable = Timer.publish(every: 8.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentIndex = (currentIndex + 1) % items.count
                }
            }
    }

    private func stopAutoAdvance() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}
