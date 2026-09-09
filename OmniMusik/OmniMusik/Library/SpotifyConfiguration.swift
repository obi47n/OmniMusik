//
//  SpotifyConfiguration.swift
//  OmniMusik
//
//  Spotify app registration values.
//
//  The client ID is not a secret. Spotify issues a secret too, and this app
//  deliberately does not use it: a native binary cannot keep one, so the app is
//  registered as a public client and PKCE secures the code exchange — the same
//  reasoning as the Cognito app client.
//

import Foundation

enum SpotifyConfiguration {

    static let clientID = "38ab0fbae2b74060b3bccf507d59f7d9"

    /// Must match the dashboard entry exactly. A mismatch fails at the redirect with
    /// an error that never mentions the URI.
    ///
    /// A distinct path from Cognito's `omnimusik://auth`: two services redirecting
    /// into one app need separate ones.
    static let redirectURI = "omnimusik://spotify-auth"
    static let redirectScheme = "omnimusik"

    /// Requested up front, including the playback scopes, so adding
    /// `SpotifyPlaybackProvider` later does not force everyone to re-authorize.
    ///
    /// - `user-read-email`, `user-read-private`: name the connected account
    /// - `user-library-read`: the saved-tracks library
    /// - `streaming`, `app-remote-control`: required by SPTAppRemote
    /// - `user-read-playback-state`, `user-modify-playback-state`: transport control
    static let scopes = [
        "user-read-email",
        "user-read-private",
        "user-library-read",
        "streaming",
        "app-remote-control",
        "user-read-playback-state",
        "user-modify-playback-state",
    ]

    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")
    static let apiBaseURL = URL(string: "https://api.spotify.com/v1")

    static var isConfigured: Bool {
        !clientID.isEmpty && clientID != "REPLACE_ME"
    }
}
