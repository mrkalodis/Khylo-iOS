//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - EPUB Reader View

public struct EPUBReaderView: View {
    @StateObject private var viewModel: ReaderViewModel
    public let onDismiss: () -> Void

    @State private var showChrome: Bool = true
    @State private var showTOCDrawer: Bool = false
    @State private var showSettingsSheet: Bool = false

    public init(
        bookId: String,
        title: String,
        author: String,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            bookId: bookId,
            initialTitle: title,
            author: author
        ))
        self.onDismiss = onDismiss
    }

    public init(
        item: KhyloMediaItem,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            bookId: item.id,
            initialTitle: item.name,
            author: item.overview ?? "Author"
        ))
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Theme Background
            viewModel.theme.backgroundColor
                .ignoresSafeArea()

            // Main Reader Content
            VStack(spacing: 0) {
                // Top Header Chrome
                if showChrome {
                    topChromeBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Chapter Reading Content
                chapterContentView

                // Bottom Progress Chrome
                if showChrome {
                    bottomChromeBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            ReaderSettingsBar(
                theme: $viewModel.theme,
                fontSize: $viewModel.fontSize,
                isSerif: $viewModel.isSerif,
                onDismiss: { showSettingsSheet = false }
            )
            .presentationDetents([.height(340)])
            .presentationBackground(viewModel.theme.backgroundColor)
        }
        .sheet(isPresented: $showTOCDrawer) {
            tableOfContentsDrawer
        }
    }

    // MARK: - Top Chrome Bar

    private var topChromeBar: some View {
        HStack(spacing: 16) {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                viewModel.saveProgress()
                onDismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(viewModel.theme.textColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.book.title)
                    .font(KhyloTypography.headline)
                    .foregroundColor(viewModel.theme.textColor)
                    .lineLimit(1)

                Text(viewModel.currentChapter?.title ?? "Chapter \(viewModel.currentChapterIndex + 1)")
                    .font(KhyloTypography.caption)
                    .foregroundColor(viewModel.theme.secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            // Table of Contents Button
            Button(action: {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                showTOCDrawer = true
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.theme.textColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())

            // Reader Settings Button
            Button(action: {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                showSettingsSheet = true
            }) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.theme.textColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(viewModel.theme.backgroundColor.opacity(0.95))
    }

    // MARK: - Chapter Content

    private var chapterContentView: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: viewModel.fontSize.lineSpacing * 1.5) {
                        // Chapter Header Title
                        if let chapter = viewModel.currentChapter {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("CHAPTER \(chapter.chapterIndex + 1)")
                                    .font(KhyloTypography.captionBold)
                                    .foregroundColor(KhyloColors.accent)

                                Text(chapter.title)
                                    .font(.system(size: viewModel.fontSize.pointSize * 1.4, weight: .bold, design: viewModel.isSerif ? .serif : .default))
                                    .foregroundColor(viewModel.theme.textColor)
                            }
                            .padding(.top, 24)
                            .padding(.bottom, 16)

                            // Paragraphs
                            ForEach(Array(chapter.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                Text(paragraph)
                                    .font(.system(size: viewModel.fontSize.pointSize, weight: .regular, design: viewModel.isSerif ? .serif : .default))
                                    .lineSpacing(viewModel.fontSize.lineSpacing)
                                    .foregroundColor(viewModel.theme.textColor)
                                    .id("para-\(index)")
                                    .padding(.bottom, 8)
                            }

                            // Chapter End Divider & Next Chapter Prompt
                            chapterEndSection
                        }
                    }
                    .padding(.horizontal, max(geometry.size.width * 0.08, 24))
                    .padding(.bottom, 60)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChrome.toggle()
                    }
                }
            }
        }
    }

    private var chapterEndSection: some View {
        VStack(spacing: 16) {
            Divider()
                .background(viewModel.theme.secondaryTextColor.opacity(0.3))
                .padding(.vertical, 24)

            if viewModel.currentChapterIndex < viewModel.totalChaptersCount - 1 {
                Button(action: {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    withAnimation {
                        viewModel.nextChapter()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Next Chapter")
                            .font(KhyloTypography.headline)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(KhyloColors.accent)
                    .cornerRadius(KhyloRadius.sm)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text("End of Book")
                    .font(KhyloTypography.headline)
                    .foregroundColor(viewModel.theme.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - Bottom Chrome Bar

    private var bottomChromeBar: some View {
        VStack(spacing: 8) {
            // Chapter Scrubber / Progress
            HStack(spacing: 16) {
                Button(action: {
                    withAnimation { viewModel.previousChapter() }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(viewModel.currentChapterIndex > 0 ? viewModel.theme.textColor : viewModel.theme.secondaryTextColor.opacity(0.4))
                }
                .disabled(viewModel.currentChapterIndex == 0)

                // Chapter Indicator
                Text("Chapter \(viewModel.currentChapterIndex + 1) of \(viewModel.totalChaptersCount)")
                    .font(KhyloTypography.captionMedium)
                    .foregroundColor(viewModel.theme.secondaryTextColor)

                Spacer()

                // Total Book Completion Percentage
                Text("\(Int(viewModel.overallProgressPercentage))% completed")
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.accent)

                Button(action: {
                    withAnimation { viewModel.nextChapter() }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(viewModel.currentChapterIndex < viewModel.totalChaptersCount - 1 ? viewModel.theme.textColor : viewModel.theme.secondaryTextColor.opacity(0.4))
                }
                .disabled(viewModel.currentChapterIndex >= viewModel.totalChaptersCount - 1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(viewModel.theme.backgroundColor.opacity(0.95))
        }
    }

    // MARK: - Table of Contents Drawer

    private var tableOfContentsDrawer: some View {
        NavigationStack {
            ZStack {
                viewModel.theme.backgroundColor
                    .ignoresSafeArea()

                List {
                    ForEach(viewModel.book.chapters) { chapter in
                        TOCChapterRow(
                            chapter: chapter,
                            isCurrent: chapter.chapterIndex == viewModel.currentChapterIndex,
                            theme: viewModel.theme,
                            onSelect: {
                                viewModel.jumpToChapter(index: chapter.chapterIndex)
                                showTOCDrawer = false
                            }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showTOCDrawer = false
                    }
                    .foregroundColor(KhyloColors.accent)
                }
            }
        }
    }
}

// MARK: - TOC Chapter Row

private struct TOCChapterRow: View {
    let chapter: EPUBChapter
    let isCurrent: Bool
    let theme: ReadingTheme
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text("\(chapter.chapterIndex + 1).")
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(isCurrent ? KhyloColors.accent : theme.secondaryTextColor)
                    .frame(width: 30, alignment: .leading)

                Text(chapter.title)
                    .font(isCurrent ? KhyloTypography.headline : KhyloTypography.body)
                    .foregroundColor(isCurrent ? KhyloColors.accent : theme.textColor)

                Spacer()

                Text("\(chapter.wordCount) words")
                    .font(KhyloTypography.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
        .listRowBackground(isCurrent ? theme.textColor.opacity(0.08) : Color.clear)
    }
}
