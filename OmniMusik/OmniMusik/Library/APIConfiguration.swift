//
//  APIConfiguration.swift
//  OmniMusik
//
//  Where the sync service lives. Edited after `terraform apply`, alongside
//  `CognitoConfiguration`.
//

import Foundation

enum APIConfiguration {

    /// Terraform output `api_url`. Not a secret.
    ///
    /// Still a placeholder because App Runner has not started: it points at an ECR
    /// tag that does not exist yet, so there is no deployed URL to put here.
    static let baseURLString = "REPLACE_ME"

    /// A backend running on the development machine.
    ///
    /// The simulator shares the host's network, so `localhost` reaches the Mac. A
    /// physical device does not: there, `localhost` is the phone, nothing is
    /// listening, and the request fails as "could not connect to the server".
    ///
    /// The device build uses the Mac's Bonjour name rather than its LAN address, for
    /// two reasons. It survives DHCP handing the Mac a different IP, and `.local`
    /// names are explicitly covered by the `NSAllowsLocalNetworking` exception in
    /// Info.plist — a raw 192.168.x.x literal is a private address but not a
    /// link-local one, so App Transport Security may still refuse it.
    ///
    /// Both machines must be on the same network. Update this if the Mac is renamed.
    #if targetEnvironment(simulator)
    static let localDevelopmentURL = URL(string: "http://localhost:8080")
    #else
    static let localDevelopmentURL = URL(string: "http://Obis-MacBook-Air.local:8080")
    #endif

    /// The service to talk to.
    ///
    /// Prefers a real deployment. Falls back to a local backend in DEBUG builds so
    /// sync can be exercised end to end before App Runner exists — a release build
    /// never silently talks to localhost, it simply reports sync as unconfigured.
    static var baseURL: URL? {
        if baseURLString != "REPLACE_ME", !baseURLString.isEmpty {
            return URL(string: baseURLString)
        }
        #if DEBUG
        return localDevelopmentURL
        #else
        return nil
        #endif
    }
}
