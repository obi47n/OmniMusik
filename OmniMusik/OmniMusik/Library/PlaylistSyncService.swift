//
//  PlaylistSyncService.swift
//  OmniMusik
//
//  Reconciles local playlists with the server.
//
//  Deliberately thin. Every decision it makes comes from `PlaylistSync.decide`, which
//  is a pure function in Domain/ with no framework dependencies, so the hard part is
//  testable without a network, a store, or two devices. What is left here is the
//  plumbing to carry out whichever answer came back.
//
//  Conflicts are never resolved automatically. When both sides have moved, the
//  playlist is reported and left exactly as it is — silently picking a winner is how
//  someone loses an evening's work without ever being told.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PlaylistSyncService {

    enum Status: Equatable {
        case idle
        case syncing
        case succeeded(pushed: Int, pulled: Int, deleted: Int)
        case failed(String)
    }

    /// Who asked for the most recent sync.
    ///
    /// The service reports the same thing either way; this exists so the UI can tell
    /// the difference. A sync a person pressed a button for owes them an answer. One
    /// that ran because they added a track does not -- narrating background work as
    /// it happens is noise, and it teaches people to ignore the one banner that
    /// matters.
    enum Reason { case requested, automatic }

    private(set) var status: Status = .idle
    private(set) var reason: Reason = .requested

    /// Playlists where both sides moved. Left untouched until a person chooses.
    private(set) var conflicts: [UUID] = []

    private let context: ModelContext
    private let api: OmniMusikAPI

    init(container: ModelContainer, api: OmniMusikAPI) {
        self.context = ModelContext(container)
        self.api = api
    }

    var isConfigured: Bool { api.isConfigured }

    func sync(reason: Reason = .requested) async {
        self.reason = reason

        guard api.isConfigured else {
            status = .failed("Sync isn't configured in this build yet.")
            return
        }

        status = .syncing
        conflicts = []

        do {
            let remote = try await api.listPlaylists()
            let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })

            let locals = (try? context.fetch(FetchDescriptor<PlaylistEntity>())) ?? []
            let localIDs = Set(locals.map(\.id))

            var pushed = 0
            var pulled = 0
            var deleted = 0

            for entity in locals {
                let decision = PlaylistSync.decide(
                    hasLocalChanges: entity.hasLocalChanges,
                    syncedVersion: entity.syncedVersion,
                    remoteVersion: remoteByID[entity.id]?.version
                )

                switch decision {
                case .upToDate:
                    continue

                case .push:
                    try await push(entity)
                    pushed += 1

                case .pull:
                    guard let match = remoteByID[entity.id] else { continue }
                    entity.adoptRemote(
                        name: match.name,
                        entries: match.entries,
                        updatedAt: match.updatedAt,
                        version: match.version
                    )
                    pulled += 1

                case .deleteLocal:
                    context.delete(entity)
                    deleted += 1

                case .conflict:
                    conflicts.append(entity.id)
                }
            }

            // Anything the server has that this device has never seen.
            for playlist in remote where !localIDs.contains(playlist.id) {
                let entity = PlaylistEntity(
                    id: playlist.id,
                    name: playlist.name,
                    entries: playlist.entries,
                    createdAt: playlist.createdAt,
                    updatedAt: playlist.updatedAt
                )
                entity.markSynced(version: playlist.version)
                context.insert(entity)
                pulled += 1
            }

            try? context.save()
            status = .succeeded(pushed: pushed, pulled: pulled, deleted: deleted)

        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Uploads one playlist and records the version the server assigned.
    ///
    /// A 409 here means the server moved between the listing and this write — a race
    /// the decision function could not have seen. Recorded as a conflict rather than
    /// retried, for the same reason: retrying with the server's new version is
    /// last-write-wins with extra steps.
    private func push(_ entity: PlaylistEntity) async throws {
        let body = UpsertPlaylistBody(
            name: entity.name,
            entries: entity.entries,
            expectedVersion: entity.syncedVersion
        )

        do {
            let saved = try await api.upsert(id: entity.id, body: body)
            entity.markSynced(version: saved.version)
        } catch APIError.conflict {
            conflicts.append(entity.id)
        }
    }

    /// Resolves a conflict by taking the server's copy, discarding local edits.
    func resolveByTakingRemote(id: UUID) async {
        guard let entity = entity(for: id) else { return }
        do {
            let remote = try await api.listPlaylists().first { $0.id == id }
            guard let remote else {
                context.delete(entity)
                try? context.save()
                conflicts.removeAll { $0 == id }
                return
            }
            entity.adoptRemote(
                name: remote.name,
                entries: remote.entries,
                updatedAt: remote.updatedAt,
                version: remote.version
            )
            try? context.save()
            conflicts.removeAll { $0 == id }
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Resolves a conflict by overwriting the server with this device's copy.
    ///
    /// Adopts the server's current version first so the write is accepted. That is
    /// deliberately an explicit, person-chosen action and never something sync does
    /// on its own.
    func resolveByKeepingLocal(id: UUID) async {
        guard let entity = entity(for: id) else { return }
        do {
            let remote = try await api.listPlaylists().first { $0.id == id }
            entity.syncedVersion = remote?.version
            try await push(entity)
            try? context.save()
            conflicts.removeAll { $0 == id }
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func entity(for id: UUID) -> PlaylistEntity? {
        var descriptor = FetchDescriptor<PlaylistEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
