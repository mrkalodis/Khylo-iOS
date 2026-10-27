//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import PDFKit
import SwiftUI
import WebKit

extension NavigationRoute {

    static func khyloReader(_ item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "khylo-reader-\(item.id ?? "")", style: .fullscreen) {
            KhyloReaderScreen(item: item)
        }
    }
}

/// Saved reading position: chapter (or page for PDFs and comics) plus fraction within it.
struct ReaderPosition: Codable {
    var section: Int
    var fraction: Double

    static func key(_ itemID: String) -> String { "khylo.reader.position.\(itemID)" }

    static func load(_ itemID: String) -> ReaderPosition? {
        guard let data = UserDefaults.standard.data(forKey: key(itemID)) else { return nil }
        return try? JSONDecoder().decode(ReaderPosition.self, from: data)
    }

    func save(_ itemID: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key(itemID))
        }
    }
}

// MARK: - Screen

struct KhyloReaderScreen: View {

    let item: BaseItemDto

    @Environment(\.dismiss) private var dismiss

    @AppStorage("khylo.reader.paper") private var theme: KhyloReaderTheme = .paper
    @AppStorage("khylo.reader.fontScale") private var fontScale: Double = 1.0
    @AppStorage("khylo.reader.font") private var font: KhyloReaderFont = .newYork
    @AppStorage("khylo.reader.spacing") private var spacing: KhyloReaderSpacing = .normal
    @AppStorage("khylo.reader.margins") private var margins: KhyloReaderMargins = .normal
    @AppStorage("khylo.reader.justified") private var justified = true
    @AppStorage("khylo.reader.pageCurl") private var pageCurl = true

    @State private var book: KhyloBook?
    @State private var errorMessage: String?
    @State private var downloadProgress: Double = 0
    @State private var isChromeVisible = true
    @State private var isShowingContents = false
    @State private var isShowingSettings = false

