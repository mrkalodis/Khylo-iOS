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

// MARK: - Quality Option

private struct SettingsQualityOption: Identifiable, Hashable {
    let id: Int
    let label: String
    let bitrateText: String
}

// MARK: - Khylo Settings View

public struct KhyloSettingsView: View {

    @EnvironmentObject private var navigator: KhyloNavigator
    @StateObject private var repository = KhyloRepository.shared
    @StateObject private var klyrp = KlyrpCounter.shared

    // Stored settings
    @AppStorage("khylo_maxBitrateIndex", store: UserDefaults(suiteName: "khyloApp"))
    private var maxBitrateIndex: Int = 0

    @AppStorage("khylo_autoSkipIntros", store: UserDefaults(suiteName: "khyloApp"))
    private var autoSkipIntros: Bool = true

    @AppStorage("khylo_autoSkipCredits", store: UserDefaults(suiteName: "khyloApp"))
    private var autoSkipCredits: Bool = true

    @AppStorage("khylo_autoPlayNextEpisode", store: UserDefaults(suiteName: "khyloApp"))
    private var autoPlayNextEpisode: Bool = true

    @AppStorage("khylo_preferredAudioLanguage", store: UserDefaults(suiteName: "khyloApp"))
    private var preferredAudioLanguage: String = "eng"

    @AppStorage("khylo_preferredSubtitleLanguage", store: UserDefaults(suiteName: "khyloApp"))
    private var preferredSubtitleLanguage: String = "eng"

    @AppStorage("khylo_subtitleMode", store: UserDefaults(suiteName: "khyloApp"))
    private var subtitleModeRaw: String = SubtitleMode.smart.rawValue

    @AppStorage("khylo_rememberAudioSubtitleSelections", store: UserDefaults(suiteName: "khyloApp"))
    private var rememberAudioSubtitleSelections: Bool = true

    @AppStorage("khylo_hideWatchedInRecentlyAdded", store: UserDefaults(suiteName: "khyloApp"))
    private var hideWatchedInRecentlyAdded: Bool = false

    @AppStorage("khylo_showMissingEpisodes", store: UserDefaults(suiteName: "khyloApp"))
    private var showMissingEpisodes: Bool = false

    @AppStorage("khylo_showCollections", store: UserDefaults(suiteName: "khyloApp"))
    private var showCollections: Bool = true

    // State for modals
    @State private var showKidsSetupSheet: Bool = false
    @State private var showSignOutAlert: Bool = false

    // App constants
    public static let khyloBuildVersion: String = "DEV-V26.10.010"

    private let qualityOptions: [SettingsQualityOption] = [
        SettingsQualityOption(id: 0, label: "Auto (Recommended)", bitrateText: "Dynamic based on network"),
        SettingsQualityOption(id: 1, label: "Maximum (120 Mbps)", bitrateText: "Original Remux 4K HDR"),
        SettingsQualityOption(id: 2, label: "Very High (60 Mbps)", bitrateText: "High Bitrate 4K"),
        SettingsQualityOption(id: 3, label: "High (20 Mbps)", bitrateText: "1080p Blu-ray Quality"),
        SettingsQualityOption(id: 4, label: "Medium (10 Mbps)", bitrateText: "Fast 1080p Streaming"),
        SettingsQualityOption(id: 5, label: "Low (4 Mbps)", bitrateText: "720p Cellular Quality"),
        SettingsQualityOption(id: 6, label: "Data Saver (1.5 Mbps)", bitrateText: "480p Ultra-Low Bandwidth")
    ]

    private let languages: [(code: String, name: String)] = [
        ("eng", "English"),
        ("spa", "Spanish"),
        ("fra", "French"),
        ("deu", "German"),
        ("ita", "Italian"),
        ("jpn", "Japanese"),
        ("kor", "Korean"),
        ("zho", "Chinese (Mandarin)"),
        ("por", "Portuguese"),
        ("rus", "Russian"),
        ("swe", "Swedish"),
        ("nor", "Norwegian")
    ]

