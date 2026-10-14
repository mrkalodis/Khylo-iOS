//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Quality Option Model

public struct QualityOption: Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let description: String

    public static let allOptions: [QualityOption] = [
        QualityOption(id: 0, name: "Auto", description: "Direct Play / Direct Stream"),
        QualityOption(id: 1, name: "120 Mbps", description: "4K UHD Maximum"),
        QualityOption(id: 2, name: "80 Mbps", description: "4K UHD High"),
        QualityOption(id: 3, name: "40 Mbps", description: "1080p High Quality"),
        QualityOption(id: 4, name: "20 Mbps", description: "1080p Standard"),
        QualityOption(id: 5, name: "10 Mbps", description: "720p HD"),
        QualityOption(id: 6, name: "1.5 Mbps", description: "Data Saver (Mobile)")
    ]
}

// MARK: - Aspect Ratio Mode

public enum VideoAspectRatioMode: String, CaseIterable, Identifiable {
    case fit = "Fit to Screen"
    case fill = "Zoom to Fill"
    case stretch = "Stretch"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .fill: return "arrow.up.left.and.arrow.down.right"
        case .stretch: return "rectangle.expand.vertical"
        }
    }
}

// MARK: - Player Settings Sheet

public struct PlayerSettingsSheet: View {
    @Binding public var selectedQualityIndex: Int
    @Binding public var selectedAudioTrackIndex: Int
    @Binding public var selectedSubtitleTrackIndex: Int
    @Binding public var subtitleOffsetSeconds: Double
    @Binding public var playbackRate: Float
    @Binding public var aspectRatioMode: VideoAspectRatioMode

    public let audioTracks: [String]
    public let subtitleTracks: [String]
    public let onDismiss: () -> Void

    @State private var autoSkipIntros: Bool = KhyloPreferences.autoSkipIntros
    @State private var autoSkipCredits: Bool = KhyloPreferences.autoSkipCredits
    @State private var autoPlayNext: Bool = KhyloPreferences.autoPlayNextEpisode

