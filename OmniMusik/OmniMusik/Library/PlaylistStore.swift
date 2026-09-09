//
//  PlaylistStore.swift
//  OmniMusik
//
//  Owns playlist reads, writes, and entry resolution.
//
//  Playlists deliberately do NOT come through `@Query` the way local tracks do.
//  A playlist is only ever displayed after resolving its entries against every
//  source, which is an async fan-out — the same shape as `SearchService`, and not
//  something a synchronous query can express. So the store holds the list and the
//  views read it, while local tracks stay reactive. That is the same asymmetry
//  `LibraryStore` documents, arrived at for the same reason.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PlaylistStore {

    private(set) var playlists: [Playlist] = []

    private let context: ModelContext
    private let sources: [any MusicSource]

    init(container: ModelContainer, sources: [any MusicSource]) {
        self.context = ModelContext(container)
        self.sources = sources
        reload()
    }

    // MARK: - Reading

    /// Most recently updated first: a playlist just edited is the one most likely
    /// to be wanted again.
    func reload() {
        let descriptor = FetchDescriptor<PlaylistEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        playlists = ((try? context.fetch(descriptor)) ?? []).map(\.asPlaylist)
    }

    func playlist(id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    // MARK: - Writing

    @discardableResult
    func create(named rawName: String, seededWith tracks: [Track] = []) -> Playlist? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var playlist = Playlist(name: name)
        playlist.append(contentsOf: tracks)

        let entity = PlaylistEntity(
            id: playlist.id,
            name: playlist.name,
            entries: playlist.entries,
            createdAt: playlist.createdAt,
            updatedAt: playlist.updatedAt
        )
        context.insert(entity)
        save()
        return playlist
    }

    func delete(id: UUID) {
        guard let entity = entity(for: id) else { return }
        context.delete(entity)
        save()
    }

    /// The single write path.
    ///
    /// Every mutation goes through the domain type and is then persisted here, so
    /// the ordering, duplicate, and timestamp rules live in `Playlist` where they
    /// are testable without a store, and never get reimplemented per view.
    func update(id: UUID, _ mutate: (inout Playlist) -> Void) {
        guard let entity = entity(for: id) else { return }

        let before = entity.asPlaylist
        var playlist = before
        mutate(&playlist)

        // Only write when something actually changed.
        //
        // `apply` marks the row as having unsynced edits, so writing unconditionally
        // means merely *opening* a playlist flags it dirty -- the detail view
        // refreshes snapshots on appear, which comes through here. The next sync then
        // sees local edits alongside a moved server and returns .conflict, which is
        // never auto-resolved, so changes made on another device silently stop
        // arriving.
        //
        // The domain mutators are already careful not to touch `updatedAt` when
        // nothing moved, which makes equality a reliable test. That care was being
        // discarded one layer down.
        guard playlist != before else { return }

        entity.apply(playlist)
        save()
    }

    func add(_ track: Track, to id: UUID) {
        update(id: id) { $0.append(track) }
    }

    func rename(id: UUID, to name: String) {
        update(id: id) { $0.rename(to: name) }
    }

    // MARK: - Resolution

    /// Pairs each entry with a live track, where some source can supply one.
    ///
    /// Fans out per source rather than per entry: a playlist with forty local
    /// tracks should be one batched lookup, not forty. Entries whose source has
    /// no match come back with `track == nil` and render from their snapshot.
    func resolve(_ playlist: Playlist) async -> [ResolvedEntry] {
        var resolved: [TrackSource: [String: Track]] = [:]

        for source in sources {
            let ids = Set(
                playlist.entries
                    .filter { $0.source == source.source }
                    .map(\.sourceID)
            )
            guard !ids.isEmpty, await source.isAvailable() else { continue }

            var found: [String: Track] = [:]
            for id in ids {
                // A source that throws on one identifier should not take down the
                // rest of the playlist, so failures degrade to "unplayable".
                if let track = try? await source.track(forSourceID: id) {
                    found[id] = track
                }
            }
            resolved[source.source] = found
        }

        return playlist.entries.map { entry in
            ResolvedEntry(entry: entry, track: resolved[entry.source]?[entry.sourceID])
        }
    }

    /// Corrects stored snapshots from whatever the sources just returned.
    /// Cheap when nothing changed: `refreshSnapshot` only writes on a difference.
    func refreshSnapshots(for playlistID: UUID, from resolved: [ResolvedEntry]) {
        let live = resolved.compactMap { entry -> (UUID, Track)? in
            guard let track = entry.track else { return nil }
            return (entry.entry.id, track)
        }
        guard !live.isEmpty else { return }

        update(id: playlistID) { playlist in
            let before = playlist.updatedAt
            for (entryID, track) in live {
                playlist.refreshSnapshot(forEntryID: entryID, from: track)
            }
            _ = before
        }
    }

    // MARK: - Private

    private func entity(for id: UUID) -> PlaylistEntity? {
        var descriptor = FetchDescriptor<PlaylistEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        try? context.save()
        reload()
    }
}
