//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import ImageIO
import SwiftUI
import UIKit

// MARK: - Options

enum KhyloComicBackground: String, CaseIterable, Identifiable {
    case black
    case gray
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Black"
        case .gray: "Gray"
        case .white: "White"
        }
    }

    var color: Color {
        switch self {
        case .black: .black
        case .gray: Color(white: 0.17)
        case .white: .white
        }
    }

    var uiColor: UIColor { UIColor(color) }
}

// MARK: - Reader

/// Comics and manga: swipe or tap the edges to turn pages, pinch or double-tap
/// to zoom, and read right to left for manga.
struct KhyloComicReader: View {

    let itemID: String
    let pages: [URL]
    let title: String
    @Binding var isChromeVisible: Bool
    let onClose: () -> Void
    let onFinished: () -> Void

    @AppStorage("khylo.comic.rightToLeft") private var rightToLeft = false
    @AppStorage("khylo.comic.fillWidth") private var fillWidth = false
    @AppStorage("khylo.comic.background") private var background: KhyloComicBackground = .black

    @State private var index = 0
    @State private var isShowingOptions = false

    private var chromeTheme: KhyloReaderTheme { background == .white ? .original : .night }

    var body: some View {
        ZStack {
            background.color.ignoresSafeArea()

            KhyloComicPager(
                pages: pages,
                index: $index,
                rightToLeft: rightToLeft,
                fillWidth: fillWidth,
                background: background.uiColor,
                onTapMiddle: { isChromeVisible.toggle() }
            )
            .ignoresSafeArea()

            if isChromeVisible {
                KhyloReaderChrome(
                    theme: chromeTheme,
                    title: title,
                    subtitle: rightToLeft ? "Right to left" : "",
                    progress: pages.count > 1 ? Double(index) / Double(pages.count - 1) : 1,
                    status: "Page \(index + 1) of \(pages.count)",
                    onScrub: { value in
                        guard pages.count > 1 else { return }
                        index = min(max(Int((value * Double(pages.count - 1)).rounded()), 0), pages.count - 1)
                    },
                    onClose: onClose
                ) {
                    KhyloReaderIconButton(systemImage: "slider.horizontal.3", theme: chromeTheme, label: "Reading options") {
                        isShowingOptions = true
                    }
                }
            }
        }
        .statusBarHidden(!isChromeVisible)
        .sheet(isPresented: $isShowingOptions) {
            KhyloComicOptionsSheet(rightToLeft: $rightToLeft, fillWidth: $fillWidth, background: $background)
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
                .preferredColorScheme(.dark)
        }
        .onAppear {
            index = min(ReaderPosition.load(itemID)?.section ?? 0, max(pages.count - 1, 0))
        }
        .onChange(of: index) { _, newValue in
            ReaderPosition(section: newValue, fraction: 0).save(itemID)
            if newValue == pages.count - 1 { onFinished() }
        }
    }
}

private struct KhyloComicOptionsSheet: View {

