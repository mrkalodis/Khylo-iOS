//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Library Tab View

public struct LibraryTabView: View {

    @StateObject private var repository = KhyloRepository.shared
    @EnvironmentObject private var navigator: KhyloNavigator
    @State private var libraries: [KhyloMediaLibrary] = []
    @State private var isLoading: Bool = true

    public init() {}

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: KhyloSpacing.lg) {
                    // Header Bar
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Media Libraries")
                            .font(KhyloTypography.largeTitle)
                            .foregroundColor(KhyloColors.textPrimary)

                        Text("Your indexed personal media collections")
                            .font(KhyloTypography.body)
                            .foregroundColor(KhyloColors.textSecondary)
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.top, KhyloSpacing.md)

                    // Quick-Access Libraries Grid
                    VStack(alignment: .leading, spacing: KhyloSpacing.md) {
                        Text("Libraries")
                            .font(KhyloTypography.title3)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(.horizontal, KhyloSpacing.lg)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: KhyloSpacing.md),
                                GridItem(.flexible(), spacing: KhyloSpacing.md)
                            ],
                            spacing: KhyloSpacing.md
                        ) {
                            ForEach(libraries) { library in
                                libraryCard(library)
                            }
                        }
                        .padding(.horizontal, KhyloSpacing.lg)
                    }

                    // Curated Collections & Playlists Section
                    VStack(alignment: .leading, spacing: KhyloSpacing.md) {
                        Text("Quick Collections")
                            .font(KhyloTypography.title3)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(.horizontal, KhyloSpacing.lg)

                        VStack(spacing: KhyloSpacing.sm) {
                            quickCollectionRow(
                                title: "Favorites & Watchlist",
                                subtitle: "Starred items across all libraries",
                                icon: "heart.fill",
                                color: Color(red: 0.94, green: 0.27, blue: 0.27)
                            ) {
                                navigator.push(.libraryCollection(collectionId: "favorites", title: "Favorites"))
                            }

                            quickCollectionRow(
                                title: "Offline Downloads",
                                subtitle: "Media synced for on-the-go playback",
                                icon: "arrow.down.circle.fill",
                                color: KhyloColors.accent
                            ) {
                                navigator.push(.libraryCollection(collectionId: "downloads", title: "Downloads"))
                            }

                            quickCollectionRow(
                                title: "Music Hub",
                                subtitle: "Listen Now, artists, albums, and genre mixes",
                                icon: "music.note",
                                color: KhyloColors.accent
                            ) {
                                navigator.push(.musicHome)
                            }

                            quickCollectionRow(
                                title: "Playlists & Mixes",
                                subtitle: "Curated series, movies, and audio playlists",
                                icon: "music.note.list",
                                color: Color(red: 0.23, green: 0.51, blue: 0.96)
                            ) {
                                navigator.push(.libraryCollection(collectionId: "playlists", title: "Playlists"))
                            }
                        }
                        .padding(.horizontal, KhyloSpacing.lg)
                    }
                }
                .padding(.bottom, 100) // Clearance for bottom tab bar
            }
            .refreshable {
                await loadLibraries()
            }
        }
        .task {
            await loadLibraries()
        }
    }

    // MARK: - Library Card

    @ViewBuilder
    private func libraryCard(_ library: KhyloMediaLibrary) -> some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            if library.collectionType.lowercased() == "music" {
                navigator.push(.musicHome)
            } else {
                navigator.push(.mediaLibrary(libraryId: library.id, title: library.name, type: library.collectionType))
            }
        }) {
            VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(KhyloColors.accent.opacity(0.18))
                            .frame(width: 44, height: 44)

                        Image(systemName: library.systemIconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(KhyloColors.accent)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(KhyloColors.textTertiary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(library.name)
                        .font(KhyloTypography.headline)
                        .foregroundColor(KhyloColors.textPrimary)
                        .lineLimit(1)

                    if let count = library.itemCount {
                        Text("\(count) titles")
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textSecondary)
                    } else {
                        Text(library.collectionType.capitalized)
                            .font(KhyloTypography.caption)
                            .foregroundColor(KhyloColors.textTertiary)
                    }
                }
            }
            .padding(KhyloSpacing.md)
            .frame(height: 130)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.md)
                    .stroke(KhyloColors.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    // MARK: - Quick Collection Row

    @ViewBuilder
    private func quickCollectionRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            action()
        }) {
            HStack(spacing: KhyloSpacing.md) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KhyloTypography.bodyMedium)
                        .foregroundColor(KhyloColors.textPrimary)

                    Text(subtitle)
                        .font(KhyloTypography.caption)
                        .foregroundColor(KhyloColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(KhyloColors.textTertiary)
            }
            .padding(KhyloSpacing.md)
            .background(KhyloColors.surface)
            .cornerRadius(KhyloRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: KhyloRadius.sm)
                    .stroke(KhyloColors.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Load Action

    private func loadLibraries() async {
        isLoading = true
        let views = await repository.fetchUserViews()
        await MainActor.run {
            self.libraries = views
            self.isLoading = false
        }
    }
}
