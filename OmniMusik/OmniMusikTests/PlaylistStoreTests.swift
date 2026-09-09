//
//  PlaylistStoreTests.swift
//  OmniMusikTests
//
//  Regression coverage for the persistence boundary.
//
//  The sync decision table is only as good as the `hasLocalChanges` flag fed into it,
//  and that flag is set here rather than in the domain. A store that marks every row
//  dirty on read turns "pull the other device's changes" into "conflict", and
//  conflicts are never auto-resolved -- so remote edits silently stop arriving. That
//  bug shipped once; these tests exist so it cannot again.
//

import Foundation
import SwiftData
import Testing
@testable import OmniMusik

@Suite("PlaylistStore", .serialized)
@MainActor
struct PlaylistStoreTests {

    private func makeStore() throws -> (PlaylistStore, ModelContainer) {
        let container = try ModelContainer(
            for: LocalTrackEntity.self, PlaylistEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (PlaylistStore(container: container, sources: []), container)
    }

    /// Marks a playlist as though it had just synced cleanly.
    private func markSynced(_ id: UUID, in container: ModelContainer, version: Int = 3) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<PlaylistEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let entity = try #require(try context.fetch(descriptor).first)
        entity.markSynced(version: version)
        try context.save()
    }

    private func isDirty(_ id: UUID, in container: ModelContainer) throws -> Bool {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<PlaylistEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try #require(try context.fetch(descriptor).first).hasLocalChanges
    }

    @Test("A newly created playlist has changes to upload")
    func newPlaylistIsDirty() throws {
        let (store, container) = try makeStore()
        let playlist = try #require(store.create(named: "Set"))
        #expect(try isDirty(playlist.id, in: container))
    }

    @Test("An update that changes nothing does not mark the playlist for upload")
    func noOpUpdateDoesNotDirty() throws {
        let (store, container) = try makeStore()
        let playlist = try #require(store.create(named: "Set"))
        try markSynced(playlist.id, in: container)

        // What the detail view does on appear: refresh snapshots, changing nothing.
        store.update(id: playlist.id) { _ in }
        #expect(try !isDirty(playlist.id, in: container), "Reading a playlist marked it dirty.")

        // Renaming to the name it already has is also a no-op.
        store.update(id: playlist.id) { $0.rename(to: "Set") }
        #expect(try !isDirty(playlist.id, in: container), "A no-op rename marked it dirty.")
    }

    @Test("A real edit does mark the playlist for upload")
    func realEditDirties() throws {
        let (store, container) = try makeStore()
        let playlist = try #require(store.create(named: "Set"))
        try markSynced(playlist.id, in: container)

        store.update(id: playlist.id) { $0.rename(to: "Renamed") }
        #expect(try isDirty(playlist.id, in: container), "A genuine edit must be uploaded.")
        #expect(store.playlist(id: playlist.id)?.name == "Renamed")
    }

    @Test("A local file and a Spotify track live in the same playlist, in order")
    func playlistMixesSources() throws {
        let (store, _) = try makeStore()
        let playlist = try #require(store.create(named: "Mixed"))

        let mp3 = Track(
            title: "Local One", artist: "Someone", duration: 120,
            source: .local, sourceID: "a.mp3"
        )
        let streamed = Track(
            title: "Streamed", artist: "Another", duration: 200,
            source: .spotify, sourceID: "4cOdK2wGLETKBW3PvgPWqT"
        )

        store.add(mp3, to: playlist.id)
        store.add(streamed, to: playlist.id)

        let saved = try #require(store.playlist(id: playlist.id))
        #expect(saved.trackCount == 2)
        #expect(saved.isCrossSource, "A playlist holding both sources must report itself mixed.")
        #expect(saved.sources == [.local, .spotify])

        // Order is insertion order, not grouped by source.
        #expect(saved.entries.map(\.source) == [.local, .spotify])
        #expect(saved.entries.map(\.sourceID) == ["a.mp3", "4cOdK2wGLETKBW3PvgPWqT"])

        // Duration sums across sources from the stored snapshots, so it is
        // answerable without reaching Spotify.
        #expect(saved.totalDuration == 320)
    }

    @Test("A mixed playlist survives being reloaded from the store")
    func mixedPlaylistPersists() throws {
        let (store, container) = try makeStore()
        let playlist = try #require(store.create(named: "Mixed"))

        store.add(Track(title: "L", artist: "A", duration: 10, source: .local, sourceID: "a.mp3"), to: playlist.id)
        store.add(Track(title: "S", artist: "B", duration: 20, source: .spotify, sourceID: "xyz"), to: playlist.id)

        // A fresh store over the same container: what a relaunch sees.
        let reopened = PlaylistStore(container: container, sources: [])
        let saved = try #require(reopened.playlist(id: playlist.id))

        #expect(saved.isCrossSource)
        #expect(saved.entries.map(\.source) == [.local, .spotify])
    }

    @Test("Adding a track marks the playlist for upload")
    func addingTrackDirties() throws {
        let (store, container) = try makeStore()
        let playlist = try #require(store.create(named: "Set"))
        try markSynced(playlist.id, in: container)

        store.add(
            Track(title: "A", artist: "B", duration: 10, source: .local, sourceID: "a.mp3"),
            to: playlist.id
        )
        #expect(try isDirty(playlist.id, in: container))
        #expect(store.playlist(id: playlist.id)?.trackCount == 1)
    }
}
