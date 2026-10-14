//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Khylo Shell View

public struct KhyloShellView: View {

    @StateObject private var navigator = KhyloNavigator()
    @EnvironmentObject private var ambientState: KhyloAmbientState

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content Area
            Group {
                switch navigator.selectedTab {
                case .home:
                    NavigationStack(path: $navigator.homePath) {
                        KhyloHomeView()
                            .navigationDestination(for: KhyloRoute.self) { route in
                                destinationView(for: route)
                            }
                    }

                case .tv:
                    NavigationStack(path: $navigator.tvPath) {
                        LiveTVView()
                            .navigationDestination(for: KhyloRoute.self) { route in
                                destinationView(for: route)
                            }
                    }

                case .search:
                    NavigationStack(path: $navigator.searchPath) {
                        KhyloSearchView()
                            .navigationDestination(for: KhyloRoute.self) { route in
                                destinationView(for: route)
                            }
                    }

                case .library:
                    NavigationStack(path: $navigator.libraryPath) {
                        LibraryTabView()
                            .navigationDestination(for: KhyloRoute.self) { route in
                                destinationView(for: route)
                            }
                    }

                case .profile:
                    NavigationStack(path: $navigator.profilePath) {
                        KhyloSettingsView()
                            .navigationDestination(for: KhyloRoute.self) { route in
                                destinationView(for: route)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom Docked Bottom Tab Bar
            customTabBar
        }
        .environmentObject(navigator)
        .fullScreenCover(item: $navigator.activePlayback) { request in
            KhyloVideoPlayer(request: request) {
                navigator.stopPlayback()
            }
        }
    }

    // MARK: - Custom Bottom Tab Bar

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(KhyloColors.border.opacity(0.8))

            HStack(spacing: 0) {
                ForEach(KhyloTab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .background(
                KhyloColors.background
                    .opacity(0.92)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    @ViewBuilder
    private func tabButton(for tab: KhyloTab) -> some View {
        let isSelected = navigator.selectedTab == tab

        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            navigator.selectTab(tab)
        }) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(KhyloColors.accent.opacity(0.18))
                            .frame(width: 44, height: 26)
                    }

                    Image(systemName: tab.iconName)
                        .font(.system(size: isSelected ? 18 : 17, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? KhyloColors.accent : KhyloColors.textTertiary)
                }

                Text(tab.title)
                    .font(isSelected ? KhyloTypography.captionMedium : KhyloTypography.caption)
                    .foregroundColor(isSelected ? KhyloColors.textPrimary : KhyloColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destinationView(for route: KhyloRoute) -> some View {
        switch route {
        case .home:
            KhyloHomeView()

        case .itemDetail(let itemId):
            DetailsView(itemId: itemId)

        case .seriesDetail(let seriesId):
            DetailsView(itemId: seriesId)

        case .seasonDetail(let seriesId, _):
            DetailsView(itemId: seriesId)

        case .liveTvGuide:
            LiveTVView()

        case .liveTvChannel(let channelId):
            LiveTVView()

        case .liveChannels:
            LiveChannelsView()

        case .multiView(let channelIds):
            MultiViewPlayer(initialChannelIds: channelIds)

        case .search:
            KhyloSearchView()

        case .library:
            LibraryTabView()

        case .libraryCollection(let collectionId, let title):
            MediaLibraryView(libraryId: collectionId, title: title, collectionType: "collection")

        case .mediaLibrary(let libraryId, let title, let type):
            MediaLibraryView(libraryId: libraryId, title: title, collectionType: type)

        case .personDetail(let personId, let name):
            PersonView(personId: personId, personName: name)

        case .music(let item):
            MusicPlayerView(
                track: MusicTrack(
                    id: item.id,
                    title: item.name,
                    artist: item.seriesName ?? item.overview ?? "Artist",
                    album: item.subtitle,
                    imageURL: item.imageURL
                ),
                onDismiss: { navigator.pop() }
            )

        case .musicHome:
            MusicHomeView()

        case .musicAlbum(let albumId, let title, let artist):
            AlbumView(albumId: albumId, albumTitle: title, artistName: artist)

        case .musicArtist(let artistId, let name):
            ArtistView(artistId: artistId, artistName: name)

        case .audiobook(let item):
            AudiobookPlayerView(item: item, onDismiss: { navigator.pop() })

        case .reader(let item):
            EPUBReaderView(item: item, onDismiss: { navigator.pop() })

        case .profile:
            KhyloSettingsView()

        case .profileSwitcher:
            ProfilePickerView()

        case .settings, .playbackSettings:
            KhyloSettingsView()
        }
    }
}

// MARK: - Live TV View

public struct KhyloLiveTVView: View {
    @EnvironmentObject private var navigator: KhyloNavigator

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KhyloSpacing.lg) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live TV")
                            .font(KhyloTypography.largeTitle)
                            .foregroundColor(KhyloColors.textPrimary)

                        Text("Broadcast channels and electronic program guide")
                            .font(KhyloTypography.body)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.top, KhyloSpacing.md)

                    // On Now Channels
                    VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                        Text("On Now")
                            .font(KhyloTypography.title3)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(.horizontal, KhyloSpacing.lg)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: KhyloSpacing.md) {
                                ForEach(1...6, id: \.self) { ch in
                                    channelCard(number: ch)
                                }
                            }
                            .padding(.horizontal, KhyloSpacing.lg)
                        }
                    }

                    // TV Guide Schedule
                    VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                        Text("Channel Guide")
                            .font(KhyloTypography.title3)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(.horizontal, KhyloSpacing.lg)

                        VStack(spacing: KhyloSpacing.xs) {
                            ForEach(1...5, id: \.self) { row in
                                guideScheduleRow(index: row)
                            }
                        }
                        .padding(.horizontal, KhyloSpacing.lg)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }

    private func channelCard(number: Int) -> some View {
        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                    .fill(KhyloColors.surfaceElevated)
                    .frame(width: 220, height: 124)

                VStack(alignment: .leading) {
                    HStack {
                        Text("CH \(number)")
                            .font(KhyloTypography.captionMedium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(KhyloColors.accent)
                            .cornerRadius(4)

                        Spacer()

                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                    Spacer()
                    Text("Broadcast Network \(number)")
                        .font(KhyloTypography.captionMedium)
                        .foregroundColor(KhyloColors.textPrimary)
                }
                .padding(10)
            }

            Text("Live Program Title")
                .font(KhyloTypography.bodyMedium)
                .foregroundColor(KhyloColors.textPrimary)
                .lineLimit(1)

            Text("Now Showing • 45m left")
                .font(KhyloTypography.caption)
                .foregroundColor(KhyloColors.textTertiary)
        }
        .frame(width: 220)
        .contentShape(Rectangle())
        .onTapGesture {
            navigator.play(itemId: "live-ch-\(number)", title: "Live Channel \(number)")
        }
    }

    private func guideScheduleRow(index: Int) -> some View {
        HStack(spacing: KhyloSpacing.md) {
            Text("0\(index)")
                .font(KhyloTypography.headline)
                .foregroundColor(KhyloColors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Channel \(index) HD")
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textPrimary)

                Text("Evening News & Special Report")
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
            }

            Spacer()

            Text("6:00 PM")
                .font(KhyloTypography.captionMedium)
                .foregroundColor(KhyloColors.textTertiary)
        }
        .padding(KhyloSpacing.md)
        .background(KhyloColors.surface)
        .cornerRadius(KhyloRadius.sm)
    }
}

