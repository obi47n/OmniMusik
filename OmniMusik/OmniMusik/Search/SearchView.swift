//
//  SearchView.swift
//  OmniMusik
//
//  Universal search across every connected source.
//
//  Results are grouped by source and labelled, rather than interleaved into one
//  ranked list. Cross-source relevance ranking would mean inventing a scoring
//  function that compares a filename match against Apple's catalog relevance —
//  two things with no common scale. Grouping is honest about that, and it also
//  answers the question people actually have mid-search: "do I already own this?"
//

import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(SearchService.self) private var search

    @Query private var localEntities: [LocalTrackEntity]

    @State private var query = ""

    /// Saved effects travel with tracks played from search, so a track keeps its
    /// treatment no matter which screen started it.
    private var editMap: [UUID: AudioEdit] {
        Dictionary(uniqueKeysWithValues: localEntities.map { ($0.id, $0.edit) })
    }

    var body: some View {
        Group {
            if search.sections.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Songs and artists")
        .onChange(of: query) { _, newValue in
            search.search(newValue)
        }
        .overlay(alignment: .top) {
            if search.isSearching {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var resultsList: some View {
        List {
            ForEach(search.sections) { section in
                Section {
                    ForEach(section.tracks) { track in
                        TrackRow(
                            track: track,
                            isCurrent: coordinator.currentTrack?.id == track.id,
                            isPlaying: coordinator.isPlaying,
                            isEdited: !(editMap[track.id] ?? .identity).isIdentity
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await coordinator.play(track, in: section.tracks, edits: editMap)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(section.source.displayName)
                        Spacer()
                        Text("\(section.tracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Sources that couldn't answer are reported at the bottom rather than
            // as an alert: a partial result is still useful, and interrupting a
            // search to say "Apple Music isn't connected" would be obnoxious.
            if !search.notes.isEmpty {
                Section {
                    ForEach(Array(search.notes.keys), id: \.self) { source in
                        Label(
                            search.notes[source] ?? "",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.isEmpty {
            ContentUnavailableView {
                Label("Search Everything", systemImage: "magnifyingglass")
            } description: {
                Text("One search across your local files and Apple Music.")
            }
        } else if search.hasSearched && !search.isSearching {
            ContentUnavailableView.search(text: query)
        } else {
            Color.clear
        }
    }
}