    public init() {}

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: KhyloSpacing.lg) {
                    headerView

                    // 1. Profile & Account
                    profileSection

                    // 2. Playback
                    playbackSection

                    // 3. Audio & Subtitles
                    audioSubtitlesSection

                    // 4. Home Screen
                    homeScreenSection

                    // 5. Server & Device
                    serverDeviceSection

                    // 6. About & Klyrp Build Button
                    aboutSection
                }
                .padding(.horizontal, KhyloSpacing.lg)
                .padding(.bottom, 140)
            }

            // Klyrp Toast Hint Overlay
            if let hint = klyrp.hint {
                VStack {
                    Spacer()
                    Text(hint)
                        .font(KhyloTypography.subheadlineMedium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(KhyloRadius.pill)
                        .shadow(radius: 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 100)
                }
            }

            // Klyrp Alien Modal Overlay
            if klyrp.isShowing {
                KlyrpView(counter: klyrp)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $showKidsSetupSheet) {
            KidsSetupView {
                showKidsSetupSheet = false
            }
        }
        .alert("Sign Out of Khylo?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                performSignOut()
            }
        } message: {
            Text("You will need to reconnect to your media server or scan a QR code to log back in.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(KhyloTypography.largeTitle)
                    .foregroundColor(KhyloColors.textPrimary)

                Text("Preferences, profiles & playback controls")
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
            }
            Spacer()
        }
        .padding(.top, KhyloSpacing.md)
    }

    // MARK: - Profile & Account Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            sectionHeader("Profile & Account", icon: "person.crop.circle.fill")

            VStack(spacing: KhyloSpacing.md) {
                // Current User Banner
                HStack(spacing: KhyloSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(KhyloColors.accent)
                            .frame(width: 52, height: 52)

                        Text("K")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Primary User")
                                .font(KhyloTypography.headline)
                                .foregroundColor(KhyloColors.textPrimary)

                            Text("ADMIN")
                                .font(KhyloTypography.caption2Bold)
                                .foregroundColor(KhyloColors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(KhyloColors.accent.opacity(0.16))
                                .cornerRadius(KhyloRadius.xs)
                        }

                        Text("Default Household Profile")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }

                    Spacer()
                }
                .padding(.bottom, 4)

                Divider().background(KhyloColors.border.opacity(0.4))

                // Profile Actions
                Button(action: {
                    navigator.push(.profileSwitcher)
                }) {
                    settingsActionRow(
                        title: "Switch Profile",
                        subtitle: "Select household member or enter PIN",
                        icon: "arrow.left.arrow.right.circle.fill",
                        color: KhyloColors.accent
                    )
                }

                Divider().background(KhyloColors.border.opacity(0.4))

                Button(action: {
                    showKidsSetupSheet = true
                }) {
                    settingsActionRow(
                        title: "Add Kids Profile",
                        subtitle: "Configure PIN protection & content rating limits",
                        icon: "figure.2.and.child.holdinghands",
                        color: Color(red: 0.23, green: 0.51, blue: 0.96)
                    )
                }

                Divider().background(KhyloColors.border.opacity(0.4))

                Button(action: {
                    showSignOutAlert = true
                }) {
                    settingsActionRow(
                        title: "Sign Out",
                        subtitle: "Disconnect from this server and clear credentials",
                        icon: "rectangle.portrait.and.arrow.right",
                        color: Color(red: 0.94, green: 0.27, blue: 0.27)
                    )
                }
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.md)
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            sectionHeader("Playback Quality & Automation", icon: "play.circle.fill")

            VStack(spacing: KhyloSpacing.md) {
                // Streaming Quality Menu
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Streaming Quality")
                                .font(KhyloTypography.headline)
                                .foregroundColor(KhyloColors.textPrimary)

                            Text(qualityOptions.first(where: { $0.id == maxBitrateIndex })?.bitrateText ?? "")
                                .font(KhyloTypography.caption)
                                .foregroundColor(KhyloColors.textSecondary)
                        }

                        Spacer()

                        Picker("Quality", selection: $maxBitrateIndex) {
                            ForEach(qualityOptions) { opt in
                                Text(opt.label).tag(opt.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(KhyloColors.accent)
                    }
                }

                Divider().background(KhyloColors.border.opacity(0.4))

                Toggle(isOn: $autoSkipIntros) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Skip Intros")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Automatically jump past opening credits")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }
                .tint(KhyloColors.accent)

                Divider().background(KhyloColors.border.opacity(0.4))

                Toggle(isOn: $autoSkipCredits) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Skip End Credits")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Seamlessly trigger Next Up episode playback")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }
                .tint(KhyloColors.accent)

                Divider().background(KhyloColors.border.opacity(0.4))

                Toggle(isOn: $autoPlayNextEpisode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Play Next Episode")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Continuous binge queue for episodic series")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }
                .tint(KhyloColors.accent)
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.md)
        }
    }

    // MARK: - Audio & Subtitles Section

    private var audioSubtitlesSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            sectionHeader("Audio & Subtitles", icon: "waveform.and.mic")

            VStack(spacing: KhyloSpacing.md) {
                // Preferred Audio Language
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preferred Audio Language")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Default soundtrack stream when available")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }

                    Spacer()

                    Picker("Audio Language", selection: $preferredAudioLanguage) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(KhyloColors.accent)
                }

                Divider().background(KhyloColors.border.opacity(0.4))

                // Subtitle Mode
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subtitle Mode")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("When subtitles should automatically activate")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }

                    Spacer()

                    Picker("Subtitle Mode", selection: $subtitleModeRaw) {
                        Text("Smart").tag(SubtitleMode.smart.rawValue)
                        Text("Always On").tag(SubtitleMode.alwaysOn.rawValue)
                        Text("Only Forced").tag(SubtitleMode.onlyForced.rawValue)
                        Text("Off").tag(SubtitleMode.off.rawValue)
                        Text("Default").tag(SubtitleMode.defaultMode.rawValue)
                    }
                    .pickerStyle(.menu)
                    .tint(KhyloColors.accent)
                }

                Divider().background(KhyloColors.border.opacity(0.4))

                // Subtitle Language
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preferred Subtitle Language")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Target language for subtitle captions")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }

                    Spacer()

                    Picker("Subtitle Language", selection: $preferredSubtitleLanguage) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(KhyloColors.accent)
                }

                Divider().background(KhyloColors.border.opacity(0.4))

                Toggle(isOn: $rememberAudioSubtitleSelections) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember Audio & Subtitle Tracks")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Persist language selection across episodes in a series")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }
                .tint(KhyloColors.accent)
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.md)
        }
    }

    // MARK: - Home Screen Section

    private var homeScreenSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            sectionHeader("Home Screen Shelves", icon: "house.fill")

            VStack(spacing: KhyloSpacing.md) {
                Toggle(isOn: $hideWatchedInRecentlyAdded) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide Watched in Recently Added")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Keep newly added shelf focused on unseen content")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }
                .tint(KhyloColors.accent)

                Divider().background(KhyloColors.border.opacity(0.4))

                Toggle(isOn: $showMissingEpisodes) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Missing Episodes")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Highlight gaps in TV series season orders")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }
                .tint(KhyloColors.accent)

                Divider().background(KhyloColors.border.opacity(0.4))

                Toggle(isOn: $showCollections) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Collections Row")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                        Text("Display boxsets and thematic sagas on Home")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }
                .tint(KhyloColors.accent)
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.md)
        }
    }

    // MARK: - Server & Device Section

    private var serverDeviceSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            sectionHeader("Server & Device", icon: "server.rack")

            VStack(spacing: KhyloSpacing.sm) {
                infoRow(
                    title: "Connected Server",
                    value: repository.currentServerUrl?.host ?? "Khylo Primary Server"
                )
                infoRow(
                    title: "Server URL",
                    value: repository.currentServerUrl?.absoluteString ?? "http://localhost:8096"
                )
                infoRow(
                    title: "Server Software",
                    value: "Khylo Core 1.0"
                )
                #if os(iOS)
                infoRow(
                    title: "Device Model",
                    value: UIDevice.current.model
                )
                infoRow(
                    title: "iOS Version",
                    value: UIDevice.current.systemVersion
                )
                #endif
                infoRow(
                    title: "Khylo Core Build",
                    value: Self.khyloBuildVersion
                )
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.md)
        }
    }

    // MARK: - About & Klyrp Easter Egg Trigger

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
            sectionHeader("About Khylo", icon: "info.circle.fill")

            VStack(spacing: KhyloSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Khylo Media Player")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)

                        Text("Cinematic open-source personal streaming experience.")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)

                        Text("Subject to Mozilla Public License v2.0 / GPLv2")
                            .font(KhyloTypography.caption2)
                            .foregroundColor(KhyloColors.textTertiary)
                            .padding(.top, 2)
                    }
                    Spacer()
                }

                Divider().background(KhyloColors.border.opacity(0.4))

                // Interactive Build Version Button (Klyrp Easter Egg Trigger)
                Button(action: {
                    klyrp.handleTap(isKidsProfile: false)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build Version")
                                .font(KhyloTypography.subheadline)
                                .foregroundColor(KhyloColors.textSecondary)

                            Text(Self.khyloBuildVersion)
                                .font(KhyloTypography.captionBold)
                                .foregroundColor(KhyloColors.accent)
                        }

                        Spacer()

                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14))
                            .foregroundColor(KhyloColors.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.md)
        }
    }

    // MARK: - Component Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(KhyloColors.accent)

            Text(title.uppercased())
                .font(KhyloTypography.captionBold)
                .foregroundColor(KhyloColors.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private func settingsActionRow(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: KhyloSpacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 38, height: 38)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KhyloTypography.headline)
                    .foregroundColor(KhyloColors.textPrimary)

                Text(subtitle)
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(KhyloColors.textTertiary)
        }
        .contentShape(Rectangle())
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(KhyloTypography.subheadline)
                .foregroundColor(KhyloColors.textSecondary)
            Spacer()
            Text(value)
                .font(KhyloTypography.captionMedium)
                .foregroundColor(KhyloColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func performSignOut() {
        KhyloPreferences.resetToDefaults()
        repository.configure(serverUrl: nil, userId: nil, accessToken: nil)
        navigator.selectTab(.home)
        navigator.push(.home)
    }
}
