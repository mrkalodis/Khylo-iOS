//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import SwiftUI

// MARK: - Kids Profile Data

public struct KidsProfileData: Sendable {
    public let name: String
    public let pin: String?
    public let maxParentalRating: Int
    public let allowUnrated: Bool
    public let allowLiveTv: Bool
    public let libraries: [String]
    public let ownerPin: String?

    public init(
        name: String,
        pin: String? = nil,
        maxParentalRating: Int = 1,
        allowUnrated: Bool = false,
        allowLiveTv: Bool = false,
        libraries: [String] = [],
        ownerPin: String? = nil
    ) {
        self.name = name
        self.pin = pin
        self.maxParentalRating = maxParentalRating
        self.allowUnrated = allowUnrated
        self.allowLiveTv = allowLiveTv
        self.libraries = libraries
        self.ownerPin = ownerPin
    }
}

// MARK: - Rating Tier

public struct RatingTier: Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let subtitle: String
    public let icon: String
}

// MARK: - Kids Setup View

public struct KidsSetupView: View {

    public let server: DiscoveredServer
    public let ownerHasPin: Bool
    public let onCreate: (KidsProfileData) -> Void
    public let onCancel: () -> Void

    @State private var profileName: String = ""
    @State private var selectedTierIndex: Int = 1 // Older Kids default
    @State private var allowUnrated: Bool = false
    @State private var allowLiveTv: Bool = false
    @State private var selectedLibraries: Set<String> = ["Movies", "TV Shows", "Animation"]
    @State private var kidPin: String = ""
    @State private var ownerPin: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    private let availableLibraries = [
        "Movies",
        "TV Shows",
        "Animation",
        "Music",
        "Audiobooks"
    ]

    private let ratingTiers: [RatingTier] = [
        RatingTier(id: 0, title: "Little Kids", subtitle: "TV-Y, G — Strictly for young children", icon: "figure.and.child.holdinghands"),
        RatingTier(id: 1, title: "Older Kids", subtitle: "TV-Y7, PG — Family friendly content", icon: "figure.walk"),
        RatingTier(id: 2, title: "Teens", subtitle: "TV-PG, PG-13 — Appropriate for teenagers", icon: "person.2")
    ]

    public init(
        server: DiscoveredServer = DiscoveredServer(name: "Home Media Server", address: "http://localhost:8096"),
        ownerHasPin: Bool = false,
        onCreate: @escaping (KidsProfileData) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.server = server
        self.ownerHasPin = ownerHasPin
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: KhyloSpacing.xl) {
                    // Header
                    HStack {
                        Button("Cancel", action: onCancel)
                            .font(KhyloTypography.bodyMedium)
                            .foregroundColor(KhyloColors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.top, KhyloSpacing.sm)

                    VStack(spacing: KhyloSpacing.xs) {
                        Image(systemName: "figure.and.child.holdinghands")
                            .font(.system(size: 40))
                            .foregroundColor(KhyloColors.accent)
                            .padding(.bottom, 4)

                        Text("Create Kids Profile")
                            .font(KhyloTypography.title2)
                            .foregroundColor(KhyloColors.textPrimary)

                        Text("Customize age-appropriate ratings and library access.")
                            .font(KhyloTypography.subheadline)
                            .foregroundColor(KhyloColors.textSecondary)
                    }

                    // Profile Name Field
                    VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
                        Text("Profile Name")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)

                        TextField("e.g. Maya", text: $profileName)
                            .font(KhyloTypography.body)
                            .foregroundColor(KhyloColors.textPrimary)
                            .padding(KhyloSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: KhyloRadius.md)
                                    .fill(KhyloColors.surfaceElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: KhyloRadius.md)
                                    .stroke(KhyloColors.border, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, KhyloSpacing.lg)

                    // Age / Rating Tier
                    VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                        Text("Content Rating Limit")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)

