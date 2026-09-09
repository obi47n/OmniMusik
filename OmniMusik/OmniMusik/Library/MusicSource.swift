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

    /// Resolves one track from the identifier this source issued for it.
    ///
    /// Added for playlists, which store `(source, sourceID)` pairs rather than
    /// tracks — see `PlaylistEntry`. Returning nil means "this source cannot
    /// supply that track right now", which covers both a deleted local file and
    /// a source that is simply not connected. That is an ordinary answer, not a
    /// failure, so it is nil rather than a throw.
    func track(forSourceID sourceID: String) async throws -> Track?
}

extension MusicSource {
    /// Sources that cannot yet resolve individual identifiers inherit this.
    /// A playlist entry from such a source renders from its stored snapshot and
    /// is marked unplayable, which is exactly the intended behaviour while
    /// Apple Music is stubbed.
    func track(forSourceID sourceID: String) async throws -> Track? { nil }
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
