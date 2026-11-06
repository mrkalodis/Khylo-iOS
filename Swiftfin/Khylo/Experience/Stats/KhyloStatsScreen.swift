//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//


import JellyfinAPI
import SwiftUI

// MARK: - Stats

/// The person's own listening: this week, each quarter, the year, and a history.
/// Everything shown comes from what the server recorded; nothing is invented.
struct KhyloStatsScreen: View {

    enum Section: String, CaseIterable {
        case week = "Week"
        case quarters = "Quarters"
        case year = "Year"
        case history = "History"
    }

    var header: AnyView?

    @State private var section: Section = .week
    @State private var isShowingPrivacy = false
    @State private var tint: Color?

    var body: some View {
        ZStack {
            KhyloStatsBackdrop(tint: tint)
                .overlay(
                    LinearGradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
                .animation(.easeInOut(duration: 1.0), value: tint)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let header {
                        header
                    } else {
                        HStack {
                            Text("Stats")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            privacyButton
                        }
                        .padding(.horizontal, KhyloStyle.gutter)
                        .padding(.top, 8)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        KhyloSegmentTabs(tabs: Section.allCases.map { ($0, $0.rawValue) }, selection: $section)
                    }
                    .scrollClipDisabled()
                    .padding(.horizontal, KhyloStyle.gutter)

                    switch section {
                    case .week: KhyloWeekStats(tint: $tint)
                    case .quarters: KhyloQuarterList()
                    case .year: KhyloYearStats()
                    case .history: KhyloStatsHistory()
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingPrivacy) { KhyloStatsPrivacySheet() }
    }

    private var privacyButton: some View {
        Button {
            isShowingPrivacy = true
        } label: {
            Image(systemName: "lock.shield")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .accessibilityLabel("Privacy")
    }
}

// MARK: - Shared pieces

private struct KhyloStatCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .textCase(.uppercase)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.01)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .padding(.horizontal, KhyloStyle.gutter)
        .khyloReveal()
    }
}

private struct KhyloStatMessage: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(KhyloStyle.tertiaryText)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(KhyloStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 50)
    }
}

/// A loading page that shows the result, an error with retry, or nothing yet.
private struct KhyloLoaded<Value, Content: View>: View {
    let load: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var value: Value?
    @State private var failed = false

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if failed {
                VStack(spacing: 14) {
                    KhyloStatMessage(symbol: "wifi.exclamationmark", title: "Couldn't load this", text: "Check your connection and that your server is up to date.")
                    Button("Try Again") { Task { await run() } }
                        .foregroundColor(KhyloStyle.accent)
                }
            } else {
                ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
        .task { await run() }
    }

    private func run() async {
        failed = false
        do {
            value = try await load()
        } catch {
            failed = true
        }
    }
}

struct KhyloBars: View {
    let values: [Double]
    let labels: [String]
    var highlight: Int?
    var height: CGFloat = 90
    var onDark = false

    @State private var grown = false

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: values.count > 14 ? 3 : 8) {
            ForEach(values.indices, id: \.self) { index in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            onDark
                                ? AnyShapeStyle(index == highlight ? Color.white : Color.white.opacity(0.4))
                                : AnyShapeStyle(LinearGradient(
                                    colors: [index == highlight ? KhyloStyle.accent : KhyloStyle.accent.opacity(0.55), KhyloStyle.accent.opacity(index == highlight ? 0.7 : 0.25)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                        )
                        .frame(height: max(4, height * CGFloat(values[index] / peak) * (grown ? 1 : 0.02)))
                        .frame(maxHeight: height, alignment: .bottom)
                        .animation(.spring(response: 0.8, dampingFraction: 0.78).delay(Double(index) * 0.04), value: grown)
                    if labels.indices.contains(index) {
                        Text(labels[index])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(onDark ? .white.opacity(0.7) : KhyloStyle.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { grown = true }
    }
}

private func artistStub(_ artist: KhyloStatArtist) -> BaseItemDto {
    BaseItemDto(id: artist.artistId, name: artist.name)
}

private struct KhyloArtistList: View {
    let artists: [KhyloStatArtist]
    var limit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(artists.prefix(limit).enumerated()), id: \.element.id) { index, artist in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .frame(width: 18)
                    KhyloArtistAvatar(artist: artistStub(artist), size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name ?? "")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(KhyloStatsAPI.duration(artist.seconds))
                            .font(.system(size: 13))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    Spacer()
                }
            }
        }
    }
}