                        VStack(spacing: KhyloSpacing.sm) {
                            ForEach(ratingTiers) { tier in
                                Button {
                                    selectedTierIndex = tier.id
                                } label: {
                                    HStack(spacing: KhyloSpacing.md) {
                                        Image(systemName: tier.icon)
                                            .font(.system(size: 20))
                                            .foregroundColor(selectedTierIndex == tier.id ? KhyloColors.accent : KhyloColors.textSecondary)
                                            .frame(width: 32)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tier.title)
                                                .font(KhyloTypography.headline)
                                                .foregroundColor(KhyloColors.textPrimary)
                                            Text(tier.subtitle)
                                                .font(KhyloTypography.caption)
                                                .foregroundColor(KhyloColors.textSecondary)
                                        }

                                        Spacer()

                                        if selectedTierIndex == tier.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(KhyloColors.accent)
                                        }
                                    }
                                    .padding(KhyloSpacing.md)
                                    .background(
                                        RoundedRectangle(cornerRadius: KhyloRadius.md)
                                            .fill(selectedTierIndex == tier.id ? KhyloColors.accent.opacity(0.12) : KhyloColors.surfaceElevated)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: KhyloRadius.md)
                                            .stroke(selectedTierIndex == tier.id ? KhyloColors.accent : KhyloColors.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(KhyloScaleButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.lg)

                    // Library Access Whitelist
                    VStack(alignment: .leading, spacing: KhyloSpacing.sm) {
                        Text("Accessible Libraries")
                            .font(KhyloTypography.headline)
                            .foregroundColor(KhyloColors.textPrimary)

                        VStack(spacing: 8) {
                            ForEach(availableLibraries, id: \.self) { lib in
                                Button {
                                    if selectedLibraries.contains(lib) {
                                        selectedLibraries.remove(lib)
                                    } else {
                                        selectedLibraries.insert(lib)
                                    }
                                } label: {
                                    HStack {
                                        Text(lib)
                                            .font(KhyloTypography.bodyMedium)
                                            .foregroundColor(KhyloColors.textPrimary)
                                        Spacer()
                                        Image(systemName: selectedLibraries.contains(lib) ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedLibraries.contains(lib) ? KhyloColors.accent : KhyloColors.textTertiary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, KhyloSpacing.md)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: KhyloRadius.md)
                                .fill(KhyloColors.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: KhyloRadius.md)
                                .stroke(KhyloColors.border, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, KhyloSpacing.lg)

                    // Additional Guardrails
                    VStack(spacing: KhyloSpacing.md) {
                        Toggle(isOn: $allowUnrated) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow Unrated Titles")
                                    .font(KhyloTypography.headline)
                                    .foregroundColor(KhyloColors.textPrimary)
                                Text("Permits content without official MPAA / TV ratings.")
                                    .font(KhyloTypography.caption)
                                    .foregroundColor(KhyloColors.textSecondary)
                            }
                        }
                        .tint(KhyloColors.accent)

                        Divider().background(KhyloColors.border)

                        Toggle(isOn: $allowLiveTv) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow Live TV")
                                    .font(KhyloTypography.headline)
                                    .foregroundColor(KhyloColors.textPrimary)
                                Text("Unfiltered live broadcast channels.")
                                    .font(KhyloTypography.caption)
                                    .foregroundColor(KhyloColors.textSecondary)
                            }
                        }
                        .tint(KhyloColors.accent)
                    }
                    .padding(KhyloSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: KhyloRadius.md)
                            .fill(KhyloColors.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: KhyloRadius.md)
                            .stroke(KhyloColors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, KhyloSpacing.lg)

                    // Optional Parent PIN challenge
                    if ownerHasPin {
                        VStack(alignment: .leading, spacing: KhyloSpacing.xs) {
                            Text("Parent / Owner PIN")
                                .font(KhyloTypography.headline)
                                .foregroundColor(KhyloColors.textPrimary)

                            SecureField("Enter Owner PIN to authorize", text: $ownerPin)
                                .font(KhyloTypography.body)
                                .foregroundColor(KhyloColors.textPrimary)
                                .padding(KhyloSpacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: KhyloRadius.md)
                                        .fill(KhyloColors.surfaceElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: KhyloRadius.md)
                                        .stroke(KhyloColors.border, lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, KhyloSpacing.lg)
                    }

                    // Submit Button
                    KhyloPrimaryButton(
                        "Create Profile",
                        icon: "checkmark",
                        isLoading: isSubmitting,
                        isEnabled: !profileName.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        createProfile()
                    }
                    .padding(.horizontal, KhyloSpacing.lg)
                    .padding(.bottom, KhyloSpacing.xxl)
                }
            }
        }
    }

    private func createProfile() {
        guard !profileName.isEmpty else { return }
        isSubmitting = true

        let data = KidsProfileData(
            name: profileName,
            pin: kidPin.isEmpty ? nil : kidPin,
            maxParentalRating: selectedTierIndex,
            allowUnrated: allowUnrated,
            allowLiveTv: allowLiveTv,
            libraries: Array(selectedLibraries),
            ownerPin: ownerPin.isEmpty ? nil : ownerPin
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isSubmitting = false
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            onCreate(data)
        }
    }
}
