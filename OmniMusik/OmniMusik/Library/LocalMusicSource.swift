//
//  LocalMusicSource.swift
//  OmniMusik
//
//  Imported files as a searchable source.
//
//  Holds its own `ModelContext` rather than borrowing the view's. Search runs off
//  the back of user typing and shouldn't contend with the context SwiftUI is using
//  to drive `@Query`; a separate context on the same container keeps the two from
//  interfering.
//

import Foundation
import SwiftData

@MainActor
final class LocalMusicSource: MusicSource {

    nonisolated let source: TrackSource = .local
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    /// Local files are always available — there is nothing to authorize.
    func isAvailable() async -> Bool { true }

    func library() async throws -> [Track] {
        let descriptor = FetchDescriptor<LocalTrackEntity>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.asTrack)
    }

    /// `sourceID` for a local track is its file name inside the audio directory.
    func track(forSourceID sourceID: String) async throws -> Track? {
        var descriptor = FetchDescriptor<LocalTrackEntity>(
            predicate: #Predicate { $0.fileName == sourceID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.asTrack
    }

    func search(_ query: String) async throws -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // localizedStandardContains gives case- and diacritic-insensitive matching,
        // so "sonderjysk" finds "Sønderjysk" — which matters more than it sounds
        // for a music library full of stylized titles.
        let predicate = #Predicate<LocalTrackEntity> { entity in
            entity.title.localizedStandardContains(trimmed)
                || entity.artist.localizedStandardContains(trimmed)
        }

        let descriptor = FetchDescriptor<LocalTrackEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor).map(\.asTrack)
    }
}
