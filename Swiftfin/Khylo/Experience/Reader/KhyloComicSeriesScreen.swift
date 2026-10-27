//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import JellyfinAPI
import SwiftUI

/// A comic or manga series: the cover, where you are, and every issue in order.
struct KhyloComicSeriesScreen: View {

    let series: BaseItemDto

    @Router private var router
    @State private var issues: [BaseItemDto]?
    @State private var errorMessage: String?
    @State private var isOverviewExpanded = false

    private var coverURL: URL? {
        KhyloArtwork.url(for: series, style: .poster, width: 400)
            ?? issues?.first.flatMap { KhyloArtwork.url(for: $0, style: .poster, width: 400) }
    }

    /// The issue to open next: one you're partway through, else the first unread one.
    private var nextIssue: BaseItemDto? {
        guard let issues else { return nil }
        return issues.first { !$0.khyloIsPlayed && $0.id.flatMap(ReaderPosition.load) != nil }
            ?? issues.first { !$0.khyloIsPlayed }
            ?? issues.first
    }

    private var readCount: Int { issues?.filter(\.khyloIsPlayed).count ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                cover
                    .frame(width: 180, height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
                    .padding(.top, 80)

                VStack(spacing: 6) {
                    Text(series.name ?? "")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if let issues {
                        Text(summary(count: issues.count))
                            .font(.system(size: 14))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                }
                .padding(.horizontal, 30)

                if let next = nextIssue {
                    KhyloPlayButton(title: buttonTitle(for: next), systemImage: "book.fill") {
                        router.route(to: .khyloReader(next))
                    }
                    .padding(.horizontal, KhyloStyle.gutter)
                    .padding(.top, 4)
                }

                if let overview = series.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 15))
                        .foregroundColor(KhyloStyle.secondaryText)
                        .lineSpacing(3)
                        .lineLimit(isOverviewExpanded ? nil : 4)
                        .padding(.horizontal, KhyloStyle.gutter)
                        .onTapGesture { withAnimation { isOverviewExpanded.toggle() } }
                }

                issueList
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
        .background(background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Again on return from the reader, so read marks and the button stay current.
        .onAppear { Task { await load() } }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverURL {
            KhyloImage(url: coverURL, placeholderSymbol: "book.pages")
        } else {
            KhyloGeneratedCover(name: series.name ?? "", width: 180)
        }
    }

    private var background: some View {
        ZStack {
            KhyloStyle.canvas
            cover
                .frame(height: 460)
                .scaleEffect(1.6)
                .blur(radius: 80)
                .opacity(0.5)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var issueList: some View {
        if let issues {
            LazyVStack(spacing: 0) {
                ForEach(issues, id: \.id) { issue in
                    Button {
                        router.route(to: .khyloReader(issue))
                    } label: {
                        KhyloIssueRow(issue: issue)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            Task { await setRead(!issue.khyloIsPlayed, issue) }
                        } label: {
                            Label(issue.khyloIsPlayed ? "Mark as Unread" : "Mark as Read",
                                  systemImage: issue.khyloIsPlayed ? "circle" : "checkmark.circle")
                        }
                        Button {
                            router.route(to: .khyloItem(issue))
                        } label: {
                            Label("Details and Download", systemImage: "info.circle")
                        }
                    }
                    if issue.id != issues.last?.id {
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, KhyloStyle.gutter + 66)
                    }
                }
            }
        } else if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 15))
                .foregroundColor(KhyloStyle.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, KhyloStyle.gutter)
        } else {
            ProgressView().tint(.white).padding(.top, 20)
        }
    }

    private func summary(count: Int) -> String {
        let issuesText = count == 1 ? "1 issue" : "\(count) issues"
        guard readCount > 0 else { return issuesText }
        return readCount == count ? "\(issuesText) · All read" : "\(issuesText) · \(readCount) read"
    }

    private func buttonTitle(for issue: BaseItemDto) -> String {
        let label = KhyloIssueRow.label(for: issue)
        if issue.id.flatMap(ReaderPosition.load) != nil, !issue.khyloIsPlayed { return "Continue \(label)" }
        if readCount == 0 { return "Start Reading" }
        return "Read \(label)"
    }

    private func load() async {
        guard let id = series.id else { return }
        do {
            let found = try await KhyloAPI.items(parentID: id, sortBy: [.indexNumber, .sortName], limit: 2000).items
            // Issues only; a series can hold extra folders (volumes) too, shown in order.
            issues = found.filter { KhyloAPI.extendedKind(of: $0) == .comic || $0.type == .book }
        } catch {
            if issues == nil { errorMessage = "Couldn't load this series. Check your connection and try again." }
        }
    }

    private func setRead(_ read: Bool, _ issue: BaseItemDto) async {
        guard let id = issue.id, let data = try? await KhyloAPI.setPlayed(read, itemID: id) else { return }
        if let index = issues?.firstIndex(where: { $0.id == id }) {
            issues?[index].userData = data
        }
    }
}

/// One issue in a series: its cover, number and title, and whether it's read.
private struct KhyloIssueRow: View {

    let issue: BaseItemDto

    /// "Issue 12", or the title when the issue has no number.
    static func label(for issue: BaseItemDto) -> String {
        if let number = issue.indexNumber { return "Issue \(number)" }
        return issue.name ?? "Issue"
    }

    private var isStarted: Bool {
        !issue.khyloIsPlayed && issue.id.flatMap(ReaderPosition.load) != nil
    }

    var body: some View {
        HStack(spacing: 14) {
            KhyloImage(url: KhyloArtwork.url(for: issue, style: .poster, width: 120), placeholderSymbol: "book.pages")
                .frame(width: 52, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .opacity(issue.khyloIsPlayed ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.label(for: issue))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if issue.indexNumber != nil, let name = issue.name, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .lineLimit(1)
                }
                if isStarted {
                    Text("In progress")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KhyloStyle.accent)
                }
            }

            Spacer(minLength: 8)

            if issue.khyloIsPlayed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(KhyloStyle.accent)
            }
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
