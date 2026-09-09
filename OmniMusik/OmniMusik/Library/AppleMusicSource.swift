//
//  AppleMusicSource.swift
//  OmniMusik
//
//  Apple Music catalog and library access.
//
//  Deliberately a stub reporting itself unavailable. The MusicKit App Service is
//  pending on the developer account, and this is the shape the real implementation
//  will take: `MusicCatalogSearchRequest` for the catalog, `MusicLibraryRequest`
//  for the user's own library, both normalized into `Track`.
//
//  It exists now rather than later so the unified library and the search fan-out
//  are built against two sources from the start. Code written against a single
//  source and generalized afterwards tends to leak that source's assumptions
//  everywhere; a second source that answers "not yet" prevents that.
//

import Foundation

@MainActor
final class AppleMusicSource: MusicSource {

    nonisolated let source: TrackSource = .appleMusic

    /// Flips to a real `MusicAuthorization.currentStatus` check once MusicKit is
    /// enabled on the App ID.
    func isAvailable() async -> Bool { false }

    func library() async throws -> [Track] {
        throw MusicSourceError.notConfigured(.appleMusic)
    }

    func search(_ query: String) async throws -> [Track] {
        throw MusicSourceError.notConfigured(.appleMusic)
    }
}
