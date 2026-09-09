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

    /// Live tracks, keyed by the entry that asked for them.
    ///
    /// A map rather than an ordered array, because order is not this view's to hold.
    /// It used to keep `[ResolvedEntry]` in state and render straight from it, which
    /// made the on-screen order a second copy of something the store already owned --
    /// so a reorder wrote to the database, left the copy untouched, and the list
    /// snapped back. It looked exactly like a change that had not been saved, and the
    /// change had in fact been saved.
    ///
    /// Resolution genuinely belongs in state: it is the async fan-out's result and
    /// cannot be recomputed synchronously. Order does not, so it is not here.
    @State private var tracksByEntryID: [UUID: Track] = [:]
    @State private var isResolving = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isAddingSongs = false

    private var playlist: Playlist? { store.playlist(id: playlistID) }

    /// The rows, ordered by the store and filled in from whatever the sources
    /// answered. Recomputed on every render, which is what makes a reorder appear
    /// the moment it is written.
    private var resolved: [ResolvedEntry] {
        (playlist?.entries ?? []).map {
            ResolvedEntry(entry: $0, track: tracksByEntryID[$0.id])
        }
    }

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
        // Keyed on which entries exist, not how many and not in what order. Count
        // misses a swap; order re-runs the whole fan-out for a drag that cannot have
        // changed a single answer.
        .task(id: playlist.map { Set($0.entries.map(\.id)) }) { await resolveEntries() }
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
                            // Drag to reorder, without going through Edit first.
                            //
                            // A List's own `onMove` only offers reorder handles in
                            // edit mode -- a long press on a row does nothing outside
                            // it, which a UI test confirmed before this was written.
                            // Edit mode is a poor default here anyway: it takes over
                            // the row, so tapping a track to play it stops working
                            // while it is on. `draggable` and `dropDestination` give
                            // the gesture directly and leave the tap alone.
                            //
                            // The payload is the entry's id, not the track's. A
                            // playlist may hold the same track twice, and dragging
                            // one copy must not move the other.
                            .draggable(item.entry.id.uuidString) {
                                DragPreview(title: item.displayTitle)
                            }
                            .dropDestination(for: String.self) { payload, _ in
                                guard let raw = payload.first, let dragged = UUID(uuidString: raw) else {
                                    return false
                                }
                                store.update(id: playlistID) {
                                    $0.move(entryID: dragged, onto: item.entry.id)
                                }
                                return true
                            }
                    }
                    .onDelete { offsets in
                        store.update(id: playlistID) { $0.remove(atOffsets: offsets) }
                    }
                    // Kept alongside the drag. Edit mode is the route VoiceOver's
                    // rotor drives, and a reorder that only exists as a drag gesture
                    // is a reorder some people cannot perform at all.
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
            ArtworkView(data: item.track?.artworkData, url: item.track?.artworkURL)
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
        tracksByEntryID = Dictionary(
            uniqueKeysWithValues: result.compactMap { entry in
                entry.track.map { (entry.entry.id, $0) }
            }
        )
        isResolving = false

        // Correct any drifted snapshots now that sources have answered. Only
        // writes when something actually differs.
        store.refreshSnapshots(for: playlistID, from: result)
    }
}

/// What follows the finger during a reorder.
///
/// A row lifted out of a list looks wrong dragged at full width over itself, and the
/// system default -- a screenshot of the row -- carries the artwork and duration into
/// a context where neither means anything. The title is the part that identifies what
/// is being moved.
private struct DragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
    }
}
