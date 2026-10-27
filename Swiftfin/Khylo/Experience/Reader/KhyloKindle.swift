//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation

/// Opens Kindle books (MOBI, AZW and AZW3) by turning them into chapter pages
/// and images that the book reader shows like any EPUB.
///
/// Handles the older MOBI text (PalmDOC or Huffman compressed) and the newer
/// KF8 layout used by AZW3, including files that carry both (KF8 is preferred).
/// Books locked with DRM can't be opened.
enum KhyloKindle {

    enum KindleError: LocalizedError {
        case locked
        case unreadable

        var errorDescription: String? {
            switch self {
            case .locked: "This book is locked to a Kindle account (DRM), so it can't be opened here."
            case .unreadable: "This Kindle book couldn't be opened. It may be damaged."
            }
        }
    }

    /// Kindle books are Palm database files of type "BOOK" by "MOBI".
    static func isKindle(_ data: Data) -> Bool {
        data.count > 68 && data[60 ..< 68].elementsEqual(Array("BOOKMOBI".utf8))
    }

    /// Writes the book's chapters and images into `folder`.
    static func convert(_ data: Data, into folder: URL) throws -> KhyloBook.EPUB {
        let book = try PalmBook(bytes: [UInt8](data))
        let temporary = folder.deletingLastPathComponent().appendingPathComponent(".\(folder.lastPathComponent)-partial", isDirectory: true)
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.createDirectory(at: temporary.appendingPathComponent("images"), withIntermediateDirectories: true)

        let mobi = try Header(book: book, start: 0)
        guard mobi.encryption == 0 else { throw KindleError.locked }

        // Pictures are shared by both layouts and numbered from the first resource record.
        let images = writeImages(book: book, first: mobi.firstImage, into: temporary.appendingPathComponent("images"))

        let chapters: [(file: String, title: String)]
        if let kf8 = try kf8Header(book: book, mobi: mobi) {
            guard kf8.encryption == 0 else { throw KindleError.locked }
            chapters = try buildKF8(book: book, header: kf8, images: images, into: temporary)
        } else {
            chapters = try buildMOBI(book: book, header: mobi, images: images, into: temporary)
        }
        guard !chapters.isEmpty else { throw KindleError.unreadable }

        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: temporary, to: folder)
        return KhyloBook.EPUB(
            root: folder,
            chapters: chapters.map { KhyloBook.Chapter(url: folder.appendingPathComponent($0.file), title: $0.title) }
        )
    }

    // MARK: - Palm database

    private struct PalmBook {
        let bytes: [UInt8]
        let offsets: [Int]

        init(bytes: [UInt8]) throws {
            self.bytes = bytes
            guard bytes.count > 78 else { throw KindleError.unreadable }
            let count = Int(Bytes.u16(bytes, 76))
            guard count > 0, bytes.count >= 78 + count * 8 else { throw KindleError.unreadable }
            offsets = (0 ..< count).map { Int(Bytes.u32(bytes, 78 + $0 * 8)) }
        }

        var count: Int { offsets.count }

        func record(_ index: Int) -> ArraySlice<UInt8> {
            guard offsets.indices.contains(index) else { return [] }
            let start = offsets[index]
            let end = index + 1 < offsets.count ? offsets[index + 1] : bytes.count
            guard start <= end, end <= bytes.count else { return [] }
            return bytes[start ..< end]
        }
    }

    private enum Bytes {
        static func u16<C: RandomAccessCollection>(_ bytes: C, _ offset: Int) -> UInt16 where C.Element == UInt8, C.Index == Int {
            let base = bytes.startIndex + offset
            guard base >= bytes.startIndex, base + 2 <= bytes.endIndex else { return 0 }
            return UInt16(bytes[base]) << 8 | UInt16(bytes[base + 1])
        }

        static func u32<C: RandomAccessCollection>(_ bytes: C, _ offset: Int) -> UInt32 where C.Element == UInt8, C.Index == Int {
            let base = bytes.startIndex + offset
            guard base >= bytes.startIndex, base + 4 <= bytes.endIndex else { return 0 }
            return UInt32(bytes[base]) << 24 | UInt32(bytes[base + 1]) << 16 | UInt32(bytes[base + 2]) << 8 | UInt32(bytes[base + 3])
        }

        static func starts<C: RandomAccessCollection>(_ bytes: C, with text: String, at offset: Int = 0) -> Bool where C.Element == UInt8, C.Index == Int {
            let pattern = Array(text.utf8)
            let base = bytes.startIndex + offset
            guard base + pattern.count <= bytes.endIndex else { return false }
            return bytes[base ..< base + pattern.count].elementsEqual(pattern)
        }
    }

    // MARK: - Headers

    private static let none: UInt32 = 0xFFFF_FFFF

    private struct Header {
        let start: Int
        let compression: UInt16
        let textLength: Int
        let textRecords: Int
        let encryption: UInt16
        let encoding: UInt32
        let version: UInt32
        let firstImage: Int
        let huffRecord: Int
        let huffCount: Int
        let extraFlags: UInt16
        let fdst: UInt32
        let ncx: UInt32
        let fragments: UInt32
        let skeletons: UInt32
        let exth: [UInt32: [ArraySlice<UInt8>]]

        init(book: PalmBook, start: Int) throws {
            let record = book.record(start)
            guard record.count >= 16 else { throw KindleError.unreadable }
            self.start = start
            compression = Bytes.u16(record, 0)
            textLength = Int(Bytes.u32(record, 4))
            textRecords = Int(Bytes.u16(record, 8))
            encryption = Bytes.u16(record, 12)

            let hasMOBI = Bytes.starts(record, with: "MOBI", at: 16)
            let headerLength = hasMOBI ? Int(Bytes.u32(record, 20)) : 0
            encoding = hasMOBI ? Bytes.u32(record, 28) : 1252
            version = hasMOBI ? Bytes.u32(record, 36) : 0
            let firstImageRaw = hasMOBI ? Bytes.u32(record, 108) : KhyloKindle.none
            firstImage = firstImageRaw == KhyloKindle.none ? book.count : start + Int(firstImageRaw)
            huffRecord = start + Int(hasMOBI ? Bytes.u32(record, 112) : 0)
            huffCount = Int(hasMOBI ? Bytes.u32(record, 116) : 0)
            extraFlags = hasMOBI && headerLength >= 0xE4 ? Bytes.u16(record, 0xF2) : 0
            let isKF8Layout = hasMOBI && headerLength >= 0xE8
            fdst = isKF8Layout ? Bytes.u32(record, 0xC0) : KhyloKindle.none
            ncx = hasMOBI && headerLength >= 0xE4 ? Bytes.u32(record, 0xF4) : KhyloKindle.none
            fragments = isKF8Layout ? Bytes.u32(record, 0xF8) : KhyloKindle.none
            skeletons = isKF8Layout ? Bytes.u32(record, 0xFC) : KhyloKindle.none

            var exth: [UInt32: [ArraySlice<UInt8>]] = [:]
            let exthFlags = hasMOBI ? Bytes.u32(record, 128) : 0
            let exthStart = 16 + headerLength
            if exthFlags & 0x40 != 0, Bytes.starts(record, with: "EXTH", at: exthStart) {
                let count = Int(Bytes.u32(record, exthStart + 8))
                var position = exthStart + 12
                for _ in 0 ..< count {
                    let type = Bytes.u32(record, position)
                    let length = Int(Bytes.u32(record, position + 4))
                    guard length >= 8, position + length <= record.count else { break }
                    let base = record.startIndex + position
                    exth[type, default: []].append(record[base + 8 ..< base + length])
                    position += length
                }
            }
            self.exth = exth
        }

        /// Turns a record-relative index into an absolute one (none stays none).
        func absolute(_ index: UInt32) -> Int? {
            index == KhyloKindle.none ? nil : start + Int(index)
        }
    }

    /// The KF8 part of the book: the whole book for AZW3, or the second half of a combined file.
    private static func kf8Header(book: PalmBook, mobi: Header) throws -> Header? {
        if mobi.version == 8 { return mobi }
        guard let boundary = mobi.exth[121]?.first, boundary.count >= 4 else { return nil }
        let index = Int(Bytes.u32(boundary, 0))
        guard index != Int(none) else { return nil }
        for candidate in [index, index + 1] where candidate < book.count {
            let record = book.record(candidate)
            if Bytes.starts(record, with: "MOBI", at: 16), Bytes.u32(record, 36) == 8 {
                return try Header(book: book, start: candidate)
            }
        }
        return nil
    }

    // MARK: - Text

    private static func text(book: PalmBook, header: Header) throws -> [UInt8] {
        var huffman: Huffman?
        if header.compression == 17480 {
            huffman = try Huffman(book: book, first: header.huffRecord, count: header.huffCount)
        } else if header.compression != 1, header.compression != 2 {
            throw KindleError.unreadable
        }
        var output: [UInt8] = []
        output.reserveCapacity(header.textLength)
        for index in header.start + 1 ... header.start + max(header.textRecords, 1) {
            guard header.textRecords > 0 else { break }
            let record = trimTrailingEntries(Array(book.record(index)), flags: header.extraFlags)
            switch header.compression {
            case 1: output += record
            case 2: output += palmDOC(record)
            default: output += huffman?.unpack(record) ?? []
            }
        }
        if output.count > header.textLength, header.textLength > 0 {
            output.removeSubrange(header.textLength...)
        }
        return output
    }

    /// Text records can end with extra data (multibyte overlap, indexing) that isn't text.
    private static func trimTrailingEntries(_ record: [UInt8], flags: UInt16) -> [UInt8] {
        var size = record.count
        var bits = flags >> 1
        while bits != 0 {
            if bits & 1 != 0 {
                // A backwards-encoded length at the end of the record.
                var value = 0
                var shift = 0
                var position = size
                while position > 0 {
                    let byte = record[position - 1]
                    value |= Int(byte & 0x7F) << shift
                    shift += 7
                    position -= 1
                    if byte & 0x80 != 0 || shift >= 28 { break }
                }
                size -= min(value, size)
            }
            bits >>= 1
        }
        if flags & 1 != 0, size > 0 {
            size -= min(Int(record[size - 1] & 0x3) + 1, size)
        }
        return Array(record[0 ..< max(size, 0)])
    }

    /// PalmDOC's simple LZ77 compression.
    private static func palmDOC(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 2)
        var index = 0
        while index < input.count {
            let byte = Int(input[index])
            index += 1
            switch byte {
            case 1 ... 8:
                let end = min(index + byte, input.count)
                output += input[index ..< end]
                index = end
            case 0 ..< 128:
                output.append(UInt8(byte))
            case 192...:
                output.append(0x20)
                output.append(UInt8(byte ^ 0x80))
            default:
                guard index < input.count else { break }
                let pair = (byte << 8) | Int(input[index])
                index += 1
                let distance = (pair >> 3) & 0x07FF
                let length = (pair & 7) + 3
                guard distance > 0, distance <= output.count else { continue }
                for _ in 0 ..< length {
                    output.append(output[output.count - distance])
                }
            }
        }
        return output
    }

    /// Huffman + dictionary compression (HUFF/CDIC records), used by many store books.
    private final class Huffman {
        private var codes: [(length: Int, terminal: Bool, maxCode: UInt64)] = []
        private var minCodes: [UInt64] = []
        private var maxCodes: [UInt64] = []
        private var dictionary: [(bytes: [UInt8], done: Bool)?] = []

        init(book: PalmBook, first: Int, count: Int) throws {
            let huff = Array(book.record(first))
            guard Bytes.starts(huff, with: "HUFF"), huff.count >= 16 else { throw KindleError.unreadable }
            let table1 = Int(Bytes.u32(huff, 8))
            let table2 = Int(Bytes.u32(huff, 12))
            guard table1 + 1024 <= huff.count, table2 + 512 <= huff.count else { throw KindleError.unreadable }
            for entry in 0 ..< 256 {
                let value = Bytes.u32(huff, table1 + entry * 4)
                let length = Int(value & 0x1F)
                let terminal = value & 0x80 != 0
                let maxCode = ((UInt64(value >> 8) + 1) << (32 - UInt64(length))) &- 1
                codes.append((length, terminal, maxCode))
            }
            minCodes = [0]
            maxCodes = [0]
            for length in 1 ... 32 {
                let low = UInt64(Bytes.u32(huff, table2 + (length - 1) * 8))
                let high = UInt64(Bytes.u32(huff, table2 + (length - 1) * 8 + 4))
                minCodes.append(low << (32 - UInt64(length)))
                maxCodes.append(((high + 1) << (32 - UInt64(length))) &- 1)
            }
            for index in first + 1 ..< first + max(count, 1) {
                let cdic = Array(book.record(index))
                guard Bytes.starts(cdic, with: "CDIC"), cdic.count >= 16 else { continue }
                let phrases = Int(Bytes.u32(cdic, 8))
                let bits = Int(Bytes.u32(cdic, 12))
                let entries = min(1 << bits, phrases - dictionary.count)
                for entry in 0 ..< max(entries, 0) {
                    let offset = Int(Bytes.u16(cdic, 16 + entry * 2))
                    let header = Int(Bytes.u16(cdic, 16 + offset))
                    let start = 18 + offset
                    let end = min(start + (header & 0x7FFF), cdic.count)
                    dictionary.append((Array(cdic[min(start, end) ..< end]), header & 0x8000 != 0))
                }
            }
        }

        func unpack(_ input: [UInt8], depth: Int = 0) -> [UInt8] {
            guard depth < 32 else { return [] }
            var data = input
            data += [UInt8](repeating: 0, count: 8)
            var bitsLeft = input.count * 8
            var position = 0
            var buffer = read64(data, position)
            var shift = 32
            var output: [UInt8] = []
            while true {
                if shift <= 0 {
                    position += 4
                    buffer = read64(data, position)
                    shift += 32
                }
                let code = (buffer >> UInt64(shift)) & 0xFFFF_FFFF
                var (length, terminal, maxCode) = codes[Int(code >> 24)]
                if !terminal {
                    while length < 32, code < minCodes[length] { length += 1 }
                    maxCode = maxCodes[length]
                }
                guard length > 0 else { break }
                shift -= length
                bitsLeft -= length
                if bitsLeft < 0 { break }
                let entry = Int((maxCode &- code) >> UInt64(32 - length))
                guard dictionary.indices.contains(entry), let phrase = dictionary[entry] else { break }
                if phrase.done {
                    output += phrase.bytes
                } else {
                    dictionary[entry] = nil
                    let expanded = unpack(phrase.bytes, depth: depth + 1)
                    dictionary[entry] = (expanded, true)
                    output += expanded
                }
            }
            return output
        }

        private func read64(_ data: [UInt8], _ offset: Int) -> UInt64 {
            var value: UInt64 = 0
            for index in 0 ..< 8 {
                let position = offset + index
                value = value << 8 | UInt64(position < data.count ? data[position] : 0)
            }
            return value
        }
    }

    // MARK: - Images

    /// Saves each picture record as images/imgN.ext (N counts from 1, as the book refers to them).
    private static func writeImages(book: PalmBook, first: Int, into folder: URL) -> [Int: String] {
        var names: [Int: String] = [:]
        guard first < book.count else { return names }
        for index in first ..< book.count {
            let record = book.record(index)
            guard let ext = imageExtension(record) else { continue }
            let number = index - first + 1
            let name = "img\(number).\(ext)"
            if (try? Data(record).write(to: folder.appendingPathComponent(name))) != nil {
                names[number] = "images/\(name)"
            }
        }
        return names
    }

    private static func imageExtension(_ record: ArraySlice<UInt8>) -> String? {
        if record.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if record.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if record.starts(with: Array("GIF8".utf8)) { return "gif" }
        if record.starts(with: Array("BM".utf8)), record.count > 26 { return "bmp" }
        return nil
    }

    // MARK: - Byte strings

    /// Bytes as a string with one character per byte (Latin-1), so offsets stay
    /// byte offsets while editing markup. Turned back into bytes before the real
    /// text encoding is decoded.
    private static func string(_ bytes: some Collection<UInt8>) -> String {
        String(bytes: Array(bytes), encoding: .isoLatin1) ?? ""
    }

    private static func bytes(_ string: String) -> [UInt8] {
        string.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
    }

    private static func replace(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive], with transform: (NSTextCheckingResult, NSString) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(match, source)
            last = match.range.location + match.range.length
        }
        result += source.substring(from: last)
        return result
    }

    private static func decode(_ bytes: [UInt8], encoding: UInt32) -> String {
        if encoding == 65001 {
            return String(decoding: bytes, as: UTF8.self)
        }
        return String(data: Data(bytes), encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The text of the first heading in a chapter, for the contents list.
    private static func heading(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<h[1-3][^>]*>(.*?)</h[1-3]>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        else { return nil }
        let inner = (html as NSString).substring(with: match.range(at: 1))
        let plain = inner.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : String(plain.prefix(80))
    }

    private static func hasContent(_ html: String) -> Bool {
        if html.range(of: "<img", options: .caseInsensitive) != nil { return true }
        let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: "")
        return !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Older MOBI

    private static func buildMOBI(book: PalmBook, header: Header, images: [Int: String], into folder: URL) throws -> [(file: String, title: String)] {
        var raw = try text(book: book, header: header)
        guard !raw.isEmpty else { throw KindleError.unreadable }

        // Contents labels from the book's index, by text position, when it has one.
        let labels = (try? navigation(book: book, header: header, positionTag: 1)) ?? []

        // Links point at byte positions; mark each target so it can be found after splitting.
        let source = string(raw)
        var targets = Set<Int>()
        if let regex = try? NSRegularExpression(pattern: "filepos\\s*=\\s*['\"]?0*(\\d+)", options: .caseInsensitive) {
            for match in regex.matches(in: source, range: NSRange(location: 0, length: (source as NSString).length)) {
                if let value = Int((source as NSString).substring(with: match.range(at: 1))) { targets.insert(value) }
            }
        }
        let labelPositions = labels.map(\.position)
        for position in (targets.union(labelPositions)).sorted(by: >) where position < raw.count {
            let at = safeInsertPosition(raw, position)
            raw.insert(contentsOf: Array("<a id=\"filepos\(position)\"></a>".utf8), at: at)
        }

        var html = string(raw)
        html = replace("filepos\\s*=\\s*['\"]?0*(\\d+)['\"]?", in: html) { match, text in
            "href=\"#filepos\(text.substring(with: match.range(at: 1)))\""
        }
        html = replace("(?:hi|lo)?recindex\\s*=\\s*['\"]?0*(\\d+)['\"]?", in: html) { match, text in
            let number = Int(text.substring(with: match.range(at: 1))) ?? 0
            return "src=\"\(images[number] ?? "")\""
        }
        // Keep the body only.
        if let body = html.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html = String(html[body.upperBound...])
        }
        if let end = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            html = String(html[..<end.lowerBound])
        }

        let pieces = html.components(separatedBy: "\u{0}").joined()
            .replacingOccurrences(of: "<mbp:pagebreak[^>]*>", with: "\u{1}", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</?mbp:[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: "\u{1}")

        var chapters: [(file: String, title: String, html: String)] = []
        var lastTitle = "Beginning"
        for piece in pieces {
            let decoded = decode(bytes(piece), encoding: header.encoding)
            guard hasContent(decoded) else { continue }
            let anchors = Set(matches("id=\"filepos(\\d+)\"", in: decoded).compactMap(Int.init))
            let label = labels.first { anchors.contains($0.position) }?.title
            let title = label ?? heading(in: decoded) ?? lastTitle
            lastTitle = title
            chapters.append(("part\(chapters.count + 1).html", title, decoded))
        }

        // Point links at the chapter that holds each target.
        var home: [String: String] = [:]
        for chapter in chapters {
            for id in matches("id=\"(filepos\\d+)\"", in: chapter.html) { home[id] = chapter.file }
        }
        for chapter in chapters {
            let linked = replace("href=\"#(filepos\\d+)\"", in: chapter.html) { match, text in
                let id = text.substring(with: match.range(at: 1))
                return "href=\"\(home[id] ?? "")#\(id)\""
            }
            let page = """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><title>\(escape(chapter.title))</title></head>
            <body>\(linked)</body></html>
            """
            try page.write(to: folder.appendingPathComponent(chapter.file), atomically: true, encoding: .utf8)
        }
        return chapters.map { ($0.file, $0.title) }
    }

    /// Moves a position out of the middle of a tag.
    private static func safeInsertPosition(_ raw: [UInt8], _ position: Int) -> Int {
        var open = position - 1
        while open >= 0, raw[open] != UInt8(ascii: "<"), raw[open] != UInt8(ascii: ">") { open -= 1 }
        guard open >= 0, raw[open] == UInt8(ascii: "<") else { return position }
        var close = position
        while close < raw.count, raw[close] != UInt8(ascii: ">") { close += 1 }
        return min(close + 1, raw.count)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            source.substring(with: $0.range(at: 1))
        }
    }

    // MARK: - KF8 (AZW3)

    private struct Fragment {
        let insertPosition: Int
        let fileNumber: Int
        let start: Int
        let length: Int
    }

    private struct Skeleton {
        let fragmentCount: Int
        let start: Int
        let length: Int
    }

    private struct Part {
        let file: String
        let start: Int
        let end: Int
        var html: String
    }

    private static func buildKF8(book: PalmBook, header: Header, images: [Int: String], into folder: URL) throws -> [(file: String, title: String)] {
        let raw = try text(book: book, header: header)
        guard !raw.isEmpty else { throw KindleError.unreadable }

        // Flows: the main text, then stylesheets and pictures drawn in SVG.
        var flowStarts = [0]
        if let fdst = header.absolute(header.fdst) {
            let record = book.record(fdst)
            if Bytes.starts(record, with: "FDST") {
                let count = Int(Bytes.u32(record, 8))
                flowStarts = (0 ..< count).map { Int(Bytes.u32(record, 12 + $0 * 8)) }
            }
        }
        flowStarts.append(raw.count)
        let flows: [[UInt8]] = (0 ..< flowStarts.count - 1).map { index in
            let start = min(flowStarts[index], raw.count)
            let end = min(max(flowStarts[index + 1], start), raw.count)
            return Array(raw[start ..< end])
        }
        let main = flows.first ?? raw

        func isSVG(_ flow: [UInt8]) -> Bool { string(flow.prefix(200)).contains("<svg") }
        for (index, flow) in flows.enumerated().dropFirst() where isSVG(flow) {
            try Data(flow).write(to: folder.appendingPathComponent("flow\(index).svg"))
        }

        // Each chapter file is a skeleton with fragments of text dropped into it.
        let skeletons = (try? index(book: book, header.absolute(header.skeletons))).map { entries in
            entries.entries.map { entry in
                Skeleton(fragmentCount: entry.tags[1]?.first ?? 0, start: entry.tags[6]?.first ?? 0, length: entry.tags[6]?.dropFirst().first ?? 0)
            }
        } ?? []
        let fragments = (try? index(book: book, header.absolute(header.fragments))).map { entries in
            entries.entries.map { entry in
                Fragment(
                    insertPosition: Int(string(entry.key)) ?? 0,
                    fileNumber: entry.tags[3]?.first ?? 0,
                    start: entry.tags[6]?.first ?? 0,
                    length: entry.tags[6]?.dropFirst().first ?? 0
                )
            }
        } ?? []

        var parts: [Part] = []
        if skeletons.isEmpty {
            parts = [Part(file: "part1.html", start: 0, end: main.count, html: string(main))]
        } else {
            var fragmentIndex = 0
            for (number, skeleton) in skeletons.enumerated() {
                let skeletonEnd = min(skeleton.start + skeleton.length, main.count)
                var assembled = Array(main[min(skeleton.start, skeletonEnd) ..< skeletonEnd])
                var base = skeletonEnd
                for _ in 0 ..< skeleton.fragmentCount where fragmentIndex < fragments.count {
                    let fragment = fragments[fragmentIndex]
                    let sliceEnd = min(base + fragment.length, main.count)
                    let slice = main[min(base, sliceEnd) ..< sliceEnd]
                    let at = max(0, min(fragment.insertPosition - skeleton.start, assembled.count))
                    assembled.insert(contentsOf: slice, at: at)
                    base = sliceEnd
                    fragmentIndex += 1
                }
                parts.append(Part(file: "part\(number + 1).html", start: skeleton.start, end: base, html: string(assembled)))
            }
        }

        // Where a link lands: the part and the nearest named tag before the position,
        // looked up in the parts as assembled, before any rewriting.
        let originals = parts
        func target(fid: Int, offset: Int) -> String {
            guard fragments.indices.contains(fid) || fragments.isEmpty else { return "" }
            let position = fragments.isEmpty ? offset : fragments[fid].insertPosition + offset
            guard let part = originals.first(where: { position >= $0.start && position < $0.end }) ?? originals.first else { return "" }
            let local = max(0, min(position - part.start, part.html.unicodeScalars.count))
            let before = String(String.UnicodeScalarView(part.html.unicodeScalars.prefix(local)))
            if let id = lastID(in: before) { return "\(part.file)#\(id)" }
            return part.file
        }

        for index in parts.indices {
            var html = parts[index].html
            html = replace("kindle:pos:fid:([0-9A-V]{4}):off:([0-9A-V]{10})", in: html, options: []) { match, text in
                target(fid: base32(text.substring(with: match.range(at: 1))), offset: base32(text.substring(with: match.range(at: 2))))
            }
            html = replace("kindle:embed:([0-9A-V]{4})(\\?[^\"')\\s]*)?", in: html, options: []) { match, text in
                images[base32(text.substring(with: match.range(at: 1)))] ?? ""
            }
            html = replace("kindle:flow:([0-9A-V]{4})\\?mime=[a-z]+/([a-z+]+)", in: html, options: []) { match, text in
                let number = base32(text.substring(with: match.range(at: 1)))
                return "flow\(number).\(text.substring(with: match.range(at: 2)).hasPrefix("svg") ? "svg" : "css")"
            }
            html = idsForAIDs(html)
            var decoded = decode(bytes(html), encoding: 65001)
            if decoded.range(of: "<meta charset", options: .caseInsensitive) == nil,
               let head = decoded.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
                decoded.insert(contentsOf: "<meta charset=\"utf-8\">", at: head.upperBound)
            }
            parts[index].html = decoded
        }
        for (index, flow) in flows.enumerated().dropFirst() where !isSVG(flow) {
            let css = replace("kindle:embed:([0-9A-V]{4})(\\?[^\"')\\s]*)?", in: string(flow), options: []) { match, text in
                images[base32(text.substring(with: match.range(at: 1)))] ?? ""
            }
            try Data(bytes(css)).write(to: folder.appendingPathComponent("flow\(index).css"))
        }

        // Contents labels from the book's index.
        var titles: [String: String] = [:]
        if let entries = try? navigation(book: book, header: header, positionTag: 6) {
            for entry in entries {
                let position = fragments.indices.contains(entry.position) ? fragments[entry.position].insertPosition + entry.offset : entry.position
                if let part = parts.first(where: { position >= $0.start && position < $0.end }), titles[part.file] == nil {
                    titles[part.file] = entry.title
                }
            }
        }

        var chapters: [(file: String, title: String)] = []
        var lastTitle = "Beginning"
        for part in parts where hasContent(part.html) {
            try part.html.write(to: folder.appendingPathComponent(part.file), atomically: true, encoding: .utf8)
            let title = titles[part.file] ?? heading(in: part.html) ?? lastTitle
            lastTitle = title
            chapters.append((part.file, title))
        }
        return chapters
    }

    /// KF8 tags carry their own position names (aid="…"); links to them need ids.
    private static func idsForAIDs(_ html: String) -> String {
        replace("<[^>]+\\said\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>", in: html, options: []) { match, text in
            let tag = text.substring(with: match.range)
            if tag.range(of: "\\sid\\s*=", options: .regularExpression) != nil { return tag }
            let aid = text.substring(with: match.range(at: 1))
            return tag.replacingOccurrences(of: "aid=", with: "id=\"aid-\(aid)\" aid=", options: [], range: tag.range(of: "aid="))
        }
    }

    private static func lastID(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]*\\s(?:id|name)\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>", options: .caseInsensitive) else { return nil }
        let source = html as NSString
        let found = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        for match in found.reversed() {
            let tag = source.substring(with: match.range).lowercased()
            if tag.hasPrefix("<body") { return nil }
            if tag.hasPrefix("<meta") { continue }
            return source.substring(with: match.range(at: 1))
        }
        // Fall back to Kindle's own position names, which get ids above.
        if let aid = matches("<[^>]+\\said\\s*=\\s*['\"]([^'\"]+)['\"]", in: html).last { return "aid-\(aid)" }
        return nil
    }

    private static func base32(_ text: String) -> Int {
        text.uppercased().reduce(0) { value, character in
            let digit = character.isNumber ? Int(character.asciiValue! - 48) : Int(character.asciiValue! - 55)
            return value * 32 + digit
        }
    }

    // MARK: - Indexes (INDX records)

    private struct IndexEntry {
        let key: [UInt8]
        let tags: [Int: [Int]]
    }

    private struct IndexTable {
        let entries: [IndexEntry]
        let names: [Int: String]
    }

    /// The contents list: a label for each position the book's index names.
    /// MOBI keeps the text position in tag 1; KF8 keeps a fragment and offset in tag 6.
    private static func navigation(book: PalmBook, header: Header, positionTag: Int) throws -> [(position: Int, offset: Int, title: String)] {
        guard let table = try? index(book: book, header.absolute(header.ncx)) else { return [] }
        return table.entries.compactMap { entry in
            guard let label = entry.tags[3]?.first.flatMap({ table.names[$0] }),
                  let values = entry.tags[positionTag], let first = values.first
            else { return nil }
            if let depth = entry.tags[4]?.first, depth > 0 { return nil }
            let offset = values.count > 1 ? values[1] : 0
            return (first, offset, label)
        }
    }

    private static func index(book: PalmBook, _ start: Int?) throws -> IndexTable {
        guard let start else { throw KindleError.unreadable }
        let main = Array(book.record(start))
        guard Bytes.starts(main, with: "INDX") else { throw KindleError.unreadable }
        let headerLength = Int(Bytes.u32(main, 4))
        let recordCount = Int(Bytes.u32(main, 24))
        let cncxCount = Int(Bytes.u32(main, 52))
        let encoding = Bytes.u32(main, 28)

        // Tag layout: (tag, values per entry, mask, end flag).
        var controlBytes = 0
        var tagTable: [(tag: Int, perEntry: Int, mask: UInt8, end: UInt8)] = []
        if Bytes.starts(main, with: "TAGX", at: headerLength) {
            let first = Int(Bytes.u32(main, headerLength + 4))
            controlBytes = Int(Bytes.u32(main, headerLength + 8))
            var position = headerLength + 12
            while position + 4 <= headerLength + first, position + 4 <= main.count {
                tagTable.append((Int(main[position]), Int(main[position + 1]), main[position + 2], main[position + 3]))
                position += 4
            }
        }

        // Names (labels) live in CNCX records after the index records.
        var names: [Int: String] = [:]
        for number in 0 ..< cncxCount {
            let record = Array(book.record(start + recordCount + 1 + number))
            var offset = 0
            while offset < record.count, record[offset] != 0 {
                let entryOffset = offset
                let (consumed, length) = forwardVarint(record, offset)
                offset += consumed
                let end = min(offset + length, record.count)
                let text = Array(record[offset ..< end])
                names[entryOffset + number * 0x10000] = encoding == 65001 || encoding == 0
                    ? String(decoding: text, as: UTF8.self)
                    : (String(data: Data(text), encoding: .windowsCP1252) ?? "")
                offset = end
            }
        }

        var entries: [IndexEntry] = []
        for number in 1 ... max(recordCount, 1) where recordCount > 0 {
            let record = Array(book.record(start + number))
            guard Bytes.starts(record, with: "INDX") else { continue }
            let idxt = Int(Bytes.u32(record, 20))
            let count = Int(Bytes.u32(record, 24))
            var positions = (0 ..< count).map { Int(Bytes.u16(record, idxt + 4 + $0 * 2)) }
            positions.append(idxt)
            for entry in 0 ..< count {
                let begin = positions[entry]
                let end = positions[entry + 1]
                guard begin < record.count, begin < end else { continue }
                let keyLength = Int(record[begin])
                let keyEnd = min(begin + 1 + keyLength, record.count)
                let key = Array(record[begin + 1 ..< keyEnd])
                let tags = tagMap(record, controlBytes: controlBytes, table: tagTable, start: keyEnd, end: end)
                entries.append(IndexEntry(key: key, tags: tags))
            }
        }
        return IndexTable(entries: entries, names: names)
    }

    private static func tagMap(_ data: [UInt8], controlBytes: Int, table: [(tag: Int, perEntry: Int, mask: UInt8, end: UInt8)], start: Int, end: Int) -> [Int: [Int]] {
        var controlIndex = 0
        var position = start + controlBytes
        var found: [(tag: Int, count: Int?, byteLength: Int?, perEntry: Int)] = []
        for entry in table {
            if entry.end == 1 {
                controlIndex += 1
                continue
            }
            guard start + controlIndex < data.count else { break }
            let control = data[start + controlIndex]
            var value = control & entry.mask
            guard value != 0 else { continue }
            if value == entry.mask {
                if entry.mask.nonzeroBitCount > 1 {
                    let (consumed, length) = forwardVarint(data, position)
                    position += consumed
                    found.append((entry.tag, nil, length, entry.perEntry))
                } else {
                    found.append((entry.tag, 1, nil, entry.perEntry))
                }
            } else {
                var mask = entry.mask
                while mask & 1 == 0 {
                    mask >>= 1
                    value >>= 1
                }
                found.append((entry.tag, Int(value), nil, entry.perEntry))
            }
        }
        var result: [Int: [Int]] = [:]
        for item in found {
            var values: [Int] = []
            if let count = item.count {
                for _ in 0 ..< count * item.perEntry where position < end {
                    let (consumed, value) = forwardVarint(data, position)
                    position += consumed
                    values.append(value)
                }
            } else if let length = item.byteLength {
                var used = 0
                while used < length, position < end {
                    let (consumed, value) = forwardVarint(data, position)
                    position += consumed
                    used += consumed
                    values.append(value)
                }
            }
            result[item.tag] = values
        }
        return result
    }

    /// A variable-width number whose last byte has the top bit set.
    private static func forwardVarint(_ data: [UInt8], _ offset: Int) -> (consumed: Int, value: Int) {
        var value = 0
        var consumed = 0
        while offset + consumed < data.count {
            let byte = data[offset + consumed]
            consumed += 1
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 != 0 || consumed >= 5 { break }
        }
        return (consumed, value)
    }
}