private struct KhyloSongList: View {
    let songs: [KhyloStatSong]
    var limit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(songs.prefix(limit).enumerated()), id: \.element.id) { index, song in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .frame(width: 18)
                    KhyloImage(
                        url: statArtwork(song.itemId, width: 90),
                        placeholderSymbol: "music.note"
                    )
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title ?? "")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(song.artist ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(KhyloStyle.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(song.plays ?? 0) play\(song.plays == 1 ? "" : "s")")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundColor(KhyloStyle.tertiaryText)
                }
            }
        }
    }
}

private struct KhyloAlbumRow: View {
    let albums: [KhyloStatAlbum]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(albums) { album in
                    VStack(alignment: .leading, spacing: 6) {
                        KhyloImage(
                            url: statArtwork(album.albumId, width: 220),
                            placeholderSymbol: "music.note"
                        )
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(album.name ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)
                        Text(KhyloStatsAPI.duration(album.seconds))
                            .font(.system(size: 12))
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct KhyloGenreChips: View {
    let genres: [KhyloStatGenre]

    var body: some View {
        let total = max(genres.reduce(0) { $0 + ($1.seconds ?? 0) }, 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(genres) { genre in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(genre.name ?? "")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(((genre.seconds ?? 0) / total * 100).rounded()))%")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundColor(KhyloStyle.tertiaryText)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Color.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(KhyloStyle.accent)
                                    .frame(width: proxy.size.width * CGFloat((genre.seconds ?? 0) / total))
                            }
                    }
                    .frame(height: 5)
                }
            }
        }
    }
}

private func bigNumber(_ value: String, _ caption: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(value)
            .font(.system(size: 30, weight: .bold).monospacedDigit())
            .foregroundColor(.white)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        Text(caption)
            .font(.system(size: 13))
            .foregroundColor(KhyloStyle.tertiaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Week

private struct KhyloWeekStats: View {

    @Binding var tint: Color?
    @State private var weekStart = KhyloWeekStats.monday(of: Date())

    private static func monday(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    private var weekEnd: Date { calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart }
    private var isThisWeek: Bool { weekStart >= Self.monday(of: Date()) }

    private var rangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return isThisWeek ? "This week" : "\(formatter.string(from: weekStart)) – \(formatter.string(from: weekEnd))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.left").frame(width: 38, height: 38)
                }
                Spacer()
                Text(rangeText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.right").frame(width: 38, height: 38)
                }
                .disabled(isThisWeek)
                .opacity(isThisWeek ? 0.3 : 1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, KhyloStyle.gutter - 8)

            KhyloLoaded(load: {
                try await KhyloStatsAPI.summary(from: KhyloStatsAPI.dayString(weekStart), to: KhyloStatsAPI.dayString(weekEnd))
            }) { summary in
                KhyloSummaryBody(summary: summary)
                    .task {
                        let id = summary.topAlbums?.first?.albumId ?? summary.topArtists?.first?.artistId
                        tint = await KhyloArtColor.color(for: statArtwork(id, width: 120))
                    }
            }
            .id(weekStart)
        }
    }
}

private struct KhyloSummaryBody: View {
    let summary: KhyloStatSummary

    private var isEmpty: Bool { (summary.totalSeconds ?? 0) == 0 && (summary.plays ?? 0) == 0 }

    private var change: String? {
        guard let before = summary.previous?.totalSeconds, before > 0, let now = summary.totalSeconds else { return nil }
        let percent = Int(((now - before) / before * 100).rounded())
        if percent == 0 { return "Same as the week before" }
        return percent > 0 ? "Up \(percent)% on the week before" : "Down \(-percent)% on the week before"
    }

