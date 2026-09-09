//
//  CognitoConfiguration.swift
//  OmniMusik
//
//  The one file to edit after `terraform apply`.
//
//  None of these values are secrets. The Cognito app client is a public client
//  with no secret — a native binary cannot keep one — so the domain and client ID
//  are safe in version control, and PKCE is what actually secures the exchange.
//  Anything that genuinely must stay out of the repo belongs in Secrets.xcconfig,
//  which .gitignore already excludes.
//

import Foundation

struct CognitoConfiguration: Sendable {
    /// Hosted UI domain, without scheme. Terraform output `cognito_domain`.
    let domain: String

    /// App client ID. Terraform output `cognito_app_client_id`.
    let clientID: String

    /// Custom scheme the hosted UI redirects back to. Registered nowhere in
    /// Info.plist on purpose: `ASWebAuthenticationSession` intercepts the
    /// callback itself via `callbackURLScheme`, so no URL type is needed.
    let redirectScheme: String

    var redirectURI: String { "\(redirectScheme)://auth" }

    /// `openid` is what makes Cognito return an ID token at all; `email` and
    /// `profile` are what put a readable name on the account screen.
    let scopes = ["openid", "email", "profile"]

    var authorizeURL: URL? { URL(string: "https://\(domain)/oauth2/authorize") }
    var tokenURL: URL? { URL(string: "https://\(domain)/oauth2/token") }
    var logoutURL: URL? { URL(string: "https://\(domain)/logout") }

    /// The deployed user pool, from `terraform output`.
    ///
    /// Not secrets: the app client is public and has no secret, because a native
    /// binary cannot keep one. PKCE is what secures the exchange.
    static let deployed = CognitoConfiguration(
        domain: "omnimusik-463092208222.auth.us-east-1.amazoncognito.com",
        clientID: "533bcjsr65iq88t7vg2kmetrkp",
        redirectScheme: "omnimusik"
    )

    /// Placeholders. `AuthProvider.isConfigured` reports false while these are in
    /// place, so a checkout without a deployment explains itself on the account
    /// screen instead of failing when someone taps sign in.
    static let unconfigured = CognitoConfiguration(
        domain: "REPLACE_ME.auth.us-east-1.amazoncognito.com",
        clientID: "REPLACE_ME",
        redirectScheme: "omnimusik"
    )

    var isPlaceholder: Bool {
        domain.contains("REPLACE_ME") || clientID == "REPLACE_ME"
    }
}
