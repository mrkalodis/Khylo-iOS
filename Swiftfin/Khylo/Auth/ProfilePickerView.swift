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

// MARK: - Profile Model

public struct KhyloProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isOwner: Bool
    public let isCurrent: Bool
    public let hasPin: Bool
    public let isKids: Bool
    public let ratingLimit: String?
    public let primaryImageTag: String?

    public init(
        id: String,
        name: String,
        isOwner: Bool = false,
        isCurrent: Bool = false,
        hasPin: Bool = false,
        isKids: Bool = false,
        ratingLimit: String? = nil,
        primaryImageTag: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isOwner = isOwner
        self.isCurrent = isCurrent
        self.hasPin = hasPin
        self.isKids = isKids
        self.ratingLimit = ratingLimit
        self.primaryImageTag = primaryImageTag
    }
}

// MARK: - Profile Colors

private enum ProfilePalette {
    static let colors: [Color] = [
        Color(red: 0.85, green: 0.47, blue: 0.20), // Orange (Khylo Accent)
        Color(red: 0.23, green: 0.51, blue: 0.96), // Blue
        Color(red: 0.06, green: 0.73, blue: 0.51), // Emerald
        Color(red: 0.66, green: 0.33, blue: 0.97), // Purple
        Color(red: 0.94, green: 0.27, blue: 0.27), // Red
        Color(red: 0.92, green: 0.70, blue: 0.03), // Yellow
        Color(red: 0.08, green: 0.72, blue: 0.65), // Teal
        Color(red: 0.93, green: 0.28, blue: 0.60)  // Pink
    ]

    static func color(for id: String) -> Color {
        let clean = id.replacingOccurrences(of: "-", with: "")
        let suffix = String(clean.suffix(4))
        let intVal = Int(suffix, radix: 16) ?? abs(id.hashValue)
        return colors[abs(intVal) % colors.count]
    }
}

// MARK: - Profile Picker View

public struct ProfilePickerView: View {

    public let server: DiscoveredServer
    public let onSelectProfile: (KhyloProfile, String?) -> Void
    public let onSwitchServer: () -> Void

    @State private var profiles: [KhyloProfile] = []
    @State private var canManage: Bool = true
    @State private var isLoading: Bool = false
    @State private var selectedProfileForPin: KhyloProfile?
    @State private var showKidsSetup: Bool = false
    @State private var errorMessage: String?

    public init(
        server: DiscoveredServer = DiscoveredServer(name: "Home Media Server", address: "http://localhost:8096"),
        onSelectProfile: @escaping (KhyloProfile, String?) -> Void = { _, _ in },
        onSwitchServer: @escaping () -> Void = {}
    ) {
        self.server = server
        self.onSelectProfile = onSelectProfile
        self.onSwitchServer = onSwitchServer
    }

    public var body: some View {
        ZStack {
            KhyloColors.background
                .ignoresSafeArea()

            if let profile = selectedProfileForPin {
                // PIN Entry modal
                PINEntryView(
                    title: profile.name,
                    subtitle: "Enter 4-digit profile PIN",
                    onSuccess: { pin in
                        selectedProfileForPin = nil
                        onSelectProfile(profile, pin)
                    },
                    onCancel: {
                        selectedProfileForPin = nil
                    }
                )
                .transition(.opacity)
            } else {
                pickerContent
            }
        }
        .sheet(isPresented: $showKidsSetup) {
            KidsSetupView(
                server: server,
                ownerHasPin: false,
                onCreate: { data in
                    showKidsSetup = false
                    createKidsProfile(data)
                },
                onCancel: {
                    showKidsSetup = false
                }
            )
        }
        .onAppear {
            loadProfiles()
        }
    }

    private var pickerContent: some View {
        VStack(spacing: KhyloSpacing.xl) {
            // Top Bar
            HStack {
                Button(action: { onSwitchServer() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                        Text(server.name)
                            .lineLimit(1)
                    }
                    .font(KhyloTypography.captionBold)
                    .foregroundColor(KhyloColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(KhyloColors.surfaceElevated)
                    )
                }

                Spacer()
            }
            .padding(.horizontal, KhyloSpacing.lg)
            .padding(.top, KhyloSpacing.sm)

            Spacer()

            // Header Title
            VStack(spacing: KhyloSpacing.xs) {
                Text("Who's watching?")
                    .font(KhyloTypography.title1)
                    .foregroundColor(KhyloColors.textPrimary)

                Text("Select your profile to customize continue watching and recommendations.")
                    .font(KhyloTypography.body)
                    .foregroundColor(KhyloColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, KhyloSpacing.xl)
            }

            // Profiles Grid
            if isLoading {
                ProgressView()
                    .tint(KhyloColors.accent)
                    .scaleEffect(1.3)
                    .padding(.vertical, 40)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KhyloSpacing.lg) {
                        ForEach(profiles) { profile in
                            profileCard(profile)
                        }

                        // Add Profile Button
                        if canManage {
                            addProfileCard
                        }
                    }
                    .padding(.horizontal, KhyloSpacing.xl)
                    .padding(.vertical, KhyloSpacing.md)
                }
            }

