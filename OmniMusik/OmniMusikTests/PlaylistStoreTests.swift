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
