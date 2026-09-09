//
//  TokenStore.swift
//  OmniMusik
//
//  Where the session lives between launches.
//
//  Keychain rather than UserDefaults: a refresh token is a long-lived bearer
//  credential, and UserDefaults is a plist in the app container that lands in
//  unencrypted backups.
//
//  `kSecAttrAccessibleAfterFirstUnlock` rather than the stricter
//  `WhenUnlockedThisDeviceOnly` because the app is expected to keep working in
//  the background with the screen locked — the very thing the background audio
//  mode exists for. A sync that fires mid-playback must still be able to read
//  its token.
//

import Foundation
import Security

protocol TokenStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String = "com.obinnaduruaku.OmniMusik.auth", account: String = "session") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }

        // A session that fails to decode is a stale schema from an older build,
        // not a bug worth surfacing. Drop it and let the person sign in again.
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }

        // Delete-then-add rather than SecItemUpdate: one code path whether or not
        // an item already exists, and no partial-update state to reason about.
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