    @Binding var rightToLeft: Bool
    @Binding var fillWidth: Bool
    @Binding var background: KhyloComicBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Reading direction") {
                Picker("Reading direction", selection: $rightToLeft) {
                    Text("Left to right").tag(false)
                    Text("Right to left (manga)").tag(true)
                }
                .pickerStyle(.segmented)
            }
            group("Page size") {
                Picker("Page size", selection: $fillWidth) {
                    Text("Whole page").tag(false)
                    Text("Fill width").tag(true)
                }
                .pickerStyle(.segmented)
            }
            group("Background") {
                Picker("Background", selection: $background) {
                    ForEach(KhyloComicBackground.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - Paging

/// Pages side by side, with the next one on the left for manga.
private struct KhyloComicPager: UIViewControllerRepresentable {

    let pages: [URL]
    @Binding var index: Int
    let rightToLeft: Bool
    let fillWidth: Bool
    let background: UIColor
    let onTapMiddle: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 14]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = background
        context.coordinator.pager = controller
        context.coordinator.show(index, animated: false, direction: .forward)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        let changedLook = coordinator.parent.rightToLeft != rightToLeft || coordinator.parent.fillWidth != fillWidth
        coordinator.parent = self
        controller.view.backgroundColor = background
        for case let page as KhyloComicPageController in controller.viewControllers ?? [] {
            page.view.backgroundColor = background
        }
        if changedLook {
            coordinator.show(index, animated: false, direction: .forward)
        } else if coordinator.currentIndex != index {
            let forward = rightToLeft ? index < coordinator.currentIndex : index > coordinator.currentIndex
            // Only a single page turn slides; a longer jump (the scrubber) just lands.
            let isNextDoor = abs(index - coordinator.currentIndex) == 1
            coordinator.show(index, animated: isNextDoor, direction: forward ? .forward : .reverse)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

        var parent: KhyloComicPager
        weak var pager: UIPageViewController?
        private(set) var currentIndex = 0

        init(_ parent: KhyloComicPager) { self.parent = parent }

        func makePage(_ index: Int) -> KhyloComicPageController? {
            guard parent.pages.indices.contains(index) else { return nil }
            let page = KhyloComicPageController(index: index, url: parent.pages[index], fillWidth: parent.fillWidth)
            page.view.backgroundColor = parent.background
            page.onTap = { [weak self] fraction in self?.tapped(at: fraction) }
            return page
        }

        func show(_ index: Int, animated: Bool, direction: UIPageViewController.NavigationDirection) {
            let target = min(max(index, 0), max(parent.pages.count - 1, 0))
            guard let page = makePage(target) else { return }
            currentIndex = target
            pager?.setViewControllers([page], direction: direction, animated: animated)
        }

        /// Left and right edges turn the page; the middle brings the controls back.
        private func tapped(at fraction: CGFloat) {
            if fraction < 0.28 || fraction > 0.72 {
                let toTheLeft = fraction < 0.5
                // On the left edge the next page for manga, the previous page otherwise.
                let delta = (toTheLeft == parent.rightToLeft) ? 1 : -1
                let target = currentIndex + delta
                guard parent.pages.indices.contains(target) else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                parent.index = target
            } else {
                parent.onTapMiddle()
            }
        }

        // MARK: Data source

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? KhyloComicPageController else { return nil }
            return makePage(parent.rightToLeft ? page.index + 1 : page.index - 1)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? KhyloComicPageController else { return nil }
            return makePage(parent.rightToLeft ? page.index - 1 : page.index + 1)
        }

        // MARK: Delegate

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

// MARK: - One page

/// A page you can pinch and double-tap to zoom.
final class KhyloComicPageController: UIViewController, UIScrollViewDelegate {

    let index: Int
    private let url: URL
    private let fillWidth: Bool
    var onTap: ((CGFloat) -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var image: UIImage?
    private var laidOutFor: CGSize = .zero

    init(index: Int, url: URL, fillWidth: Bool) {
        self.index = index
        self.url = url
        self.fillWidth = fillWidth
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)

        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        spinner.startAnimating()
        view.addSubview(spinner)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped(_:)))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let url = url
        Task.detached(priority: .userInitiated) { [weak self] in
            let loaded = Self.downsampledImage(at: url, maxDimension: 3200)
            await MainActor.run {
                self?.spinner.stopAnimating()
                self?.image = loaded
                self?.imageView.image = loaded
                self?.laidOutFor = .zero
                self?.view.setNeedsLayout()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let image, laidOutFor != view.bounds.size, view.bounds.width > 0 else { return }
        laidOutFor = view.bounds.size

        let bounds = view.bounds.size
        let fitScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let widthScale = bounds.width / image.size.width
        let start = fillWidth ? widthScale : fitScale

        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size
        scrollView.minimumZoomScale = min(fitScale, start)
        scrollView.maximumZoomScale = max(start * 4, 3)
        scrollView.zoomScale = start
        centerContent()
        // Fill width starts at the top of the page.
        scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
    }

    private func centerContent() {
        let content = scrollView.contentSize
        let bounds = scrollView.bounds.size
        scrollView.contentInset = UIEdgeInsets(
            top: max((bounds.height - content.height) / 2, 0),
            left: max((bounds.width - content.width) / 2, 0),
            bottom: 0,
            right: 0
        )
    }

    // MARK: Zoom

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    @objc private func singleTapped(_ gesture: UITapGestureRecognizer) {
        let width = max(view.bounds.width, 1)
        onTap?(gesture.location(in: view).x / width)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard image != nil else { return }
        let start = scrollView.minimumZoomScale
        if scrollView.zoomScale > start * 1.05 {
            scrollView.setZoomScale(start, animated: true)
        } else {
            let target = min(max(start * 2.5, 1), scrollView.maximumZoomScale)
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
            scrollView.zoom(
                to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
                animated: true
            )
        }
    }

    // MARK: Loading

    /// Large scans are shrunk as they load so a long comic doesn't fill memory.
    nonisolated private static func downsampledImage(at url: URL, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
        let thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
