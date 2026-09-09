//
//  SyncEpoch.swift
//  OmniMusik
//
//  Whether this device's recorded sync versions describe the server it is talking to.
//
//  `PlaylistSync` reads "the server does not have this playlist, and I last synced it
//  at version 7" as a deletion, and deleting is the right answer -- as long as the
//  absence really is a deletion. Against a database that was replaced, restored from
//  a backup, or restarted while it was in memory, the same absence means those
//  version numbers were never that server's, and honouring it destroys playlists
//  nobody deleted.
//
//  Nothing in the version numbers themselves can distinguish those two cases, which
//  is why this exists as a separate question asked before the table is consulted.
//

import Foundation

enum SyncEpochDecision: Equatable {

    /// The recorded versions came from this server's history. Reconcile as normal.
    case trustRecordedVersions

    /// They did not, or cannot be shown to have. Forget them, so every playlist looks
    /// like one that has never been uploaded and is pushed rather than deleted.
    case discardRecordedVersions
}

enum SyncEpochRule {

    /// - Parameters:
    ///   - stored: the epoch this device recorded at its last sync, or nil if it has
    ///     never recorded one.
    ///   - server: the epoch the server reports now.
    ///   - deviceHasSyncedPlaylists: whether this device holds any playlist carrying
    ///     a version it believes the server assigned.
    static func decide(
        stored: String?,
        server: String,
        deviceHasSyncedPlaylists: Bool
    ) -> SyncEpochDecision {
        guard let stored else {
            // No recorded epoch. Either this device has never synced -- in which case
            // there are no versions to distrust and nothing is at stake -- or it
            // synced before epochs existed, and there is no way to tell whether that
            // was against this database.
            //
            // Unverifiable is treated as replaced, because the two outcomes are not
            // symmetrical. Re-uploading a playlist the server already has costs a
            // request and produces a conflict a person can resolve; deleting one it
            // does not have costs the playlist, and nothing can bring it back.
            return deviceHasSyncedPlaylists ? .discardRecordedVersions : .trustRecordedVersions
        }

        return stored == server ? .trustRecordedVersions : .discardRecordedVersions
    }
}
