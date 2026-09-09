//
//  CognitoAuthProvider.swift
//  OmniMusik
//
//  Sign-in against a Cognito user pool, with Sign in with Apple federated in.
//
//  No AWS SDK. This is a plain OAuth2 authorization-code flow with PKCE against
//  the Cognito Hosted UI, driven by `ASWebAuthenticationSession`. Three reasons:
//
//  1. Amplify Swift is a large dependency for what amounts to two HTTP calls.
//  2. The hosted UI renders the Sign in with Apple button itself, so the account
//     being too new for MusicKit does not block a working login today — email and
//     password work now, and SIWA becomes the primary button once the Services ID
//     is configured, with no client change.
//  3. The React client runs this identical flow against the same pool, so there
//     is one mental model across both clients rather than two SDKs to reconcile.
//
//  `ASWebAuthenticationSession` also means the credential is typed into a Safari
//  view this app cannot read, which is the property that makes federated sign-in
//  trustworthy in the first place.
//

import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class CognitoAuthProvider: NSObject, AuthProvider {

    let displayName = "OmniMusik Account"

    private let configuration: CognitoConfiguration
    private let urlSession: URLSession

    /// Held for the lifetime of the flow. `ASWebAuthenticationSession` is
    /// deallocated out from under itself — and silently never calls back — if
    /// nothing retains it while the sheet is up.
    private var activeSession: ASWebAuthenticationSession?

    init(configuration: CognitoConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    var isConfigured: Bool { !configuration.isPlaceholder }

    // MARK: - Sign in

    func signIn() async throws -> AuthSession {
        guard isConfigured,
              let authorizeURL = configuration.authorizeURL,
              let tokenURL = configuration.tokenURL else {
            throw AuthError.notConfigured
        }

        let verifier = PKCE.makeVerifier()

        // `state` is round-tripped and compared on return. It defends the
        // callback against a code injected by something other than the flow
        // this app started.
        let state = PKCE.makeVerifier()

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let requestURL = components?.url else { throw AuthError.notConfigured }

        let callback = try await presentAuthorization(at: requestURL)
        let code = try authorizationCode(from: callback, expectedState: state)
        let credentials = try await exchange(code: code, verifier: verifier, at: tokenURL)

        return AuthSession(user: try user(from: credentials), credentials: credentials)
    }

    /// Bridges the delegate-style web auth sheet into async/await.
    private func presentAuthorization(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.redirectScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: AuthError.tokenExchangeFailed(error.localizedDescription))
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self

            // The person may well have signed in on Safari already; sharing the
            // cookie is the difference between one tap and retyping a password.
            session.prefersEphemeralWebBrowserSession = false

            activeSession = session
            session.start()
        }
    }

    private func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []

        // Cognito reports refusals as a query parameter on a 200 redirect rather
        // than as a transport error, so this is the only place they surface.
        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value
            throw AuthError.tokenExchangeFailed(description ?? error)
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw AuthError.invalidCallback
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidCallback
        }
        return code
    }

    // MARK: - Token exchange

    private func exchange(code: String, verifier: String, at tokenURL: URL) async throws -> AuthCredentials {
        try await postForm(to: tokenURL, fields: [
            "grant_type": "authorization_code",
            "client_id": configuration.clientID,
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "code_verifier": verifier
        ])
    }

    func refresh(using refreshToken: String) async throws -> AuthCredentials {
        guard let tokenURL = configuration.tokenURL else { throw AuthError.notConfigured }
        do {
            return try await postForm(to: tokenURL, fields: [
                "grant_type": "refresh_token",
                "client_id": configuration.clientID,
                "refresh_token": refreshToken
            ])
        } catch {
            // A rejected refresh means the grant is revoked or expired outright.
            // Distinguished from a transport failure so the caller knows to sign
            // the person out rather than retry.
            throw AuthError.refreshRejected
        }
    }

    private func postForm(to url: URL, fields: [String: String]) async throws -> AuthCredentials {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed("No HTTP response.")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw AuthError.tokenExchangeFailed(body)
        }

        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthCredentials(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            idToken: payload.id_token,
            // Cognito returns a lifetime, not a deadline. Converting at the
            // moment of receipt is what lets `isExpired` be a plain comparison
            // later, with no need to remember when the response arrived.
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in))
        )
    }

    /// Percent-encodes for `application/x-www-form-urlencoded`.
    ///
    /// `.urlQueryAllowed` is not sufficient on its own: it permits `+` and `&`,
    /// which a form body reads as a space and a field separator respectively.
    private static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let id_token: String?
        let refresh_token: String?
        let expires_in: Int
    }

    // MARK: - Identity

    /// Reads the account's display claims out of the ID token.
    ///
    /// The signature is deliberately not verified here. A client verifying a
    /// token it just received over TLS from the issuer proves nothing, and
    /// shipping a JWKS cache to do it would be security theatre. The Spring Boot
    /// service verifies signature, issuer, and audience on every request, which
    /// is where it actually counts. These claims are for rendering a name.
    private func user(from credentials: AuthCredentials) throws -> AuthenticatedUser {
        guard let idToken = credentials.idToken else { throw AuthError.malformedIdentityToken }

        let segments = idToken.split(separator: ".")
        guard segments.count == 3,
              let payload = PKCE.base64URLDecode(String(segments[1])),
              let claims = try? JSONDecoder().decode(IdentityClaims.self, from: payload) else {
            throw AuthError.malformedIdentityToken
        }

        return AuthenticatedUser(
            id: claims.sub,
            email: claims.email,
            displayName: claims.name ?? claims.given_name
        )
    }

    private struct IdentityClaims: Decodable {
        let sub: String
        let email: String?
        let name: String?
        let given_name: String?
    }

    // MARK: - Sign out

    func signOut(_ session: AuthSession) async {
        guard let logoutURL = configuration.logoutURL,
              var components = URLComponents(url: logoutURL, resolvingAgainstBaseURL: false) else { return }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "logout_uri", value: configuration.redirectURI)
        ]
        guard let url = components.url else { return }

        // Clears the hosted UI cookie so the next sign-in genuinely prompts
        // rather than silently reusing the previous account. Failure is ignored
        // on purpose: the local tokens are gone either way.
        _ = try? await urlSession.data(from: url)
    }
}

extension CognitoAuthProvider: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
