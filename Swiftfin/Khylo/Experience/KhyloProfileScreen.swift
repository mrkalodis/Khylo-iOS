//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import FactoryKit
import SwiftUI

struct KhyloProfileScreen: View {

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingSignOut = false

    private var session: UserSession? { KhyloAPI.session }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        KhyloImage(
                            url: session.flatMap { $0.user.profileImageSource(client: $0.client).url },
                            placeholderSymbol: "person.fill"
                        )
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session?.user.username ?? "")
                                .font(.system(size: 19, weight: .semibold))
                            Text(session?.server.name ?? "")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                KhyloDownloadSettingsSection {
                    dismiss()
                    KhyloPageRelay.shared.showDownloads.send()
                }

                Section("Server") {
                    LabeledContent("Name", value: session?.server.name ?? "–")
                    LabeledContent("Address", value: session?.server.effectiveServerURL.host() ?? "–")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KhyloStyle.canvas)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Sign out of Khylo?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    Task { await userSessionManager.signOut(reason: .explicit) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}
