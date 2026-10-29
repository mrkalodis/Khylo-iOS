//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

@MainActor
final class KhyloHomeModel: ObservableObject {

    @Published private(set) var libraries: [BaseItemDto] = []
    @Published private(set) var sections: [KhyloFeedSection] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Re-fetches only Continue Watching and Up Next and swaps them in place,
    /// so progress from this device or any other shows up without a reload.
    func refreshInProgress() async {
        guard hasLoaded else { return }
        async let resume = KhyloAPI.resume(limit: 20)
        async let next = KhyloAPI.nextUp(limit: 20)
        guard let resumeItems = try? await resume else { return }
        let resumeIDs = Set(resumeItems.compactMap(\.id))
        let upNext = KhyloRowRemovals.shared.visibleUpNext(((try? await next) ?? []).filter { !resumeIDs.contains($0.id ?? "") })

        var lead: [KhyloFeedSection] = []
        if !resumeItems.isEmpty {
            lead.append(.init(id: "home-resume", title: "Continue Watching", action: .play, items: resumeItems))
        }
        if !upNext.isEmpty {
            lead.append(.init(id: "home-upnext", title: "Up Next", action: .play, items: upNext))
        }
        let rest = sections.filter { $0.id != "home-resume" && $0.id != "home-upnext" }
        withAnimation(.easeInOut(duration: 0.25)) {
            sections = lead + rest
        }
    }

    func load() async {
        errorMessage = nil
        do {
            async let resume = KhyloAPI.resume(limit: 20)
            async let next = KhyloAPI.nextUp(limit: 20)
            let allLibraries = try await KhyloAPI.libraries()
            libraries = allLibraries.filter { $0.collectionType != .livetv && $0.collectionType != .playlists }

            let resumeItems = (try? await resume) ?? []
            let resumeIDs = Set(resumeItems.compactMap(\.id))
            let upNext = KhyloRowRemovals.shared.visibleUpNext(((try? await next) ?? []).filter { !resumeIDs.contains($0.id ?? "") })

            var rows: [KhyloFeedSection] = []
            if !resumeItems.isEmpty {
                rows.append(.init(id: "home-resume", title: "Continue Watching", action: .play, items: resumeItems))
            }
            if !upNext.isEmpty {
                rows.append(.init(id: "home-upnext", title: "Up Next", action: .play, items: upNext))
            }

            // Each library contributes its rows, in a deliberate order: watch, listen, read.
            let order: (BaseItemDto) -> Int = { library in
                switch (library.collectionType, KhyloAPI.extendedCollectionType(for: library)) {
                case (.movies, _): 0
                case (.tvshows, _): 1
                case (_, .audiobooks?): 2
                case (.books, _): 3
                case (_, .comics?): 3
                case (.music, _): 4
                default: 5
                }
            }
            // Show what's in progress right away; library rows stream in after.
            sections = rows
            isLoading = false

            let ordered = libraries.sorted { order($0) < order($1) }
            libraries = ordered
            let perLibrary = await withTaskGroup(of: (Int, [KhyloFeedSection]).self) { group in
                for (index, library) in ordered.enumerated() {
                    let includeResume = KhyloAPI.extendedCollectionType(for: library) == .audiobooks
                    group.addTask { (index, await KhyloFeedBuilder.sections(for: library, includeResume: includeResume)) }
                }
                var results: [(Int, [KhyloFeedSection])] = []
                for await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
            }
            sections = rows + perLibrary
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct KhyloHomeScreen: View {

    @StateObject private var model = KhyloHomeModel()
    @Router private var router

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()

            if model.isLoading {
                KhyloLoadingState()
            } else if let error = model.errorMessage, model.sections.isEmpty {
                KhyloEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Can't reach your server",
                    message: error,
                    actionTitle: "Try Again"
                ) {
                    Task { await model.load() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        KhyloHandoffCard()
                        KhyloFeedView(sections: model.sections)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 40)
                }
                .refreshable { await model.load() }
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await model.loadIfNeeded()
            // While Home is on screen, pick up progress made on other devices.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await model.refreshInProgress()
            }
        }
        .onAppear {
            Task { await model.refreshInProgress() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .khyloPlaybackDidEnd)) { _ in
            Task {
                // Give the server a moment to record the final position.
                try? await Task.sleep(for: .seconds(1.5))
                await model.refreshInProgress()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshInProgress() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .khyloProgressDidChange)) { _ in
            Task { await model.refreshInProgress() }
        }
    }

    private var header: some View {
        HStack {
            KhyloAuthLogo(width: 108)
            Spacer()
            KhyloProfileButton()
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.top, 6)
    }
}
