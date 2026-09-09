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
    /// Left as a placeholder so a fresh checkout reports sync as unconfigured rather
    /// than failing at tap time, matching how sign-in behaves.
    static let baseURLString = "REPLACE_ME"

    static var baseURL: URL? {
        guard baseURLString != "REPLACE_ME", !baseURLString.isEmpty else { return nil }
        return URL(string: baseURLString)
    }

    /// For running against a service on the development machine. The simulator
    /// reaches the host as localhost; a device needs the machine's LAN address.
    static let localDevelopmentURL = URL(string: "http://localhost:8080")
}
