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
                    PlaylistRow(playlist: playlist)
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
