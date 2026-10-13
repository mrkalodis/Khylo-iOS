//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import SwiftUI

// MARK: - App Navigation Tabs

public enum KhyloTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case tv
    case search
    case library
    case profile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Home"
        case .tv: return "Live TV"
        case .search: return "Search"
        case .library: return "Library"
        case .profile: return "Profile"
        }
    }

    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .tv: return "play.tv.fill"
        case .search: return "magnifyingglass"
        case .library: return "rectangle.stack.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

// MARK: - Navigation Routes

public enum KhyloRoute: Hashable {
    case home
    case itemDetail(itemId: String)
    case seriesDetail(seriesId: String)
    case seasonDetail(seriesId: String, seasonId: String)
    case liveTvGuide
    case liveTvChannel(channelId: String)
    case liveChannels
    case multiView(channelIds: [String])
    case search
    case library
    case libraryCollection(collectionId: String, title: String)
    case mediaLibrary(libraryId: String, title: String, type: String)
    case personDetail(personId: String, name: String)
    case music(item: KhyloMediaItem)
    case musicHome
    case musicAlbum(albumId: String, title: String, artist: String)
    case musicArtist(artistId: String, name: String)
    case audiobook(item: KhyloMediaItem)
    case reader(item: KhyloMediaItem)
    case profile
    case profileSwitcher
    case settings
    case playbackSettings
}

// MARK: - Playback Request

public struct PlaybackRequest: Identifiable, Equatable {
    public let id: String
    public let itemId: String
    public let resumePositionTicks: Int64?
    public let title: String?
    public let mediaSourceId: String?

    public init(
        itemId: String,
        resumePositionTicks: Int64? = nil,
        title: String? = nil,
        mediaSourceId: String? = nil
    ) {
        self.id = UUID().uuidString
        self.itemId = itemId
        self.resumePositionTicks = resumePositionTicks
        self.title = title
        self.mediaSourceId = mediaSourceId
    }
}

// MARK: - Khylo Navigator

@MainActor
public final class KhyloNavigator: ObservableObject {

    @Published public var selectedTab: KhyloTab = .home
    @Published public var homePath: [KhyloRoute] = []
    @Published public var tvPath: [KhyloRoute] = []
    @Published public var searchPath: [KhyloRoute] = []
    @Published public var libraryPath: [KhyloRoute] = []
    @Published public var profilePath: [KhyloRoute] = []

    @Published public var activePlayback: PlaybackRequest?
    @Published public var presentedSheetRoute: KhyloRoute?

    public init() {}

    // MARK: - Tab Switching

    public func selectTab(_ tab: KhyloTab) {
        if selectedTab == tab {
            popToRoot(for: tab)
        } else {
            selectedTab = tab
        }
    }

    // MARK: - Push Navigation

    public func push(_ route: KhyloRoute, in tab: KhyloTab? = nil) {
        let targetTab = tab ?? selectedTab
        switch targetTab {
        case .home:
            homePath.append(route)
        case .tv:
            tvPath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .profile:
            profilePath.append(route)
        }
    }

    public func pop(in tab: KhyloTab? = nil) {
        let targetTab = tab ?? selectedTab
        switch targetTab {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
        case .tv:
            if !tvPath.isEmpty { tvPath.removeLast() }
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
        case .library:
            if !libraryPath.isEmpty { libraryPath.removeLast() }
        case .profile:
            if !profilePath.isEmpty { profilePath.removeLast() }
        }
    }

    public func popToRoot(for tab: KhyloTab? = nil) {
        let targetTab = tab ?? selectedTab
        switch targetTab {
        case .home:
            homePath.removeAll()
        case .tv:
            tvPath.removeAll()
        case .search:
            searchPath.removeAll()
        case .library:
            libraryPath.removeAll()
        case .profile:
            profilePath.removeAll()
        }
    }

    // MARK: - Player Navigation

    public func play(
        itemId: String,
        resumePositionTicks: Int64? = nil,
        title: String? = nil,
        mediaSourceId: String? = nil
    ) {
        activePlayback = PlaybackRequest(
            itemId: itemId,
            resumePositionTicks: resumePositionTicks,
            title: title,
            mediaSourceId: mediaSourceId
        )
    }

    public func stopPlayback() {
        activePlayback = nil
    }

    // MARK: - Sheet Navigation

    public func presentSheet(_ route: KhyloRoute) {
        presentedSheetRoute = route
    }

    public func dismissSheet() {
        presentedSheetRoute = nil
    }
}
