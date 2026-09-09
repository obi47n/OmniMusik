//
//  SourceConnectionCenter.swift
//  OmniMusik
//
//  Observable owner of every connectable source's state.
//
//  Exists so the UI has one thing to read rather than reaching into each source, and
//  so a source added later shows up in the account screen without that screen
//  changing. The same reasoning as `SearchService` fanning out over `[any
//  MusicSource]`: the list is the extension point.
//

import Foundation
import Observation

@MainActor
@Observable
final class SourceConnectionCenter {

    /// One row per connectable source, in canonical source order so the list does
    /// not reshuffle as states change.
    struct Row: Identifiable {
        let source: TrackSource
        let state: SourceConnectionState
        var id: TrackSource { source }
    }

    private(set) var rows: [Row] = []

    /// Surfaced by the account screen. Cancellation is not an error and never
    /// lands here.
    var errorMessage: String?

    private let sources: [any ConnectableSource]

    init(sources: [any ConnectableSource]) {
        self.sources = sources
        refresh()
    }

    var isEmpty: Bool { sources.isEmpty }

    func refresh() {
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.source, $0) })
        rows = TrackSource.allCases.compactMap { source in
            guard let connectable = byID[source] else { return nil }
            return Row(source: source, state: connectable.connectionState)
        }
    }

    func connect(_ source: TrackSource) async {
        guard let connectable = sources.first(where: { $0.source == source }) else { return }
        errorMessage = nil
        refresh()

        do {
            try await connectable.connect()

            // Connecting is a foreground action, and it is the moment this becomes
            // relevant: a queue mixing this service with local files will eventually
            // need to ask the person to come back. Asking later means asking from a
            // lock screen, where iOS shows no prompt at all.
            await PlaybackNotifier.requestIfNeededAfterConnecting()
        } catch SourceConnectionError.cancelled {
            // Backing out is an ordinary outcome, not a failure.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        refresh()
    }

    func disconnect(_ source: TrackSource) async {
        guard let connectable = sources.first(where: { $0.source == source }) else { return }
        await connectable.disconnect()
        refresh()
    }
}