// MARK: - Search View

public struct KhyloSearchView: View {
    @State private var query: String = ""
    @EnvironmentObject private var navigator: KhyloNavigator

    private let sampleGenres = [
        "Action", "Sci-Fi", "Drama", "Comedy", "Thriller",
        "Animation", "Horror", "Documentary", "Fantasy", "Mystery"
    ]

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KhyloSpacing.lg) {
                    // Search Bar
                    HStack(spacing: KhyloSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(KhyloColors.textSecondary)

                        TextField("Movies, shows, actors, genres...", text: $query)
                            .font(KhyloTypography.body)
                            .foregroundColor(KhyloColors.textPrimary)

                        if !query.isEmpty {
                            Button(action: { query = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(KhyloColors.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.md)
                    .frame(height: 48)
                    .background(KhyloColors.surfaceElevated)
                    .cornerRadius(KhyloRadius.sm)
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.top, KhyloSpacing.md)

                    // Explore Genres
                    VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                        Text("Browse by Genre")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(.horizontal, KhyloSpacing.lg)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: KhyloSpacing.sm),
                                GridItem(.flexible(), spacing: KhyloSpacing.sm)
                            ],
                            spacing: KhyloSpacing.sm
                        ) {
                            ForEach(sampleGenres, id: \.self) { genre in
                                GenreSearchChip(genre: genre) {
                                    query = genre
                                }
                            }
                        }
                        .padding(.horizontal, KhyloSpacing.lg)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Library View

public struct KhyloLibraryView: View {
    @EnvironmentObject private var navigator: KhyloNavigator

    private let librarySections = [
        ("Movies", "film.stack", "All films in collection"),
        ("TV Shows", "tv", "Complete series and episodes"),
        ("Collections", "square.stack.3d.up", "Custom boxsets and sagas"),
        ("Favorites", "heart.fill", "Items in your list"),
        ("Downloads", "arrow.down.circle", "Available offline")
    ]

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KhyloSpacing.lg) {
                    Text("Library")
                        .font(KhyloTypography.largeTitle)
                        .foregroundColor(KhyloColors.textPrimary)
                        .padding(.horizontal, KhyloSpacing.lg)
                        .padding(.top, KhyloSpacing.md)

                    VStack(spacing: KhyloSpacing.sm) {
                        ForEach(librarySections, id: \.0) { title, icon, desc in
                            Button(action: {
                                navigator.push(.libraryCollection(collectionId: title.lowercased(), title: title))
                            }) {
                                HStack(spacing: KhyloSpacing.md) {
                                    Image(systemName: icon)
                                        .font(.system(size: 22))
                                        .foregroundColor(KhyloColors.accent)
                                        .frame(width: 36)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title)
                                            .font(KhyloTypography.headline)
                                            .foregroundColor(KhyloColors.textPrimary)

                                        Text(desc)
                                            .font(KhyloTypography.caption)
                                            .foregroundColor(KhyloColors.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(KhyloColors.textTertiary)
                                }
                                .padding(KhyloSpacing.md)
                                .background(KhyloColors.surface)
                                .cornerRadius(KhyloRadius.sm)
                            }
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                }
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Profile & Settings View

public struct KhyloProfileView: View {
    @EnvironmentObject private var navigator: KhyloNavigator
    @State private var autoSkipIntro: Bool = KhyloPreferences.autoSkipIntros
    @State private var autoSkipCredits: Bool = KhyloPreferences.autoSkipCredits
    @State private var autoPlayNext: Bool = KhyloPreferences.autoPlayNextEpisode
    @State private var selectedSubtitleMode: SubtitleMode = KhyloPreferences.subtitleMode

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: KhyloSpacing.xl) {
                    // Profile Header
                    VStack(spacing: KhyloSpacing.sm) {
                        Circle()
                            .fill(KhyloColors.accent)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text("K")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .shadow(color: KhyloColors.accent.opacity(0.4), radius: 12)

                        Text("Khylo User")
                            .font(KhyloTypography.title2)
                            .foregroundColor(KhyloColors.textPrimary)

                        Text("Primary Account")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                    .padding(.top, KhyloSpacing.lg)

                    // Playback Preferences Section
                    VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                        Text("Playback Preferences")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(.horizontal, KhyloSpacing.lg)

                        VStack(spacing: 0) {
                            Toggle("Auto-Skip Intros", isOn: $autoSkipIntro)
                                .onChange(of: autoSkipIntro) { KhyloPreferences.autoSkipIntros = $0 }
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
                        .background(KhyloColors.surface)
                        .cornerRadius(KhyloRadius.sm)
                        .padding(.horizontal, KhyloSpacing.lg)
                    }

                    // Subtitles Section
                    VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                        Text("Subtitles")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(.horizontal, KhyloSpacing.lg)

                        Picker("Subtitle Mode", selection: $selectedSubtitleMode) {
                            Text("Smart").tag(SubtitleMode.smart)
                            Text("Always On").tag(SubtitleMode.alwaysOn)
                            Text("Only Forced").tag(SubtitleMode.onlyForced)
                            Text("Off").tag(SubtitleMode.off)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, KhyloSpacing.lg)
                        .onChange(of: selectedSubtitleMode) {
                            KhyloPreferences.subtitleMode = $0
                        }
                    }

                    // Reset to Defaults
                    Button(action: {
                        KhyloPreferences.resetToDefaults()
                        autoSkipIntro = KhyloPreferences.autoSkipIntros
                        autoSkipCredits = KhyloPreferences.autoSkipCredits
                        autoPlayNext = KhyloPreferences.autoPlayNextEpisode
                        selectedSubtitleMode = KhyloPreferences.subtitleMode
                    }) {
                        Text("Reset Preferences to Defaults")
                            .font(KhyloTypography.subheadline)
                            .foregroundColor(KhyloColors.textTertiary)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Detail Placeholder View

private struct KhyloDetailPlaceholderView: View {
    let title: String
    let identifier: String

    var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            VStack(spacing: KhyloSpacing.md) {
                Text(title)
                    .font(KhyloTypography.title1)
                    .foregroundColor(KhyloColors.textPrimary)

                Text("ID: \(identifier)")
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textSecondary)
            }
        }
    }
}

// MARK: - Settings Sub View

private struct KhyloSettingsSubView: View {
    var body: some View {
        KhyloProfileView()
    }
}

// MARK: - Player Overlay

private struct KhyloPlayerStubView: View {
    let request: PlaybackRequest
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: {
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(request.title ?? "Playback")
                        .font(KhyloTypography.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding()

                Spacer()

                VStack(spacing: KhyloSpacing.md) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(KhyloColors.accent)

                    Text("Now Playing")
                        .font(KhyloTypography.title2)
                        .foregroundColor(.white)

                    if let ticks = request.resumePositionTicks, ticks > 0 {
                        Text("Resumed at \(ticks / 10_000_000)s")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                }

                Spacer()
            }
        }
    }
}

// MARK: - Genre Search Chip

private struct GenreSearchChip: View {
    let genre: String
    let onSelect: () -> Void

    private var color: Color {
        GenreColors.color(for: genre)
    }

    var body: some View {
        Button(action: {
            onSelect()
        }) {
            HStack {
                Text(genre)
                    .font(KhyloTypography.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(KhyloSpacing.md)
            .frame(height: 72)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(KhyloRadius.md)
        }
    }
}
