//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

/// Launch splash: shows the Khylo logo briefly, then hands off to the app.
public struct KhyloIntroView: View {
    public let onComplete: () -> Void

    // Starts fully visible so it continues seamlessly from LaunchScreen.storyboard.
    @State private var opacity: Double = 1.0
    @State private var isFinished: Bool = false

    /// How long the logo stays fully visible before fading out.
    private let holdDuration: TimeInterval = 1.0

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            KhyloAuthLogo(width: 280)
                .opacity(opacity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            finishIntro()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
                finishIntro()
            }
        }
    }

    private func finishIntro() {
        guard !isFinished else { return }
        isFinished = true

        withAnimation(.easeInOut(duration: 0.3)) {
            opacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onComplete()
        }
    }
}
