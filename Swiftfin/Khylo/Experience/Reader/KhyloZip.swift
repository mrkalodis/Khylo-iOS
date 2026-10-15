//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Compression
import Foundation

/// Minimal ZIP reader for EPUB and CBZ files: reads the central directory and
/// extracts stored or deflated entries. No ZIP64, encryption or spanning,
/// which ebook files don't use.
enum KhyloZip {

    enum ZipError: LocalizedError {
        case notAZip
        case corrupt
        case unsupportedCompression(UInt16)

        var errorDescription: String? {
            switch self {
            case .notAZip: "This file isn't a valid archive."
            case .corrupt: "This file is damaged."
            case let .unsupportedCompression(method): "Unsupported compression (\(method))."
            }
        }
    }

    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Lists the archive's entries.
    static func entries(in data: Data) throws -> [Entry] {
        // End of central directory: last 22+ bytes, signature 0x06054b50.
        guard data.count >= 22 else { throw ZipError.notAZip }
        let searchStart = max(0, data.count - 22 - 65535)
        var eocd: Int?
        var index = data.count - 22
        while index >= searchStart {
            if data.u32(at: index) == 0x0605_4B50 {
                eocd = index
                break
            }
            index -= 1
        }
        guard let eocd else { throw ZipError.notAZip }

        let count = Int(data.u16(at: eocd + 10))
        var offset = Int(data.u32(at: eocd + 16))
        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for _ in 0 ..< count {
            guard offset + 46 <= data.count, data.u32(at: offset) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = data.u16(at: offset + 10)
            let compressed = Int(data.u32(at: offset + 20))
            let uncompressed = Int(data.u32(at: offset + 24))
            let nameLength = Int(data.u16(at: offset + 28))
            let extraLength = Int(data.u16(at: offset + 30))
            let commentLength = Int(data.u16(at: offset + 32))
            let localOffset = Int(data.u32(at: offset + 42))
            guard offset + 46 + nameLength <= data.count else { throw ZipError.corrupt }
            let nameData = data.subdata(in: offset + 46 ..< offset + 46 + nameLength)
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            entries.append(Entry(
                path: name,
                method: method,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Returns one entry's uncompressed bytes.
    static func read(_ entry: Entry, from data: Data) throws -> Data {
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, data.u32(at: header) == 0x0403_4B50 else { throw ZipError.corrupt }
        let nameLength = Int(data.u16(at: header + 26))
        let extraLength = Int(data.u16(at: header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt }
        let compressed = data.subdata(in: start ..< start + entry.compressedSize)

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    /// Extracts every file into `directory`, refusing paths that escape it.
    static func extract(_ data: Data, to directory: URL) throws {
        let root = directory.standardizedFileURL
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        for entry in try entries(in: data) where !entry.path.hasSuffix("/") {
            let components = entry.path.split(separator: "/")
            guard !components.contains(".."), !entry.path.hasPrefix("/") else { continue }
            let destination = root.appendingPathComponent(entry.path).standardizedFileURL
            guard destination.path.hasPrefix(root.path + "/") else { continue }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try read(entry, from: data).write(to: destination)
        }
    }

    /// Raw DEFLATE (what ZIP uses); `COMPRESSION_ZLIB` decodes raw deflate streams.
    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError.corrupt }
        return output
    }
}

private extension Data {
    func u16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func u32(at offset: Int) -> UInt32 {
        UInt32(u16(at: offset)) | UInt32(u16(at: offset + 2)) << 16
    }
}
