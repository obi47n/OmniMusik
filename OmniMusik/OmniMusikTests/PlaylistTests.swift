//
//  PlaylistTests.swift
//  OmniMusikTests
//
//  Unit coverage for the playlist domain rules.
//
//  These are the rules most worth testing in the whole app: they are pure value
//  semantics with no store, no network, and no simulator, and they encode
//  decisions that are easy to break silently later — duplicates being legal,
//  reordering being stable, and snapshot refresh not dirtying a record that has
//  not actually changed.
//

import Foundation
import Testing
@testable import OmniMusik

@Suite("Playlist")
struct PlaylistTests {

    // MARK: - Fixtures

    private func track(
        _ title: String,
        source: TrackSource = .local,
        sourceID: String? = nil,
        duration: TimeInterval = 100
    ) -> Track {
        Track(
            title: title,
            artist: "\(title) Artist",
            duration: duration,
            source: source,
            sourceID: sourceID ?? "\(title).mp3"
        )
    }

    // MARK: - Adding

    @Test("Appending snapshots the track rather than referencing it")
    func appendSnapshotsTrack() {
        var playlist = Playlist(name: "Set")
        playlist.append(track("Midnight", duration: 240))

        #expect(playlist.trackCount == 1)
        let entry = try! #require(playlist.entries.first)
        #expect(entry.title == "Midnight")
        #expect(entry.artist == "Midnight Artist")
        #expect(entry.duration == 240)
        #expect(entry.source == .local)
        #expect(entry.sourceID == "Midnight.mp3")
    }

    @Test("The same track may appear twice, and each copy is independently removable")
    func duplicatesAreAllowedAndIndependent() {
        var playlist = Playlist(name: "Set")
        let opener = track("Opener")
        playlist.append(opener)
        playlist.append(track("Middle"))
        playlist.append(opener)

        #expect(playlist.trackCount == 3)

        // Both copies share a sourceID but not an entry id, which is what makes
        // removing exactly one of them well defined.
        let first = playlist.entries[0]
        let last = playlist.entries[2]
        #expect(first.refersToSameTrack(as: last))
        #expect(first.id != last.id)

        playlist.remove(entryID: first.id)
        #expect(playlist.trackCount == 2)
        #expect(playlist.entries.map(\.title) == ["Middle", "Opener"])
    }

    @Test("Appending an empty batch leaves the playlist untouched")
    func appendEmptyBatchIsNoOp() {
        var playlist = Playlist(name: "Set")
        let before = playlist.updatedAt
        playlist.append(contentsOf: [])

        #expect(playlist.isEmpty)
        #expect(playlist.updatedAt == before)
    }

    // MARK: - Ordering

    @Test("Moving reorders using SwiftUI's offset convention")
    func moveReorders() {
        var playlist = Playlist(name: "Set")
        playlist.append(contentsOf: [track("A"), track("B"), track("C")])

        playlist.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(playlist.entries.map(\.title) == ["B", "C", "A"])
    }

    @Test("Removing at offsets deletes exactly those positions")
    func removeAtOffsets() {
        var playlist = Playlist(name: "Set")
        playlist.append(contentsOf: [track("A"), track("B"), track("C")])

        playlist.remove(atOffsets: IndexSet([0, 2]))
        #expect(playlist.entries.map(\.title) == ["B"])
    }

    // MARK: - Naming

    @Test("Renaming trims whitespace and refuses an empty name")
    func renameTrimsAndRejectsEmpty() {
        var playlist = Playlist(name: "Original")

        playlist.rename(to: "   Late Night   ")
        #expect(playlist.name == "Late Night")

        playlist.rename(to: "    ")
        #expect(playlist.name == "Late Night", "An all-whitespace name must not be accepted.")
    }

    @Test("Renaming to the current name does not mark the playlist edited")
    func renameToSameNameDoesNotTouch() {
        var playlist = Playlist(name: "Late Night")
        let before = playlist.updatedAt

        playlist.rename(to: "Late Night")
        #expect(playlist.updatedAt == before)
    }

    // MARK: - Membership

    @Test("Membership matches on the source pair, not on entry identity")
    func containsMatchesSourcePair() {
        var playlist = Playlist(name: "Set")
        let midnight = track("Midnight")
        playlist.append(midnight)

        #expect(playlist.contains(midnight))
        #expect(playlist.contains(source: .local, sourceID: "Midnight.mp3"))

        // Same identifier, different source, is a different track.
        #expect(!playlist.contains(source: .appleMusic, sourceID: "Midnight.mp3"))
    }

