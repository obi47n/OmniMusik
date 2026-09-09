//
//  AccountView.swift
//  OmniMusik
//
//  The account tab: sign in, or the state of the session that exists.
//
//  Written to be honest about what an account is for. Everything local works
//  without one, so this screen sells the thing signing in actually buys —
//  playlists that survive across devices and the web client — rather than
//  blocking the door and implying the app is useless until you comply.
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthController.self) private var auth
    @Environment(SourceConnectionCenter.self) private var connections

    var body: some View {
        Group {
            if auth.isSignedIn {
                signedIn
            } else {
                signedOut
            }
        }
        .navigationTitle("Account")
        .alert(
            "Sign-in Problem",
            isPresented: Binding(
                get: { auth.errorMessage != nil },
                set: { if !$0 { auth.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { auth.errorMessage = nil }
        } message: {
            Text(auth.errorMessage ?? "")
        }
    }

    // MARK: - Signed out

    /// Connected music services.
    ///
    /// Shown regardless of OmniMusik sign-in state, because the two are unrelated:
    /// you can play Spotify without an OmniMusik account, and sync playlists without
    /// Spotify. Presenting them together would imply a dependency that does not
    /// exist.
    @ViewBuilder
    private var sourcesSection: some View {
        if !connections.isEmpty {
            Section {
                ForEach(connections.rows) { row in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.source.displayName)
                            sourceSubtitle(for: row)
                        }

                        Spacer(minLength: 8)

                        switch row.state {
                        case .connecting:
                            ProgressView().controlSize(.small)
                        case .connected:
                            Button("Disconnect") {
                                Task { await connections.disconnect(row.source) }
                            }
                            .font(.subheadline)
                        case .disconnected:
                            Button("Connect") {
                                Task { await connections.connect(row.source) }
                            }
                            .font(.subheadline.weight(.medium))
                        case .unavailable:
                            EmptyView()
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Music Services")
            }
        }
    }

    @ViewBuilder
    private func sourceSubtitle(for row: SourceConnectionCenter.Row) -> some View {
        switch row.state {
        case .connected(let account):
            Text(account ?? "Connected")
                .font(.caption)
                .foregroundStyle(Theme.accent)
        case .disconnected:
            Text("Not connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .connecting:
            Text("Connecting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable(let reason):
            // An explanation rather than a dead button, matching how the sign-in
            // screen behaves in an unconfigured build.
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 8) {
                Text("Sign in to sync")
                    .font(.title2.weight(.semibold))

                Text("Your library and effects work without an account. Signing in adds Omni playlists that follow you across devices, and access to OmniMusik on the web.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if auth.isConfigured {
                Button {
                    Task { await auth.signIn() }
                } label: {
                    HStack(spacing: 8) {
                        if auth.isSigningIn {
                            ProgressView().tint(.white)
                        }
                        Text(auth.isSigningIn ? "Signing in" : "Sign In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .foregroundStyle(.white)
                }
                .disabled(auth.isSigningIn)
                .padding(.horizontal, 32)
            } else {
                // A checkout without the Terraform outputs filled in should say so
                // plainly rather than offer a button that cannot work.
                VStack(spacing: 6) {
                    Text("Sign-in not configured in this build")
                        .font(.subheadline.weight(.medium))
                    Text("Fill in CognitoConfiguration from the Terraform outputs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            if !connections.isEmpty {
                List { sourcesSection }
                    .listStyle(.insetGrouped)
                    .scrollDisabled(true)
                    .frame(maxHeight: 220)
            }

            Spacer()
        }
    }

    // MARK: - Signed in

    private var signedIn: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.user?.presentationName ?? "Signed in")
                            .font(.headline)
                        if let email = auth.user?.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            sourcesSection

            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            } footer: {
                Text("Signing out removes this device's tokens. Your local library and edits stay on the device.")
            }
        }
    }
}
