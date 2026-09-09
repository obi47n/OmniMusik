//
//  PlaylistDetailView.swift
//  OmniMusik
//
//  One playlist, with its entries resolved against every source.
//
//  The screen is built around a state the rest of the app does not have: an entry
//  that exists but cannot currently be played. Rather than hiding those rows or
//  showing them as errors, they render from their stored snapshot, dimmed and
//  labelled with why. A playlist you built while subscribed should still be
//  legible after the subscription lapses.
//

import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID

    @Environment(PlaylistStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(PlaylistSyncService.self) private var sync

    @Query private var entities: [LocalTrackEntity]

    @State private var resolved: [ResolvedEntry] = []
    @State private var isResolving = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isAddingSongs = false

    private var playlist: Playlist? { store.playlist(id: playlistID) }

    private var editMap: [UUID: AudioEdit] {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0.edit) })
    }

    var body: some View {
        Group {
            if let playlist {
                content(for: playlist)
            } else {
                // The playlist was deleted while open.
                ContentUnavailableView("Playlist Unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let playlist, !playlist.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAddingSongs = true } label: {
                    Label("Add Songs", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftName = playlist?.name ?? ""
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
        }
        .alert("Rename Playlist", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.rename(id: playlistID, to: draftName) }
        }
        .sheet(isPresented: $isAddingSongs) {
            AddSongsView(playlistID: playlistID)
        }
        // Keyed on the entry count so closing the picker re-resolves whatever was
        // added, without polling.
        .task(id: playlist?.entries.count) { await resolveEntries() }
    }

    /// Offered when sync found this playlist changed in two places.
    ///
    /// Nothing here resolves automatically: both sides hold work somebody did, and
    /// picking a winner silently is how an evening's edits disappear without anyone
    /// being told. The banner names what each choice discards.
    @ViewBuilder
    private var conflictBanner: some View {
        if sync.conflicts.contains(playlistID) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Changed in two places", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))

                Text("This playlist was edited here and on another device. Choose which version to keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Use Other Device") {
                        Task {
                            await sync.resolveByTakingRemote(id: playlistID)
                            store.reload()
                            await resolveEntries()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Keep This One") {
                        Task {
                            await sync.resolveByKeepingLocal(id: playlistID)
                            store.reload()
                            await resolveEntries()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func content(for playlist: Playlist) -> some View {
        if playlist.isEmpty {
            ContentUnavailableView {
                Label("Nothing Here Yet", systemImage: "music.note.list")
            } description: {
                Text("Mix your own files with anything from a connected service.")
            } actions: {
                Button("Add Songs") { isAddingSongs = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 0) {
            conflictBanner
            List {
                Section {
                    ForEach(resolved) { item in
                        row(for: item, in: playlist)
                    }
                    .onDelete { offsets in
                        store.update(id: playlistID) { $0.remove(atOffsets: offsets) }
                    }
                    .onMove { offsets, destination in
                        store.update(id: playlistID) {
                            $0.move(fromOffsets: offsets, toOffset: destination)
                        }
                    }
                } header: {
                    header(for: playlist)
                } footer: {
                    footer
                }
            }
            .listStyle(.plain)
            }
        }
    }

    private func header(for playlist: Playlist) -> some View {
        HStack {
            Button {
                Task { await playAll() }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(resolved.playableTracks.isEmpty)

            Spacer()

            if isResolving {
                ProgressView().controlSize(.small)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var footer: some View {
        let unavailable = resolved.unplayableCount
        if unavailable > 0 {
            Text("\(unavailable) \(unavailable == 1 ? "track is" : "tracks are") unavailable and will be skipped.")
        }
    }

    @ViewBuilder
    private func row(for item: ResolvedEntry, in playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            ArtworkView(data: item.track?.artworkData)
                .frame(width: 44, height: 44)
                .opacity(item.isPlayable ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(1)
                    .foregroundStyle(titleColor(for: item))

                HStack(spacing: 4) {
                    Text(item.displayArtist).lineLimit(1)
                    Text("·")
                    Text(item.entry.source.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if item.isPlayable {
                Text(Track.timeFormatter(item.displayDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                // Says why, rather than just going grey. An entry whose source is
                // not connected is a different problem from a deleted file, and
                // the person can only act on one of them.
                Text(item.entry.source == .local ? "Missing" : "Not connected")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let track = item.track else { return }
            Task {
                await coordinator.play(track, in: resolved.playableTracks, edits: editMap)
            }
        }
    }

    private func titleColor(for item: ResolvedEntry) -> Color {
        guard item.isPlayable else { return .secondary }
        return coordinator.currentTrack?.id == item.track?.id ? Theme.accent : .primary
    }

    // MARK: - Actions

    private func playAll() async {
        let tracks = resolved.playableTracks
        guard let first = tracks.first else { return }
        await coordinator.play(first, in: tracks, edits: editMap)
    }

    private func resolveEntries() async {
        guard let playlist else { return }
        isResolving = true
        let result = await store.resolve(playlist)
        resolved = result
        isResolving = false

        // Correct any drifted snapshots now that sources have answered. Only
        // writes when something actually differs.
        store.refreshSnapshots(for: playlistID, from: result)
    }
}
