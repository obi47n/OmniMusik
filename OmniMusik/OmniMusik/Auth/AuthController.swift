//
//  AuthController.swift
//  OmniMusik
//
//  Observable owner of the signed-in session.
//
//  Sits between the provider and the UI so views never touch tokens, and so the
//  refresh rule lives in exactly one place. `@Observable` rather than
//  `ObservableObject`, matching the rest of the app.
//
//  Signing in is deliberately optional. The local library, the effects chain,
//  and playback all work with no account at all — an owned MP3 does not need a
//  server's permission to play, and gating it behind a login would be a worse
//  product and a worse story. An account buys cross-device Omni playlists and
//  the web client; nothing else is withheld.
//

import Foundation

@MainActor
@Observable
final class AuthController {

    private(set) var session: AuthSession?
    private(set) var isSigningIn = false

    /// Surfaced by the account screen. Cancellation is not an error and never
    /// lands here.
    var errorMessage: String?

    private let provider: any AuthProvider
    private let tokenStore: any TokenStore

    var isSignedIn: Bool { session != nil }
    var isConfigured: Bool { provider.isConfigured }
    var providerName: String { provider.displayName }
    var user: AuthenticatedUser? { session?.user }

    init(provider: any AuthProvider, tokenStore: any TokenStore = KeychainTokenStore()) {
        self.provider = provider
        self.tokenStore = tokenStore
        self.session = tokenStore.load()
    }

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await provider.signIn()
            self.session = session
            tokenStore.save(session)
        } catch AuthError.cancelled {
            // Backing out of the sheet is an ordinary outcome, not a failure.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let session else { return }

        // Local state is cleared first and unconditionally. Sign-out must never
        // appear to fail because a network call did.
        self.session = nil
        tokenStore.clear()
        await provider.signOut(session)
    }

    /// A token guaranteed fresh at the moment it is returned.
    ///
    /// Every authenticated request goes through here rather than reading
    /// `session.credentials` directly, so no caller has to remember the refresh
    /// rule. A refresh that Cognito rejects signs the person out, because the
    /// grant is gone and no retry will bring it back.
    func validAccessToken() async throws -> String {
        guard let session else { throw AuthError.notConfigured }
        guard session.credentials.isExpired else { return session.credentials.accessToken }

        guard let refreshToken = session.credentials.refreshToken else {
            await signOut()
            throw AuthError.refreshRejected
        }

        do {
            let refreshed = try await provider.refresh(using: refreshToken)

            // Cognito omits the refresh token on a refresh response, so the
            // original is carried forward rather than lost.
            let merged = AuthCredentials(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? refreshToken,
                idToken: refreshed.idToken ?? session.credentials.idToken,
                expiresAt: refreshed.expiresAt
            )
            var updated = session
            updated.credentials = merged
            self.session = updated
            tokenStore.save(updated)
            return merged.accessToken
        } catch {
            await signOut()
            throw AuthError.refreshRejected
        }
    }
}