    // MARK: - Derived values

    @Test("Total duration sums snapshots, so it is answerable offline")
    func totalDurationSumsSnapshots() {
        var playlist = Playlist(name: "Set")
        playlist.append(contentsOf: [
            track("A", duration: 90),
            track("B", duration: 150)
        ])

        #expect(playlist.totalDuration == 240)
        #expect(playlist.formattedTotalDuration == "4:00")
    }

    @Test("A playlist is only cross-source when it genuinely mixes sources")
    func crossSourceOnlyWhenMixed() {
        var playlist = Playlist(name: "Set")
        playlist.append(track("A", source: .local))
        #expect(!playlist.isCrossSource)
        #expect(playlist.sources == [.local])

        playlist.append(track("B", source: .appleMusic, sourceID: "12345"))
        #expect(playlist.isCrossSource)
        #expect(playlist.sources == [.local, .appleMusic])
    }

    // MARK: - Snapshot refresh

    @Test("Refreshing a snapshot with identical data does not dirty the record")
    func refreshWithIdenticalDataDoesNotTouch() {
        var playlist = Playlist(name: "Set")
        let midnight = track("Midnight", duration: 240)
        playlist.append(midnight)
        let entryID = playlist.entries[0].id
        let before = playlist.updatedAt

        playlist.refreshSnapshot(forEntryID: entryID, from: midnight)

        #expect(playlist.updatedAt == before, "Opening a playlist must not force a save.")
    }

    @Test("Refreshing a snapshot adopts corrected metadata")
    func refreshAdoptsNewMetadata() {
        var playlist = Playlist(name: "Set")
        playlist.append(track("Old Title", duration: 100))
        let entryID = playlist.entries[0].id

        let corrected = Track(
            title: "Correct Title",
            artist: "Correct Artist",
            duration: 175,
            source: .local,
            sourceID: "Old Title.mp3"
        )
        playlist.refreshSnapshot(forEntryID: entryID, from: corrected)

        #expect(playlist.entries[0].title == "Correct Title")
        #expect(playlist.entries[0].artist == "Correct Artist")
        #expect(playlist.entries[0].duration == 175)
    }

    @Test("Refreshing an unknown entry is ignored")
    func refreshUnknownEntryIsIgnored() {
        var playlist = Playlist(name: "Set")
        playlist.append(track("A"))
        let before = playlist.updatedAt

        playlist.refreshSnapshot(forEntryID: UUID(), from: track("B"))
        #expect(playlist.updatedAt == before)
    }

    // MARK: - Resolution

    @Test("A queue built from a playlist skips entries no source can supply")
    func unplayableEntriesAreSkippedInQueue() {
        let playable = track("Local One")
        let entries = [
            ResolvedEntry(entry: PlaylistEntry(snapshotting: playable), track: playable),
            ResolvedEntry(
                entry: PlaylistEntry(
                    source: .appleMusic,
                    sourceID: "12345",
                    title: "Streamed",
                    artist: "Someone",
                    duration: 200
                ),
                track: nil
            )
        ]

        #expect(entries.playableTracks.count == 1)
        #expect(entries.playableTracks.first?.title == "Local One")
        #expect(entries.unplayableCount == 1)
    }

    @Test("An unresolved entry still renders from its stored snapshot")
    func unresolvedEntryStillDescribesItself() {
        let entry = PlaylistEntry(
            source: .appleMusic,
            sourceID: "12345",
            title: "Glue",
            artist: "Bicep",
            duration: 320
        )
        let resolved = ResolvedEntry(entry: entry, track: nil)

        #expect(!resolved.isPlayable)
        #expect(resolved.displayTitle == "Glue")
        #expect(resolved.displayArtist == "Bicep")
        #expect(resolved.displayDuration == 320)
    }

    @Test("Live data wins over a stale snapshot when the source answered")
    func resolvedEntryPrefersLiveData() {
        let entry = PlaylistEntry(
            source: .local,
            sourceID: "a.mp3",
            title: "Stale",
            artist: "Stale Artist",
            duration: 10
        )
        let live = Track(
            title: "Fresh",
            artist: "Fresh Artist",
            duration: 200,
            source: .local,
            sourceID: "a.mp3"
        )
        let resolved = ResolvedEntry(entry: entry, track: live)

        #expect(resolved.isPlayable)
        #expect(resolved.displayTitle == "Fresh")
        #expect(resolved.displayDuration == 200)
    }
}
