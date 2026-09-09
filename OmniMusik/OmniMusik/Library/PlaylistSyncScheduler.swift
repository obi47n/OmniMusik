//
//  PlaylistSyncScheduler.swift
//  OmniMusik
//
//  Decides when to sync. `PlaylistSyncService` decides what a sync does.
//
//  Sync used to happen only when someone pressed a button, which made the button the
//  feature: an edit made on the phone did not exist anywhere else until a person
//  remembered to press it, and the web client -- which has no way to know that -- just
//  showed stale playlists. A person should not have to know a sync protocol exists.
//
//  What this is not: a queue. The queue is already in the database. Every edited row
//  carries `hasLocalChanges`, which survives a crash, a force-quit and a flat battery,
//  and `PlaylistSyncService` pushes whatever carries it whenever it runs. So nothing
//  here is load-bearing for correctness -- a missed trigger delays an edit, it never
//  loses one. That is what makes it safe to coalesce aggressively.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PlaylistSyncScheduler {

    /// How long to wait for edits to stop before syncing.
    ///
    /// Adding five tracks to a playlist is five writes in a few seconds. Syncing each
    /// one means five round trips to push what one would carry, and five chances for
    /// the server to move underneath the next -- which is a conflict, reported to a
    /// person, for something they experienced as a single action.
    private let quietPeriod: Duration

    private let service: PlaylistSyncService

    /// Called after each sync so the store re-reads. The sync service writes through
    /// its own `ModelContext`, so rows pulled from the server are on disk but not in
    /// the store's memory until it looks again.
    private let didSync: () -> Void

    private var debounce: Task<Void, Never>?

    /// A hint, not a record. See the note above: the real pending state is in the
    /// database. This only avoids pointless network calls.
    private var mayHaveUnsyncedEdits = false

    init(
        service: PlaylistSyncService,
        quietPeriod: Duration = .seconds(2),
        didSync: @escaping () -> Void
    ) {
        self.service = service
        self.quietPeriod = quietPeriod
        self.didSync = didSync
    }

    // MARK: - Triggers

    /// Something changed on this device.
    ///
    /// Coalesced: each new edit cancels the previous wait and starts another, so a
    /// burst of edits produces one sync after the burst rather than one per edit.
    func playlistsChangedLocally() {
        mayHaveUnsyncedEdits = true

        debounce?.cancel()
        debounce = Task { [quietPeriod] in
            try? await Task.sleep(for: quietPeriod)
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    /// The app came to the foreground.
    ///
    /// Immediate rather than debounced, and it runs even with nothing to push: this
    /// is the moment to *pull*, because anything edited on the web client happened
    /// while this app was not running to hear about it.
    func appBecameActive() {
        debounce?.cancel()
        debounce = Task { await run() }
    }

    /// The app is leaving the screen.
    ///
    /// A pending debounce would be suspended along with the app and might never
    /// resume, so anything waiting has to go now. The background-task assertion buys
    /// the seconds a request needs; without it iOS can suspend mid-flight, and the
    /// edit would then wait for the next launch.
    func appIsLeaving() async {
        guard mayHaveUnsyncedEdits else { return }

        debounce?.cancel()
        debounce = nil

        let assertion = UIApplication.shared.beginBackgroundTask(withName: "Playlist sync")
        await run()
        if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
    }

    // MARK: - Private

    private func run() async {
        guard service.isConfigured else { return }

        await service.sync(reason: .automatic)
        didSync()

        // A failure leaves the edits local and still flagged, so the next trigger
        // picks them up. Nothing to retry here -- retrying on a timer against an
        // unreachable server is how an app burns a battery it cannot spend.
        if case .failed = service.status {
            mayHaveUnsyncedEdits = true
        } else {
            mayHaveUnsyncedEdits = false
        }
    }
}
