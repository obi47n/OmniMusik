//
//  MusicSource.swift
//  OmniMusik
//
//  The content-side counterpart to `PlaybackProvider`.
//
//  `PlaybackProvider` answers "how is this track played"; `MusicSource` answers
//  "where do tracks come from". Keeping them separate matters because the two do
//  not line up one-to-one — a source can be browsable while playback is
//  unavailable (Apple Music with a lapsed subscription), and a provider can play
//  tracks a source no longer lists.
//
//  Both return the same `Track` type, so by the time anything reaches the UI the
//  distinction between a file on disk and a row in Apple's catalog is gone.
//
//  Sendable, and the methods are async, so a search can fan out across sources
//  concurrently without each one blocking the next.
//

import Foundation

protocol MusicSource: Sendable {
    nonisolated var source: TrackSource { get }

    /// Whether this source can currently answer queries. A source that isn't
    /// authorized or configured reports false rather than throwing on every call,
    /// so the UI can offer a way to connect it instead of showing an error.
    func isAvailable() async -> Bool

    /// Everything this source knows about, for the unified library.
    func library() async throws -> [Track]

    func search(_ query: String) async throws -> [Track]
}

enum MusicSourceError: LocalizedError {
    case notAuthorized(TrackSource)
    case notConfigured(TrackSource)
    case requestFailed(TrackSource, String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let source):
            "\(source.displayName) hasn't been authorized yet."
        case .notConfigured(let source):
            "\(source.displayName) isn't set up yet."
        case .requestFailed(let source, let detail):
            "\(source.displayName) request failed: \(detail)"
        }
    }
}
