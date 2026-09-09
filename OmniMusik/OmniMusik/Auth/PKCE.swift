//
//  PKCE.swift
//  OmniMusik
//
//  Proof Key for Code Exchange (RFC 7636).
//
//  Required here, not optional. A native app cannot keep a client secret — the
//  binary ships to the device and can be read — so the Cognito app client is a
//  public client with no secret at all. PKCE is what stops an attacker who
//  intercepts the redirect from redeeming the authorization code: without the
//  original verifier, the code is worthless.
//
//  The React client will run this same flow against the same user pool.
//

import CryptoKit
import Foundation

enum PKCE {

    /// A fresh high-entropy verifier. 32 bytes lands inside the 43-128 character
    /// window the spec requires once base64url-encoded.
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    /// The S256 challenge sent on the authorize request. Only the hash travels
    /// over the front channel; the verifier itself is held until token exchange.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Base64url without padding, per RFC 7636. Standard base64 is rejected:
    /// `+` and `/` are not URL-safe and `=` confuses query parsing.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Re-pads a base64url string so `Data(base64Encoded:)` will accept it.
    /// Used to read JWT payloads, which are encoded the same way.
    static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if s.count % 4 != 0 {
            s.append(String(repeating: "=", count: 4 - s.count % 4))
        }
        return Data(base64Encoded: s)
    }
}
