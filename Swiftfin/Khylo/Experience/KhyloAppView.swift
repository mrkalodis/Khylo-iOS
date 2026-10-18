//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
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
        case khyloTV
        case liveTV
        case search
    }

    @State private var selection: TabID = .home
    /// Remembered so a slow or failed check doesn't hide the tab.
    @AppStorage("khylo.hasLiveTV") private var hasLiveTV = false
    @AppStorage("khylo.hasKhyloTV") private var hasKhyloTV = false
    @ObservedObject private var libraryStore = KhyloLibraryStore.shared

    /// Libraries goes back to the library you were last in. The library list comes
    /// up the first time (nothing picked yet) or when you tap Libraries again while
    /// you're already on it.
    private var tabSelection: Binding<TabID> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .libraries,
                   selection == .libraries || libraryStore.selectedID.isEmpty {
                    libraryStore.isPickerPresented = true
                }
                selection = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(value: TabID.home) {
                stack(.home) { KhyloHomeScreen() }
            } label: {
                tabLabel("Home", "house")
            }

            Tab(value: TabID.libraries) {
                stack(.libraries) { KhyloLibrariesScreen() }
            } label: {
                tabLabel("Libraries", "books.vertical")
            }

            // The server's always-on channels, built from your library.
            if hasKhyloTV {
                Tab(value: TabID.khyloTV) {
                    stack(.khyloTV) { KhyloTVScreen() }
                } label: {
                    tabLabel("Khylo TV", "play.tv")
                }
            }

            // Only servers with a tuner or IPTV source have channels.
            if hasLiveTV {
                Tab(value: TabID.liveTV) {
                    stack(.liveTV) { KhyloLiveTVScreen() }
                } label: {
                    tabLabel("Live TV", "tv")
                }
            }

            Tab(value: TabID.search) {
                stack(.search) { KhyloSearchScreen() }
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
            // Khylo TV shows when the server has it turned on and has channels.
            if let enabled = try? await KhyloAPI.khyloTVEnabled() {
                let channels = enabled ? ((try? await KhyloAPI.khyloTVGuide(hours: 1)) ?? []) : []
                hasKhyloTV = !channels.isEmpty
            }
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

    private func stack(_ tab: TabID, @ViewBuilder _ content: @escaping () -> some View) -> some View {
        NavigationInjectionView(coordinator: NavigationCoordinator()) {
            content()
                .background { KhyloRouteRelay(isActive: selection == tab) }
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

// MARK: - Opening pages from outside a tab

/// Lets places that sit above the tabs (Now Playing, the mini player) open a
/// page in whichever tab is showing, e.g. tapping an artist's name.
@MainActor
final class KhyloPageRelay {
    static let shared = KhyloPageRelay()

    let routes = PassthroughSubject<NavigationRoute, Never>()

    func open(_ route: NavigationRoute) {
        routes.send(route)
    }

    /// Opens an artist's page by ID.
    func openArtist(id: String) {
        Task {
            if let artist = try? await KhyloAPI.item(id) {
                open(.khyloItem(artist))
            }
        }
    }
}

/// Sits in each tab's stack and pushes relayed pages onto the tab that's showing.
private struct KhyloRouteRelay: View {
    let isActive: Bool
    @Router private var router

    var body: some View {
        Color.clear
            .onReceive(KhyloPageRelay.shared.routes) { route in
                if isActive { router.route(to: route) }
            }
    }
}
