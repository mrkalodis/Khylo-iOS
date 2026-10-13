//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Audiobook Player View

public struct AudiobookPlayerView: View {
    @StateObject private var viewModel: AudiobookViewModel
    public let onDismiss: () -> Void

    @State private var showPartsDrawer: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0

    // Warm Paper Aesthetic Color Tokens
    private let warmBackground = Color(red: 21/255, green: 16/255, blue: 11/255) // #15100B
    private let warmAmber = Color(red: 227/255, green: 168/255, blue: 87/255) // #E3A857
    private let warmSurface = Color(red: 32/255, green: 25/255, blue: 18/255)
    private let warmTextSecondary = Color(red: 198/255, green: 184/255, blue: 166/255)

    public init(
        bookId: String,
        bookTitle: String,
        author: String,
        coverURL: URL? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: AudiobookViewModel(
            bookId: bookId,
            bookTitle: bookTitle,
            author: author,
            coverURL: coverURL
        ))
        self.onDismiss = onDismiss
    }

    public init(
        item: KhyloMediaItem,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: AudiobookViewModel(
            bookId: item.id,
            bookTitle: item.name,
            author: item.overview ?? "Audiobook Author",
            coverURL: item.imageURL
        ))
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Warm Aesthetic Background
            warmBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar
                topHeaderBar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                Spacer(minLength: 12)

                // Book Cover with Realistic Book Spine Shadow
                bookCoverView
                    .padding(.horizontal, 48)

                Spacer(minLength: 16)

                // Total Book Completion Progress Badge
                totalProgressBadge
                    .padding(.horizontal, 32)

                // Metadata Section (Title, Author, Current Chapter)
                metadataSection
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                // Scrubber Slider
                scrubberSection
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                // Main Transport Controls (← 10s, Play/Pause, 30s →)
                mainTransportControls
                    .padding(.horizontal, 32)
                    .padding(.top, 20)

                // Bottom Utilities (Speed & Sleep Timer Pills)
                bottomUtilitiesRow
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showPartsDrawer) {
            AudiobookPartsDrawer(
                parts: viewModel.parts,
                currentPartIndex: viewModel.currentPartIndex,
                onSelectPart: { index in
                    viewModel.jumpToPart(index: index)
                },
                onDismiss: {
                    showPartsDrawer = false
                }
            )
        }
    }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                viewModel.pause()
                onDismiss()
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(warmAmber)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(warmSurface))
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Text("AUDIOBOOK")
                .font(KhyloTypography.captionBold)
                .foregroundColor(warmTextSecondary)

            Spacer()

            Button(action: {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                showPartsDrawer = true
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(warmAmber)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(warmSurface))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Book Cover

    private var bookCoverView: some View {
        ZStack {
            if let url = viewModel.coverURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(2/3, contentMode: .fit)
                    default:
                        coverFallback
                    }
                }
            } else {
                coverFallback
            }
        }
        .frame(maxHeight: 280)
        .aspectRatio(2/3, contentMode: .fit)
        .cornerRadius(KhyloRadius.sm)
        .overlay(
            // Book Spine Highlight Effect
            HStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.4), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 14)
                Spacer()
            }
            .cornerRadius(KhyloRadius.sm)
        )
        .shadow(color: Color.black.opacity(0.7), radius: 24, x: -6, y: 14)
    }

    private var coverFallback: some View {
        ZStack {
            LinearGradient(
                colors: [warmSurface, Color(red: 45/255, green: 32/255, blue: 22/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.system(size: 54))
                    .foregroundColor(warmAmber)
                Text(viewModel.bookTitle)
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Total Progress Badge

    private var totalProgressBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 11))
                .foregroundColor(warmAmber)

            Text("\(Int(viewModel.totalCompletionPercentage))% of total book • \(viewModel.totalRemainingString)")
                .font(KhyloTypography.captionMedium)
                .foregroundColor(warmTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(warmSurface)
                .overlay(Capsule().strokeBorder(warmAmber.opacity(0.25), lineWidth: 1))
        )
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(spacing: 4) {
            Text(viewModel.currentPart?.title ?? viewModel.bookTitle)
                .font(KhyloTypography.title2)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Text(viewModel.author)
                .font(KhyloTypography.bodyMedium)
                .foregroundColor(warmAmber)
                .lineLimit(1)

            Text("Part \(viewModel.currentPartIndex + 1) of \(viewModel.parts.count)")
                .font(KhyloTypography.caption)
                .foregroundColor(warmTextSecondary)
        }
    }

    // MARK: - Scrubber

    private var scrubberSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let activeSec = isScrubbing ? scrubTime : viewModel.currentPartTime
                let totalSec = max(viewModel.currentPart?.durationSeconds ?? 1.0, 1.0)
                let progress = min(max(activeSec / totalSec, 0.0), 1.0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: isScrubbing ? 8 : 5)

                    Capsule()
                        .fill(warmAmber)
                        .frame(width: width * progress, height: isScrubbing ? 8 : 5)

                    Circle()
                        .fill(warmAmber)
                        .frame(width: isScrubbing ? 20 : 14, height: isScrubbing ? 20 : 14)
                        .shadow(color: Color.black.opacity(0.4), radius: 4)
                        .offset(x: max((width * progress) - (isScrubbing ? 10 : 7), 0))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isScrubbing { isScrubbing = true }
                            let locationX = min(max(gesture.location.x, 0.0), width)
                            let ratio = locationX / width
                            scrubTime = ratio * totalSec
                        }
                        .onEnded { _ in
                            viewModel.seekPart(to: scrubTime)
                            isScrubbing = false
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                )
            }
            .frame(height: 24)

            // Timestamps
            HStack {
                let activeSec = isScrubbing ? scrubTime : viewModel.currentPartTime
                Text(formatDuration(activeSec))
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(warmTextSecondary)

                Spacer()

                let totalSec = viewModel.currentPart?.durationSeconds ?? 0
                let remaining = max(totalSec - activeSec, 0.0)
                Text("-\(formatDuration(remaining))")
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(warmTextSecondary)
            }
        }
    }

    // MARK: - Main Transport Controls

    private var mainTransportControls: some View {
        HStack(spacing: 36) {
            // Skip -10s
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                viewModel.skip(seconds: -10)
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 32, weight: .medium))
                    Text("10s")
                        .font(KhyloTypography.caption)
                }
                .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())

            // Play / Pause
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.togglePlayPause()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(warmAmber)
                        .frame(width: 76, height: 76)
                        .shadow(color: warmAmber.opacity(0.4), radius: 14)

                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(warmBackground)
                        .offset(x: viewModel.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Skip +30s
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                viewModel.skip(seconds: 30)
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 32, weight: .medium))
                    Text("30s")
                        .font(KhyloTypography.caption)
                }
                .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Bottom Utilities (Speed & Sleep Timer)

    private var bottomUtilitiesRow: some View {
        HStack(spacing: 16) {
            // Speed Pill
            Button(action: {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                viewModel.cyclePlaybackSpeed()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .semibold))
                    Text(viewModel.playbackRate == 1.0 ? "1.0x" : "\(String(format: "%.2gx", viewModel.playbackRate))")
                        .font(KhyloTypography.captionBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(warmSurface)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Sleep Timer Pill
            Button(action: {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                viewModel.cycleSleepTimer()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(viewModel.sleepTimerSecondsRemaining != nil ? warmAmber : .white)

                    if let remaining = viewModel.sleepTimerSecondsRemaining {
                        let mins = remaining / 60
                        let secs = remaining % 60
                        Text("\(mins):\(String(format: "%02d", secs))")
                            .font(KhyloTypography.captionBold)
                            .foregroundColor(warmAmber)
                    } else {
                        Text("Sleep Off")
                            .font(KhyloTypography.captionMedium)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(warmSurface)
                        .overlay(
                            Capsule()
                                .strokeBorder(viewModel.sleepTimerSecondsRemaining != nil ? warmAmber.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}
