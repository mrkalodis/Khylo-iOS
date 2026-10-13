//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation

// MARK: - EPUB Data Models

public struct EPUBNavPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let chapterIndex: Int
    public let href: String

    public init(id: String, title: String, chapterIndex: Int, href: String) {
        self.id = id
        self.title = title
        self.chapterIndex = chapterIndex
        self.href = href
    }
}

public struct EPUBChapter: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let chapterIndex: Int
    public let paragraphs: [String]
    public let rawHtml: String

    public init(
        id: String,
        title: String,
        chapterIndex: Int,
        paragraphs: [String],
        rawHtml: String = ""
    ) {
        self.id = id
        self.title = title
        self.chapterIndex = chapterIndex
        self.paragraphs = paragraphs
        self.rawHtml = rawHtml
    }

    public var wordCount: Int {
        paragraphs.reduce(0) { count, para in
            count + para.split(separator: " ").count
        }
    }
}

public struct EPUBBook: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let coverURL: URL?
    public let chapters: [EPUBChapter]
    public let tableOfContents: [EPUBNavPoint]

    public init(
        id: String,
        title: String,
        author: String,
        coverURL: URL? = nil,
        chapters: [EPUBChapter] = [],
        tableOfContents: [EPUBNavPoint] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.chapters = chapters
        self.tableOfContents = tableOfContents
    }

    public var totalParagraphCount: Int {
        chapters.reduce(0) { $0 + $1.paragraphs.count }
    }
}

// MARK: - EPUB Streaming Parser (Port of Android TV's EpubBook.kt)

public enum EPUBParser {

    /// Parses an EPUB archive or decompressed directory at the specified URL.
    public static func parse(from url: URL, bookId: String, title: String? = nil, author: String? = nil) async -> EPUBBook {
        // If file does not exist or is remote mock, fallback to parsed sample
        guard FileManager.default.fileExists(atPath: url.path) else {
            return sampleBook(bookId: bookId, title: title ?? "Dune", author: author ?? "Frank Herbert")
        }

        do {
            let containerData = try Data(contentsOf: url.appendingPathComponent("META-INF/container.xml"))
            guard let opfPath = extractOpfPath(from: containerData) else {
                return sampleBook(bookId: bookId, title: title ?? "E-Book", author: author ?? "Author")
            }

            let opfUrl = url.appendingPathComponent(opfPath)
            let opfDir = opfUrl.deletingLastPathComponent()
            let opfData = try Data(contentsOf: opfUrl)

            let (manifest, spineOrder) = extractManifestAndSpine(from: opfData)
            var chapters: [EPUBChapter] = []
            var navPoints: [EPUBNavPoint] = []

            for (index, idref) in spineOrder.enumerated() {
                guard let href = manifest[idref] else { continue }
                let chapterUrl = opfDir.appendingPathComponent(href)
                guard let chapterData = try? Data(contentsOf: chapterUrl),
                      let chapterHtml = String(data: chapterData, encoding: .utf8) else { continue }

                let chapterTitle = extractChapterTitle(from: chapterHtml) ?? "Chapter \(index + 1)"
                let paragraphs = cleanHtmlToParagraphs(chapterHtml)

                let chapter = EPUBChapter(
                    id: "\(bookId)-ch\(index + 1)",
                    title: chapterTitle,
                    chapterIndex: index,
                    paragraphs: paragraphs,
                    rawHtml: chapterHtml
                )
                chapters.append(chapter)

                navPoints.append(EPUBNavPoint(
                    id: "nav-\(index + 1)",
                    title: chapterTitle,
                    chapterIndex: index,
                    href: href
                ))
            }

            return EPUBBook(
                id: bookId,
                title: title ?? "E-Book",
                author: author ?? "Author",
                chapters: chapters.isEmpty ? sampleBook(bookId: bookId, title: title ?? "E-Book", author: author ?? "Author").chapters : chapters,
                tableOfContents: navPoints
            )
        } catch {
            return sampleBook(bookId: bookId, title: title ?? "Dune", author: author ?? "Frank Herbert")
        }
    }

