//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation

/// A downloaded, ready-to-read book.
enum KhyloBook {

    struct Chapter: Hashable {
        /// Absolute file URL of the chapter's XHTML.
        let url: URL
        let title: String
    }

    struct EPUB {
        /// Folder the book was unzipped into (WebKit is given read access to it).
        let root: URL
        let chapters: [Chapter]
    }

    case epub(EPUB)
    case pdf(URL)
    case comic([URL])

    enum LoadError: LocalizedError {
        case notSignedIn
        case unsupported
        case empty

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "You're not signed in."
            case .unsupported: "This book's format isn't supported yet. EPUB, PDF and CBZ files can be read."
            case .empty: "This book has no readable pages."
            }
        }
    }

    // MARK: - Loading

    private static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KhyloBooks", isDirectory: true)
    }

    /// Downloads (once) and opens the book.
    static func load(itemID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> KhyloBook {
        let folder = cacheRoot.appendingPathComponent(itemID, isDirectory: true)
        let file = folder.appendingPathComponent("book")
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: file.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try await download(itemID: itemID, to: file, progress: progress)
        }

        let data = try Data(contentsOf: file, options: .mappedIfSafe)

        if data.starts(with: Array("%PDF".utf8)) {
            return .pdf(file)
        }

        guard data.starts(with: [0x50, 0x4B]) else { throw LoadError.unsupported }

        let extracted = folder.appendingPathComponent("contents", isDirectory: true)
        if !fileManager.fileExists(atPath: extracted.path) {
            try KhyloZip.extract(data, to: extracted)
        }

        if fileManager.fileExists(atPath: extracted.appendingPathComponent("META-INF/container.xml").path) {
            return .epub(try parseEPUB(at: extracted))
        }

        let images = imageFiles(in: extracted)
        guard !images.isEmpty else { throw LoadError.unsupported }
        return .comic(images)
    }

    private static func download(itemID: String, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let url = KhyloAPI.downloadURL(itemID: itemID), let token = KhyloAPI.accessToken else {
            throw LoadError.notSignedIn
        }
        var request = URLRequest(url: url)
        request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")

        let downloaded = try await KhyloDownloader.download(request, progress: progress)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded, to: destination)
        progress(1)
    }

    private static func imageFiles(in folder: URL) -> [URL] {
        let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        let files = (enumerator?.allObjects as? [URL] ?? [])
            .filter { extensions.contains($0.pathExtension.lowercased()) && !$0.path.contains("__MACOSX") }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - EPUB

    private static func parseEPUB(at root: URL) throws -> EPUB {
        let container = try Data(contentsOf: root.appendingPathComponent("META-INF/container.xml"))
        let rootfile = XMLScan(container).elements.first { $0.name == "rootfile" }?.attributes["full-path"]
        guard let rootfile else { throw LoadError.unsupported }

        let opfURL = root.appendingPathComponent(rootfile.removingPercentEncoding ?? rootfile)
        let opfBase = opfURL.deletingLastPathComponent()
        let opf = XMLScan(try Data(contentsOf: opfURL))

        var manifest: [String: (href: String, type: String, properties: String)] = [:]
        var spine: [String] = []
        var ncxID: String?

        for element in opf.elements {
            switch element.name {
            case "item":
                if let id = element.attributes["id"], let href = element.attributes["href"] {
                    manifest[id] = (href, element.attributes["media-type"] ?? "", element.attributes["properties"] ?? "")
                }
            case "itemref":
                if let idref = element.attributes["idref"], element.attributes["linear"] != "no" {
                    spine.append(idref)
                }
            case "spine":
                ncxID = element.attributes["toc"]
            default:
                break
            }
        }

        func resolve(_ href: String, relativeTo base: URL) -> URL {
            let path = href.components(separatedBy: "#")[0]
            return base.appendingPathComponent(path.removingPercentEncoding ?? path).standardizedFileURL
        }

        // Titles from the EPUB3 nav document or the EPUB2 NCX, keyed by file.
        var titles: [String: String] = [:]
        if let nav = manifest.values.first(where: { $0.properties.contains("nav") }) {
            let navURL = resolve(nav.href, relativeTo: opfBase)
            if let data = try? Data(contentsOf: navURL) {
                for link in XMLScan(data).links {
                    let key = resolve(link.href, relativeTo: navURL.deletingLastPathComponent()).path
                    if titles[key] == nil { titles[key] = link.text }
                }
            }
        } else if let ncxID, let ncx = manifest[ncxID] {
            let ncxURL = resolve(ncx.href, relativeTo: opfBase)
            if let data = try? Data(contentsOf: ncxURL) {
                for link in XMLScan(data).ncxPoints {
                    let key = resolve(link.href, relativeTo: ncxURL.deletingLastPathComponent()).path
                    if titles[key] == nil { titles[key] = link.text }
                }
            }
        }

        var chapters: [Chapter] = []
        var lastTitle = ""
        for (index, idref) in spine.enumerated() {
            guard let item = manifest[idref] else { continue }
            let url = resolve(item.href, relativeTo: opfBase)
            let title = titles[url.path] ?? (index == 0 ? "Beginning" : lastTitle)
            lastTitle = title
            chapters.append(Chapter(url: url, title: title))
        }

        guard !chapters.isEmpty else { throw LoadError.empty }
        return EPUB(root: root, chapters: chapters)
    }
}

// MARK: - XML scanning

/// Collects elements, nav links and NCX points from an XML document.
private final class XMLScan: NSObject, XMLParserDelegate {

    struct Element {
        let name: String
        let attributes: [String: String]
    }

    struct Link {
        let href: String
        let text: String
    }

    private(set) var elements: [Element] = []
    private(set) var links: [Link] = []
    private(set) var ncxPoints: [Link] = []

    private var currentHref: String?
    private var currentText = ""
    private var inNavLabel = false
    private var pendingLabel: String?

    init(_ data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.lowercased()
        elements.append(Element(name: elementName, attributes: attributes))

        switch name {
        case "a":
            currentHref = attributes["href"]
            currentText = ""
        case "navlabel":
            inNavLabel = true
            currentText = ""
        case "content":
            if let src = attributes["src"], let label = pendingLabel {
                ncxPoints.append(Link(href: src, text: label))
                pendingLabel = nil
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentHref != nil || inNavLabel {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.lowercased() {
        case "a":
            if let href = currentHref {
                let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { links.append(Link(href: href, text: text)) }
            }
            currentHref = nil
        case "navlabel":
            inNavLabel = false
            pendingLabel = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            break
        }
    }
}

// MARK: - Download

/// One-shot file download with progress callbacks.
private final class KhyloDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    static func download(_ request: URLRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let downloader = KhyloDownloader(progress: progress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            continuation?.resume(throwing: URLError(.badServerResponse))
            continuation = nil
            return
        }
        // The system deletes `location` when this returns, so move it first.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
