//
//  OmniMusikAPI.swift
//  OmniMusik
//
//  Typed access to the sync service.
//
//  Takes a token provider rather than an `AuthController`, so the refresh rule stays
//  in one place and this layer holds no opinion about sessions. It also makes the
//  client trivially testable against a stub token and a `URLProtocol` fake.
//

import Foundation

struct APIPlaylist: Codable, Sendable {
    let id: UUID
    var name: String
    var entries: [PlaylistEntry]
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

struct UpsertPlaylistBody: Encodable, Sendable {
    let name: String
    let entries: [PlaylistEntry]

    /// Null on a create. On an update this is the version this device last read;
    /// omitting it is refused by the server rather than allowed to clobber.
    let expectedVersion: Int?
}

enum APIError: LocalizedError {
    case notConfigured
    case notSignedIn
    case conflict(APIPlaylist)
    case notFound
    case transport(String)
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Sync isn't configured in this build yet."
        case .notSignedIn: "Sign in to sync playlists."
        case .conflict: "This playlist was changed on another device."
        case .notFound: "That playlist no longer exists on the server."
        case .transport(let detail): "Could not reach the server: \(detail)"
        case .status(let code, let detail): "The server refused the request (\(code)). \(detail)"
        }
    }
}

@MainActor
final class OmniMusikAPI {

    private let baseURL: URL?
    private let session: URLSession
    private let accessToken: () async throws -> String

    /// ISO-8601, matching the service.
    ///
    /// Not optional: Swift's default strategy encodes a `Date` as seconds since the
    /// 2001 Apple epoch, which the server reads as a nonsensical instant without
    /// erroring. This is the single most likely way for the two sides to disagree
    /// silently, so both coders are configured explicitly.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    init(
        baseURL: URL?,
        session: URLSession = .shared,
        accessToken: @escaping () async throws -> String
    ) {
        self.baseURL = baseURL
        self.session = session
        self.accessToken = accessToken
    }

    var isConfigured: Bool { baseURL != nil }

    /// The server's identity, used to decide whether recorded versions still mean
    /// anything. See `SyncEpochRule`.
    func syncEpoch() async throws -> String {
        let response: SyncEpochResponse = try await send(
            path: "/api/v1/sync/epoch", method: "GET", body: Optional<UpsertPlaylistBody>.none
        )
        return response.epoch
    }

    private struct SyncEpochResponse: Decodable {
        let epoch: String
    }

    func listPlaylists() async throws -> [APIPlaylist] {
        try await send(path: "/api/v1/playlists", method: "GET", body: Optional<UpsertPlaylistBody>.none)
    }

    func upsert(id: UUID, body: UpsertPlaylistBody) async throws -> APIPlaylist {
        try await send(path: "/api/v1/playlists/\(id.uuidString.lowercased())", method: "PUT", body: body)
    }

    func delete(id: UUID) async throws {
        let _: EmptyResponse = try await send(
            path: "/api/v1/playlists/\(id.uuidString.lowercased())",
            method: "DELETE",
            body: Optional<UpsertPlaylistBody>.none
        )
    }

    private struct EmptyResponse: Decodable {}

    private struct ConflictBody: Decodable {
        let current: APIPlaylist
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        guard let baseURL else { throw APIError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.makeEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response.")
        }

        switch http.statusCode {
        case 200...299:
            if data.isEmpty, let empty = EmptyResponse() as? Response { return empty }
            return try Self.makeDecoder().decode(Response.self, from: data)

        case 401:
            throw APIError.notSignedIn

        case 404:
            throw APIError.notFound

        case 409:
            // The conflict body carries the server's current playlist precisely so
            // the caller can merge without another round trip.
            if let conflict = try? Self.makeDecoder().decode(ConflictBody.self, from: data) {
                throw APIError.conflict(conflict.current)
            }
            throw APIError.status(409, "Conflict.")

        default:
            throw APIError.status(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
