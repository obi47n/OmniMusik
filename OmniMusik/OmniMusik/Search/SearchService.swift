//
//  SearchService.swift
//  OmniMusik
//
//  One query, every source, concurrently.
//
//  Three properties this has to get right, none of which come for free:
//
//  Failure isolation — Apple Music being down, unauthorized, or slow must not cost
//  you your local results. Each source's outcome is captured independently and a
//  thrown error becomes a per-source note in the results, never a failed search.
//
//  Cancellation — typing "midnight" fires eight searches if you let it. Each new
//  query cancels the one in flight, and results are discarded if cancellation lands
//  while they're being collected, so a slow earlier query can't overwrite a fast
//  later one.
//
//  Debouncing — a 250ms pause before dispatching, so the network source isn't hit
//  on every keystroke.
//

import Foundation
import Observation

struct SearchSection: Identifiable, Sendable {
    let source: TrackSource
    let tracks: [Track]
    var id: TrackSource { source }
}

@MainActor
@Observable
final class SearchService {

    private(set) var sections: [SearchSection] = []
    private(set) var isSearching = false

    /// Sources that declined to answer, and why. Surfaced as a footnote rather than
    /// an error dialog — a partial result is still a useful result.
    private(set) var notes: [TrackSource: String] = [:]

    private(set) var hasSearched = false

    private let sources: [any MusicSource]
    private var inFlight: Task<Void, Never>?

    init(sources: [any MusicSource]) {
        self.sources = sources
    }

    func search(_ rawQuery: String) {
        inFlight?.cancel()

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clear()
            return
        }

        inFlight = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.performSearch(query)
        }
    }

    func clear() {
        inFlight?.cancel()
        inFlight = nil
        sections = []
        notes = [:]
        isSearching = false
        hasSearched = false
    }

    // MARK: - Fan-out

    private struct Outcome: Sendable {
        let source: TrackSource
        let tracks: [Track]
        let note: String?
    }

    private func performSearch(_ query: String) async {
        isSearching = true

        var collected: [TrackSource: [Track]] = [:]
        var collectedNotes: [TrackSource: String] = [:]

        await withTaskGroup(of: Outcome.self) { group in
            for source in sources {
                group.addTask {
                    guard await source.isAvailable() else {
                        return Outcome(
                            source: source.source,
                            tracks: [],
                            note: "\(source.source.displayName) isn't connected yet."
                        )
                    }
                    do {
                        let tracks = try await source.search(query)
                        return Outcome(source: source.source, tracks: tracks, note: nil)
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                        return Outcome(source: source.source, tracks: [], note: message)
                    }
                }
            }

            for await outcome in group {
                collected[outcome.source] = outcome.tracks
                if let note = outcome.note { collectedNotes[outcome.source] = note }
            }
        }

        // A newer query superseded this one while results were being gathered.
        guard !Task.isCancelled else { return }

        // Ordered by the canonical source order rather than by whichever source
        // happened to answer first, so results don't reshuffle between searches.
        sections = TrackSource.allCases.compactMap { source in
            guard let tracks = collected[source], !tracks.isEmpty else { return nil }
            return SearchSection(source: source, tracks: tracks)
        }
        notes = collectedNotes
        hasSearched = true
        isSearching = false
    }
}
