//
//  AuthModels.swift
//  OmniMusik
//
//  Identity as the rest of the app sees it.
//
//  Nothing here is Cognito-shaped. That is the whole point: DECISIONS.md commits
//  to Sign in with Apple behind a thin interface, and a thin interface is only
//  thin if the types crossing it don't leak the vendor. Swapping Cognito for a
//  self-hosted identity service should touch `CognitoAuthProvider` and nothing
//  else.
//
//  Deliberately free of framework dependencies beyond Foundation, for the same
//  reason `Domain/` is: these types describe the account, not the platform.
//

import Foundation

/// The signed-in person, reduced to what the UI actually renders.
///
/// `id` is the identity provider's stable subject claim, not an email. Emails
/// change and Sign in with Apple may withhold one entirely via Hide My Email,
/// so the subject is the only durable key to hang server-side rows off.
struct AuthenticatedUser: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var email: String?
    var displayName: String?

    /// What to show when the provider gave us nothing but a subject, which is
    /// the normal case for a Hide My Email account on second launch.
    var presentationName: String {
        displayName ?? email ?? "Signed in"
    }
}

/// OAuth tokens plus the expiry we compute at issue time.
struct AuthCredentials: Sendable, Codable {
    let accessToken: String

    /// Absent on a refresh response: Cognito returns a new access token but
    /// expects the caller to keep using the original refresh token.
    let refreshToken: String?

    let idToken: String?
    let expiresAt: Date

    /// Treated as expired slightly early so a token cannot lapse in flight
    /// between this check and the request that uses it.
    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

/// A user and their credentials, as persisted between launches.
struct AuthSession: Sendable, Codable {
    let user: AuthenticatedUser
    var credentials: AuthCredentials
}

enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case invalidCallback
    case tokenExchangeFailed(String)
    case refreshRejected
    case malformedIdentityToken

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Sign-in isn't configured in this build yet."
        case .cancelled:
            "Sign-in was cancelled."
        case .invalidCallback:
            "The sign-in response was missing or malformed."
        case .tokenExchangeFailed(let detail):
            "Could not complete sign-in: \(detail)"
        case .refreshRejected:
            "The session expired and could not be renewed."
        case .malformedIdentityToken:
            "The identity token could not be read."
        }
    }
}
