//
//  LibraryStore.swift
//  OmniMusik
//
//  Non-local library content.
//
//  Local tracks deliberately do not flow through here — they come from SwiftData's
//  `@Query`, which keeps the list live as imports and deletions happen. Routing them
//  through a manually-refreshed store would trade that reactivity for uniformity
//  that only helps the code, not the user.
//
//  So the unified library is a merge of one reactive source and N fetched ones,
//  which is the honest shape of the problem rather than a wart.
//

import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {

    private(set) var remoteTracks: [Track] = []
    private(set) var notes: [TrackSource: String] = [:]
    private(set) var isLoading = false

    private let sources: [any MusicSource]

    init(sources: [any MusicSource]) {
        // Local content arrives via @Query; this store owns everything else.
        self.sources = sources.filter { $0.source != .local }
    }

    func refresh() async {
        guard !sources.isEmpty else { return }
        isLoading = true

        var collected: [Track] = []
        var collectedNotes: [TrackSource: String] = [:]

        for source in sources {
            guard await source.isAvailable() else {
                collectedNotes[source.source] = "\(source.source.displayName) isn't connected yet."
                continue
            }
            do {
                collected.append(contentsOf: try await source.library())
            } catch {
                collectedNotes[source.source] =
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        remoteTracks = collected
        notes = collectedNotes
        isLoading = false
    }
}
