//
//  Playlist.swift
//  OmniMusik
//
//  Cross-source playlists — the feature the two-protocol architecture exists to
//  make possible.
//
//  The central problem: a playlist has to hold a local file and an Apple Music
//  track in the same ordered list, but those two things are persisted in
//  completely different places. Local tracks are rows in SwiftData. Apple Music
//  tracks are not stored at all — they are fetched live, because caching a catalog
//  that changes underneath you means serving stale copies of someone else's data.
//
//  So a playlist cannot hold `Track` values and it cannot hold SwiftData
//  relationships. It holds `PlaylistEntry`: the pair (source, sourceID) that
//  identifies a track anywhere, plus a denormalized snapshot of what it was called
//  when it was added.
//
//  That snapshot is the part worth defending. Without it, a playlist containing
//  Apple Music tracks renders as blank rows the moment the subscription lapses,
//  the account is unauthorized, or the network is gone — the entries are still
//  there, but nothing can say what they were. With it, the row still reads
//  "Midnight — Bicep" and is simply marked unplayable. A playlist should be able
//  to describe itself without asking permission from a server.
//
//  No framework imports, like the rest of Domain/. Every rule below is testable
//  without a store, a network, or a simulator.
//

import Foundation

/// One track's place in a playlist, identified in a way that survives the source
/// being unreachable.
struct PlaylistEntry: Identifiable, Hashable, Sendable, Codable {

    /// Identity of the *entry*, not of the track.
    ///
    /// Distinct from `sourceID` because the same track may legitimately appear
    /// more than once in one playlist — a set that opens and closes on the same
    /// record is a real thing people build. Giving each entry its own identity
    /// keeps reordering and deletion unambiguous when it does.
    let id: UUID

    let source: TrackSource
    let sourceID: String

    /// Snapshot taken at the moment of adding, so the playlist can render when
    /// its source cannot answer. Refreshed opportunistically whenever a source
    /// does resolve the entry, so a retitled local file eventually corrects.
    var title: String
    var artist: String
    var duration: TimeInterval

    init(
        id: UUID = UUID(),
        source: TrackSource,
        sourceID: String,
        title: String,
        artist: String,
        duration: TimeInterval
    ) {
        self.id = id
        self.source = source
        self.sourceID = sourceID
        self.title = title
        self.artist = artist
        self.duration = duration
    }

    init(snapshotting track: Track) {
        self.init(
            source: track.source,
            sourceID: track.sourceID,
            title: track.title,
            artist: track.artist,
            duration: track.duration
        )
    }

    /// Whether this entry refers to the same underlying track as another.
    /// Compares the source pair, deliberately ignoring `id` and the snapshot.
    func refersToSameTrack(as other: PlaylistEntry) -> Bool {
        source == other.source && sourceID == other.sourceID
    }
}

/// An ordered, cross-source list of tracks.
struct Playlist: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var entries: [PlaylistEntry]
    let createdAt: Date
    private(set) var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        entries: [PlaylistEntry] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Derived

extension Playlist {
    var isEmpty: Bool { entries.isEmpty }
    var trackCount: Int { entries.count }

    /// Sum of the snapshot durations, so it is answerable offline.
    var totalDuration: TimeInterval { entries.reduce(0) { $0 + $1.duration } }

    /// Which sources this playlist draws on. Drives the "spans two sources" badge,
    /// which is the visible payoff of the whole design.
    var sources: Set<TrackSource> { Set(entries.map(\.source)) }

    /// True when the playlist genuinely mixes sources, which is the case the
    /// architecture exists for and the one worth surfacing.
    var isCrossSource: Bool { sources.count > 1 }

    var formattedTotalDuration: String { Track.timeFormatter(totalDuration) }

    func contains(source: TrackSource, sourceID: String) -> Bool {
        entries.contains { $0.source == source && $0.sourceID == sourceID }
    }

    func contains(_ track: Track) -> Bool {
        contains(source: track.source, sourceID: track.sourceID)
    }
}

// MARK: - Mutation

