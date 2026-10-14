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

// MARK: - Klyrp Counter Manager

@MainActor
public final class KlyrpCounter: ObservableObject {

    public static let shared = KlyrpCounter()

    private let tapsToUnlock: Int = 7

    @Published public private(set) var taps: Int = 0
    @Published public var isShowing: Bool = false
    @Published public var hint: String?
    @Published public var hasInsisted: Bool = false

    private var hintDismissTask: Task<Void, Never>?

    public init() {}

    public func handleTap(isKidsProfile: Bool = false) {
        guard !isKidsProfile else {
            // Disabled on Kids profiles
            return
        }

        taps += 1
        let left = tapsToUnlock - taps

        if left <= 0 {
            taps = 0
            hint = nil
            hasInsisted = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                isShowing = true
            }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } else if taps >= 4 {
            hint = left == 1
                ? "You are 1 step away from being a developer…"
                : "You are \(left) steps away from being a developer…"

            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif

            // Auto-clear hint after 2.5s
            hintDismissTask?.cancel()
            hintDismissTask = Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    self.hint = nil
                }
            }
        }
    }

    public func insist() {
        hasInsisted = true
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }

    public func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            isShowing = false
            hasInsisted = false
        }
    }
}

// MARK: - Klyrp Alien Modal View

public struct KlyrpView: View {

    @ObservedObject var counter: KlyrpCounter
    @State private var autoDismissTask: Task<Void, Never>?

    @MainActor
    public init(counter: KlyrpCounter = .shared) {
        self.counter = counter
    }

    public var body: some View {
        ZStack {
            // Dimmed scrim backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    counter.dismiss()
                }

            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: KhyloSpacing.md) {
                    // Speech Bubble
                    VStack(alignment: .leading, spacing: 4) {
                        Text(counter.hasInsisted ? "I said do not develop my app." : "DO NOT DEVELOP MY APP.")
                            .font(.system(size: 19, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.97, green: 0.95, blue: 0.91))
                            .cornerRadius(18)
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                        // Speech bubble tail
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.97, green: 0.95, blue: 0.91))
                            .offset(x: 24, y: -6)
                    }
                    .frame(maxWidth: 240)
                    .padding(.bottom, 60)

                    // Klyrp Alien Character
                    Button(action: {
                        if !counter.hasInsisted {
                            counter.insist()
                            scheduleDismiss(seconds: 4)
                        } else {
                            counter.dismiss()
                        }
                    }) {
                        klyrpGraphicView
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, KhyloSpacing.lg)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            scheduleDismiss(seconds: 9)
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }

    // MARK: - Klyrp Character Graphic

    @ViewBuilder
    private var klyrpGraphicView: some View {
        if let image = loadKlyrpImage() {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 260)
                .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
        } else {
            // High fidelity vector fallback alien holding sign
            ZStack(alignment: .center) {
                // Alien Head & Body
                VStack(spacing: 0) {
                    // Antennae
                    HStack(spacing: 24) {
                        Circle()
                            .fill(Color(red: 0.35, green: 0.78, blue: 0.35))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(Color(red: 0.35, green: 0.78, blue: 0.35))
                            .frame(width: 12, height: 12)
                    }

                    // Head
                    ZStack {
                        Ellipse()
                            .fill(Color(red: 0.40, green: 0.82, blue: 0.42))
                            .frame(width: 90, height: 70)

                        // Big alien eyes
                        HStack(spacing: 16) {
                            Ellipse()
                                .fill(Color.black)
                                .frame(width: 20, height: 28)
                                .rotationEffect(.degrees(-15))
                                .overlay(
                                    Circle().fill(Color.white).frame(width: 6, height: 6).offset(x: -2, y: -4)
                                )

                            Ellipse()
                                .fill(Color.black)
                                .frame(width: 20, height: 28)
                                .rotationEffect(.degrees(15))
                                .overlay(
                                    Circle().fill(Color.white).frame(width: 6, height: 6).offset(x: 2, y: -4)
                                )
                        }
                    }

                    // Body holding wooden sign
                    ZStack {
                        Capsule()
                            .fill(Color(red: 0.35, green: 0.75, blue: 0.38))
                            .frame(width: 70, height: 80)

                        // Sign board
                        VStack(spacing: 2) {
                            Text("DEV")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(Color(red: 0.60, green: 0.15, blue: 0.15))
                            Rectangle()
                                .fill(Color(red: 0.60, green: 0.15, blue: 0.15))
                                .frame(width: 36, height: 3)
                        }
                        .frame(width: 80, height: 46)
                        .background(Color(red: 0.90, green: 0.75, blue: 0.55))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.45, green: 0.30, blue: 0.18), lineWidth: 2)
                        )
                        .offset(y: 10)
                    }
                }
            }
            .frame(width: 170, height: 260)
        }
    }

    private func loadKlyrpImage() -> UIImage? {
        #if canImport(UIKit)
        if let direct = UIImage(named: "klyrp") {
            return direct
        }
        if let path = Bundle.main.path(forResource: "klyrp", ofType: "webp"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }
        #endif
        return nil
    }

    private func scheduleDismiss(seconds: UInt64) {
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            await MainActor.run {
                counter.dismiss()
            }
        }
    }
}
