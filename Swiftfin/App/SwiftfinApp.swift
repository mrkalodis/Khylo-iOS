//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import PreferencesView
import SwiftUI
import UIKit

@main
struct SwiftfinApp: App {

    @UIApplicationDelegateAdaptor(KhyloAppDelegate.self)
    private var appDelegate

    init() {
        Self.configure()

        UIScrollView.appearance().keyboardDismissMode = .onDrag

        // Sometimes the tab bar won't appear properly on push, always have material background.
        UITabBar.appearance().scrollEdgeAppearance = UITabBarAppearance(idiom: .unspecified)

        SwiftfinSpotlight().addSwiftfinToSpotlight()
    }

    var body: some Scene {
        WindowGroup {
            OverlayToastView {
                PreferencesView {
                    WithLocalUserAuthentication {
                        KhyloRootView()
                            .supportedOrientations(UIDevice.isPad ? .allButUpsideDown : .portrait)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// Hands finished background downloads back to Khylo when the system wakes it.
final class KhyloAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Reconnects to downloads that carried on while Khylo was closed.
        _ = KhyloNetwork.shared
        _ = KhyloDownloads.shared
        // Image caches kept under their old names are only a copy of what the server has.
        Task.detached(priority: .background) {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            for name in ["org.jellyfin.swiftfin", "org.jellyfin.swiftfin.local"] {
                try? FileManager.default.removeItem(at: caches.appendingPathComponent(name))
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == KhyloDownloads.sessionIdentifier else {
            completionHandler()
            return
        }
        KhyloDownloads.shared.backgroundCompletion = completionHandler
    }
}

extension UINavigationController {

    // Remove back button text
    override open func viewWillLayoutSubviews() {
        navigationBar.topItem?.backButtonDisplayMode = .minimal
    }
}
