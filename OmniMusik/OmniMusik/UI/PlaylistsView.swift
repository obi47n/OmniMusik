//
//  PlaylistsView.swift
//  OmniMusik
//
//  The playlist index.
//
//  A two-column grid rather than a list. Playlists are things you recognise rather
//  than lines you read, and a grid gives each one a tile with its own identity
//  instead of a row indistinguishable from its neighbours.
//
//  Every tile shows how many tracks and how long, both answerable from stored
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
                grid
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

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(store.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id)
                    } label: {
                        PlaylistTile(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    // A grid has no swipe-to-delete, so the destructive action moves
                    // to a context menu rather than disappearing with the list.
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.delete(id: playlist.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    /// Two flexible columns rather than an adaptive minimum, because the count is the
    /// point: two per row is what makes the tiles large enough to read at a glance.
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]
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

    /// Reports sync state inline rather than as an alert, and often reports nothing.
    ///
    /// Conflicts in particular must not be a modal: they are not errors, they are a
    /// decision waiting for a person, and interrupting them to say so would be worse
    /// than showing it in place.
    ///
    /// Syncing is automatic, which changes what this is for. Reporting every
    /// background sync would put a banner on screen every time someone added a track
    /// -- constant, uninformative, and the fastest way to make the one banner that
    /// matters invisible. So progress and success are reported only for a sync
    /// somebody actually asked for.
    ///
    /// Failures and conflicts are shown either way. Both mean edits are not where the
    /// person thinks they are, and that is true regardless of who started the sync.
    @ViewBuilder
    private var syncBanner: some View {
        switch sync.status {
        case .syncing:
            if sync.reason == .requested {
                banner(text: "Syncing…", systemImage: "arrow.triangle.2.circlepath", tint: .secondary)
            }

        case .failed(let message):
            banner(text: message, systemImage: "exclamationmark.triangle", tint: .orange)

        case .succeeded(let pushed, let pulled, let deleted):
            if !sync.conflicts.isEmpty {
                banner(
                    text: "\(sync.conflicts.count) playlist\(sync.conflicts.count == 1 ? "" : "s") changed in both places. Open one to choose.",
                    systemImage: "arrow.triangle.branch",
                    tint: Theme.accent
                )
            } else if sync.reason == .requested, pushed + pulled + deleted > 0 {
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

/// One playlist as a tile.
///
/// Playlists carry no artwork of their own: `PlaylistEntry` stores a title, artist
/// and duration, deliberately not an expiring cover URL. Rather than showing four
/// grey squares, each tile gets a gradient derived from its own id -- stable across
/// launches, distinct between playlists, and honest about being generated rather
/// than pretending to be album art.
struct PlaylistTile: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(subtitle)
                        .lineLimit(1)

                    if playlist.isCrossSource {
                        // Only when a playlist genuinely mixes sources -- the case
                        // this whole architecture exists to support.
                        Text("MIXED")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                Image(systemName: playlist.isEmpty ? "music.note.list" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
    }

    private var subtitle: String {
        guard !playlist.isEmpty else { return "Empty" }
        let noun = playlist.trackCount == 1 ? "track" : "tracks"
        return "\(playlist.trackCount) \(noun) · \(playlist.formattedTotalDuration)"
    }

    /// Deterministic from the id, so a playlist keeps its colour across launches and
    /// devices. Hue only: saturation and brightness stay fixed so no tile arrives
    /// muddy or fluorescent.
    private var tint: Color {
        var hash: UInt64 = 5381
        for byte in playlist.id.uuidString.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.62)
    }
}
