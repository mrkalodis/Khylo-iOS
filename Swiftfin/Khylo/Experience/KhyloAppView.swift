//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

/// Signed-in app. Each tab hosts its own navigation stack so screens can
/// push details and present the player.
///
/// The tab bar is the system Liquid Glass bar, styled after premium media apps:
/// thin outline icons, the selected tab in the brand color, search as a peer tab.
struct KhyloAppView: View {

    enum TabID: Hashable {
        case home
        case libraries
        case liveTV
        case search
    }

    @State private var selection: TabID = .home
    /// Remembered so a slow or failed check doesn't hide the tab.
    @AppStorage("khylo.hasLiveTV") private var hasLiveTV = false
    @ObservedObject private var libraryStore = KhyloLibraryStore.shared

    /// Choosing Libraries also brings up the library picker.
    private var tabSelection: Binding<TabID> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .libraries {
                    libraryStore.isPickerPresented = true
                }
                selection = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(value: TabID.home) {
                stack { KhyloHomeScreen() }
            } label: {
                tabLabel("Home", "house")
            }

            Tab(value: TabID.libraries) {
                stack { KhyloLibrariesScreen() }
            } label: {
                tabLabel("Libraries", "books.vertical")
            }

            // Only servers with a tuner or IPTV source have channels.
            if hasLiveTV {
                Tab(value: TabID.liveTV) {
                    stack { KhyloLiveTVScreen() }
                } label: {
                    tabLabel("Live TV", "tv")
                }
            }

            Tab(value: TabID.search) {
                stack { KhyloSearchScreen() }
            } label: {
                tabLabel("Search", "magnifyingglass")
            }
        }
        .tint(KhyloStyle.accent)
        .preferredColorScheme(.dark)
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .sheet(isPresented: $libraryStore.isPickerPresented) {
            KhyloLibraryPickerSheet()
        }
        .task {
            await libraryStore.load()
            // Only update on a successful answer; retry a few times if the server is slow.
            for attempt in 0 ..< 3 {
                if let channels = try? await KhyloAPI.channels(limit: 1) {
                    hasLiveTV = !channels.isEmpty
                    break
                }
                try? await Task.sleep(for: .seconds(3 * (attempt + 1)))
            }
        }
    }

    /// Outline icon in every state; the selected tab is picked out by color.
    private func tabLabel(_ title: String, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .environment(\.symbolVariants, .none)
        }
    }

    private func stack(@ViewBuilder _ content: @escaping () -> some View) -> some View {
        NavigationInjectionView(coordinator: NavigationCoordinator()) {
            content()
        }
        .overlay { KhyloStatusBarScrim() }
        // Sits just above the tab bar on every screen of the tab.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KhyloMiniPlayer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: KhyloAudioPlayer.shared.isActive)
    }
}

/// The signed-in user's avatar; opens the account sheet.
struct KhyloProfileButton: View {

    @Router private var router

    var body: some View {
        Button {
            router.route(to: .khyloProfile())
        } label: {
            KhyloImage(
                url: KhyloAPI.session.flatMap { $0.user.profileImageSource(client: $0.client).url },
                placeholderSymbol: "person.fill"
            )
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .accessibilityLabel("Account")
    }
}
