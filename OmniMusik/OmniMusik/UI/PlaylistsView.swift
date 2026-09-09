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

    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        Group {
            if store.playlists.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
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
