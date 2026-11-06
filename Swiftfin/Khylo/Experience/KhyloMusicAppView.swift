//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

/// The signed-in Khylo Music app: the same music pages as the Khylo app (For You,
/// Browse, Now Playing, downloads), without movies, shows or books.
struct KhyloMusicAppView: View {

    enum TabID: Hashable {
        case music
        case search
        case stats
        case downloads
    }

    @State private var selection: TabID = .music
    @ObservedObject private var libraryStore = KhyloLibraryStore.shared

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: TabID.music) {
                stack(.music) { KhyloMusicHomeTab() }
            } label: {
                tabLabel("Music", "music.note.house")
            }

            Tab(value: TabID.search) {
                stack(.search) { KhyloSearchScreen() }
            } label: {
                tabLabel("Search", "magnifyingglass")
            }

            Tab(value: TabID.stats) {
                stack(.stats) { KhyloStatsScreen() }
            } label: {
                tabLabel("Stats", "chart.bar")
            }

            Tab(value: TabID.downloads) {
                stack(.downloads) { KhyloDownloadsScreen { downloadsHeader } }
            } label: {
                tabLabel("Downloads", "arrow.down.circle")
            }
        }
        .tint(KhyloStyle.accent)
        .preferredColorScheme(.dark)
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .modifier(KhyloNowPlayingPresenter())
        .overlay { KhyloHandoffNotice() }
        .onReceive(KhyloPageRelay.shared.showDownloads) { _ in
            selection = .downloads
        }
        .task {
            _ = KhyloHandoff.shared
            await KhyloHandoff.shared.refresh()
        }
        .task {
            // Back on the song you were listening to when the app was closed.
            KhyloAudioPlayer.shared.restoreSession()
            KhyloDownloads.shared.reconnect()
            await KhyloDownloads.shared.syncProgress()
        }
        .task {
            await libraryStore.load()
            // No connection: open straight onto what's downloaded.
            if libraryStore.errorMessage != nil, KhyloDownloads.shared.hasDownloads {
                selection = .downloads
            }
        }
    }

    private var downloadsHeader: some View {
        HStack {
            Text("Downloads")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            KhyloProfileButton()
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.top, 8)
    }

    private func tabLabel(_ title: String, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .environment(\.symbolVariants, .none)
        }
    }

    private func stack(_ tab: TabID, @ViewBuilder _ content: @escaping () -> some View) -> some View {
        NavigationInjectionView(coordinator: NavigationCoordinator()) {
            content()
                .background { KhyloRouteRelay(isActive: selection == tab) }
        }
        .overlay { KhyloStatusBarScrim() }
        // The mini player sits just above the tab bar on every page while music plays.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KhyloMusicMiniPlayerSlot()
        }
    }
}

private struct KhyloMusicMiniPlayerSlot: View {

    @ObservedObject private var player = KhyloAudioPlayer.shared

    var body: some View {
        Group {
            if player.isActive {
                KhyloMiniPlayer()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.isActive)
    }
}

/// The Music tab: the music library's For You and Browse pages, with its name at the top.
struct KhyloMusicHomeTab: View {

    @ObservedObject private var store = KhyloLibraryStore.shared

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            if store.isLoading {
                KhyloLoadingState()
            } else if store.libraries.isEmpty {
                KhyloEmptyState(
                    systemImage: "music.note",
                    title: "No music library",
                    message: store.errorMessage ?? "Add a music library to your Khylo server and it will appear here.",
                    actionTitle: "Try Again"
                ) {
                    Task { await store.load() }
                }
            } else if let library = store.selected {
                KhyloLibraryHome(library: library) {
                    header(title: library.name ?? "Music")
                }
                .id(library.id)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            if store.libraries.isEmpty { await store.load() }
        }
    }

    /// Just the profile button; with more than one music library, a switcher beside it.
    private func header(title: String) -> some View {
        HStack(alignment: .center) {
            if store.libraries.count > 1 {
                Menu {
                    ForEach(store.libraries, id: \.id) { library in
                        Button {
                            store.select(library.id ?? "")
                        } label: {
                            if library.id == store.selected?.id {
                                Label(library.name ?? "Music", systemImage: "checkmark")
                            } else {
                                Text(library.name ?? "Music")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }

            Spacer()
            KhyloProfileButton()
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.top, 8)
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 34, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