    var body: some View {
        if isEmpty {
            KhyloStatMessage(symbol: "waveform", title: "Nothing played this week", text: "Songs you listen to are added here as you play them.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        KhyloCountUp(target: (summary.totalSeconds ?? 0) / 60, duration: 1.5) { value in
                            let minutes = Int(value)
                            return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
                        }
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    }
                    Text("of music · \(summary.plays ?? 0) plays · \(summary.distinctSongs ?? 0) songs · \(summary.distinctArtists ?? 0) artists")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                    if let change {
                        Text(change)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(KhyloStyle.accent)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KhyloStyle.gutter)
                .khyloReveal()

                if let top = summary.topArtists?.first {
                    KhyloStatCard("Top artist this week") {
                        HStack(spacing: 16) {
                            KhyloArtistAvatar(artist: artistStub(top), size: 92)
                                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(top.name ?? "")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                Text("\(KhyloStatsAPI.duration(top.seconds)) · \(top.plays ?? 0) plays")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                }

                if let days = summary.days, !days.isEmpty {
                    KhyloStatCard("Each day") {
                        KhyloBars(
                            values: days.map { $0.seconds ?? 0 },
                            labels: days.map { Self.weekdayLetter($0.date) },
                            highlight: days.indices.max { (days[$0].seconds ?? 0) < (days[$1].seconds ?? 0) }
                        )
                        if let busiest = summary.busiestDay, let date = KhyloStatsAPI.day(busiest.date) {
                            Text("Busiest day: \(date.formatted(.dateTime.weekday(.wide))), \(KhyloStatsAPI.duration(busiest.seconds))")
                                .font(.system(size: 13))
                                .foregroundColor(KhyloStyle.secondaryText)
                        }
                    }
                }

                if let artists = summary.topArtists, !artists.isEmpty {
                    KhyloStatCard("Top artists") { KhyloArtistList(artists: artists) }
                }
                if let songs = summary.topSongs, !songs.isEmpty {
                    KhyloStatCard("Top songs") { KhyloSongList(songs: songs) }
                }
                if let albums = summary.topAlbums, !albums.isEmpty {
                    KhyloStatCard("Top albums") { KhyloAlbumRow(albums: albums) }
                }
                if let genres = summary.topGenres, !genres.isEmpty {
                    KhyloStatCard("Genres") { KhyloGenreChips(genres: genres) }
                }
                if let fresh = summary.newArtists, !fresh.isEmpty {
                    KhyloStatCard("New to you") {
                        Text(fresh.prefix(8).compactMap(\.name).joined(separator: ", "))
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private static func weekdayLetter(_ date: String) -> String {
        guard let day = KhyloStatsAPI.day(date) else { return "" }
        return String(day.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
    }
}

// MARK: - Quarters and year

/// Something to show as a story, with the means to show its full breakdown too.
private struct KhyloStoryItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let review: KhyloStatReview
    let comparesToLast: Bool
    let load: () async throws -> KhyloStatReview
}

private struct KhyloQuarterList: View {

    @State private var story: KhyloStoryItem?
    @State private var breakdown: KhyloStoryItem?
    @State private var opening: String?
    @State private var message: String?

    var body: some View {
        KhyloLoaded(load: { try await KhyloStatsAPI.quarters() }) { quarters in
            if quarters.isEmpty {
                KhyloStatMessage(symbol: "calendar", title: "No quarters yet", text: "Your first quarterly review appears once you've listened to something.")
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(quarters.enumerated()), id: \.element.id) { index, quarter in
                        Button {
                            open(quarter)
                        } label: {
                            KhyloQuarterRow(quarter: quarter, isOpening: opening == quarter.id)
                        }
                        .buttonStyle(KhyloScaleButtonStyle())
                        .khyloReveal(delay: Double(index) * 0.08)
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundColor(KhyloStyle.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, KhyloStyle.gutter)
            }
        }
        .fullScreenCover(item: $story) { item in
            KhyloStoryView(title: item.title, subtitle: item.subtitle, review: item.review, comparesToLast: item.comparesToLast) {
                story = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    breakdown = item
                }
            }
        }
        .sheet(item: $breakdown) { item in
            NavigationStack {
                KhyloReviewScreen(title: item.title, subtitle: item.subtitle, load: item.load, showsComparison: item.comparesToLast)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { breakdown = nil } } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func open(_ quarter: KhyloStatQuarter) {
        message = nil
        opening = quarter.id
        Task {
            defer { opening = nil }
            let load = { try await KhyloStatsAPI.quarter(year: quarter.year, quarter: quarter.quarter) }
            guard let review = try? await load() else {
                message = "That review couldn't be loaded. Check your connection."
                return
            }
            if review.available == false {
                let day = KhyloStatsAPI.day(review.availableFrom ?? quarter.availableFrom)
                message = day.map { "\(quarter.title) opens on \($0.formatted(.dateTime.weekday(.wide).month(.wide).day()))." } ?? "This review isn't open yet."
                return
            }
            story = KhyloStoryItem(title: quarter.title, subtitle: quarter.months, review: review, comparesToLast: true, load: load)
        }
    }
}

private struct KhyloQuarterRow: View {
    let quarter: KhyloStatQuarter
    var isOpening = false

    private var isOpen: Bool { quarter.available == true || KhyloStatsAPI.opensReviewsEarly }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(quarter.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(quarter.months)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            if isOpening {
                ProgressView().tint(.white)
            } else if isOpen {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, Color.white.opacity(0.2))
            } else if let opens = KhyloStatsAPI.day(quarter.availableFrom) {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "lock.fill").foregroundColor(.white.opacity(0.6))
                    Text("Opens \(opens.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [KhyloStyle.accent.opacity(isOpen ? 0.45 : 0.12), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct KhyloYearStats: View {

    @State private var story: KhyloStoryItem?
    @State private var breakdown: KhyloStoryItem?

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        KhyloLoaded(load: { try await KhyloStatsAPI.wrapped(year: year) }) { review in
            if review.available == false {
                KhyloStatMessage(
                    symbol: "gift",
                    title: "Your \(year) Wrapped",
                    text: opensText(review.availableFrom)
                )
            } else {
                Button {
                    story = KhyloStoryItem(
                        title: "Your \(year) Wrapped",
                        subtitle: "Your year in music",
                        review: review,
                        comparesToLast: false,
                        load: { try await KhyloStatsAPI.wrapped(year: year) }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Spacer(minLength: 90)
                        Text("WRAPPED \(String(year))")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(1.8)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Your year\nin music")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("\(KhyloStatsAPI.duration(review.totalSeconds)) · tap to play")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(
                        ZStack {
                            KhyloAuroraBackground(tint: KhyloStyle.accent, isPlaying: true)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: KhyloStyle.accent.opacity(0.35), radius: 30, y: 14)
                    .padding(.horizontal, KhyloStyle.gutter)
                    .khyloReveal()
                }
                .buttonStyle(KhyloScaleButtonStyle())
            }
        }
        .fullScreenCover(item: $story) { item in
            KhyloStoryView(title: item.title, subtitle: item.subtitle, review: item.review) {
                story = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    breakdown = item
                }
            }
        }
        .sheet(item: $breakdown) { item in
            NavigationStack {
                KhyloReviewScreen(title: item.title, subtitle: item.subtitle, load: item.load, showsComparison: false)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { breakdown = nil } } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func opensText(_ date: String?) -> String {
        guard let day = KhyloStatsAPI.day(date) else { return "It opens on the Monday after Black Friday." }
        return "It opens on \(day.formatted(.dateTime.weekday(.wide).month(.wide).day())). It covers this year's listening since Khylo began keeping it."
    }
}

// MARK: - A full review

struct KhyloReviewScreen: View {

    let title: String
    let subtitle: String
    let load: () async throws -> KhyloStatReview
    let showsComparison: Bool

    var body: some View {
        ZStack {
            KhyloStyle.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundColor(KhyloStyle.secondaryText)
                    }
                    .padding(.horizontal, KhyloStyle.gutter)

                    KhyloLoaded(load: load) { review in
                        if review.available == false {
                            KhyloStatMessage(symbol: "lock", title: "Not open yet", text: opensText(review.availableFrom))
                        } else {
                            KhyloReviewBody(review: review, showsComparison: showsComparison)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func opensText(_ date: String?) -> String {
        guard let day = KhyloStatsAPI.day(date) else { return "This review opens soon." }
        return "It opens on \(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))."
    }
}

private struct KhyloReviewBody: View {
    let review: KhyloStatReview
    let showsComparison: Bool

    private static let monthNames = Calendar.current.shortMonthSymbols

    var body: some View {
        if (review.totalSeconds ?? 0) == 0 {
            KhyloStatMessage(symbol: "waveform", title: "No listening in this period", text: "There's nothing recorded for these dates.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                KhyloStatCard {
                    bigNumber(KhyloStatsAPI.duration(review.totalSeconds), "of music")
                    HStack(alignment: .top, spacing: 16) {
                        bigNumber("\(review.plays ?? 0)", "plays")
                        bigNumber("\(review.distinctSongs ?? 0)", "different songs")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        bigNumber("\(review.distinctArtists ?? 0)", "artists")
                        bigNumber("\(review.distinctAlbums ?? 0)", "albums")
                    }
                }

                if showsComparison, let previous = review.previous?.value, let before = previous.totalSeconds, before > 0,
                   let percent = review.changePercent?.value
                {
                    KhyloStatCard("Compared with last quarter") {
                        Text(percent >= 0 ? "Up \(Int(percent.rounded()))%" : "Down \(Int((-percent).rounded()))%")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(percent >= 0 ? KhyloStyle.accent : .white)
                        Text("Last quarter: \(KhyloStatsAPI.duration(before))")
                            .font(.system(size: 14))
                            .foregroundColor(KhyloStyle.secondaryText)
                        if review.topChanged?.value == true {
                            Text("You have a new number one artist.")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        if let climbers = review.climbers?.value, !climbers.isEmpty {
                            Text("Climbing: " + climbers.prefix(3).compactMap(\.name).joined(separator: ", "))
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }
                }

                if let top = review.topArtist {
                    KhyloStatCard("Your top artist") {
                        HStack(spacing: 16) {
                            KhyloArtistAvatar(artist: artistStub(top), size: 84)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(top.name ?? "")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                Text("\(KhyloStatsAPI.duration(top.seconds)) · \(top.plays ?? 0) plays")
                                    .font(.system(size: 14))
                                    .foregroundColor(KhyloStyle.secondaryText)
                            }
                        }
                    }
                }

                if let artists = review.topArtists, artists.count > 1 {
                    KhyloStatCard("Top artists") { KhyloArtistList(artists: artists, limit: 10) }
                }
                if let songs = review.topSongs, !songs.isEmpty {
                    KhyloStatCard("Top songs") { KhyloSongList(songs: songs, limit: 10) }
                }
                if let albums = review.topAlbums, !albums.isEmpty {
                    KhyloStatCard("Top albums") { KhyloAlbumRow(albums: albums) }
                }
                if let genres = review.topGenres, !genres.isEmpty {
                    KhyloStatCard("Genres") { KhyloGenreChips(genres: genres) }
                }

                if let months = review.byMonth, months.count > 1 {
                    KhyloStatCard("Month by month") {
                        KhyloBars(
                            values: months.map { $0.seconds ?? 0 },
                            labels: months.map { Self.monthNames[max(0, min(11, $0.month - 1))] }
                        )
                    }
                }

                KhyloStatCard("Your habits") {
                    if let streak = review.longestStreakDays, streak > 0 {
                        Text("Longest streak: \(streak) day\(streak == 1 ? "" : "s") in a row")
                            .font(.system(size: 15)).foregroundColor(.white)
                    }
                    if let busiest = review.busiestDay, let date = KhyloStatsAPI.day(busiest.date) {
                        Text("Busiest day: \(date.formatted(.dateTime.month(.wide).day())), \(KhyloStatsAPI.duration(busiest.seconds))")
                            .font(.system(size: 15)).foregroundColor(.white)
                    }
                    if let time = review.timeOfDay, !time.isEmpty {
                        Text("You listen most in the \(time).")
                            .font(.system(size: 15)).foregroundColor(.white)
                    }
                    if let fresh = review.newArtists?.value, fresh > 0 {
                        Text("\(fresh) artist\(fresh == 1 ? "" : "s") new to you")
                            .font(.system(size: 15)).foregroundColor(.white)
                    }
                    if let first = review.firstSong?.value, let title = first.title {
                        Text("First song: \(title)\(first.artist.map { " · \($0)" } ?? "")")
                            .font(.system(size: 14)).foregroundColor(KhyloStyle.secondaryText)
                    }
                    if let last = review.lastSong?.value, let title = last.title {
                        Text("Latest song: \(title)\(last.artist.map { " · \($0)" } ?? "")")
                            .font(.system(size: 14)).foregroundColor(KhyloStyle.secondaryText)
                    }
                }

                if let hours = review.byHour, hours.count == 24 {
                    KhyloStatCard("Time of day") {
                        KhyloBars(values: hours.map { $0.seconds ?? 0 }, labels: hours.map { $0.hour % 6 == 0 ? "\($0.hour)" : "" }, height: 70)
                    }
                }
            }
        }
    }
}

// MARK: - History

private struct KhyloStatsHistory: View {

    @State private var rows: [KhyloStatHistoryRow] = []
    @State private var next: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var failed = false

    private var days: [(Date, [KhyloStatHistoryRow])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date ?? .distantPast) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.top, 60)
            } else if failed && rows.isEmpty {
                KhyloStatMessage(symbol: "wifi.exclamationmark", title: "Couldn't load your history", text: "Check your connection and that your server is up to date.")
            } else if rows.isEmpty {
                KhyloStatMessage(symbol: "clock", title: "No history yet", text: "Songs you play are added here, newest first.")
            } else {
                ForEach(days, id: \.0) { day, dayRows in
                    Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(KhyloStyle.tertiaryText)
                        .textCase(.uppercase)
                        .padding(.horizontal, KhyloStyle.gutter)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    ForEach(dayRows) { row in
                        historyRow(row)
                            .task { await loadMore(after: row) }
                    }
                }
            }
        }
        .task { await loadFirst() }
    }

    private func historyRow(_ row: KhyloStatHistoryRow) -> some View {
        HStack(spacing: 12) {
            KhyloImage(
                url: statArtwork(row.albumId, width: 90) ?? statArtwork(row.itemId, width: 90),
                placeholderSymbol: "music.note"
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title ?? "")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(row.artistLine)
                    .font(.system(size: 13))
                    .foregroundColor(KhyloStyle.tertiaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(row.date?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(KhyloStyle.tertiaryText)
        }
        .padding(.horizontal, KhyloStyle.gutter)
        .padding(.vertical, 6)
    }

    private func loadFirst() async {
        do {
            let page = try await KhyloStatsAPI.history(before: nil)
            rows = page.items ?? []
            next = page.next
        } catch {
            failed = true
        }
        isLoading = false
    }

    private func loadMore(after row: KhyloStatHistoryRow) async {
        guard !isLoadingMore, let next, rows.last?.id == row.id else { return }
        isLoadingMore = true
        if let page = try? await KhyloStatsAPI.history(before: next) {
            let known = Set(rows.map(\.id))
            rows += (page.items ?? []).filter { !known.contains($0.id) }
            self.next = page.next
        }
        isLoadingMore = false
    }
}

// MARK: - Privacy

struct KhyloStatsPrivacySheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = true
    @State private var isLoaded = false
    @State private var isConfirmingDelete = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Record My Listening", isOn: Binding(
                        get: { isRecording },
                        set: { newValue in
                            isRecording = newValue
                            Task {
                                do { try await KhyloStatsAPI.setRecording(newValue) } catch {
                                    isRecording = !newValue
                                    message = "That didn't save. Check your connection."
                                }
                            }
                        }
                    ))
                    .tint(KhyloStyle.accent)
                    .disabled(!isLoaded)
                } footer: {
                    Text("Khylo keeps a private history of what you play, for your weekly stats, quarterly reviews and yearly Wrapped. When this is off, nothing is recorded, and what was already kept stays until you delete it.")
                }

                Section {
                    Button("Delete All My History", role: .destructive) { isConfirmingDelete = true }
                } footer: {
                    Text("The person who runs this server can see what is played and watched, but not your weekly, quarterly or yearly reviews.")
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KhyloStyle.canvas)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Delete everything Khylo has kept about what you played?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete All My History", role: .destructive) {
                    Task {
                        do {
                            try await KhyloStatsAPI.deleteAll()
                            message = "Your history was deleted."
                        } catch {
                            message = "That didn't work. Check your connection."
                        }
                    }
                }
            } message: {
                Text("This can't be undone. Your stats and reviews start over.")
            }
            .task {
                if let value = try? await KhyloStatsAPI.isRecording() {
                    isRecording = value
                    isLoaded = true
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