            Spacer()

            // Footer info
            HStack {
                Text(server.address.host ?? server.address.absoluteString)
                    .font(KhyloTypography.caption)
                    .foregroundColor(KhyloColors.textTertiary)
            }
            .padding(.bottom, KhyloSpacing.lg)
        }
    }

    private func profileCard(_ profile: KhyloProfile) -> some View {
        Button(action: {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            if profile.hasPin {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedProfileForPin = profile
                }
            } else {
                onSelectProfile(profile, nil)
            }
        }) {
            VStack(spacing: KhyloSpacing.sm) {
                ZStack(alignment: .bottomTrailing) {
                    // Avatar circle
                    ZStack {
                        Circle()
                            .fill(ProfilePalette.color(for: profile.id))
                            .frame(width: 96, height: 96)

                        Text(String(profile.name.prefix(1)).uppercased())
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(profile.isCurrent ? KhyloColors.accent : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                    // Badges overlay
                    HStack(spacing: 4) {
                        if profile.hasPin {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Circle().fill(KhyloColors.surfaceElevated))
                        }

                        if profile.isKids {
                            Text("KIDS")
                                .font(KhyloTypography.badge)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue))
                        }
                    }
                    .offset(x: 4, y: 4)
                }

                Text(profile.name)
                    .font(KhyloTypography.headline)
                    .foregroundColor(KhyloColors.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 110)
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private var addProfileCard: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showKidsSetup = true
        }) {
            VStack(spacing: KhyloSpacing.sm) {
                ZStack {
                    Circle()
                        .stroke(KhyloColors.border, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: 96, height: 96)
                        .background(Circle().fill(KhyloColors.surfaceElevated.opacity(0.4)))

                    Image(systemName: "plus")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(KhyloColors.accent)
                }

                Text("Add Profile")
                    .font(KhyloTypography.bodyMedium)
                    .foregroundColor(KhyloColors.textSecondary)
            }
            .frame(width: 110)
        }
        .buttonStyle(KhyloScaleButtonStyle())
    }

    private func loadProfiles() {
        isLoading = true
        Task {
            do {
                // Try Khylo HomeProfiles endpoint first
                let fetched = try await fetchHomeProfiles()
                self.profiles = fetched
            } catch {
                // Fallback: public users endpoint
                if let publicUsers = try? await fetchPublicUsers() {
                    self.profiles = publicUsers
                } else {
                    // Default fallback: Owner profile
                    self.profiles = [
                        KhyloProfile(id: UUID().uuidString, name: "Owner", isOwner: true, isCurrent: true, hasPin: false),
                        KhyloProfile(id: UUID().uuidString, name: "Kids", isOwner: false, isCurrent: false, hasPin: false, isKids: true)
                    ]
                }
            }
            isLoading = false
        }
    }

    private func fetchHomeProfiles() async throws -> [KhyloProfile] {
        let url = server.address.appendingPathComponent("Khylo/HomeProfiles")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profilesArray = json["Profiles"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        return profilesArray.map { dict in
            KhyloProfile(
                id: dict["Id"] as? String ?? UUID().uuidString,
                name: dict["Name"] as? String ?? "User",
                isOwner: dict["IsOwner"] as? Bool ?? false,
                isCurrent: dict["IsCurrent"] as? Bool ?? false,
                hasPin: dict["HasPin"] as? Bool ?? false,
                isKids: dict["IsKids"] as? Bool ?? false,
                ratingLimit: dict["RatingLimit"] as? String,
                primaryImageTag: dict["PrimaryImageTag"] as? String
            )
        }
    }

    private func fetchPublicUsers() async throws -> [KhyloProfile] {
        let url = server.address.appendingPathComponent("Users/Public")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        return array.map { dict in
            KhyloProfile(
                id: dict["Id"] as? String ?? UUID().uuidString,
                name: dict["Name"] as? String ?? "User",
                isOwner: false,
                isCurrent: false,
                hasPin: dict["HasConfiguredPassword"] as? Bool ?? false
            )
        }
    }

    private func createKidsProfile(_ data: KidsProfileData) {
        let newProfile = KhyloProfile(
            id: UUID().uuidString,
            name: data.name,
            isOwner: false,
            isCurrent: false,
            hasPin: data.pin != nil,
            isKids: true
        )
        profiles.append(newProfile)
    }
}
