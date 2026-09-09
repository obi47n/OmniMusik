//
//  PlaylistsView.swift
//  OmniMusik
//
//  The playlist index.
//
//  Every row shows how many tracks and how long, both answerable from stored
//  snapshots without touching a source, so this screen renders instantly and
//  offline. Resolution only happens when a playlist is opened.
//

import SwiftUI

struct PlaylistsView: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(PlaylistSyncService.self) private var sync

    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            syncBanner

            if store.playlists.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        await sync.sync()
                        store.reload()
                    }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!sync.isConfigured || sync.status == .syncing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { beginCreating() } label: {
                    Label("New Playlist", systemImage: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $isCreating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create") {
                store.create(named: newName)
                newName = ""
            }
        } message: {
            Text("Playlists can mix local files and Apple Music.")
        }
    }

    private var list: some View {
        List {
            ForEach(store.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id)
                } label: {
                    PlaylistRow(playlist: playlist)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    store.delete(id: store.playlists[index].id)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Playlists", systemImage: "music.note.list")
        } description: {
            Text("Build a set that mixes your own files with Apple Music.")
        } actions: {
            Button("New Playlist") { beginCreating() }
                .buttonStyle(.borderedProminent)
        }
    }

    /// Reports sync state inline rather than as an alert.
    ///
    /// Conflicts in particular must not be a modal: they are not errors, they are a
    /// decision waiting for a person, and interrupting them to say so would be worse
    /// than showing it in place.
    @ViewBuilder
    private var syncBanner: some View {
        switch sync.status {
        case .syncing:
            banner(text: "Syncing…", systemImage: "arrow.triangle.2.circlepath", tint: .secondary)

        case .failed(let message):
            banner(text: message, systemImage: "exclamationmark.triangle", tint: .orange)

        case .succeeded(let pushed, let pulled, let deleted):
            if !sync.conflicts.isEmpty {
                banner(
                    text: "\(sync.conflicts.count) playlist\(sync.conflicts.count == 1 ? "" : "s") changed in both places. Open one to choose.",
                    systemImage: "arrow.triangle.branch",
                    tint: Theme.accent
                )
            } else if pushed + pulled + deleted > 0 {
                banner(
                    text: "Synced · \(pushed) up, \(pulled) down\(deleted > 0 ? ", \(deleted) removed" : "")",
                    systemImage: "checkmark.circle",
                    tint: .secondary
                )
            }

        case .idle:
            EmptyView()
        }
    }

    private func banner(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(text).font(.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private func beginCreating() {
        newName = ""
        isCreating = true
    }
}

struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playlist.name)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(subtitle)

                // The badge only appears when a playlist genuinely mixes sources.
                // That is the case this whole architecture exists to support, so
                // it is worth pointing at when it happens.
                if playlist.isCrossSource {
                    Text("MIXED")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        guard !playlist.isEmpty else { return "Empty" }
        let noun = playlist.trackCount == 1 ? "track" : "tracks"
        return "\(playlist.trackCount) \(noun) · \(playlist.formattedTotalDuration)"
    }
}
