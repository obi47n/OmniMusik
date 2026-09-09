//
//  PlaylistSync.swift
//  OmniMusik
//
//  What to do with a playlist that exists in two places.
//
//  Deliberately a pure function over three inputs, in Domain/ with no framework
//  imports. Sync bugs are the hardest kind to reproduce — they need two devices, a
//  particular interleaving, and often a network failure at the right moment — so the
//  decision itself is separated from everything that makes it hard to test. The
//  service that performs the resulting action is thin and boring on purpose.
//
//  The three inputs:
//    - the local playlist, and whether it has edits that have never been uploaded
//    - `syncedVersion`: the server version this device last successfully matched
//    - the remote playlist, if the server still has one
//
//  `syncedVersion` is what makes the difference between "the server changed" and
//  "I changed" answerable. Comparing timestamps instead would be guesswork: clocks
//  on two devices disagree, and an edit made offline can carry a later timestamp
//  than the server state it is behind.
//

import Foundation

enum SyncDecision: Equatable {
    /// Local is ahead. Upload it.
    case push

    /// Remote is ahead and nothing local would be lost. Take the server's copy.
    case pull

    /// Both sides match. Do nothing — the common case, and it should stay cheap.
    case upToDate

    /// The playlist was deleted on another device and this one has no edits worth
    /// keeping. Remove it locally.
    case deleteLocal

    /// Both sides moved. A person has to choose; nothing here may silently discard
    /// someone's work.
    case conflict
}

enum PlaylistSync {

    /// Decides what a single playlist needs.
    ///
    /// - Parameters:
    ///   - hasLocalChanges: whether the local copy has edits not yet uploaded.
    ///   - syncedVersion: the server version this device last matched, or nil if it
    ///     has never been uploaded.
    ///   - remoteVersion: the server's current version, or nil if the server has no
    ///     such playlist.
    static func decide(
        hasLocalChanges: Bool,
        syncedVersion: Int?,
        remoteVersion: Int?
    ) -> SyncDecision {
        switch (remoteVersion, syncedVersion) {

        case (nil, nil):
            // Created here and never uploaded.
            return .push

        case (nil, .some):
            // The server had it and no longer does, so it was deleted elsewhere.
            // With no local edits, honour the deletion. With local edits, refuse to
            // choose: re-creating something a person deleted on another device is
            // just as wrong as discarding work they did on this one.
            return hasLocalChanges ? .conflict : .deleteLocal

        case (.some, nil):
            // The server has this id but this device has never synced it. Two
            // independent histories under one identity — rare, and not something to
            // resolve by guessing.
            return .conflict

        case let (.some(remote), .some(synced)):
            if remote == synced {
                // The server has not moved since this device last matched it, so
                // local edits are strictly ahead.
                return hasLocalChanges ? .push : .upToDate
            }
            // The server moved. Safe to take unless this device also has edits.
            return hasLocalChanges ? .conflict : .pull
        }
    }
}
