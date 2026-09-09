//
//  SyncEpochTests.swift
//  OmniMusikTests
//
//  Whether recorded versions can be trusted.
//
//  Every case here is a data-loss case if it goes the wrong way, and none of them can
//  be reproduced casually: they need a server whose database was replaced underneath
//  a client that had already synced against it. That is a Tuesday for a developer
//  restarting a service and close to impossible to stage deliberately, which is
//  exactly the argument for the rule being a pure function.
//

import Foundation
import Testing
@testable import OmniMusik

@Suite("Sync epoch")
struct SyncEpochTests {

    @Test("The same server is trusted")
    func sameEpoch() {
        #expect(
            SyncEpochRule.decide(stored: "abc", server: "abc", deviceHasSyncedPlaylists: true)
                == .trustRecordedVersions
        )
    }

    /// The case that started this: a development server restarted with an in-memory
    /// database, so every synced playlist looked deleted.
    @Test("A replaced server is not trusted")
    func changedEpoch() {
        #expect(
            SyncEpochRule.decide(stored: "abc", server: "xyz", deviceHasSyncedPlaylists: true)
                == .discardRecordedVersions
        )
    }

    /// A device upgrading from a build that had no epochs. It holds versions and no
    /// way to say where they came from, and unverifiable has to mean unsafe: the two
    /// mistakes are not the same size. Re-uploading costs a request; deleting costs
    /// the playlist.
    @Test("No recorded epoch with synced playlists is not trusted")
    func firstContactWithSyncedPlaylists() {
        #expect(
            SyncEpochRule.decide(stored: nil, server: "abc", deviceHasSyncedPlaylists: true)
                == .discardRecordedVersions
        )
    }

    /// A device that has never synced. Nothing to distrust, so nothing to discard --
    /// and getting this wrong would make every first sync do pointless work.
    @Test("No recorded epoch and nothing synced proceeds normally")
    func firstContactWithNothingSynced() {
        #expect(
            SyncEpochRule.decide(stored: nil, server: "abc", deviceHasSyncedPlaylists: false)
                == .trustRecordedVersions
        )
    }

    /// A replaced server is a replaced server whether or not anything is at stake.
    @Test("A replaced server with nothing synced is harmless either way")
    func changedEpochWithNothingSynced() {
        #expect(
            SyncEpochRule.decide(stored: "abc", server: "xyz", deviceHasSyncedPlaylists: false)
                == .discardRecordedVersions
        )
    }
}
