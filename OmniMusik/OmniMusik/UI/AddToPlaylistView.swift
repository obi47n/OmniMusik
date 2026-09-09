//
//  AddToPlaylistView.swift
//  OmniMusik
//
//  Sheet for putting a track into a playlist, or into a new one.
//
//  Shows which playlists already contain the track without preventing a second
//  add. `Playlist.append` permits duplicates on purpose — a set that opens and
//  closes on the same record is a real thing — so the policy here is to inform
//  rather than to block.
//

import SwiftUI

struct AddToPlaylistView: View {
    let track: Track

    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.playlists.isEmpty {
                    ContentUnavailableView {
                        Label("No Playlists", systemImage: "music.note.list")
                    } description: {
                        Text("Create one to start collecting tracks.")
                    } actions: {
                        Button("New Playlist") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCreating = true } label: {
                        Label("New Playlist", systemImage: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $isCreating) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") {
                    // Seeded with this track, so creating from here is one step
                    // rather than create-then-find-it-again.
                    store.create(named: newName, seededWith: [track])
                    newName = ""
                    dismiss()
                }
            }
        }
    }

    private var list: some View {
        List(store.playlists) { playlist in
            Button {
                store.add(track, to: playlist.id)
                dismiss()
            } label: {
                HStack {
                    PlaylistPickerRow(playlist: playlist)
                    Spacer()
                    if playlist.contains(track) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Already added")
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}


/// A playlist as one line, for picking.
///
/// The index shows playlists as tiles, which is right for recognising them and wrong
/// for choosing from a list: a sheet of squares is harder to scan than a column of
/// names. Different job, different shape.
private struct PlaylistPickerRow: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(playlist.name)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(subtitle)

                if playlist.isCrossSource {
                    Text("MIXED")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
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
