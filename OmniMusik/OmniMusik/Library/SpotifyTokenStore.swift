//
//  SpotifyTokenStore.swift
//  OmniMusik
//
//  Keychain storage for the Spotify connection.
//
//  A separate item from the OmniMusik session in `TokenStore`, because they are
//  independent: disconnecting Spotify must not sign you out of OmniMusik, and
//  signing out of OmniMusik should not silently forget a connected service.
//

import Foundation
import Security

struct SpotifyTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    var accountName: String?

    /// Treated as expired slightly early so a token cannot lapse in flight.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

struct SpotifyTokenStore: Sendable {
    private let service = "com.obinnaduruaku.OmniMusik.spotify"
    private let account = "connection"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> SpotifyTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    func save(_ tokens: SpotifyTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
