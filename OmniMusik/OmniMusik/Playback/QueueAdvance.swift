//
//  QueueAdvance.swift
//  OmniMusik
//
//  Where the queue goes when the track it wanted cannot start.
//
//  Extracted from the coordinator for the same reason as `PlaylistSync`: the rule is
//  pure, the code around it is not. Deciding this inside `PlaybackCoordinator` means
//  it can only be exercised through `UIApplication`, an audio session and a live
//  `MPNowPlayingInfoCenter` -- so in practice it would not be exercised at all, and
//  the failure mode is a queue that either stops early or never stops looking.
//

import Foundation

enum QueueAdvance {

    /// The next position at or after `index + 1` holding a track that can start now,
    /// or `nil` when the rest of the queue cannot.
    ///
    /// `canStart` answers only "could this source begin playing at this moment",
    /// which is not a property of the track: the same Spotify track is playable with
    /// the app on screen and not playable behind a lock screen, because waking
    /// another app is a foreground-only privilege. So the caller supplies it rather
    /// than the queue knowing.
    ///
    /// Strictly forward and bounded by the queue's end. That matters more than it
    /// looks: the caller starts the returned track, starting can fail with the same
    /// foreground problem, and the failure path lands back here. Because every pass
    /// begins after the previous one, that chain walks the queue once and stops --
    /// no counter needed to prove it terminates.
    static func nextPlayableIndex(
        after index: Int,
        in sources: [TrackSource],
        canStart: (TrackSource) -> Bool
    ) -> Int? {
        var candidate = max(index, -1) + 1
        while candidate < sources.count {
            if canStart(sources[candidate]) { return candidate }
            candidate += 1
        }
        return nil
    }
}
