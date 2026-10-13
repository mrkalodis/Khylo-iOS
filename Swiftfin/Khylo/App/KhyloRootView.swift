//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import FactoryKit
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
                    withAnimation(.easeInOut(duration: 0.3)) {
                        configureActiveSession()
                        appState = .ready
                    }
                }
                .transition(.opacity)

            case .ready:
                KhyloShellView()
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
