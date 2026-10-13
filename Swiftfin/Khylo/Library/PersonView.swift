//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Person View

public struct PersonView: View {

    public let personId: String
    public let personName: String

    @StateObject private var repository = KhyloRepository.shared
    @EnvironmentObject private var navigator: KhyloNavigator

    @State private var person: KhyloPerson?
    @State private var appearances: [KhyloMediaItem] = []
    @State private var isLoading: Bool = true
    @State private var isBioExpanded: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: KhyloSpacing.md)
    ]

    public init(personId: String, personName: String) {
        self.personId = personId
        self.personName = personName
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: KhyloSpacing.lg) {
                    // Top Navigation Bar
                    HStack {
                        Button(action: {
                            navigator.pop()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(KhyloTypography.bodyMedium)
                            .foregroundColor(KhyloColors.textPrimary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.top, KhyloSpacing.md)

                    // Profile Header: Circular Photo & Name
                    VStack(spacing: KhyloSpacing.md) {
                        let photoUrl = person?.imageURL(width: 400)
                        AsyncImage(url: photoUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                ZStack {
                                    KhyloColors.surfaceElevated
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(KhyloColors.textTertiary)
                                }
                            }
                        }
                        .frame(width: 128, height: 128)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(KhyloColors.accent.opacity(0.6), lineWidth: 2)
                        )
                        .shadow(color: KhyloColors.accent.opacity(0.3), radius: 14)

                        VStack(spacing: 4) {
                            Text(person?.name ?? personName)
                                .font(KhyloTypography.title1)
                                .foregroundColor(KhyloColors.textPrimary)
                                .multilineTextAlignment(.center)

                            if let role = person?.role ?? person?.type {
                                Text(role)
                                    .font(KhyloTypography.headline)
                                    .foregroundColor(KhyloColors.accent)
                            }
                        }

                        // Biography
                        if let bio = person?.overview, !bio.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bio)
                                    .font(KhyloTypography.body)
                                    .foregroundColor(KhyloColors.textSecondary)
                                    .lineLimit(isBioExpanded ? nil : 4)

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isBioExpanded.toggle()
                                    }
                                }) {
                                    Text(isBioExpanded ? "Show Less" : "Read More")
                                        .font(KhyloTypography.captionMedium)
                                        .foregroundColor(KhyloColors.accent)
                                }
                            }
                            .padding(.horizontal, KhyloSpacing.lg)
                            .padding(.top, KhyloSpacing.xs)
                        }
                    }

                    Divider()
                        .background(KhyloColors.border.opacity(0.6))
                        .padding(.horizontal, KhyloSpacing.lg)

                    // Filmography / Known For
                    VStack(alignment: .leading, spacing: KhyloSpacing.md) {
                        HStack {
                            Text("Filmography")
                                .font(KhyloTypography.title2)
                                .foregroundColor(KhyloColors.textPrimary)

                            Spacer()

                            Text("\(appearances.count) titles")
                                .font(KhyloTypography.caption)
                                .foregroundColor(KhyloColors.textTertiary)
                        }
                        .padding(.horizontal, KhyloSpacing.lg)

                        LazyVGrid(columns: columns, spacing: KhyloSpacing.md) {
                            ForEach(appearances) { item in
                                KhyloPosterCard(
                                    imageURL: item.posterURL() ?? item.backdropURL(),
                                    title: item.name,
                                    subtitle: item.displaySubtitle,
                                    width: nil,
                                    onTap: {
                                        if item.type == "Series" || item.type == "Show" {
                                            navigator.push(.seriesDetail(seriesId: item.seriesId ?? item.id))
                                        } else {
                                            navigator.push(.itemDetail(itemId: item.id))
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, KhyloSpacing.lg)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .task {
            let (fetchedPerson, fetchedItems) = await repository.fetchPerson(personId: personId)
            await MainActor.run {
                self.person = fetchedPerson
                self.appearances = fetchedItems
                self.isLoading = false
            }
        }
    }
}
