//
//  ConnectableSource.swift
//  OmniMusik
//
//  Sources that need an account connected before they can answer.
//
//  This is the gap the architecture had. `MusicSource.isAvailable()` could say "no"
//  but never "no, and here is how to fix that" — so `AppleMusicSource` returned false
//  forever and nothing in the UI could offer to connect it. Every streaming source
//  needs this, so it belongs beside `MusicSource` rather than inside whichever one
//  gets built first.
//
//  Deliberately a *separate* protocol rather than more methods on `MusicSource`, for
//  the same reason `PlaybackProvider` and `MusicSource` are separate: local files
//  have no account to connect, and forcing every source to implement a connection
//  flow would mean one of them lying about what it is. A type adopts both when both
//  apply.
//
//  Note this is distinct from `AuthProvider`, which owns the *OmniMusik* account.
//  Signing into OmniMusik and connecting Spotify are unrelated: you can sync
//  playlists without Spotify, and play Spotify without an OmniMusik account.
//

import Foundation

enum SourceConnectionState: Equatable {
    /// Connected, optionally naming the account for display.
    case connected(account: String?)

    /// Not connected, but connectable — the UI should offer to.
    case disconnected

    /// A connection attempt is in flight.
    case connecting

    /// Cannot be connected in this build at all, with the reason.
    ///
    /// Distinct from `disconnected` because the honest UI is different: an
    /// explanation, not a button that cannot work. Apple Music sits here while
    /// MusicKit is unprovisioned.
    case unavailable(reason: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Whether offering a connect action makes sense right now.
    var canConnect: Bool {
        self == .disconnected
    }
}

@MainActor
protocol ConnectableSource: AnyObject {
    var source: TrackSource { get }
    var connectionState: SourceConnectionState { get }

    /// Begins an interactive connection. Throws `SourceConnectionError.cancelled`
    /// when the person backs out, which callers should treat as ordinary.
    func connect() async throws

    /// Forgets the connection. Not throwing: local disconnection must always
    /// succeed, whatever the network says.
    func disconnect() async
}

enum SourceConnectionError: LocalizedError {
    case cancelled
    case notConfigured(TrackSource)
    case appNotInstalled(TrackSource)
    case failed(TrackSource, String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Connecting was cancelled."
        case .notConfigured(let source):
            "\(source.displayName) isn't configured in this build yet."
        case .appNotInstalled(let source):
            "\(source.displayName) needs its app installed on this device."
        case .failed(let source, let detail):
            "Could not connect \(source.displayName): \(detail)"
        }
    }
}
