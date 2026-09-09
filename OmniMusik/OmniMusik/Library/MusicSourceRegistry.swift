//
//  MusicSourceRegistry.swift
//  OmniMusik
//
//  The list of sources, available to any view that needs to build its own query.
//
//  Exists because `SearchService` is stateful — it owns the current query, its
//  results and the in-flight task — and two screens searching at once would
//  otherwise fight over one instance. The song picker creates its own service from
//  this list rather than borrowing the Search tab's.
//

import Foundation
import Observation

@Observable
final class MusicSourceRegistry {
    let sources: [any MusicSource]

    init(sources: [any MusicSource]) {
        self.sources = sources
    }
}
