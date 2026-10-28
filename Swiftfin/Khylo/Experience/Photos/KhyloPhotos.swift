//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Helpers

extension BaseItemDto {

    /// When the picture was taken, falling back to when it was added.
    var khyloPhotoDate: Date? { premiereDate ?? dateCreated }
}

enum KhyloPhotoArt {

    static func thumbnail(_ item: BaseItemDto, side: CGFloat) -> URL? {
        guard let id = item.id else { return nil }
        return KhyloArtwork.url(itemID: id, type: .primary, tag: item.imageTags?["Primary"], width: side)
    }

    static func full(_ item: BaseItemDto) -> URL? {
        guard let id = item.id else { return nil }
        return KhyloArtwork.url(itemID: id, type: .primary, tag: item.imageTags?["Primary"], width: 2000)
    }
}

// MARK: - Loading

/// Photos, newest first, grouped by month. Months are contiguous runs of the list.
@MainActor
final class KhyloPhotoLoader: ObservableObject {

    struct Month: Identifiable {
        let id: String
        let title: String
        var range: Range<Int>
    }

    @Published private(set) var photos: [BaseItemDto] = []
    @Published private(set) var months: [Month] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = true
    @Published private(set) var failed = false

    private var parentID: String?
    private var isFetching = false
    private let pageSize = 240

    func reload(parentID: String?) async {
        self.parentID = parentID
        photos = []
        months = []
        total = 0
        isLoading = true
        failed = false
        await loadMore()
        isLoading = false
    }

    func loadMore() async {
        guard !isFetching, photos.isEmpty || photos.count < total else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let page = try await KhyloAPI.items(
                parentID: parentID,
                types: [.photo],
                sortBy: [.premiereDate, .dateCreated],
                sortOrder: .descending,
                recursive: true,
                startIndex: photos.count,
                limit: pageSize,
                extraFields: [.dateCreated]
            )
            total = page.total
            let known = Set(photos.compactMap(\.id))
            append(page.items.filter { !known.contains($0.id ?? "") })
        } catch {
            failed = photos.isEmpty
        }
    }

    private func append(_ fresh: [BaseItemDto]) {
        let calendar = Calendar.current
        for photo in fresh {
            let index = photos.count
            photos.append(photo)
            let parts = photo.khyloPhotoDate.map { calendar.dateComponents([.year, .month], from: $0) }
            let key = parts.map { "\($0.year ?? 0)-\($0.month ?? 0)" } ?? "undated"
            if let last = months.last, last.id == key {
                months[months.count - 1].range = last.range.lowerBound ..< index + 1
            } else {
                let title = photo.khyloPhotoDate.map { $0.formatted(.dateTime.month(.wide).year()) } ?? "Undated"
                months.append(Month(id: key, title: title, range: index ..< index + 1))
            }
        }
    }
}

// MARK: - Grid

/// Every picture below a library or album, edge to edge, a month at a time.
struct KhyloPhotoGrid: View {

    let parentID: String?
    let header: AnyView

    @StateObject private var loader = KhyloPhotoLoader()
    @State private var viewerStart: Int?

    private let columns = 3
    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let side = (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header.padding(.bottom, 10)

                    if loader.isLoading {
                        ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 80)
                    } else if loader.photos.isEmpty {
                        KhyloEmptyState(
                            systemImage: "photo.on.rectangle.angled",
                            title: loader.failed ? "Can't load your photos" : "No photos yet",
                            message: loader.failed ? "Check your connection and pull down to try again." : "Pictures you add to this library show up here."
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(loader.months) { month in
                            Section {
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns),
                                    spacing: spacing
                                ) {
                                    ForEach(month.range, id: \.self) { index in
                                        cell(index, side: side)
                                    }
                                }
                            } header: {
                                monthHeader(month)
                            }
                        }

