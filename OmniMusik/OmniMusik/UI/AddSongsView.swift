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
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss

    /// Its own service, not the Search tab's: two screens sharing one would
    /// overwrite each other's results.
    @State private var search: SearchService?
    @State private var query = ""

    /// Local tracks, so an empty query still offers something to add.
    @Query(sort: \LocalTrackEntity.dateAdded, order: .reverse)
    private var localEntities: [LocalTrackEntity]

    private var playlist: Playlist? { store.playlist(id: playlistID) }

    /// Local files plus every connected service's library, in canonical source order
    /// so the list does not reshuffle as sources finish loading.
    private var librarySections: [(source: TrackSource, tracks: [Track])] {
        let all = localEntities.map(\.asTrack) + libraryStore.remoteTracks
        return TrackSource.allCases.compactMap { source in
            let tracks = all.filter { $0.source == source }
            return tracks.isEmpty ? nil : (source, tracks)
        }
    }

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
                    // Everything already loaded, grouped by source. Searching is for
                    // reaching past the library, not for using it -- a connected
                    // service's saved tracks are right here and should not need a
                    // query to find.
                    ForEach(librarySections, id: \.source) { section in
                        Section(section.source.displayName) {
                            ForEach(section.tracks) { track in
                                row(for: track)
                            }
                        }
                    }

                    if librarySections.isEmpty {
                        Text("Import music, or connect a service in Account.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    // Sources that could not answer, reported quietly.
                    ForEach(Array(libraryStore.notes.keys), id: \.self) { source in
                        Text(libraryStore.notes[source] ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                // Pull connected services' libraries if they have not been fetched
                // yet, so opening this straight after launch is not empty.
                if libraryStore.remoteTracks.isEmpty { await libraryStore.refresh() }
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
