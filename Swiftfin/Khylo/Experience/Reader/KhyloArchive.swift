//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Darwin
import Foundation

/// Opens comic archives that aren't ZIP files (CBR, CB7, CBT) with the
/// system's libarchive, which reads RAR, RAR 5, 7-Zip and tar.
///
/// iOS ships libarchive but not its headers, so the handful of functions used
/// here are looked up when first needed.
enum KhyloArchive {

    enum ArchiveError: LocalizedError {
        case unavailable
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "This comic's format can't be opened on this iPhone."
            case let .unreadable(reason): "This comic couldn't be opened. \(reason)"
            }
        }
    }

    /// Recognises RAR, 7-Zip and tar files by their first bytes.
    static func isArchive(_ data: Data) -> Bool {
        if data.starts(with: Array("Rar!".utf8)) { return true }
        if data.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return true }
        if data.count > 262, data[257 ..< 262].elementsEqual(Array("ustar".utf8)) { return true }
        return false
    }

    /// Extracts every image in the archive into `folder`, keeping their order.
    static func extractImages(from file: URL, to folder: URL) throws {
        guard let lib = Library.shared else { throw ArchiveError.unavailable }

        let temporary = folder.deletingLastPathComponent().appendingPathComponent(".\(folder.lastPathComponent)-partial", isDirectory: true)
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

        guard let archive = lib.readNew() else { throw ArchiveError.unavailable }
        defer { _ = lib.readFree(archive) }
        _ = lib.supportFilterAll(archive)
        _ = lib.supportFormatAll(archive)

        let opened = file.withUnsafeFileSystemRepresentation { path in
            path.map { lib.openFilename(archive, $0, 64 * 1024) } ?? -1
        }
        guard opened == Library.ok else {
            throw ArchiveError.unreadable(lib.message(archive))
        }

        let images: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "avif"]
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        var written = 0
        var entry: OpaquePointer?

        while true {
            let status = lib.nextHeader(archive, &entry)
            if status == Library.eof { break }
            guard status == Library.ok || status == Library.warn, let entry else {
                throw ArchiveError.unreadable(lib.message(archive))
            }
            guard lib.fileType(entry) == Library.regularFile,
                  let rawPath = lib.pathname(entry).map({ String(cString: $0) }),
                  let name = safeName(for: rawPath),
                  images.contains((name as NSString).pathExtension.lowercased())
            else {
                _ = lib.dataSkip(archive)
                continue
            }

            let destination = temporary.appendingPathComponent(name)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            while true {
                let count = buffer.withUnsafeMutableBytes { lib.readData(archive, $0.baseAddress, $0.count) }
                if count == 0 { break }
                guard count > 0 else { throw ArchiveError.unreadable(lib.message(archive)) }
                handle.write(Data(buffer[0 ..< count]))
            }
            written += 1
        }

        guard written > 0 else { throw ArchiveError.unreadable("It has no pages.") }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: temporary, to: folder)
    }

    /// A flat file name that keeps the archive's sort order ("ch01/p002.jpg" → "ch01 ∕ p002.jpg"),
    /// or nil for paths to skip (Mac resource forks, hidden files).
    private static func safeName(for path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard let last = parts.last, !last.hasPrefix("."), !parts.contains("__MACOSX") else { return nil }
        return parts.joined(separator: " \u{2215} ")
    }

    // MARK: - libarchive

    private final class Library: @unchecked Sendable {

        static let ok: Int32 = 0
        static let eof: Int32 = 1
        static let warn: Int32 = -20
        /// `AE_IFREG`
        static let regularFile: UInt16 = 0o100000

        static let shared = Library()

        let readNew: @convention(c) () -> OpaquePointer?
        let supportFilterAll: @convention(c) (OpaquePointer) -> Int32
        let supportFormatAll: @convention(c) (OpaquePointer) -> Int32
        let openFilename: @convention(c) (OpaquePointer, UnsafePointer<CChar>, Int) -> Int32
        let nextHeader: @convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32
        let pathname: @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
        let fileType: @convention(c) (OpaquePointer) -> UInt16
        let readData: @convention(c) (OpaquePointer, UnsafeMutableRawPointer?, Int) -> Int
        let dataSkip: @convention(c) (OpaquePointer) -> Int32
        let errorString: @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
        let readFree: @convention(c) (OpaquePointer) -> Int32

        private init?() {
            guard let handle = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW) else { return nil }
            func symbol<T>(_ name: String, as _: T.Type) -> T? {
                dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
            }
            guard let readNew = symbol("archive_read_new", as: (@convention(c) () -> OpaquePointer?).self),
                  let supportFilterAll = symbol("archive_read_support_filter_all", as: (@convention(c) (OpaquePointer) -> Int32).self),
                  let supportFormatAll = symbol("archive_read_support_format_all", as: (@convention(c) (OpaquePointer) -> Int32).self),
                  let openFilename = symbol("archive_read_open_filename", as: (@convention(c) (OpaquePointer, UnsafePointer<CChar>, Int) -> Int32).self),
                  let nextHeader = symbol("archive_read_next_header", as: (@convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32).self),
                  let pathname = symbol("archive_entry_pathname_utf8", as: (@convention(c) (OpaquePointer) -> UnsafePointer<CChar>?).self)
                  ?? symbol("archive_entry_pathname", as: (@convention(c) (OpaquePointer) -> UnsafePointer<CChar>?).self),
                  let fileType = symbol("archive_entry_filetype", as: (@convention(c) (OpaquePointer) -> UInt16).self),
                  let readData = symbol("archive_read_data", as: (@convention(c) (OpaquePointer, UnsafeMutableRawPointer?, Int) -> Int).self),
                  let dataSkip = symbol("archive_read_data_skip", as: (@convention(c) (OpaquePointer) -> Int32).self),
                  let errorString = symbol("archive_error_string", as: (@convention(c) (OpaquePointer) -> UnsafePointer<CChar>?).self),
                  let readFree = symbol("archive_read_free", as: (@convention(c) (OpaquePointer) -> Int32).self)
            else { return nil }
            self.readNew = readNew
            self.supportFilterAll = supportFilterAll
            self.supportFormatAll = supportFormatAll
            self.openFilename = openFilename
            self.nextHeader = nextHeader
            self.pathname = pathname
            self.fileType = fileType
            self.readData = readData
            self.dataSkip = dataSkip
            self.errorString = errorString
            self.readFree = readFree
        }

        func message(_ archive: OpaquePointer) -> String {
            errorString(archive).map { String(cString: $0) } ?? ""
        }
    }
}