extension Playlist {

    /// Appends a track.
    ///
    /// Duplicates are permitted by design — see `PlaylistEntry.id`. Callers that
    /// want "add unless already present" should check `contains(_:)` first, which
    /// keeps the policy at the call site instead of buried in here.
    mutating func append(_ track: Track) {
        entries.append(PlaylistEntry(snapshotting: track))
        touch()
    }

    mutating func append(contentsOf tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        entries.append(contentsOf: tracks.map(PlaylistEntry.init(snapshotting:)))
        touch()
    }

    mutating func remove(entryID: UUID) {
        let before = entries.count
        entries.removeAll { $0.id == entryID }
        if entries.count != before { touch() }
    }

    mutating func remove(atOffsets offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        entries.remove(atOffsets: offsets)
        touch()
    }

    /// Reorders, using the same (offsets, destination) convention as SwiftUI's
    /// `onMove` so the view layer needs no translation step.
    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !offsets.isEmpty else { return }
        entries.move(fromOffsets: offsets, toOffset: destination)
        touch()
    }

    /// Moves one entry to the position another currently occupies.
    ///
    /// The drag-and-drop counterpart to `move(fromOffsets:toOffset:)`. That one
    /// speaks SwiftUI's edit-mode convention, where the destination is an insertion
    /// point between rows; a drop names a *row*, and the two do not translate cleanly
    /// -- SwiftUI's destination is off by one in one direction and not the other,
    /// which is exactly the kind of arithmetic that belongs somewhere it can be
    /// tested rather than in a view.
    ///
    /// The rule: the dragged entry takes the target's place. Its index is read before
    /// the removal, so dropping the first row onto the last puts it last rather than
    /// second-to-last -- which is what dropping something on a row looks like it
    /// should do.
    ///
    /// Both identifiers are entry ids, not track ids: a playlist may legitimately
    /// hold the same track twice, and dragging one copy must not move the other.
    mutating func move(entryID: UUID, onto targetID: UUID) {
        guard entryID != targetID,
              let from = entries.firstIndex(where: { $0.id == entryID }),
              let to = entries.firstIndex(where: { $0.id == targetID })
        else { return }

        let moved = entries.remove(at: from)
        entries.insert(moved, at: min(to, entries.count))
        touch()
    }

    mutating func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        name = trimmed
        touch()
    }

    /// Corrects a stale snapshot from a track the source just resolved.
    ///
    /// Only writes when something actually differs, so opening a playlist does not
    /// mark every entry dirty and force a pointless save on every appearance.
    mutating func refreshSnapshot(forEntryID entryID: UUID, from track: Track) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let current = entries[index]
        guard current.title != track.title
                || current.artist != track.artist
                || current.duration != track.duration else { return }

        entries[index].title = track.title
        entries[index].artist = track.artist
        entries[index].duration = track.duration
        touch()
    }

    private mutating func touch() { updatedAt = .now }
}

// MARK: - Resolution

/// A playlist entry paired with the live track it resolved to, if any.
///
/// `track == nil` is an ordinary state, not an error: Apple Music is not connected,
/// or a local file was deleted out from under the playlist. The row still renders
/// from the snapshot and is marked unplayable.
struct ResolvedEntry: Identifiable, Sendable {
    let entry: PlaylistEntry
    let track: Track?

    var id: UUID { entry.id }
    var isPlayable: Bool { track != nil }

    /// Prefers live data when the source answered, falls back to the snapshot.
    var displayTitle: String { track?.title ?? entry.title }
    var displayArtist: String { track?.artist ?? entry.artist }
    var displayDuration: TimeInterval { track?.duration ?? entry.duration }
}

extension Array where Element == ResolvedEntry {
    /// The playable tracks, in playlist order. This is what gets handed to the
    /// coordinator as a queue: unplayable entries are skipped rather than
    /// producing a queue that stalls partway through.
    var playableTracks: [Track] { compactMap(\.track) }

    var unplayableCount: Int { filter { !$0.isPlayable }.count }
}
