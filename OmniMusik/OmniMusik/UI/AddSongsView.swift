//
//  AddSongsView.swift
//  OmniMusik
//
//  Adding tracks from inside a playlist.
//
//  The library and search screens can already push a track *into* a playlist, but
//  that is the wrong direction for the common case: you open a playlist you are
//  building and want to add several things to it. This is that flow — search once,
//  tap several results, leave.
//
//  Adds are applied immediately rather than collected and confirmed. There is no
//  destructive step to guard, the playlist screen behind is the undo, and a "Done"
//  that could discard a dozen taps is worse than no confirmation at all.
//

import SwiftData
import SwiftUI

struct AddSongsView: View {
    let playlistID: UUID

    @Environment(PlaylistStore.self) private var store
    @Environment(MusicSourceRegistry.self) private var registry
    @Environment(\.dismiss) private var dismiss

    /// Its own service, not the Search tab's: two screens sharing one would
    /// overwrite each other's results.
    @State private var search: SearchService?
    @State private var query = ""

    /// Local tracks, so an empty query still offers something to add.
    @Query(sort: \LocalTrackEntity.dateAdded, order: .reverse)
    private var localEntities: [LocalTrackEntity]

    private var playlist: Playlist? { store.playlist(id: playlistID) }

    var body: some View {
        NavigationStack {
            List {
                if let search, !query.isEmpty {
                    if search.sections.isEmpty && search.hasSearched && !search.isSearching {
                        Text("No matches.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(search.sections) { section in
                        Section(section.source.displayName) {
                            ForEach(section.tracks) { track in
                                row(for: track)
                            }
                        }
                    }
                    // Sources that declined, reported quietly rather than as an alert.
                    ForEach(Array(search.notes.keys), id: \.self) { source in
                        Text(search.notes[source] ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your Library") {
                        if localEntities.isEmpty {
                            Text("Import music, or search to add from a connected service.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(localEntities.map(\.asTrack)) { track in
                            row(for: track)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Songs and artists")
            .onChange(of: query) { _, value in search?.search(value) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if search == nil { search = SearchService(sources: registry.sources) }
            }
        }
    }

    private func row(for track: Track) -> some View {
        let alreadyIn = playlist?.contains(track) ?? false

        return Button {
            store.add(track, to: playlistID)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(track: track)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(track.artist).lineLimit(1)
                        SourceBadge(source: track.source)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                // Informational, not a block: duplicates are legal by design, so
                // this says "already here" rather than disabling the row.
                Image(systemName: alreadyIn ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(alreadyIn ? Theme.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
