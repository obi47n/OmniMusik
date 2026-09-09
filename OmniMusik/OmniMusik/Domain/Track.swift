//
//  Track.swift
//  OmniMusik
//
//  The unified track model. Every source — local files, Apple Music, and any
//  provider added later — normalizes into this type before reaching the UI.
//
//  Deliberately free of framework dependencies (no AVFoundation, no MusicKit,
//  no SwiftData). That keeps the domain layer portable and testable, and means
//  the UI never has to know where a track came from.
//

import Foundation

/// Where a track's audio actually lives. Determines which `PlaybackProvider`
/// can play it and what operations are legal on it.
enum TrackSource: String, Codable, Sendable, CaseIterable {
    case local
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .local: "Local"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    /// Whether audio from this source can be routed through the effects chain.
    ///
    /// Apple Music audio is DRM-protected and played by a system-owned player we
    /// get no sample access to, so effects are structurally impossible — not
    /// merely unimplemented. Encoding that here keeps the rule in one place.
    var supportsAudioEffects: Bool {
        switch self {
        case .local: true
        // Spotify is the same structural case as Apple Music: SPTAppRemote
        // remote-controls the Spotify app and exposes no samples, so there is
        // nothing to route through the effects chain.
        case .appleMusic, .spotify: false
        }
    }
}

/// A single playable item, normalized across sources.
struct Track: Identifiable, Hashable, Sendable {
    /// Stable OmniMusik-scoped identity. Distinct from `sourceID` so the same
    /// song from two sources remains two tracks with two identities.
    let id: UUID

    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    let source: TrackSource

    /// The identifier this track's own source uses.
    /// - `.local`: the file name inside the app's audio directory.
    /// - `.appleMusic`: the MusicKit catalog/library identifier.
    let sourceID: String

    var artworkData: Data?

    /// Artwork hosted by the source, for services that hand back a URL rather than
    /// bytes. Local files carry `artworkData` instead, extracted at import.
    ///
    /// Deliberately not part of anything that crosses the wire: `PlaylistEntry`
    /// snapshots a title, artist and duration, and an expiring CDN URL is not
    /// something to persist on a server.
    var artworkURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval,
        source: TrackSource,
        sourceID: String,
        artworkData: Data? = nil,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.source = source
        self.sourceID = sourceID
        self.artworkData = artworkData
        self.artworkURL = artworkURL
    }
}

extension Track {
    var displaySubtitle: String {
        if let album, !album.isEmpty { "\(artist) — \(album)" } else { artist }
    }

    var formattedDuration: String { Self.timeFormatter(duration) }

    /// `m:ss`, or `h:mm:ss` past an hour. Used for durations and playback position.
    static func timeFormatter(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
