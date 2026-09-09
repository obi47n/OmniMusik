//
//  AuthProvider.swift
//  OmniMusik
//
//  The thin interface DECISIONS.md called for.
//
//  Mirrors the shape of `PlaybackProvider` and `MusicSource`: a protocol naming
//  one capability, with the vendor confined to the implementation. A second
//  provider — a mock in tests, a self-hosted service later — is an additive
//  change rather than a refactor.
//
//  `@MainActor` because signing in means presenting a web sheet. Auth is
//  UI-adjacent by nature and pretending otherwise would only push the hop
//  somewhere less obvious.
//

import Foundation

@MainActor
protocol AuthProvider: AnyObject {
    /// Named in the UI so the sign-in screen doesn't hardcode a vendor.
    var displayName: String { get }

    /// Whether this build has the configuration needed to sign in at all.
    /// False in a checkout that has not had the Terraform outputs filled in,
    /// which lets the UI explain itself instead of failing at tap time.
    var isConfigured: Bool { get }

    /// Interactive sign-in. Throws `AuthError.cancelled` if the person backs out,
    /// which callers should treat as an ordinary outcome rather than a failure.
    func signIn() async throws -> AuthSession

    /// Exchanges a refresh token for a fresh access token.
    ///
    /// Takes the token rather than the whole session because a refresh response
    /// does not always carry a new refresh token, so the caller owns the job of
    /// merging the result back into the session it already holds.
    func refresh(using refreshToken: String) async throws -> AuthCredentials

    /// Best-effort teardown of the provider's own session cookie.
    ///
    /// Not throwing: local sign-out must always succeed. If the network call
    /// fails, the tokens are still discarded on this device, which is the part
    /// the person actually asked for.
    func signOut(_ session: AuthSession) async
}