    var body: some View {
        ZStack {
            KhyloPaperBackground(theme: theme)

            switch book {
            case let .epub(epub):
                KhyloEPUBReader(
                    itemID: item.id ?? "",
                    book: epub,
                    theme: theme,
                    style: KhyloEPUBStyle(pageCurl: pageCurl, fontScale: fontScale, font: font, spacing: spacing, margins: margins, justified: justified),
                    isChromeVisible: $isChromeVisible,
                    isShowingContents: $isShowingContents,
                    title: item.name ?? "",
                    onClose: { dismiss() },
                    onSettings: { isShowingSettings = true },
                    onFinished: markFinished
                )
            case let .pdf(url):
                KhyloPDFReader(
                    itemID: item.id ?? "",
                    url: url,
                    theme: theme,
                    title: item.name ?? "",
                    isChromeVisible: $isChromeVisible,
                    onClose: { dismiss() },
                    onSettings: { isShowingSettings = true },
                    onFinished: markFinished
                )
            case let .comic(pages):
                KhyloComicReader(
                    itemID: item.id ?? "",
                    pages: pages,
                    title: item.name ?? "",
                    isChromeVisible: $isChromeVisible,
                    onClose: { dismiss() },
                    onFinished: markFinished
                )
            case nil:
                loadingView
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .statusBarHidden(!isChromeVisible)
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        .sheet(isPresented: $isShowingSettings) {
            KhyloReaderSettingsSheet(
                theme: $theme,
                fontScale: $fontScale,
                font: $font,
                spacing: $spacing,
                margins: $margins,
                justified: $justified,
                pageCurl: $pageCurl,
                showsTextOptions: isEPUB
            )
            .presentationDetents(isEPUB ? [.height(520), .large] : [.height(200)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            .preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .task { await load() }
    }

    private var isEPUB: Bool {
        if case .epub = book { return true }
        return false
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            KhyloImage(url: KhyloArtwork.url(for: item, style: .poster, width: 180), placeholderSymbol: "book.closed")
                .frame(width: 140, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)

            Text(item.name ?? "")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(theme.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 15))
                    .foregroundColor(theme.foreground.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Close") { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KhyloStyle.accent)
            } else {
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.linear)
                    .tint(KhyloStyle.accent)
                    .frame(width: 160)
                Text(downloadProgress > 0 && downloadProgress < 1 ? "Downloading…" : "Opening…")
                    .font(.system(size: 13))
                    .foregroundColor(theme.foreground.opacity(0.6))
            }
        }
        .overlay(alignment: .topLeading) {
            KhyloReaderCloseButton(theme: theme) { dismiss() }
                .padding(.leading, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard book == nil, let id = item.id else { return }
        do {
            let loaded = try await KhyloBook.load(itemID: id) { value in
                Task { @MainActor in downloadProgress = value }
            }
            book = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markFinished() {
        guard let id = item.id else { return }
        Task { try? await KhyloAPI.setPlayed(true, itemID: id) }
    }
}

// MARK: - EPUB

/// Drives a WKWebView that lays each chapter out in screen-width CSS columns,
/// so the book reads as pages.
@MainActor
final class KhyloEPUBPager: NSObject, ObservableObject, WKNavigationDelegate {

    enum Landing {
        case first
        case last
        case fraction(Double)
        /// The page holding an element, for links to a spot inside a chapter.
        case anchor(String)
    }

    @Published private(set) var chapterIndex = 0
    @Published private(set) var page = 0
    @Published private(set) var pageCount = 1
    @Published private(set) var isReady = false

    let book: KhyloBook.EPUB
    let webView: WKWebView
    private let itemID: String
    private var landing: Landing = .first
    private var css = ""
    var onFinished: (() -> Void)?
    /// Turn pages with a paper curl rather than a slide.
    var usesPageCurl = true
    /// Holds the web view and draws the page-curl animation over it.
    private(set) lazy var container = KhyloPageCurlContainer(webView: webView)
    private var isTurning = false
    /// A curl waiting for the next chapter to finish laying out.
    private var pendingCurlForward: Bool?

    init(itemID: String, book: KhyloBook.EPUB) {
        self.itemID = itemID
        self.book = book

        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        self.webView = webView
        super.init()
        webView.navigationDelegate = self

        if let saved = ReaderPosition.load(itemID), saved.section < book.chapters.count {
            chapterIndex = saved.section
            landing = .fraction(saved.fraction)
        }
    }

    var chapterTitle: String {
        book.chapters[safe: chapterIndex]?.title ?? ""
    }

    /// 0...1 across the whole book (chapters weighted equally).
    var overallProgress: Double {
        let within = pageCount > 1 ? Double(page) / Double(pageCount - 1) : 1
        return (Double(chapterIndex) + within) / Double(max(book.chapters.count, 1))
    }

    var pagesLeftInChapter: Int { max(pageCount - page - 1, 0) }

    func start(css: String) {
        self.css = css
        loadChapter(chapterIndex, landing: landing)
    }

    func updateStyle(css: String) {
        guard css != self.css else { return }
        self.css = css
        let fraction = pageCount > 1 ? Double(page) / Double(pageCount) : 0
        landing = .fraction(fraction)
        applyStyleAndPaginate()
    }

    func goToChapter(_ index: Int) {
        guard book.chapters.indices.contains(index) else { return }
        loadChapter(index, landing: .first)
    }

    func next() {
        guard !isTurning else { return }
        if page < pageCount - 1 {
            turn(forward: true) { self.show(page: self.page + 1, animated: !self.usesPageCurl) }
        } else if chapterIndex < book.chapters.count - 1 {
            turnChapter(to: chapterIndex + 1, landing: .first, forward: true)
        } else {
            onFinished?()
        }
    }

    func previous() {
        guard !isTurning else { return }
        if page > 0 {
            turn(forward: false) { self.show(page: self.page - 1, animated: !self.usesPageCurl) }
        } else if chapterIndex > 0 {
            turnChapter(to: chapterIndex - 1, landing: .last, forward: false)
        }
    }

    // MARK: Page curl

    /// Covers the page with a picture of itself, moves the real page underneath,
    /// then curls the picture away to reveal it.
    private func turn(forward: Bool, move: @escaping () -> Void) {
        guard usesPageCurl else {
            move()
            return
        }
        isTurning = true
        snapshot { [weak self] current in
            guard let self else { return }
            guard let current else {
                move()
                isTurning = false
                return
            }
            container.cover(with: current)
            move()
            snapshot { [weak self] revealed in
                guard let self else { return }
                container.curl(to: revealed ?? current, forward: forward) { self.isTurning = false }
            }
        }
    }

    /// Same as `turn`, but the next page is in another chapter that has to load first.
    private func turnChapter(to index: Int, landing: Landing, forward: Bool) {
        guard usesPageCurl else {
            loadChapter(index, landing: landing)
            return
        }
        isTurning = true
        snapshot { [weak self] current in
            guard let self else { return }
            if let current {
                container.cover(with: current)
                pendingCurlForward = forward
            } else {
                isTurning = false
            }
            loadChapter(index, landing: landing)
        }
    }

    private func finishPendingCurl() {
        guard let forward = pendingCurlForward else { return }
        pendingCurlForward = nil
        snapshot { [weak self] revealed in
            guard let self else { return }
            if let revealed {
                container.curl(to: revealed, forward: forward) { self.isTurning = false }
            } else {
                container.uncover()
                isTurning = false
            }
        }
    }

    private func snapshot(_ completion: @escaping (UIImage?) -> Void) {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { image, _ in completion(image) }
    }

    private func loadChapter(_ index: Int, landing: Landing) {
        chapterIndex = index
        self.landing = landing
        isReady = false
        webView.loadFileURL(book.chapters[index].url, allowingReadAccessTo: book.root)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyStyleAndPaginate()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Keep the reader inside the book; follow internal links to other chapters.
        guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
        if url.isFileURL,
           let index = book.chapters.firstIndex(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) {
            let fragment = url.fragment.flatMap { $0.isEmpty ? nil : $0 }
            if index == chapterIndex, let fragment {
                pageOfAnchor(fragment) { [weak self] page in self?.show(page: page, animated: false) }
            } else {
                loadChapter(index, landing: fragment.map(Landing.anchor) ?? .first)
            }
        }
        return .cancel
    }

    private func applyStyleAndPaginate() {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        let script = """
        (function() {
          var meta = document.querySelector('meta[name=viewport]');
          if (!meta) { meta = document.createElement('meta'); meta.name = 'viewport'; document.head.appendChild(meta); }
          meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
          var style = document.getElementById('khylo-style');
          if (!style) { style = document.createElement('style'); style.id = 'khylo-style'; document.head.appendChild(style); }
          style.textContent = `\(escaped)`;
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, _ in
            // Let layout settle, then count columns.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self?.measure()
            }
        }
    }

    private func measure() {
        webView.evaluateJavaScript("Math.max(1, Math.round(document.documentElement.scrollWidth / window.innerWidth))") { [weak self] result, _ in
            guard let self else { return }
            pageCount = max(1, (result as? Int) ?? Int((result as? Double) ?? 1))
            let finish = { [weak self] (target: Int) in
                guard let self else { return }
                show(page: target, animated: false)
                withAnimation(.easeOut(duration: 0.2)) { self.isReady = true }
                finishPendingCurl()
            }
            switch landing {
            case .first: finish(0)
            case .last: finish(pageCount - 1)
            case let .fraction(value): finish(min(pageCount - 1, Int((value * Double(pageCount)).rounded(.down))))
            case let .anchor(id): pageOfAnchor(id, completion: finish)
            }
        }
    }

    /// Which page an element (by id or name) is on.
    private func pageOfAnchor(_ id: String, completion: @escaping (Int) -> Void) {
        let escaped = id.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
          var el = document.getElementById('\(escaped)') || document.getElementsByName('\(escaped)')[0];
          if (!el) { return 0; }
          return Math.max(0, Math.floor((el.getBoundingClientRect().left + window.scrollX + 1) / window.innerWidth));
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            let page = (result as? Int) ?? Int((result as? Double) ?? 0)
            completion(min(max(page, 0), pageCount - 1))
        }
    }

    private func show(page newPage: Int, animated: Bool) {
        page = max(0, min(newPage, pageCount - 1))
        let x = CGFloat(page) * webView.bounds.width
        webView.scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
        ReaderPosition(section: chapterIndex, fraction: pageCount > 0 ? Double(page) / Double(pageCount) : 0).save(itemID)
    }
}

private struct KhyloEPUBWebView: UIViewRepresentable {
    let container: KhyloPageCurlContainer
    let background: Color
    let isReady: Bool

    func makeUIView(context: Context) -> KhyloPageCurlContainer {
        container.setPaper(UIColor(background))
        container.webView.alpha = isReady ? 1 : 0
        return container
    }

    func updateUIView(_ uiView: KhyloPageCurlContainer, context: Context) {
        uiView.setPaper(UIColor(background))
        let alpha: CGFloat = isReady ? 1 : 0
        if uiView.webView.alpha != alpha {
            UIView.animate(withDuration: 0.2) { uiView.webView.alpha = alpha }
        }
    }
}

/// The book's web view with a page-curl layer above it. Turning a page shows a
/// picture of the old page on top and curls it away, like turning real paper.
final class KhyloPageCurlContainer: UIView {

    let webView: WKWebView
    private let pageController = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: .horizontal,
        options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
    )
    private var paper: UIColor = .white

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
        pageController.isDoubleSided = false
        pageController.view.isHidden = true
        // Turning is driven by the reader's own taps and swipes.
        pageController.view.isUserInteractionEnabled = false
        pageController.gestureRecognizers.forEach { $0.isEnabled = false }
        addSubview(pageController.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = bounds
        pageController.view.frame = bounds
    }

    func setPaper(_ color: UIColor) {
        paper = color
        backgroundColor = color
        webView.backgroundColor = color
        webView.scrollView.backgroundColor = color
    }

    /// Shows a still of the current page above the web view.
    func cover(with image: UIImage) {
        pageController.setViewControllers([page(image)], direction: .forward, animated: false)
        pageController.view.isHidden = false
    }

    func uncover() {
        pageController.view.isHidden = true
    }

    /// Curls the covering page away (forward) or back in (reverse) to show `image`, then steps aside.
    func curl(to image: UIImage, forward: Bool, completion: @escaping () -> Void) {
        pageController.setViewControllers([page(image)], direction: forward ? .forward : .reverse, animated: true) { [weak self] _ in
            self?.pageController.view.isHidden = true
            completion()
        }
    }

    private func page(_ image: UIImage) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = paper
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.frame = controller.view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(imageView)
        return controller
    }
}

/// Text settings for EPUB pages.
struct KhyloEPUBStyle: Equatable {
    var pageCurl: Bool = true
    var fontScale: Double
    var font: KhyloReaderFont
    var spacing: KhyloReaderSpacing
    var margins: KhyloReaderMargins
    var justified: Bool
}

struct KhyloEPUBReader: View {

    let itemID: String
    let theme: KhyloReaderTheme
    let style: KhyloEPUBStyle
    @Binding var isChromeVisible: Bool
    @Binding var isShowingContents: Bool
    let title: String
    let onClose: () -> Void
    let onSettings: () -> Void
    let onFinished: () -> Void

    @StateObject private var pager: KhyloEPUBPager

    init(
        itemID: String,
        book: KhyloBook.EPUB,
        theme: KhyloReaderTheme,
        style: KhyloEPUBStyle,
        isChromeVisible: Binding<Bool>,
        isShowingContents: Binding<Bool>,
        title: String,
        onClose: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.itemID = itemID
        self.theme = theme
        self.style = style
        self._isChromeVisible = isChromeVisible
        self._isShowingContents = isShowingContents
        self.title = title
        self.onClose = onClose
        self.onSettings = onSettings
        self.onFinished = onFinished
        self._pager = StateObject(wrappedValue: KhyloEPUBPager(itemID: itemID, book: book))
    }

    private var css: String {
        let margin = style.margins.points
        let fontRule = style.font.cssFamily.map { "font-family: \($0) !important;" } ?? ""
        let inheritFont = style.font.cssFamily == nil ? "" : "font-family: inherit !important;"
        return """
        html { -webkit-text-size-adjust: 100%; }
        html { margin: 0 !important; background-color: \(theme.backgroundHex) !important; \(theme.texture.css(dark: theme.isDark)) }
        body { margin: 0 !important; background: transparent !important; }
        body {
          box-sizing: border-box !important;
          height: 100vh !important;
          padding: 74px \(margin)px 62px \(margin)px !important;
          column-width: calc(100vw - \(margin * 2)px) !important;
          column-gap: \(margin * 2)px !important;
          column-fill: auto !important;
          \(fontRule)
          font-size: \(Int(style.fontScale * 112))% !important;
          line-height: \(style.spacing.lineHeight) !important;
          color: \(theme.foregroundHex) !important;
          text-align: \(style.justified ? "justify" : "left");
          -webkit-hyphens: \(style.justified ? "auto" : "manual"); hyphens: \(style.justified ? "auto" : "manual");
          text-rendering: optimizeLegibility;
          -webkit-font-smoothing: antialiased;
          font-feature-settings: "kern", "liga", "onum";
          widows: 2; orphans: 2;
        }
        body * { color: inherit !important; background-color: transparent !important; \(inheritFont) max-width: 100% !important; line-height: inherit; }
        p { margin-top: 0 !important; margin-bottom: 0.85em !important; }
        h1, h2, h3 { text-align: left; line-height: 1.25 !important; -webkit-hyphens: none; hyphens: none; letter-spacing: -0.01em; }
        h1 { font-size: 1.6em !important; margin: 0.4em 0 0.9em !important; }
        img, svg, video { max-width: 100% !important; max-height: calc(100vh - 150px) !important; height: auto !important; object-fit: contain; break-inside: avoid; display: block; margin: 0 auto; }
        a { color: \(theme.linkHex) !important; text-decoration: none !important; }
        ::selection { background: rgba(217, 119, 50, 0.3); }
        """
    }

    var body: some View {
        ZStack {
            // The page itself fades in once laid out; the curl layer above it stays visible.
            KhyloEPUBWebView(container: pager.container, background: theme.background, isReady: pager.isReady)
                .ignoresSafeArea()

            if !pager.isReady {
                ProgressView().tint(theme.foreground.opacity(0.5))
            }

            if !isChromeVisible, pager.isReady {
                runningHeadAndFoot
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Tap the edges to turn pages, the middle to show controls; swipe also turns.
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                if value.translation.width < -40 { pager.next() }
                                else if value.translation.width > 40 { pager.previous() }
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            let x = value.location.x / proxy.size.width
                            if x < 0.28 {
                                pager.previous()
                            } else if x > 0.72 {
                                pager.next()
                            } else {
                                isChromeVisible.toggle()
                            }
                        }
                    )
            }
            .ignoresSafeArea()

            if isChromeVisible {
                KhyloReaderChrome(
                    theme: theme,
                    title: title,
                    subtitle: pager.chapterTitle,
                    progress: pager.overallProgress,
                    status: status,
                    onScrub: { fraction in
                        let count = pager.book.chapters.count
                        pager.goToChapter(min(count - 1, max(0, Int(fraction * Double(count)))))
                    },
                    onClose: onClose
                ) {
                    KhyloReaderIconButton(systemImage: "list.bullet", theme: theme, label: "Contents") {
                        isShowingContents = true
                    }
                    KhyloReaderIconButton(systemImage: "textformat.size", theme: theme, label: "Appearance") {
                        onSettings()
                    }
                }
            }
        }
        .onAppear {
            pager.onFinished = onFinished
            pager.usesPageCurl = style.pageCurl
            pager.start(css: css)
            // Hide controls once reading starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isChromeVisible = false }
        }
        .onChange(of: css) { _, newValue in
            pager.updateStyle(css: newValue)
        }
        .onChange(of: style.pageCurl) { _, newValue in
            pager.usesPageCurl = newValue
        }
        .sheet(isPresented: $isShowingContents) {
            contents
        }
    }

    /// Chapter title above the page and pages left below it, like a printed book.
    private var runningHeadAndFoot: some View {
        VStack {
            Text(pager.chapterTitle)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .lineLimit(1)
                .padding(.top, 14)
                .padding(.horizontal, 60)
            Spacer()
            HStack {
                Text(pager.pagesLeftInChapter == 0 ? "Last page in chapter" : "\(pager.pagesLeftInChapter) page\(pager.pagesLeftInChapter == 1 ? "" : "s") left in chapter")
                Spacer()
                Text("\(Int((pager.overallProgress * 100).rounded()))%")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .padding(.horizontal, CGFloat(style.margins.points))
            .padding(.bottom, 8)
        }
        .foregroundColor(theme.foreground.opacity(0.42))
    }

    private var status: String {
        let pagesLeft = pager.pagesLeftInChapter
        let chapterPart = "\(Int((pager.overallProgress * 100).rounded()))%"
        return pagesLeft == 0
            ? "\(chapterPart) · Last page in chapter"
            : "\(chapterPart) · \(pagesLeft) page\(pagesLeft == 1 ? "" : "s") left in chapter"
    }

    private var contents: some View {
        NavigationStack {
            List {
                ForEach(Array(uniqueChapters.enumerated()), id: \.offset) { _, entry in
                    Button {
                        pager.goToChapter(entry.index)
                        isShowingContents = false
                    } label: {
                        HStack {
                            Text(entry.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if entry.index <= pager.chapterIndex,
                               pager.chapterIndex < (entry.nextIndex ?? Int.max) {
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(KhyloStyle.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isShowingContents = false }
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    /// Chapters that share a title (split files) collapse into one entry.
    private var uniqueChapters: [(index: Int, title: String, nextIndex: Int?)] {
        var result: [(index: Int, title: String, nextIndex: Int?)] = []
        for (index, chapter) in pager.book.chapters.enumerated() where result.last?.title != chapter.title {
            if !result.isEmpty { result[result.count - 1].nextIndex = index }
            result.append((index, chapter.title, nil))
        }
        return result
    }
}

// MARK: - PDF

struct KhyloPDFReader: View {

    let itemID: String
    let url: URL
    let theme: KhyloReaderTheme
    let title: String
    @Binding var isChromeVisible: Bool
    let onClose: () -> Void
    let onSettings: () -> Void
    let onFinished: () -> Void

    @State private var page = 0
    @State private var pageCount = 1

    var body: some View {
        ZStack {
            KhyloPDFView(
                url: url,
                background: theme.background,
                startPage: ReaderPosition.load(itemID)?.section ?? 0,
                page: $page,
                pageCount: $pageCount,
                onTap: { isChromeVisible.toggle() }
            )
            .ignoresSafeArea()

            if isChromeVisible {
                KhyloReaderChrome(
                    theme: theme,
                    title: title,
                    subtitle: "",
                    progress: pageCount > 1 ? Double(page) / Double(pageCount - 1) : 1,
                    status: "Page \(page + 1) of \(pageCount)",
                    onClose: onClose
                ) {
                    KhyloReaderIconButton(systemImage: "circle.lefthalf.filled", theme: theme, label: "Appearance") {
                        onSettings()
                    }
                }
            }
        }
        .onChange(of: page) { _, newValue in
            ReaderPosition(section: newValue, fraction: 0).save(itemID)
            if newValue == pageCount - 1 { onFinished() }
        }
    }
}

private struct KhyloPDFView: UIViewRepresentable {
    let url: URL
    let background: Color
    let startPage: Int
    @Binding var page: Int
    @Binding var pageCount: Int
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true)
        view.autoScales = true
        view.backgroundColor = UIColor(background)
        view.document = PDFDocument(url: url)

        if let document = view.document {
            DispatchQueue.main.async {
                pageCount = document.pageCount
                if let start = document.page(at: min(startPage, max(document.pageCount - 1, 0))) {
                    view.go(to: start)
                }
                page = min(startPage, max(document.pageCount - 1, 0))
            }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.backgroundColor = UIColor(background)
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: KhyloPDFView

        init(_ parent: KhyloPDFView) { self.parent = parent }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let current = view.currentPage,
                  let index = view.document?.index(for: current)
            else { return }
            parent.page = index
        }

        @objc func tapped() { parent.onTap() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Book page

/// Book page: the cover front and center, title and author, and Read.
struct KhyloBookScreen: View {

    @State var book: BaseItemDto
    @Router private var router
    @State private var isOverviewExpanded = false

    private var position: ReaderPosition? {
        book.id.flatMap(ReaderPosition.load)
    }

    private var coverURL: URL? {
        KhyloArtwork.url(for: book, style: .poster, width: 400)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Group {
                    if let coverURL {
                        KhyloImage(url: coverURL, placeholderSymbol: "book.closed")
                    } else {
                        KhyloGeneratedCover(name: book.name ?? "", width: 190)
                    }
                }
                .frame(width: 190, height: 285)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
                .padding(.top, 80)

                VStack(spacing: 6) {
                    let parts = KhyloGeneratedCover.parse(book.name ?? "")
                    Text(parts.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if let author = parts.author {
                        Text(author)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(KhyloStyle.secondaryText)
                    }
                    if let year = book.productionYear {
                        Text(String(year))
                            .font(.system(size: 14))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                }
                .padding(.horizontal, 30)

                KhyloPlayButton(
                    title: position == nil ? "Read" : "Continue Reading",
                    systemImage: "book.fill"
                ) {
                    router.route(to: .khyloReader(book))
                }
                .padding(.horizontal, KhyloStyle.gutter)
                .padding(.top, 4)

                HStack(spacing: 28) {
                    KhyloIconAction(
                        title: book.khyloIsPlayed ? "Finished" : "Mark Finished",
                        systemImage: book.khyloIsPlayed ? "checkmark.circle.fill" : "checkmark.circle",
                        isActive: book.khyloIsPlayed
                    ) {
                        Task {
                            if let id = book.id, let data = try? await KhyloAPI.setPlayed(!book.khyloIsPlayed, itemID: id) {
                                book.userData = data
                            }
                        }
                    }
                    KhyloIconAction(
                        title: book.khyloIsFavorite ? "Favorited" : "Favorite",
                        systemImage: book.khyloIsFavorite ? "heart.fill" : "heart",
                        isActive: book.khyloIsFavorite
                    ) {
                        Task {
                            if let id = book.id, let data = try? await KhyloAPI.setFavorite(!book.khyloIsFavorite, itemID: id) {
                                book.userData = data
                            }
                        }
                    }
                    KhyloDownloadButton(item: book)
                }

                if let overview = book.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 15))
                        .foregroundColor(KhyloStyle.secondaryText)
                        .lineSpacing(3)
                        .lineLimit(isOverviewExpanded ? nil : 6)
                        .padding(.horizontal, KhyloStyle.gutter)
                        .padding(.top, 8)
                        .onTapGesture { withAnimation { isOverviewExpanded.toggle() } }
                }
            }
            .padding(.bottom, 40)
        }
        .background(
            ZStack {
                KhyloStyle.canvas
                Group {
                    if let coverURL {
                        KhyloImage(url: coverURL, showsPlaceholder: false)
                    } else {
                        KhyloGeneratedCover(name: book.name ?? "", width: 300)
                    }
                }
                .frame(height: 460)
                .scaleEffect(1.6)
                .blur(radius: 80)
                .opacity(0.5)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if let id = book.id, let full = try? await KhyloAPI.item(id) { book = full }
        }
    }
}
