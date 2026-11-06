//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//


import JellyfinAPI
import SwiftUI

// MARK: - Motion building blocks

/// A number that counts up to its value when it appears.
struct KhyloCountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

/// Counts from zero to `target` once, when shown.
struct KhyloCountUp: View {
    let target: Double
    var duration: Double = 1.6
    var delay: Double = 0
    let format: (Double) -> String

    @State private var shown: Double = 0

    var body: some View {
        KhyloCountingText(value: shown, format: format)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) { shown = target }
            }
    }
}

private struct KhyloRevealModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .blur(radius: shown ? 0 : 6)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Fades and floats in when it first appears.
    func khyloReveal(delay: Double = 0) -> some View {
        modifier(KhyloRevealModifier(delay: delay))
    }
}

/// Slow, soft colour behind a page, taken from an album or artist.
struct KhyloStatsBackdrop: View {
    let tint: Color?
    var shift: Double = 0

    var body: some View {
        ZStack {
            Color(hex: "#08090A")
            KhyloAuroraBackground(tint: (tint ?? KhyloStyle.accent).khyloShifted(hue: shift, brightness: 1), isPlaying: true)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Story

/// A full-screen, tap-through review: one big idea per page, moving colour behind it.
struct KhyloStoryView: View {

    let title: String
    let subtitle: String
    let review: KhyloStatReview
    var comparesToLast = false
    var onFullBreakdown: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var tint: Color?
    @State private var progress: Double = 0
    @State private var isHolding = false

    private static let pageSeconds = 7.0

    private var pages: [Page] {
        var list: [Page] = [.intro, .time]
        if review.topArtist != nil || !(review.topArtists ?? []).isEmpty { list.append(.artist) }
        if !(review.topSongs ?? []).isEmpty { list.append(.songs) }
        if !(review.topAlbums ?? []).isEmpty { list.append(.albums) }
        if !(review.topGenres ?? []).isEmpty { list.append(.genres) }
        list.append(.habits)
        if (review.byMonth ?? []).count > 1 { list.append(.months) }
        if comparesToLast, review.changePercent?.value != nil { list.append(.compare) }
        list.append(.summary)
        return list
    }

    enum Page: Hashable {
        case intro, time, artist, songs, albums, genres, habits, months, compare, summary
    }

    var body: some View {
        let pages = pages
        ZStack {
            KhyloStatsBackdrop(tint: tint, shift: Double(page) * 0.07)
                .animation(.easeInOut(duration: 1.2), value: page)

            content(for: pages[min(page, pages.count - 1)])
                .id(page)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 70)
                .padding(.bottom, 30)

            // Tap the left or right side to go back or forward; hold to pause.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { go(-1, count: pages.count) }
                Color.clear.contentShape(Rectangle()).onTapGesture { go(1, count: pages.count) }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isHolding = true }
                    .onEnded { _ in isHolding = false }
            )

            VStack(spacing: 14) {
                HStack(spacing: 4) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule().fill(Color.white)
                                        .frame(width: proxy.size.width * (index < page ? 1 : (index == page ? progress : 0)))
                                }
                            }
                            .frame(height: 3)
                    }
                }
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(.dark)
        .task { await loadTint() }
        .task(id: page) { await run(count: pages.count) }
    }

    private func go(_ step: Int, count: Int) {
        let target = page + step
        guard target >= 0 else { progress = 0; return }
        guard target < count else { return }
        withAnimation(.easeInOut(duration: 0.45)) { page = target }
        progress = 0
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Fills the bar, then moves on; holding pauses it. The last page stays.
    private func run(count: Int) async {
        progress = 0
        guard page < count - 1 else { progress = 1; return }
        let step = 0.05
        while progress < 1 {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }
            if !isHolding { progress += step / Self.pageSeconds }
        }
        if !Task.isCancelled { go(1, count: count) }
    }

    private func loadTint() async {
        let id = review.topAlbums?.first?.albumId ?? review.topArtist?.artistId ?? review.topArtists?.first?.artistId
        guard let id, let url = KhyloArtwork.url(itemID: id, type: .primary, tag: nil, width: 120) else { return }
        tint = await KhyloArtColor.color(for: url)
    }

    // MARK: Pages

    @ViewBuilder
    private func content(for page: Page) -> some View {
        switch page {
        case .intro: introPage
        case .time: timePage
        case .artist: artistPage
        case .songs: songsPage
        case .albums: albumsPage
        case .genres: genresPage
        case .habits: habitsPage
        case .months: monthsPage
        case .compare: comparePage
        case .summary: summaryPage
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .heavy))
            .tracking(1.6)
            .foregroundColor(.white.opacity(0.7))
    }

    private var coverURLs: [URL] {
        let albums = (review.topAlbums ?? []).compactMap { statArtwork($0.albumId, width: 300) }
        let songs = (review.topSongs ?? []).compactMap { statArtwork($0.itemId, width: 300) }
        return albums + songs
    }

    private var introPage: some View {
        ZStack {
            KhyloCoverCollage(urls: coverURLs, opacity: 0.5)
                .ignoresSafeArea()
            LinearGradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                label(subtitle).khyloReveal(delay: 0.1)
                Text(title)
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.55)
                    .lineSpacing(-4)
                    .shadow(color: .black.opacity(0.4), radius: 20)
                    .khyloReveal(delay: 0.3)
                Text("Tap to begin")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.top, 8)
                    .khyloReveal(delay: 1.0)
                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
        }
    }

    private var timePage: some View {
        let minutes = (review.totalSeconds ?? 0) / 60
        let albumsWorth = max(1, Int((minutes / 45).rounded()))
        let fact: String = minutes >= 1440
            ? String(format: "That's %.1f days of non-stop music.", minutes / 1440)
            : "That's about \(albumsWorth) full album\(albumsWorth == 1 ? "" : "s") back to back."
        return VStack(alignment: .leading, spacing: 10) {
            Spacer()
            label("You listened for").khyloReveal(delay: 0.1)
            KhyloCountUp(target: minutes, duration: 2.2, delay: 0.3) { "\(Int($0).formatted())" }
                .font(.system(size: 104, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .shadow(color: .white.opacity(0.25), radius: 30)
            Text("minutes of music")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .khyloReveal(delay: 0.6)
            KhyloEqualiserStrip()
                .frame(height: 70)
                .padding(.vertical, 14)
                .khyloReveal(delay: 0.9)
            Text(fact)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .khyloReveal(delay: 1.2)
            HStack(spacing: 30) {
                stat("\(review.plays ?? 0)", "plays")
                stat("\(review.distinctSongs ?? 0)", "songs")
                stat("\(review.distinctArtists ?? 0)", "artists")
            }
            .padding(.top, 18)
            .khyloReveal(delay: 1.5)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(caption).font(.system(size: 13)).foregroundColor(.white.opacity(0.65))
        }
    }

    private var artistPage: some View {
        let top = review.topArtist ?? review.topArtists?.first
        return ZStack {
            if let top {
                KhyloArtistHero(artist: BaseItemDto(id: top.artistId, name: top.name))
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                label("Your top artist").khyloReveal(delay: 0.2)
                if let top {
                    Text(top.name ?? "")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 18)
                        .khyloReveal(delay: 0.5)
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 0) {
                            KhyloCountUp(target: (top.seconds ?? 0) / 60, duration: 1.8, delay: 0.8) { "\(Int($0).formatted())" }
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("minutes together").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            KhyloCountUp(target: Double(top.plays ?? 0), duration: 1.8, delay: 0.8) { "\(Int($0))" }
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("plays").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.top, 6)
                    .khyloReveal(delay: 0.8)
                }
                Spacer().frame(height: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
        }
    }

    private var songsPage: some View {
        let songs = Array((review.topSongs ?? []).prefix(5))
        return VStack(alignment: .leading, spacing: 16) {
            Spacer()
            label("Your top songs").khyloReveal(delay: 0.1)
            if let first = songs.first {
                HStack(alignment: .bottom, spacing: 16) {
                    KhyloImage(url: statArtwork(first.itemId, width: 600), placeholderSymbol: "music.note")
                        .frame(width: 168, height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: (tint ?? .black).opacity(0.8), radius: 34, y: 14)
                        .overlay(alignment: .topLeading) {
                            Text("1")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.black)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.white))
                                .offset(x: -10, y: -10)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(first.title ?? "")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                        Text(first.artist ?? "")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                        Text("\(first.plays ?? 0) plays")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .khyloReveal(delay: 0.3)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(songs.enumerated().dropFirst()), id: \.element.id) { index, song in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(width: 30)
                        KhyloImage(url: statArtwork(song.itemId, width: 120), placeholderSymbol: "music.note")
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.title ?? "")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(song.artist ?? "") · \(song.plays ?? 0) plays")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .khyloReveal(delay: 0.7 + Double(index) * 0.16)
                }
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var albumsPage: some View {
        let albums = Array((review.topAlbums ?? []).prefix(3))
        return VStack(spacing: 26) {
            Spacer()
            label("Your top albums").khyloReveal(delay: 0.1)
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(albums.enumerated().reversed()), id: \.element.id) { index, album in
                        let side = CGFloat(index == 0 ? 0 : (index == 1 ? 1 : -1))
                        KhyloImage(url: statArtwork(album.albumId, width: 600), placeholderSymbol: "music.note")
                            .frame(width: index == 0 ? 236 : 190, height: index == 0 ? 236 : 190)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                            .rotation3DEffect(.degrees(Double(-side) * 26), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                            .offset(x: side * 112, y: CGFloat(sin(t * 0.8 + Double(index))) * 6 + (index == 0 ? 0 : 18))
                            .khyloReveal(delay: 0.3 + Double(index) * 0.2)
                    }
                }
            }
            .frame(height: 280)
            VStack(spacing: 4) {
                Text(albums.first?.name ?? "")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("\(albums.first?.artist ?? "") · \(KhyloStatsAPI.duration(albums.first?.seconds))")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 24)
            .khyloReveal(delay: 1.0)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var genresPage: some View {
        let genres = Array((review.topGenres ?? []).prefix(5))
        let total = max(genres.reduce(0) { $0 + ($1.seconds ?? 0) }, 1)
        return VStack(spacing: 26) {
            Spacer()
            label("What you listen to").khyloReveal(delay: 0.1)
            ZStack {
                KhyloDonut(shares: genres.map { ($0.name ?? "", $0.seconds ?? 0) })
                VStack(spacing: 2) {
                    Text(genres.first?.name ?? "")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("\(Int(((genres.first?.seconds ?? 0) / total * 100).rounded()))% of your time")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(width: 150)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                    HStack(spacing: 10) {
                        Circle().fill(Color.white.opacity(1 - Double(index) * 0.17)).frame(width: 10, height: 10)
                        Text(genre.name ?? "").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        Spacer()
                        Text("\(Int(((genre.seconds ?? 0) / total * 100).rounded()))%")
                            .font(.system(size: 14).monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .khyloReveal(delay: 0.6 + Double(index) * 0.1)
                }
            }
            .padding(.horizontal, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var habitsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            label("Your habits").khyloReveal(delay: 0.1)
            if let time = review.timeOfDay, !time.isEmpty {
                Text("You're a\(["a", "e", "i", "o", "u"].contains(String(time.prefix(1))) ? "n" : "") \(time) listener.")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .khyloReveal(delay: 0.3)
            }
            if let hours = review.byHour, hours.count == 24 {
                KhyloHourClock(hours: hours)
                    .frame(maxWidth: .infinity)
                    .khyloReveal(delay: 0.5)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let streak = review.longestStreakDays, streak > 0 {
                    habit("flame.fill", "\(streak) day\(streak == 1 ? "" : "s")", "longest streak in a row", delay: 1.0)
                }
                if let busiest = review.busiestDay, let date = KhyloStatsAPI.day(busiest.date) {
                    habit("calendar", date.formatted(.dateTime.month(.wide).day()), "your busiest day · \(KhyloStatsAPI.duration(busiest.seconds))", delay: 1.2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func habit(_ symbol: String, _ title: String, _ caption: String, delay: Double) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text(caption).font(.system(size: 14)).foregroundColor(.white.opacity(0.7))
            }
        }
        .khyloReveal(delay: delay)
    }

    private var monthsPage: some View {
        let months = review.byMonth ?? []
        let names = Calendar.current.shortMonthSymbols
        return VStack(alignment: .leading, spacing: 20) {
            Spacer()
            label("Month by month").khyloReveal(delay: 0.1)
            if let peak = months.max(by: { ($0.seconds ?? 0) < ($1.seconds ?? 0) }) {
                Text("\(names[max(0, min(11, peak.month - 1))]) was your month.")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .khyloReveal(delay: 0.3)
            }
            KhyloBars(
                values: months.map { $0.seconds ?? 0 },
                labels: months.map { names[max(0, min(11, $0.month - 1))] },
                highlight: months.indices.max { (months[$0].seconds ?? 0) < (months[$1].seconds ?? 0) },
                height: 190,
                onDark: true
            )
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var comparePage: some View {
        let percent = review.changePercent?.value ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            Spacer()
            label("Compared with last quarter").khyloReveal(delay: 0.1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 44, weight: .black))
                KhyloCountUp(target: abs(percent), duration: 1.4, delay: 0.3) { "\(Int($0))%" }
                    .font(.system(size: 88, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
            Text(percent >= 0 ? "more listening than the quarter before." : "less listening than the quarter before.")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .khyloReveal(delay: 0.7)
            if review.topChanged?.value == true {
                Text("There's a new number one artist.")
                    .font(.system(size: 17)).foregroundColor(.white.opacity(0.8)).khyloReveal(delay: 1.0)
            }
            if let climbers = review.climbers?.value, !climbers.isEmpty {
                Text("Climbing: " + climbers.prefix(3).compactMap(\.name).joined(separator: ", "))
                    .font(.system(size: 17)).foregroundColor(.white.opacity(0.8)).khyloReveal(delay: 1.2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }

    private var summaryPage: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TOP ARTISTS").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundColor(.white.opacity(0.6))
                        ForEach(Array((review.topArtists ?? []).prefix(5).enumerated()), id: \.element.id) { index, artist in
                            Text("\(index + 1)  \(artist.name ?? "")")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TOP SONGS").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundColor(.white.opacity(0.6))
                        ForEach(Array((review.topSongs ?? []).prefix(5).enumerated()), id: \.element.id) { index, song in
                            Text("\(index + 1)  \(song.title ?? "")")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 24) {
                    stat(KhyloStatsAPI.duration(review.totalSeconds), "listened")
                    stat("\(review.plays ?? 0)", "plays")
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 24)
            .khyloReveal(delay: 0.2)

            if let onFullBreakdown {
                Button {
                    onFullBreakdown()
                } label: {
                    Text("See the full breakdown")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 22)
                        .frame(height: 46)
                        .background(Capsule().fill(Color.white))
                }
                .khyloReveal(delay: 0.6)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Bars

/// A labelled bar that grows to its share when shown.
struct KhyloGrowBar: View {
    let label: String
    let fraction: Double
    var delay: Double = 0

    @State private var grown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
            }
            GeometryReader { proxy in
                Capsule().fill(Color.white.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.white)
                            .frame(width: proxy.size.width * CGFloat(grown ? fraction : 0))
                    }
            }
            .frame(height: 8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(delay)) { grown = true }
        }
    }
}

/// Artwork for a library item by id (songs, albums), with no extra lookup.
func statArtwork(_ id: String?, width: CGFloat) -> URL? {
    guard let id, !id.isEmpty else { return nil }
    return KhyloArtwork.url(itemID: id, type: .primary, tag: nil, width: width)
}


// MARK: - Premium pieces

/// Album covers drifting past in tilted columns, softened into the background.
struct KhyloCoverCollage: View {
    let urls: [URL]
    var opacity: Double = 0.42

    var body: some View {
        GeometryReader { proxy in
            let columns = 4
            let size = proxy.size.width / CGFloat(columns) * 1.05
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0 ..< columns, id: \.self) { column in
                        let speed = 9.0 + Double(column) * 4.0
                        let travel = (t * speed).truncatingRemainder(dividingBy: Double(size + 10) * 6)
                        VStack(spacing: 10) {
                            ForEach(0 ..< 14, id: \.self) { row in
                                let url = urls.isEmpty ? nil : urls[(row * 3 + column * 5) % urls.count]
                                KhyloImage(url: url, placeholderSymbol: "music.note")
                                    .frame(width: size, height: size)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .offset(y: (column.isMultiple(of: 2) ? -travel : travel - Double(size + 10) * 6) - 200)
                    }
                }
            }
            .rotationEffect(.degrees(-12))
            .scaleEffect(1.35)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(opacity)
            .mask(
                LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom)
            )
        }
        .allowsHitTesting(false)
    }
}

/// The artist's photo filling the top of the screen, fading into the page.
struct KhyloArtistHero: View {
    let artist: BaseItemDto
    @State private var url: URL?

    var body: some View {
        GeometryReader { proxy in
            KhyloImage(url: url, showsPlaceholder: false)
                .frame(width: proxy.size.width, height: proxy.size.height * 0.62)
                .clipped()
                .overlay(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.35), .init(color: Color.black.opacity(0.85), location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .task(id: artist.id) {
            url = KhyloArtistArt.ownImage(for: artist, width: 900)
            if url == nil { url = await KhyloArtistArt.shared.image(for: artist, width: 900) }
        }
    }
}

/// Listening round the clock: twenty-four spokes, longer where you listen more.
struct KhyloHourClock: View {
    let hours: [KhyloStatHour]
    @State private var grown = false

    var body: some View {
        let peak = max(hours.map { $0.seconds ?? 0 }.max() ?? 0, 1)
        let peakHour = hours.max { ($0.seconds ?? 0) < ($1.seconds ?? 0) }?.hour
        ZStack {
            ForEach(hours) { hour in
                let fraction = CGFloat((hour.seconds ?? 0) / peak)
                Capsule()
                    .fill(hour.hour == peakHour ? Color.white : Color.white.opacity(0.45))
                    .frame(width: 7, height: 14 + 78 * fraction * (grown ? 1 : 0.02))
                    .offset(y: -(62 + (14 + 78 * fraction * (grown ? 1 : 0.02)) / 2))
                    .rotationEffect(.degrees(Double(hour.hour) * 15))
                    .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(Double(hour.hour) * 0.03), value: grown)
            }
            VStack(spacing: 2) {
                if let peakHour {
                    Text(Self.clock(peakHour))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("peak hour")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .frame(width: 280, height: 280)
        .onAppear { grown = true }
    }

    static func clock(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }
}

/// A ring split into shares, drawn in as it appears.
struct KhyloDonut: View {
    let shares: [(String, Double)]
    @State private var progress: CGFloat = 0

    var body: some View {
        let total = max(shares.reduce(0) { $0 + $1.1 }, 1)
        ZStack {
            ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                let start = shares.prefix(index).reduce(0) { $0 + $1.1 } / total
                let end = start + share.1 / total
                Circle()
                    .trim(from: CGFloat(start) + 0.004, to: max(CGFloat(start) + 0.004, CGFloat(end) - 0.004) * progress)
                    .stroke(
                        Color.white.opacity(1 - Double(index) * 0.17),
                        style: StrokeStyle(lineWidth: 26, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 230, height: 230)
        .onAppear { withAnimation(.easeOut(duration: 1.6).delay(0.3)) { progress = 1 } }
    }
}

/// A row of bars that dance, for the page about time.
struct KhyloEqualiserStrip: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0 ..< 38, id: \.self) { index in
                    let wave = (sin(t * 2.2 + Double(index) * 0.55) + sin(t * 1.3 + Double(index) * 0.9) + 2) / 4
                    Capsule()
                        .fill(Color.white.opacity(0.35 + 0.55 * wave))
                        .frame(height: 8 + 62 * wave)
                }
            }
        }
    }
}
