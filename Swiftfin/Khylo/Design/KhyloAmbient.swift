//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import SwiftUI

// MARK: - Ambient State

public final class KhyloAmbientState: ObservableObject {
    @MainActor @Published public private(set) var currentImageURL: URL?
    @MainActor @Published public private(set) var isBackdrop: Bool = false
    @MainActor @Published public private(set) var tintColor: Color?

    private var debounceTask: Task<Void, Never>?

    public nonisolated init(currentImageURL: URL? = nil, isBackdrop: Bool = false, tintColor: Color? = nil) {
        self._currentImageURL = Published(initialValue: currentImageURL)
        self._isBackdrop = Published(initialValue: isBackdrop)
        self._tintColor = Published(initialValue: tintColor)
    }

    /// Sets the ambient tint color.
    @MainActor
    public func tint(_ color: Color?) {
        withAnimation(.easeInOut(duration: 0.5)) {
            self.tintColor = color
        }
    }

    /// Shows an ambient artwork image with 280ms debounce.
    ///
    /// - Parameters:
    ///   - url: URL of the poster or backdrop image.
    ///   - isBackdrop: Whether the source image is a 16:9 backdrop (versus 2:3 poster).
    @MainActor
    public func show(url: URL?, isBackdrop: Bool = false) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            // 280ms debounce to prevent flicker during fast scrolling
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                self.currentImageURL = url
                self.isBackdrop = isBackdrop
            }
        }
    }

    /// Clears the ambient background image.
    @MainActor
    public func clear() {
        debounceTask?.cancel()
        withAnimation(.easeInOut(duration: 0.5)) {
            self.currentImageURL = nil
            self.isBackdrop = false
        }
    }
}

// MARK: - Ambient Background View

public struct KhyloAmbientBackground: View {
    @Environment(\.khyloAmbient) private var environmentState
    private var explicitState: KhyloAmbientState?

    public init(ambientState: KhyloAmbientState? = nil) {
        self.explicitState = ambientState
    }

    private var activeState: KhyloAmbientState {
        explicitState ?? environmentState
    }

    public var body: some View {
        AmbientContent(state: activeState)
    }
}

private struct AmbientContent: View {
    @ObservedObject var state: KhyloAmbientState

    var body: some View {
        ZStack {
            // Base background
            KhyloColors.background
                .ignoresSafeArea()

            if let url = state.currentImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .blur(radius: 60)
                            .opacity(0.55)
                            .scaleEffect(1.3)
                            .clipped()
                    default:
                        EmptyView()
                    }
                }
                .id(url)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.5), value: state.currentImageURL)
                .ignoresSafeArea()
            }

            // Readability gradient scrim
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.35),
                    KhyloColors.background.opacity(0.75),
                    KhyloColors.background
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Environment

private struct KhyloAmbientKey: EnvironmentKey {
    static let defaultValue: KhyloAmbientState = KhyloAmbientState()
}

public extension EnvironmentValues {
    var khyloAmbient: KhyloAmbientState {
        get { self[KhyloAmbientKey.self] }
        set { self[KhyloAmbientKey.self] = newValue }
    }
}

public extension View {
    func khyloAmbient(_ state: KhyloAmbientState) -> some View {
        environment(\.khyloAmbient, state)
    }
}
