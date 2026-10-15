//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Defaults
import FactoryKit
import Logging
import SwiftUI

public enum KhyloAppState: Equatable {
    case intro
    case loading
    case unauthenticated
    case ready
}

public struct KhyloRootView: View {

    // Requires FactoryKit - registered in SwiftfinApp
    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @StateObject
    private var ambientState = KhyloAmbientState()

    @State
    private var appState: KhyloAppState = .intro

    @MainActor
    private static var isDataStackReady = false

    public init() {}

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            switch appState {
            case .intro:
                KhyloIntroView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState = .loading
                    }
                }
                .transition(.opacity)

            case .loading:
                ZStack {
                    KhyloAmbientBackground(ambientState: ambientState)

                    ProgressView()
                        .tint(KhyloColors.accent)
                        .scaleEffect(1.2)
                }
                .transition(.opacity)
                .task {
                    await resolveSessionState()
                }

            case .unauthenticated:
                KhyloStartupView {
                    // Only enter the app with a real session; the session observer
                    // below handles the transition once sign-in completes.
                    guard userSessionManager.state == .signedIn else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState = .ready
                    }
                }
                .transition(.opacity)

            case .ready:
                KhyloAppView()
                    .transition(.opacity)
            }
        }
        .background(KhyloColors.background)
        .animation(.easeInOut(duration: 0.3), value: appState)
        .environmentObject(ambientState)
        .khyloAmbient(ambientState)
        .onChange(of: userSessionManager.state) { newState in
            if newState == .signedOut && appState == .ready {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState = .unauthenticated
                }
            } else if newState == .signedIn && appState != .ready {
                configureActiveSession()
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState = .ready
                }
            }
        }
    }

    /// Resolves the user session state before transitioning to ready or unauthenticated.
    private func resolveSessionState() async {
        // The local database holds saved servers, users and settings. It must be
        // opened before the stored session is read or any sign-in is saved.
        if !Self.isDataStackReady {
            do {
                try await SwiftfinStore.setupDataStack()
                Self.isDataStackReady = true
            } catch {
                Logger.swiftfin().critical("Failed to open local database: \(error.localizedDescription)")
            }
        }

        // Player controls and other shared components tint with this color.
        Defaults[.accentColor] = KhyloColors.accent

        if userSessionManager.state == .initial {
            await userSessionManager.start()
        }

        try? await Task.sleep(nanoseconds: 250_000_000)

        withAnimation(.easeInOut(duration: 0.3)) {
            if userSessionManager.state == .signedIn && userSessionManager.currentSession != nil {
                configureActiveSession()
                appState = .ready
            } else {
                appState = .unauthenticated
            }
        }
    }

    private func configureActiveSession() {
        if let session = userSessionManager.currentSession {
            KhyloRepository.shared.configure(
                serverUrl: session.server.effectiveServerURL,
                userId: session.user.id,
                accessToken: session.user.accessToken
            )
        }
    }
}