                        Text(loader.total == 1 ? "1 Photo" : "\(loader.total.formatted()) Photos")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(KhyloStyle.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(.bottom, 30)
            }
            .refreshable { await loader.reload(parentID: parentID) }
        }
        .task(id: parentID) { await loader.reload(parentID: parentID) }
        .fullScreenCover(isPresented: Binding(get: { viewerStart != nil }, set: { if !$0 { viewerStart = nil } })) {
            KhyloPhotoViewerScreen(photos: loader.photos, start: viewerStart ?? 0)
        }
    }

    private func cell(_ index: Int, side: CGFloat) -> some View {
        let photo = loader.photos[index]
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewerStart = index
        } label: {
            KhyloImage(url: KhyloPhotoArt.thumbnail(photo, side: side), placeholderSymbol: "photo")
                .frame(width: side, height: side)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if photo.khyloIsFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if index >= loader.photos.count - 60 { Task { await loader.loadMore() } }
        }
    }

    private func monthHeader(_ month: KhyloPhotoLoader.Month) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(month.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Library

/// A photo library: all your pictures by month, and your albums.
struct KhyloPhotoLibrary: View {

    enum Section: Hashable {
        case photos
        case albums
    }

    let library: BaseItemDto
    let header: AnyView

    @State private var section: Section = .photos

    private var top: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 14) {
                header
                KhyloSegmentTabs(tabs: [(Section.photos, "Photos"), (Section.albums, "Albums")], selection: $section)
                    .padding(.horizontal, KhyloStyle.gutter - 4)
            }
        )
    }

    var body: some View {
        switch section {
        case .photos:
            KhyloPhotoGrid(parentID: library.id, header: top)
        case .albums:
            KhyloItemGrid(shape: .square, reloadKey: "albums-\(library.id ?? "")", header: { top }) { start, limit in
                try await KhyloAPI.items(
                    parentID: library.id,
                    types: [.photoAlbum, .folder],
                    sortBy: [.sortName],
                    recursive: false,
                    startIndex: start,
                    limit: limit
                )
            }
        }
    }
}

/// One album: its pictures by month.
struct KhyloPhotoAlbumScreen: View {

    let album: BaseItemDto

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()
            KhyloPhotoGrid(
                parentID: album.id,
                header: AnyView(
                    Text(album.name ?? "Album")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, KhyloStyle.gutter)
                )
            )
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Viewer

/// One picture, or a run of them, full screen on black. Swipe between them,
/// pinch to zoom, swipe down to close.
struct KhyloPhotoViewerScreen: View {

    let photos: [BaseItemDto]

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var isChromeVisible = true
    @State private var isSlideshow = false
    @State private var dragY: CGFloat = 0
    @State private var favorites: [String: Bool] = [:]

    init(photos: [BaseItemDto], start: Int) {
        self.photos = photos
        _index = State(initialValue: min(max(start, 0), max(photos.count - 1, 0)))
    }

    private var current: BaseItemDto? { photos.indices.contains(index) ? photos[index] : nil }

