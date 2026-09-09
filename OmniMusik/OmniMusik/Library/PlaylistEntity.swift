//
//  PlaylistEntity.swift
//  OmniMusik
//
//  SwiftData persistence for playlists.
//
//  Entries are stored as encoded JSON in a single property rather than as a
//  SwiftData relationship to a child model. Three reasons, and this is the design
//  question most worth being able to answer:
//
//  1. Order is the whole point of a playlist, and SwiftData relationships are
//     unordered sets. Preserving order through a relationship means carrying an
//     explicit position column and re-numbering every sibling on each move, which
//     is a lot of machinery to reimplement what an array already gives.
//
//  2. Entries are never queried independently. Nothing asks "which playlists
//     contain this track" — the access pattern is always "load this playlist,
//     show its entries in order". A relationship buys indexing nobody uses.
//
//  3. Entries must be able to describe Apple Music tracks, which have no row
//     anywhere in this store. A relationship would have to point at
//     `LocalTrackEntity`, which would quietly make cross-source playlists
//     impossible — the exact thing the feature exists to do.
//
//  The tradeoff, stated honestly: entries are opaque to the query engine, so a
//  future "playlists containing this track" screen would need a scan or a
//  secondary index. That is a fair price for ordering and cross-source support.
//

import Foundation
import SwiftData

@Model
final class PlaylistEntity {
    #Index<PlaylistEntity>([\.updatedAt])

    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    /// JSON-encoded `[PlaylistEntry]`. See the type comment for why this is not
    /// a relationship.
    var entriesData: Data

    /// The server version this device last successfully matched, or nil if this
    /// playlist has never been uploaded.
    ///
    /// Sync decisions are made from this rather than from timestamps. Clocks on two
    /// devices disagree, and an edit made offline can carry a later timestamp than
    /// the server state it is actually behind, so comparing dates would be guesswork.
    var syncedVersion: Int?

    /// Whether there are edits here that have not been uploaded.
    ///
    /// Set on every local mutation and cleared only by a successful sync. A new
    /// playlist starts true because it exists nowhere else yet.
    var hasLocalChanges: Bool = true

    init(
        id: UUID = UUID(),
        name: String,
        entries: [PlaylistEntry] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entriesData = (try? JSONEncoder().encode(entries)) ?? Data()
        self.syncedVersion = nil
        self.hasLocalChanges = true
    }
}

extension PlaylistEntity {

    /// Decoded entries, or empty when the blob is from an older schema.
    ///
    /// A playlist that fails to decode is degraded, not fatal: the row still has
    /// a name and the person can delete or rebuild it. Trapping here would make
    /// one bad record take down the whole screen.
    var entries: [PlaylistEntry] {
        get { (try? JSONDecoder().decode([PlaylistEntry].self, from: entriesData)) ?? [] }
        set {
            guard let encoded = try? JSONEncoder().encode(newValue) else { return }
            entriesData = encoded
            updatedAt = .now
        }
    }

    /// The domain value this row represents. The UI works with `Playlist`; this
    /// type exists only at the persistence boundary.
    var asPlaylist: Playlist {
        Playlist(
            id: id,
            name: name,
            entries: entries,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Writes a mutated domain value back onto the row, marking it for upload.
    func apply(_ playlist: Playlist) {
        name = playlist.name
        entries = playlist.entries
        updatedAt = playlist.updatedAt
        hasLocalChanges = true
    }

    /// Adopts the server's copy after a successful sync, leaving nothing to upload.
    func adoptRemote(name: String, entries: [PlaylistEntry], updatedAt: Date, version: Int) {
        self.name = name
        self.entries = entries
        self.updatedAt = updatedAt
        self.syncedVersion = version
        self.hasLocalChanges = false
    }

    /// Records that the local copy is now what the server holds.
    func markSynced(version: Int) {
        syncedVersion = version
        hasLocalChanges = false
    }
}