    private let playbackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init(
        selectedQualityIndex: Binding<Int>,
        selectedAudioTrackIndex: Binding<Int>,
        selectedSubtitleTrackIndex: Binding<Int>,
        subtitleOffsetSeconds: Binding<Double>,
        playbackRate: Binding<Float>,
        aspectRatioMode: Binding<VideoAspectRatioMode>,
        audioTracks: [String],
        subtitleTracks: [String],
        onDismiss: @escaping () -> Void
    ) {
        self._selectedQualityIndex = selectedQualityIndex
        self._selectedAudioTrackIndex = selectedAudioTrackIndex
        self._selectedSubtitleTrackIndex = selectedSubtitleTrackIndex
        self._subtitleOffsetSeconds = subtitleOffsetSeconds
        self._playbackRate = playbackRate
        self._aspectRatioMode = aspectRatioMode
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                KhyloColors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: KhyloSpacing.lg) {
                        // Playback Speed
                        sectionContainer(title: "Playback Speed") {
                            HStack(spacing: 8) {
                                ForEach(playbackRates, id: \.self) { rate in
                                    PlaybackRateButton(
                                        rate: rate,
                                        isSelected: abs(playbackRate - rate) < 0.05,
                                        onSelect: { playbackRate = rate }
                                    )
                                }
                            }
                            .padding(KhyloSpacing.sm)
                        }

                        // Aspect Ratio / Scaling
                        sectionContainer(title: "Aspect Ratio") {
                            HStack(spacing: 8) {
                                ForEach(VideoAspectRatioMode.allCases) { mode in
                                    AspectRatioButton(
                                        mode: mode,
                                        isSelected: aspectRatioMode == mode,
                                        onSelect: { aspectRatioMode = mode }
                                    )
                                }
                            }
                            .padding(KhyloSpacing.sm)
                        }

                        // Quality & Bitrate
                        sectionContainer(title: "Stream Quality & Bitrate") {
                            VStack(spacing: 0) {
                                ForEach(QualityOption.allOptions) { option in
                                    QualityOptionRow(
                                        option: option,
                                        isSelected: selectedQualityIndex == option.id,
                                        isLast: option.id == QualityOption.allOptions.last?.id,
                                        onSelect: {
                                            selectedQualityIndex = option.id
                                            KhyloPreferences.maxBitrateIndex = option.id
                                        }
                                    )
                                }
                            }
                        }

                        // Audio Stream Track
                        sectionContainer(title: "Audio Track") {
                            VStack(spacing: 0) {
                                ForEach(Array(audioTracks.enumerated()), id: \.offset) { index, track in
                                    AudioTrackRow(
                                        track: track,
                                        isSelected: selectedAudioTrackIndex == index,
                                        isLast: index == audioTracks.count - 1,
                                        onSelect: { selectedAudioTrackIndex = index }
                                    )
                                }
                            }
                        }

                        // Subtitle Track
                        sectionContainer(title: "Subtitles") {
                            VStack(spacing: 0) {
                                ForEach(Array(subtitleTracks.enumerated()), id: \.offset) { index, track in
                                    SubtitleTrackRow(
                                        index: index,
                                        track: track,
                                        isSelected: selectedSubtitleTrackIndex == index,
                                        isLast: index == subtitleTracks.count - 1,
                                        onSelect: { selectedSubtitleTrackIndex = index }
                                    )
                                }

                                if selectedSubtitleTrackIndex > 0 {
                                    Divider().background(KhyloColors.border)

                                    // Subtitle Sync Offset
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Subtitle Delay / Offset")
                                                .font(KhyloTypography.captionMedium)
                                                .foregroundColor(KhyloColors.textSecondary)

                                            Spacer()

                                            Text(String(format: "%+.1fs", subtitleOffsetSeconds))
                                                .font(KhyloTypography.captionBold)
                                                .foregroundColor(KhyloColors.accent)

                                            if abs(subtitleOffsetSeconds) > 0.05 {
                                                Button("Reset") {
                                                    subtitleOffsetSeconds = 0.0
                                                }
                                                .font(KhyloTypography.caption)
                                                .foregroundColor(KhyloColors.textTertiary)
                                                .padding(.leading, 8)
                                            }
                                        }

                                        HStack(spacing: 12) {
                                            Button(action: {
                                                subtitleOffsetSeconds -= 0.1
                                            }) {
                                                Image(systemName: "minus")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                                    .background(KhyloColors.surfaceElevated)
                                                    .cornerRadius(KhyloRadius.xs)
                                            }
                                            .buttonStyle(PlainButtonStyle())

                                            Button(action: {
                                                subtitleOffsetSeconds += 0.1
                                            }) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                                    .background(KhyloColors.surfaceElevated)
                                                    .cornerRadius(KhyloRadius.xs)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(KhyloSpacing.md)
                                }
                            }
                        }

                        // Smart Automation Preferences
                        sectionContainer(title: "Smart Features") {
                            VStack(spacing: 0) {
                                Toggle("Auto-Skip Intros", isOn: $autoSkipIntros)
                                    .onChange(of: autoSkipIntros) { KhyloPreferences.autoSkipIntros = $0 }
                                    .padding(KhyloSpacing.md)

                                Divider().background(KhyloColors.border)

                                Toggle("Auto-Skip Credits", isOn: $autoSkipCredits)
                                    .onChange(of: autoSkipCredits) { KhyloPreferences.autoSkipCredits = $0 }
                                    .padding(KhyloSpacing.md)

                                Divider().background(KhyloColors.border)

                                Toggle("Autoplay Next Episode", isOn: $autoPlayNext)
                                    .onChange(of: autoPlayNext) { KhyloPreferences.autoPlayNextEpisode = $0 }
                                    .padding(KhyloSpacing.md)
                            }
                        }
                    }
                    .padding(KhyloSpacing.lg)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Player Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(KhyloColors.accent)
                }
            }
        }
    }

    private func sectionContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(KhyloTypography.captionBold)
                .foregroundColor(KhyloColors.textTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                    .strokeBorder(KhyloColors.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Row Subviews

private struct PlaybackRateButton: View {
    let rate: Double
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            Text(rate == 1.0 ? "1x" : "\(String(format: "%.2gx", rate))")
                .font(isSelected ? KhyloTypography.captionBold : KhyloTypography.captionMedium)
                .foregroundColor(isSelected ? .white : KhyloColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KhyloRadius.xs)
                        .fill(isSelected ? KhyloColors.accent : KhyloColors.surfaceElevated)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct AspectRatioButton: View {
    let mode: VideoAspectRatioMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            HStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 13, weight: .bold))
                Text(mode.rawValue)
                    .font(isSelected ? KhyloTypography.captionBold : KhyloTypography.caption)
            }
            .foregroundColor(isSelected ? .white : KhyloColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: KhyloRadius.xs)
                    .fill(isSelected ? KhyloColors.accent : KhyloColors.surfaceElevated)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct QualityOptionRow: View {
    let option: QualityOption
    let isSelected: Bool
    let isLast: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(KhyloTypography.bodyMedium)
                        .foregroundColor(KhyloColors.textPrimary)
                    Text(option.description)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(KhyloColors.accent)
                }
            }
            .padding(KhyloSpacing.md)
        }
        .buttonStyle(PlainButtonStyle())

        if !isLast {
            Divider().background(KhyloColors.border)
        }
    }
}

private struct AudioTrackRow: View {
    let track: String
    let isSelected: Bool
    let isLast: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? KhyloColors.accent : KhyloColors.textTertiary)
                    .frame(width: 24)

                Text(track)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(KhyloColors.accent)
                }
            }
            .padding(KhyloSpacing.md)
        }
        .buttonStyle(PlainButtonStyle())

        if !isLast {
            Divider().background(KhyloColors.border)
        }
    }
}

private struct SubtitleTrackRow: View {
    let index: Int
    let track: String
    let isSelected: Bool
    let isLast: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            onSelect()
        }) {
            HStack {
                Image(systemName: index == 0 ? "captions.bubble" : "captions.bubble.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? KhyloColors.accent : KhyloColors.textTertiary)
                    .frame(width: 24)

                Text(track)
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(KhyloColors.accent)
                }
            }
            .padding(KhyloSpacing.md)
        }
        .buttonStyle(PlainButtonStyle())

        if !isLast {
            Divider().background(KhyloColors.border)
        }
    }
}
