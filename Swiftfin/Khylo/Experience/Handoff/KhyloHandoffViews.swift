//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

private var thisDeviceName: String {
    UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
}

// MARK: - List

/// Your other devices: take over what one is playing, or hand it what is
/// playing here.
struct KhyloHandoffList: View {

    /// Called after something playing here was handed to another device.
    var onSent: (() -> Void)? = nil
    var onFinished: (() -> Void)? = nil

    @ObservedObject private var handoff = KhyloHandoff.shared
    @State private var busyID: String?
    @State private var hasLoaded = false

    private var canSend: Bool { handoff.canSend }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !hasLoaded {
                    ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 50)
                } else if handoff.devices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(.white.opacity(0.35))
                        Text("No other devices found. Open Khylo on your TV or tablet, signed in as you.")
                            .font(.system(size: 15))
                            .foregroundColor(KhyloStyle.tertiaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
                    .padding(.horizontal, 30)
                } else {
                    if !handoff.playingElsewhere.isEmpty {
                        section("Bring to this \(thisDeviceName)") {
                            ForEach(handoff.playingElsewhere) { device in
                                bringRow(device)
                            }
                        }
                    }
                    if canSend {
                        section("Send what's playing") {
                            ForEach(handoff.devices) { device in
                                sendRow(device)
                            }
                        }
                    } else if handoff.playingElsewhere.isEmpty {
                        section("Your devices") {
                            ForEach(handoff.devices) { device in
                                infoRow(device)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 30)
        }
        .task {
            while !Task.isCancelled {
                await handoff.refresh()
                hasLoaded = true
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, KhyloStyle.gutter)
            VStack(spacing: 8) { content() }
                .padding(.horizontal, KhyloStyle.gutter)
        }
    }

    private func symbol(for device: KhyloHandoffDevice) -> String {
        let client = (device.client ?? "").lowercased()
        if client.contains("tv") { return "tv" }
        if client.contains("web") { return "laptopcomputer" }
        if client.contains("ipad") { return "ipad" }
        return "iphone"
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func bringRow(_ device: KhyloHandoffDevice) -> some View {
        Button {
            Task {
                busyID = device.id
                let done = await handoff.bringHere(from: device)
                busyID = nil
                if done { onFinished?() }
            }
        } label: {
            card {
                HStack(spacing: 14) {
                    Image(systemName: symbol(for: device))
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(KhyloStyle.accent)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.title.isEmpty ? "Playing" : device.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text([device.deviceName, device.timeLeftText].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    Spacer(minLength: 8)
                    if busyID == device.id {
                        ProgressView().tint(.white)
                    } else {
                        Text("Bring here")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Capsule().fill(Color.white))
                    }
                }
            }
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .disabled(busyID != nil)
    }

    private func sendRow(_ device: KhyloHandoffDevice) -> some View {
        Button {
            Task {
                busyID = device.id
                let done = await handoff.send(to: device)
                busyID = nil
                if done {
                    onSent?()
                    onFinished?()
                }
            }
        } label: {
            card {
                HStack(spacing: 14) {
                    Image(systemName: symbol(for: device))
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.deviceName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        if device.isPlaying, !device.title.isEmpty {
                            Text("Will replace \(device.title)")
                                .font(.system(size: 13))
                                .foregroundColor(KhyloStyle.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if busyID == device.id {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .buttonStyle(KhyloScaleButtonStyle())
        .disabled(busyID != nil)
    }

    private func infoRow(_ device: KhyloHandoffDevice) -> some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: symbol(for: device))
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.deviceName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Nothing playing")
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.tertiaryText)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Sheet and buttons

struct KhyloHandoffSheet: View {

    var onSent: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Handoff")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, KhyloStyle.gutter)
            .padding(.top, 22)
            .padding(.bottom, 10)

            KhyloHandoffList(onSent: onSent, onFinished: { dismiss() })
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

/// The Handoff button in the players. It hands what's playing here to another device.
struct KhyloHandoffButton: View {

    var color: Color = .white
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Handoff")
        .sheet(isPresented: $isPresented) {
            KhyloHandoffSheet {
                KhyloHandoff.shared.endLocalPlayback()
            }
        }
    }
}

// MARK: - Home card

/// On Home: when another of your devices is playing something, a way to bring it here.
struct KhyloHandoffCard: View {

    @ObservedObject private var handoff = KhyloHandoff.shared
    @State private var isSpoken = false
    @State private var isBusy = false

    var body: some View {
        Group {
            if let device = handoff.playingElsewhere.first {
                Button {
                    Task {
                        isBusy = true
                        _ = await handoff.bringHere(from: device)
                        isBusy = false
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(KhyloStyle.accent)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isSpoken ? "Bring audiobook here" : "Bring to this \(thisDeviceName)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text(subtitle(for: device))
                                .font(.system(size: 13))
                                .foregroundColor(KhyloStyle.tertiaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                }
                .buttonStyle(KhyloScaleButtonStyle())
                .disabled(isBusy)
                .padding(.horizontal, KhyloStyle.gutter)
                .transition(.opacity)
                .task(id: device.itemID) {
                    guard let id = device.itemID, let item = try? await KhyloAPI.item(id) else { return }
                    isSpoken = item.type == .audioBook || KhyloAPI.extendedKind(of: item) == .podcastEpisode
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: handoff.playingElsewhere)
        .task {
            while !Task.isCancelled {
                await handoff.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func subtitle(for device: KhyloHandoffDevice) -> String {
        let title = device.title.isEmpty ? "What's playing" : device.title
        var text = "\(title) from \(device.deviceName)"
        if let left = device.timeLeftText { text += ", \(left)" }
        return text
    }
}
