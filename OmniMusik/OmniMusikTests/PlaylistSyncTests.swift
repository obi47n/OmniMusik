//
//  PlaylistSyncTests.swift
//  OmniMusikTests
//
//  The sync decision table.
//
//  Every one of these cases needs two devices, a particular interleaving, and often a
//  network failure at the right moment to reproduce by hand. That is exactly why the
//  decision was extracted into a pure function: the conditions that make sync bugs
//  hard to find are all in the plumbing, and none of them are in here.
//
//  The cases that matter most are the ones where the answer is `conflict`. Anything
//  that silently resolves those is discarding somebody's work.
//

import Foundation
import Testing
@testable import OmniMusik

@Suite("Playlist sync decisions")
struct PlaylistSyncTests {

    // MARK: - Nothing on the server

    @Test("A playlist created locally and never uploaded is pushed")
    func newLocalIsPushed() {
        #expect(
            PlaylistSync.decide(hasLocalChanges: true, syncedVersion: nil, remoteVersion: nil) == .push
        )
    }

    @Test("A synced playlist that vanished from the server is deleted locally when clean")
    func remoteDeletionIsHonouredWhenClean() {
        #expect(
            PlaylistSync.decide(hasLocalChanges: false, syncedVersion: 3, remoteVersion: nil) == .deleteLocal
        )
    }

    @Test("A playlist deleted remotely but edited locally is a conflict, not a deletion")
    func remoteDeletionWithLocalEditsConflicts() {
        // Re-creating something deleted on another device is just as wrong as
        // discarding work done on this one, so neither happens automatically.
        #expect(
            PlaylistSync.decide(hasLocalChanges: true, syncedVersion: 3, remoteVersion: nil) == .conflict
        )
    }

    // MARK: - Present on both sides

    @Test("Matching versions with no local edits needs no work")
    func matchingAndCleanIsUpToDate() {
        #expect(
            PlaylistSync.decide(hasLocalChanges: false, syncedVersion: 5, remoteVersion: 5) == .upToDate
        )
    }

    @Test("Local edits on top of the version the server still holds are pushed")
    func localEditsOnCurrentVersionArePushed() {
        #expect(
            PlaylistSync.decide(hasLocalChanges: true, syncedVersion: 5, remoteVersion: 5) == .push
        )
    }

    @Test("A moved server and a clean local copy pulls")
    func remoteAheadAndCleanPulls() {
        #expect(
            PlaylistSync.decide(hasLocalChanges: false, syncedVersion: 5, remoteVersion: 7) == .pull
        )
    }

    @Test("Both sides moved is a conflict")
    func bothMovedConflicts() {
        // The case the whole design exists for. Anything other than `conflict` here
        // silently discards one side's edits.
        #expect(
            PlaylistSync.decide(hasLocalChanges: true, syncedVersion: 5, remoteVersion: 7) == .conflict
        )
    }

    // MARK: - Same id, no shared history

    @Test("A server playlist this device has never synced is a conflict")
    func unsyncedLocalAgainstExistingRemoteConflicts() {
        // Two independent histories under one identity. Rare, and not something to
        // resolve by guessing which is authoritative.
        #expect(
            PlaylistSync.decide(hasLocalChanges: true, syncedVersion: nil, remoteVersion: 2) == .conflict
        )
        #expect(
            PlaylistSync.decide(hasLocalChanges: false, syncedVersion: nil, remoteVersion: 2) == .conflict
        )
    }

    // MARK: - Properties of the table

    @Test("No input combination ever silently discards local edits")
    func localEditsAreNeverSilentlyDiscarded() {
        // A pull or a local delete overwrites whatever is here, so neither may ever
        // be chosen while there are unsynced local changes. Asserted across the whole
        // input space rather than case by case, so a future edit to the table cannot
        // quietly break the guarantee.
        let versions: [Int?] = [nil, 0, 1, 5]

        for synced in versions {
            for remote in versions {
                let decision = PlaylistSync.decide(
                    hasLocalChanges: true,
                    syncedVersion: synced,
                    remoteVersion: remote
                )
                #expect(
                    decision != .pull && decision != .deleteLocal,
                    "synced=\(String(describing: synced)) remote=\(String(describing: remote)) chose \(decision) with unsynced local edits"
                )
            }
        }
    }

    @Test("A clean local copy is never pushed, because there is nothing to push")
    func cleanCopiesAreNeverPushed() {
        let versions: [Int?] = [0, 1, 5]

        for synced in versions {
            for remote in versions {
                let decision = PlaylistSync.decide(
                    hasLocalChanges: false,
                    syncedVersion: synced,
                    remoteVersion: remote
                )
                #expect(decision != .push)
            }
        }
    }
}