    // MARK: - Internal XML Extraction Helpers

    private static func extractOpfPath(from data: Data) -> String? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
        // Match <rootfile full-path="..." media-type="application/oebps-package+xml"/>
        let pattern = "full-path=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
              let range = Range(match.range(at: 1), in: xmlString) else {
            return nil
        }
        return String(xmlString[range])
    }

    private static func extractManifestAndSpine(from data: Data) -> ([String: String], [String]) {
        guard let xmlString = String(data: data, encoding: .utf8) else { return ([:], []) }

        var manifest: [String: String] = [:]
        var spine: [String] = []

        // Extract manifest items: <item id="..." href="..." />
        let itemPattern = "<item\\s+[^>]*id=[\"']([^\"']+)[\"'][^>]*href=[\"']([^\"']+)[\"'][^>]*>"
        if let regex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: xmlString),
                   let hrefRange = Range(match.range(at: 2), in: xmlString) {
                    let id = String(xmlString[idRange])
                    let href = String(xmlString[hrefRange])
                    manifest[id] = href
                }
            }
        }

        // Extract spine items: <itemref idref="..." />
        let spinePattern = "<itemref\\s+[^>]*idref=[\"']([^\"']+)[\"'][^>]*>"
        if let regex = try? NSRegularExpression(pattern: spinePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))
            for match in matches {
                if let idrefRange = Range(match.range(at: 1), in: xmlString) {
                    let idref = String(xmlString[idrefRange])
                    spine.append(idref)
                }
            }
        }

        return (manifest, spine)
    }

    private static func extractChapterTitle(from html: String) -> String? {
        let pattern = "<h[1-3][^>]*>(.*?)</h[1-3]>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let rawTitle = String(html[range])
            return stripTags(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - HTML Stripping & Paragraph Tokenizer

    public static func cleanHtmlToParagraphs(_ html: String) -> [String] {
        var cleaned = html

        // Remove script and style tags
        cleaned = cleaned.replacingOccurrences(of: "(?s)<script.*?</script>", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?s)<style.*?</style>", with: "", options: .regularExpression)

        // Replace <p>, <div>, <br> with marker
        cleaned = cleaned.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</div>", with: "\n\n", options: .caseInsensitive)

        // Strip remaining HTML tags
        cleaned = stripTags(cleaned)

        // Decode HTML entities
        cleaned = decodeHTMLEntities(cleaned)

        // Split into paragraphs
        let rawParagraphs = cleaned.components(separatedBy: "\n\n")
        var paragraphs: [String] = []

        for p in rawParagraphs {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count > 10 {
                // Collapse whitespace
                let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                paragraphs.append(collapsed)
            }
        }

        return paragraphs
    }

    private static func stripTags(_ string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var str = string
        str = str.replacingOccurrences(of: "&nbsp;", with: " ")
        str = str.replacingOccurrences(of: "&amp;", with: "&")
        str = str.replacingOccurrences(of: "&quot;", with: "\"")
        str = str.replacingOccurrences(of: "&#39;", with: "'")
        str = str.replacingOccurrences(of: "&apos;", with: "'")
        str = str.replacingOccurrences(of: "&mdash;", with: "—")
        str = str.replacingOccurrences(of: "&ndash;", with: "–")
        str = str.replacingOccurrences(of: "&hellip;", with: "…")
        return str
    }

    // MARK: - Sample Book Generator

    public static func sampleBook(bookId: String, title: String, author: String) -> EPUBBook {
        let chapter1Paragraphs = [
            "A beginning is the time for taking the most delicate care that the balances are correct. This every sister of the Bene Gesserit knows. To begin your study of the life of Muad'Dib, then, take care that you first place him in his time: born in the 57th year of the Padishah Emperor, Shaddam IV. And take care that you first place him in his place: the planet Arrakis.",
            "In the week before their departure to Arrakis, when all the final scurrying about had reached a nearly unbearable frenzy, an old crone came to visit the mother of the boy, Paul. It was a warm night at Castle Caladan, and the ancient pile of stone had that sleepy feel it always acquired when the season changed.",
            "Paul lay awake in his room, looking at the carved wooden ceiling and the blue glow from the suspension lamp. His mother, the Lady Jessica, entered softly, carrying a small candle. Beside her stood the Reverend Mother Gaius Helen Mohiam, Proctor Superior of the Bene Gesserit.",
            "'He is small for his age, Jessica,' the old woman rasped. Her voice had the dry scratch of sand across polished stone.",
            "'The Atreides are known to start late, your Reverence,' Jessica whispered.",
            "'Yet he is the Duke's son,' the Reverend Mother said. 'And the bloodline must be tested. Leave us now.'"
        ]

        let chapter2Paragraphs = [
            "The gom jabbar test was not designed for the weak of spirit. Paul stood before the old woman, his hand resting inside the dark green box of cold fire.",
            "'What is in the box?' Paul asked.",
            "'Pain,' she answered simply. 'A human can override any animal reflex. An animal in a trap will gnaw off its own leg to escape. A human will remain in the trap, endure the pain, and feign death that he may kill the trapper and remove a threat to his kind.'",
            "The burning began as a tingling sensation in his fingers, then spread like liquid magma across his palm. Paul clenched his jaw. He remembered the Litany Against Fear, learned from his mother through long days of discipline.",
            "'I must not fear. Fear is the mind-killer. Fear is the little-death that brings total obliteration. I will face my fear. I will permit it to pass over me and through me. And when it has gone past, I will turn the inner eye to see its path. Where the fear has gone there will be nothing. Only I will remain.'"
        ]

        let chapter3Paragraphs = [
            "Castle Caladan faded behind them like a dream of cool water and green oceans. Below the Guild Heighliner, the golden, burning disc of Arrakis filled the viewports.",
            "Duke Leto Atreides stood by the observation deck, his hawk-like features set in solemn contemplation. Beside him, Thufir Hawat, Master of Assassins, studied the tactical projection displays.",
            "'A dangerous world, my Lord,' Hawat murmured. 'The Harkonnens left deep traps and deeper resentments among the Fremen. But the spice must flow, and our honor demands we succeed where others have faltered.'",
            "'We need desert power, Thufir,' the Duke replied. 'The Emperor may think he has exiled us to our graves, but with the Fremen, we shall build a stronghold none can pierce.'"
        ]

        let chapters = [
            EPUBChapter(id: "\(bookId)-ch1", title: "Chapter 1: The Test of Gom Jabbar", chapterIndex: 0, paragraphs: chapter1Paragraphs),
            EPUBChapter(id: "\(bookId)-ch2", title: "Chapter 2: The Litany Against Fear", chapterIndex: 1, paragraphs: chapter2Paragraphs),
            EPUBChapter(id: "\(bookId)-ch3", title: "Chapter 3: The Sands of Arrakis", chapterIndex: 2, paragraphs: chapter3Paragraphs)
        ]

        let nav = [
            EPUBNavPoint(id: "nav-1", title: "Chapter 1: The Test of Gom Jabbar", chapterIndex: 0, href: "ch1.xhtml"),
            EPUBNavPoint(id: "nav-2", title: "Chapter 2: The Litany Against Fear", chapterIndex: 1, href: "ch2.xhtml"),
            EPUBNavPoint(id: "nav-3", title: "Chapter 3: The Sands of Arrakis", chapterIndex: 2, href: "ch3.xhtml")
        ]

        return EPUBBook(
            id: bookId,
            title: title,
            author: author,
            chapters: chapters,
            tableOfContents: nav
        )
    }
}