    private var isFavorite: Bool {
        guard let current, let id = current.id else { return false }
        return favorites[id] ?? current.khyloIsFavorite
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(dragY) / 420, 0.7))
                .ignoresSafeArea()

            KhyloPhotoPager(
                photos: photos,
                index: $index,
                onTap: { isChromeVisible.toggle(); isSlideshow = false },
                onDrag: handleDrag
            )
            .ignoresSafeArea()
            .offset(y: dragY)
            .scaleEffect(1 - min(abs(dragY), 300) / 2400)

            if isChromeVisible, !isSlideshow, dragY == 0 {
                chrome
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!isChromeVisible || isSlideshow)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        .animation(.easeInOut(duration: 0.2), value: isSlideshow)
        .task(id: isSlideshow) {
            guard isSlideshow else { return }
            isChromeVisible = false
            while !Task.isCancelled, isSlideshow {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, isSlideshow else { break }
                if index < photos.count - 1 {
                    index += 1
                } else {
                    isSlideshow = false
                    isChromeVisible = true
                }
            }
        }
    }

    // MARK: Controls

    private var chrome: some View {
        VStack {
            HStack(alignment: .center) {
                circleButton("xmark", label: "Close") { dismiss() }
                Spacer()
                VStack(spacing: 1) {
                    if let date = current?.khyloPhotoDate {
                        Text(date.formatted(.dateTime.month(.wide).day().year()))
                            .font(.system(size: 15, weight: .semibold))
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12))
                            .opacity(0.65)
                    }
                }
                .foregroundColor(.white)
                Spacer()
                Menu {
                    Button {
                        isSlideshow = true
                    } label: {
                        Label("Slideshow", systemImage: "rectangle.stack")
                    }
                } label: {
                    circleLabel("ellipsis")
                }
                .accessibilityLabel("More")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .background(
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            )

            Spacer()

            HStack {
                circleButton(isFavorite ? "heart.fill" : "heart", label: isFavorite ? "Remove from Favorites" : "Favorite", tint: isFavorite ? KhyloStyle.accent : .white) {
                    toggleFavorite()
                }
                Spacer()
                Text("\(index + 1) of \(photos.count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                circleButton("rectangle.stack", label: "Slideshow") { isSlideshow = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private func circleLabel(_ systemImage: String, tint: Color = .white) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
    }

    private func circleButton(_ systemImage: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(systemImage, tint: tint) }
            .buttonStyle(KhyloScaleButtonStyle())
            .accessibilityLabel(label)
    }

    private func toggleFavorite() {
        guard let id = current?.id else { return }
        let target = !isFavorite
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        favorites[id] = target
        Task {
            if (try? await KhyloAPI.setFavorite(target, itemID: id)) == nil {
                favorites[id] = !target
            }
        }
    }

    private func handleDrag(_ translation: CGFloat, _ state: UIGestureRecognizer.State, _ velocity: CGFloat) {
        switch state {
        case .changed:
            dragY = max(translation, 0)
        case .ended, .cancelled, .failed:
            if state == .ended, translation > 110 || velocity > 900 {
                dismiss()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragY = 0 }
            }
        default:
            break
        }
    }
}

/// Pictures side by side; swiping moves between them.
private struct KhyloPhotoPager: UIViewControllerRepresentable {

    let photos: [BaseItemDto]
    @Binding var index: Int
    let onTap: () -> Void
    let onDrag: (CGFloat, UIGestureRecognizer.State, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 14]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        context.coordinator.pager = controller
        context.coordinator.show(index, animated: false, direction: .forward)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.currentIndex != index {
            let forward = index > coordinator.currentIndex
            coordinator.show(index, animated: abs(index - coordinator.currentIndex) == 1, direction: forward ? .forward : .reverse)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

        var parent: KhyloPhotoPager
        weak var pager: UIPageViewController?
        private(set) var currentIndex = 0

        init(_ parent: KhyloPhotoPager) { self.parent = parent }

        func makePage(_ index: Int) -> KhyloComicPageController? {
            guard parent.photos.indices.contains(index), let url = KhyloPhotoArt.full(parent.photos[index]) else { return nil }
            let page = KhyloComicPageController(index: index, url: url, fillWidth: false, isRemote: true)
            page.view.backgroundColor = .clear
            page.onTap = { [weak self] _ in self?.parent.onTap() }
            page.onDismissDrag = { [weak self] translation, state, velocity in self?.parent.onDrag(translation, state, velocity) }
            return page
        }

        func show(_ index: Int, animated: Bool, direction: UIPageViewController.NavigationDirection) {
            let target = min(max(index, 0), max(parent.photos.count - 1, 0))
            guard let page = makePage(target) else { return }
            currentIndex = target
            pager?.setViewControllers([page], direction: direction, animated: animated)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            (viewController as? KhyloComicPageController).flatMap { makePage($0.index - 1) }
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            (viewController as? KhyloComicPageController).flatMap { makePage($0.index + 1) }
        }

        func pageViewController(
            _ controller: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed, let page = controller.viewControllers?.first as? KhyloComicPageController else { return }
            currentIndex = page.index
            parent.index = page.index
        }
    }
}
