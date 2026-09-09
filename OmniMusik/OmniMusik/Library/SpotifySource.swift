//
//  SpotifySource.swift
//  OmniMusik
//
//  Spotify as a browsable source.
//
//  Adopts both protocols, which is the point of keeping them separate:
//  `MusicSource` for where tracks come from, `ConnectableSource` for the account that
//  has to exist first. Local files need only the former; Spotify needs both.
//
//  Authorization is authorization-code with PKCE via `ASWebAuthenticationSession` —
//  the same flow as Cognito, against a different issuer. Spotify issues a client
//  secret and this app never uses it: a public client plus PKCE is the correct shape
//  for a native app, and a secret in a shipped binary is not a secret.
//
//  Playback is deliberately not here. `SPTAppRemote` remote-controls the Spotify app
//  and exposes no samples, so Spotify tracks are browsable and queueable but carry
//  `supportsAudioEffects == false`, exactly like Apple Music.
//

import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class SpotifySource: NSObject, MusicSource, ConnectableSource {

    nonisolated let source: TrackSource = .spotify

    private let store = SpotifyTokenStore()
    private let urlSession: URLSession
    private var tokens: SpotifyTokens?

    /// Held for the flow's lifetime; `ASWebAuthenticationSession` is deallocated out
    /// from under itself, and never calls back, if nothing retains it.
    private var activeSession: ASWebAuthenticationSession?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.tokens = store.load()
        super.init()
    }

    // MARK: - ConnectableSource

    var connectionState: SourceConnectionState {
        guard SpotifyConfiguration.isConfigured else {
            return .unavailable(reason: "Spotify isn't configured in this build yet.")
        }
        guard let tokens else { return .disconnected }
        return .connected(account: tokens.accountName)
    }

    func connect() async throws {
        guard SpotifyConfiguration.isConfigured,
              let authorizeURL = SpotifyConfiguration.authorizeURL else {
            throw SourceConnectionError.notConfigured(.spotify)
        }

        let verifier = PKCE.makeVerifier()
        let state = PKCE.makeVerifier()

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: SpotifyConfiguration.clientID),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfiguration.redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let requestURL = components?.url else {
            throw SourceConnectionError.notConfigured(.spotify)
        }

        let callback = try await present(requestURL)
        let code = try authorizationCode(from: callback, expectedState: state)
        var received = try await exchange(code: code, verifier: verifier)

        // Name the account so the settings row says who is connected rather than
        // just "Connected".
        received.accountName = try? await fetchAccountName(accessToken: received.accessToken)

        tokens = received
        store.save(received)
    }

    func disconnect() async {
        tokens = nil
        store.clear()
    }

    // MARK: - MusicSource

    func isAvailable() async -> Bool {
        connectionState.isConnected
    }

    func library() async throws -> [Track] {
        // Saved tracks, newest first. One page is plenty for a library view; the
        // unified library is a browse surface, not an export.
        let payload: SavedTracksResponse = try await get("/me/tracks", query: ["limit": "50"])
        return payload.items.compactMap { $0.track?.asTrack }
    }

    func search(_ query: String) async throws -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let payload: SearchResponse = try await get(
            "/search",
            query: ["q": trimmed, "type": "track", "limit": "20"]
        )
        return payload.tracks?.items.compactMap(\.asTrack) ?? []
    }

    func track(forSourceID sourceID: String) async throws -> Track? {
        let payload: SpotifyTrack = try await get("/tracks/\(sourceID)", query: [:])
        return payload.asTrack
    }

    // MARK: - Authorization plumbing

    private func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SpotifyConfiguration.redirectScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: SourceConnectionError.cancelled)
                } else if let error {
                    continuation.resume(throwing: SourceConnectionError.failed(.spotify, error.localizedDescription))
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: SourceConnectionError.failed(.spotify, "No response."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }
    }

    private func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []

        // Spotify reports refusals as a query parameter on a successful redirect
        // rather than as a transport error, so this is where they surface.
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw SourceConnectionError.failed(.spotify, error)
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw SourceConnectionError.failed(.spotify, "The response did not match the request that started it.")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw SourceConnectionError.failed(.spotify, "The response carried no authorization code.")
        }
        return code
    }

    private func exchange(code: String, verifier: String) async throws -> SpotifyTokens {
        try await postForm([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfiguration.redirectURI,
            "client_id": SpotifyConfiguration.clientID,
            "code_verifier": verifier,
        ])
    }

    /// A token guaranteed fresh at the moment it is returned.
    ///
    /// Every request goes through here so no caller has to remember the refresh
    /// rule — the same shape as `AuthController.validAccessToken`.
    private func validAccessToken() async throws -> String {
        guard let current = tokens else { throw MusicSourceError.notAuthorized(.spotify) }
        guard current.isExpired else { return current.accessToken }

        guard let refreshToken = current.refreshToken else {
            await disconnect()
            throw MusicSourceError.notAuthorized(.spotify)
        }

        do {
            var refreshed = try await postForm([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": SpotifyConfiguration.clientID,
            ])
            // Spotify may omit a new refresh token; carry the original forward.
            refreshed = SpotifyTokens(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? refreshToken,
                expiresAt: refreshed.expiresAt,
                accountName: current.accountName
            )
            tokens = refreshed
            store.save(refreshed)
            return refreshed.accessToken
        } catch {
            // A rejected refresh means the grant is gone; no retry recovers it.
            await disconnect()
            throw MusicSourceError.notAuthorized(.spotify)
        }
    }

    private func postForm(_ fields: [String: String]) async throws -> SpotifyTokens {
        guard let tokenURL = SpotifyConfiguration.tokenURL else {
            throw SourceConnectionError.notConfigured(.spotify)
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw SourceConnectionError.failed(.spotify, body)
        }

        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SpotifyTokens(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            // Spotify returns a lifetime, not a deadline. Converting at receipt is
            // what lets `isExpired` stay a plain comparison later.
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in)),
            accountName: nil
        )
    }

    /// `.urlQueryAllowed` is not sufficient for a form body: it permits `+` and `&`,
    /// which read as a space and a field separator.
    private static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }

    /// A fresh token for the playback provider.
    ///
    /// Exposed rather than handing the provider this whole object: the provider needs
    /// exactly one thing from the source, and passing a closure keeps them testable
    /// apart and stops the provider growing opinions about connection state.
    func accessTokenForPlayback() async throws -> String {
        try await validAccessToken()
    }

    private func fetchAccountName(accessToken: String) async throws -> String? {
        let profile: SpotifyProfile = try await get("/me", query: [:], accessToken: accessToken)
        return profile.display_name ?? profile.email
    }

    private func get<Response: Decodable>(
        _ path: String,
        query: [String: String],
        accessToken: String? = nil
    ) async throws -> Response {
        guard let base = SpotifyConfiguration.apiBaseURL,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw MusicSourceError.notConfigured(.spotify)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw MusicSourceError.notConfigured(.spotify) }

        // Not `accessToken ?? validAccessToken()`: `??` takes an autoclosure, which
        // cannot be async.
        let token: String
        if let accessToken {
            token = accessToken
        } else {
            token = try await validAccessToken()
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MusicSourceError.requestFailed(.spotify, "No HTTP response.")
        }
        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                // A decode failure on a 200 means Spotify's shape changed, not that
                // the request was wrong. Saying so saves chasing the wrong thing.
                throw MusicSourceError.requestFailed(.spotify, "Unexpected response shape: \(error)")
            }
        case 401:
            throw MusicSourceError.notAuthorized(.spotify)
        default:
            // Spotify explains every failure in the body. Reporting only the status
            // code throws away the one piece of information that identifies the
            // cause, which is how a 400 becomes a guessing game.
            let detail = Self.describe(errorBody: data) ?? "no detail"
            throw MusicSourceError.requestFailed(.spotify, "\(http.statusCode) — \(detail) [\(url.absoluteString)]")
        }
    }

    // MARK: - Wire types

    /// Spotify returns either `{"error": {"status": …, "message": …}}` or the OAuth
    /// shape `{"error": "…", "error_description": "…"}` depending on the endpoint.
    private static func describe(errorBody data: Data) -> String? {
        struct APIError: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        struct OAuthError: Decodable {
            let error: String?
            let error_description: String?
        }
        if let parsed = try? JSONDecoder().decode(APIError.self, from: data),
           let message = parsed.error?.message {
            return message
        }
        if let parsed = try? JSONDecoder().decode(OAuthError.self, from: data) {
            return [parsed.error, parsed.error_description].compactMap { $0 }.joined(separator: ": ")
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(200)) }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private struct SpotifyProfile: Decodable {
        let display_name: String?
        let email: String?
    }

    private struct SearchResponse: Decodable {
        let tracks: TrackPage?
        struct TrackPage: Decodable { let items: [SpotifyTrack] }
    }

    private struct SavedTracksResponse: Decodable {
        let items: [SavedItem]
        struct SavedItem: Decodable { let track: SpotifyTrack? }
    }
}

/// Spotify's track shape, normalized into `Track` at the boundary so nothing above
/// this file learns Spotify's vocabulary.
private struct SpotifyTrack: Decodable {
    let id: String
    let name: String
    let duration_ms: Int
    let artists: [Artist]
    let album: Album?

    struct Artist: Decodable { let name: String }
    struct Album: Decodable {
        let name: String?
        let images: [Image]?
        struct Image: Decodable { let url: String; let width: Int? }
    }

    var asTrack: Track {
        Track(
            title: name,
            artist: artists.first?.name ?? "Unknown Artist",
            album: album?.name,
            duration: Double(duration_ms) / 1000,
            source: .spotify,
            sourceID: id,
            // Smallest image at least 200pt wide, falling back to the first. Spotify
            // returns them largest-first, and a 640px cover in a 48pt row is waste.
            artworkURL: album?.images?
                .filter { ($0.width ?? 0) >= 200 }
                .last
                .flatMap { URL(string: $0.url) }
                ?? album?.images?.first.flatMap { URL(string: $0.url) }
        )
    }
}

extension SpotifySource: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
