//
//  PlaylistEntryCodingTests.swift
//  OmniMusikTests
//
//  Playlist entries are persisted as encoded JSON inside `PlaylistEntity`, so
//  their Codable conformance is load-bearing: a change that breaks it turns every
//  saved playlist into an empty list, and `PlaylistEntity.entries` swallows the
//  decode failure by design so nothing would be logged.
//

import Foundation
import Testing
@testable import OmniMusik

@Suite("PlaylistEntry coding")
struct PlaylistEntryCodingTests {

    @Test("Entries round trip with identity and order intact")
    func entriesRoundTrip() throws {
        let entries = [
            PlaylistEntry(source: .local, sourceID: "a.mp3", title: "A", artist: "Artist A", duration: 100),
            PlaylistEntry(source: .appleMusic, sourceID: "12345", title: "B", artist: "Artist B", duration: 200)
        ]

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([PlaylistEntry].self, from: data)

        #expect(decoded == entries)
        #expect(decoded.map(\.id) == entries.map(\.id), "Entry identity must survive persistence.")
        #expect(decoded[0].source == .local)
        #expect(decoded[1].source == .appleMusic)
    }

    @Test("Order is preserved through encoding, because order is the point")
    func orderIsPreserved() throws {
        let titles = ["First", "Second", "Third", "Fourth"]
        let entries = titles.map {
            PlaylistEntry(source: .local, sourceID: "\($0).mp3", title: $0, artist: "X", duration: 10)
        }

        let decoded = try JSONDecoder().decode(
            [PlaylistEntry].self,
            from: try JSONEncoder().encode(entries)
        )

        #expect(decoded.map(\.title) == titles)
    }

    @Test("An empty entry list round trips as empty rather than failing")
    func emptyRoundTrips() throws {
        let decoded = try JSONDecoder().decode(
            [PlaylistEntry].self,
            from: try JSONEncoder().encode([PlaylistEntry]())
        )
        #expect(decoded.isEmpty)
    }
}
