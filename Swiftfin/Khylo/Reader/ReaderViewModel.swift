//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Foundation
import SwiftUI

// MARK: - Reading Theme

public enum ReadingTheme: String, CaseIterable, Identifiable {
    case night = "Night"
    case sepia = "Sepia"
    case paper = "Paper"

    public var id: String { rawValue }

    public var backgroundColor: Color {
        switch self {
        case .night: return Color(red: 18/255, green: 17/255, blue: 16/255) // #121110
        case .sepia: return Color(red: 241/255, green: 229/255, blue: 204/255) // #F1E5CC
        case .paper: return Color(red: 250/255, green: 248/255, blue: 243/255) // #FAF8F3
        }
    }

    public var textColor: Color {
        switch self {
        case .night: return Color(red: 224/255, green: 220/255, blue: 211/255) // #E0DCD3
        case .sepia: return Color(red: 60/255, green: 50/255, blue: 38/255) // #3C3226
        case .paper: return Color(red: 31/255, green: 30/255, blue: 29/255) // #1F1E1D
        }
    }

    public var secondaryTextColor: Color {
        switch self {
        case .night: return Color(red: 140/255, green: 135/255, blue: 125/255)
        case .sepia: return Color(red: 120/255, green: 105/255, blue: 85/255)
        case .paper: return Color(red: 110/255, green: 105/255, blue: 100/255)
        }
    }
}

// MARK: - Reading Font Size

public enum ReadingFontSize: CGFloat, CaseIterable, Identifiable {
    case s = 16.0
    case m = 18.0
    case l = 20.0
    case xl = 22.0
    case xxl = 26.0

    public var id: CGFloat { rawValue }

    public var label: String {
        switch self {
        case .s: return "S"
        case .m: return "M"
        case .l: return "L"
        case .xl: return "XL"
        case .xxl: return "XXL"
        }
    }

    public var pointSize: CGFloat { rawValue }
    public var lineSpacing: CGFloat {
        switch self {
        case .s: return 8.0
        case .m: return 10.0
        case .l: return 12.0
        case .xl: return 14.0
        case .xxl: return 16.0
        }
    }
}

// MARK: - Reader View Model

@MainActor
public final class ReaderViewModel: ObservableObject {

    public let bookId: String
    @Published public var book: EPUBBook
    @Published public var currentChapterIndex: Int = 0
    @Published public var currentParagraphIndex: Int = 0
    @Published public var theme: ReadingTheme = .night
    @Published public var fontSize: ReadingFontSize = .m
    @Published public var isSerif: Bool = true
    @Published public var showSettings: Bool = false
    @Published public var showTOC: Bool = false

    private let defaults = UserDefaults.standard

    public init(bookId: String, book: EPUBBook? = nil, initialTitle: String? = nil, author: String? = nil) {
        self.bookId = bookId
        if let book {
            self.book = book
        } else {
            self.book = EPUBParser.sampleBook(bookId: bookId, title: initialTitle ?? "Dune", author: author ?? "Frank Herbert")
        }

        // Restore progress
        let savedChapter = defaults.integer(forKey: "khylo_reader_chapter_\(bookId)")
        let savedParagraph = defaults.integer(forKey: "khylo_reader_paragraph_\(bookId)")
        self.currentChapterIndex = max(min(savedChapter, max(self.book.chapters.count - 1, 0)), 0)
        self.currentParagraphIndex = max(savedParagraph, 0)
    }

    public var currentChapter: EPUBChapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < book.chapters.count else { return nil }
        return book.chapters[currentChapterIndex]
    }

    public var totalChaptersCount: Int {
        book.chapters.count
    }

    public var overallProgressPercentage: Double {
        guard totalChaptersCount > 0 else { return 0 }
        let chapterFraction = Double(currentChapterIndex) / Double(totalChaptersCount)
        let paragraphFraction: Double
        if let chapter = currentChapter, chapter.paragraphs.count > 0 {
            paragraphFraction = (Double(currentParagraphIndex) / Double(chapter.paragraphs.count)) / Double(totalChaptersCount)
        } else {
            paragraphFraction = 0
        }
        return min(max((chapterFraction + paragraphFraction) * 100.0, 0.0), 100.0)
    }

    // MARK: - Chapter Navigation

    public func nextChapter() {
        if currentChapterIndex < book.chapters.count - 1 {
            currentChapterIndex += 1
            currentParagraphIndex = 0
            saveProgress()
        }
    }

    public func previousChapter() {
        if currentChapterIndex > 0 {
            currentChapterIndex -= 1
            currentParagraphIndex = 0
            saveProgress()
        }
    }

    public func jumpToChapter(index: Int) {
        guard index >= 0 && index < book.chapters.count else { return }
        currentChapterIndex = index
        currentParagraphIndex = 0
        saveProgress()
    }

    public func saveProgress() {
        defaults.set(currentChapterIndex, forKey: "khylo_reader_chapter_\(bookId)")
        defaults.set(currentParagraphIndex, forKey: "khylo_reader_paragraph_\(bookId)")
    }
}
