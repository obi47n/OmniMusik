//
//  TrackImporter.swift
//  OmniMusik
//
//  Copies user-selected audio into app storage and extracts its metadata.
//

import AVFoundation
import Foundation

enum ImportError: LocalizedError {
    case accessDenied(String)
    case copyFailed(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let name):
            "Couldn't get permission to read \(name)."
        case .copyFailed(let detail):
            "Couldn't import the file: \(detail)"
        case .unreadable(let name):
            "\(name) doesn't appear to be a readable audio file."
        }
    }
}

enum TrackImporter {

    /// Imports one file and returns an unsaved entity for the caller to insert.
    ///
    /// The file is copied before metadata is read, so extraction runs against a URL
    /// that stays valid — reading from the picker's security-scoped URL works right
    /// up until the scope closes mid-`await`, which fails intermittently and only
    /// on real devices.
    static func importTrack(from sourceURL: URL) async throws -> LocalTrackEntity {
        let displayName = sourceURL.lastPathComponent

        // iCloud Drive and other providers hand back scoped URLs. Files already
        // inside our own container don't need scoping and return false here, which
        // is not an error — hence no guard.
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        try LocalAudioStorage.ensureDirectoryExists()

        let fileName = LocalAudioStorage.uniqueFileName(for: displayName)
        let destination = LocalAudioStorage.url(forFileName: fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }

        do {
            let metadata = try await extractMetadata(from: destination, fallbackTitle: displayName)
            return LocalTrackEntity(
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                duration: metadata.duration,
                fileName: fileName,
                artworkData: metadata.artwork
            )
        } catch {
            // Don't leave an orphaned file behind if metadata extraction fails.
            try? LocalAudioStorage.delete(fileName: fileName)
            throw error
        }
    }

    private struct Metadata {
        var title: String
        var artist: String
        var album: String?
        var duration: TimeInterval
        var artwork: Data?
    }

    private static func extractMetadata(
        from url: URL,
        fallbackTitle: String
    ) async throws -> Metadata {
        let asset = AVURLAsset(url: url)

        let duration: TimeInterval
        do {
            duration = try await asset.load(.duration).seconds
        } catch {
            throw ImportError.unreadable(fallbackTitle)
        }
        guard duration.isFinite, duration > 0 else {
            throw ImportError.unreadable(fallbackTitle)
        }

        // Untagged files are common; fall back to the file name rather than
        // showing an empty row.
        var title = (fallbackTitle as NSString).deletingPathExtension
        var artist = "Unknown Artist"
        var album: String?
        var artwork: Data?

        let items = (try? await asset.load(.commonMetadata)) ?? []
        for item in items {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                if let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
            case .commonKeyArtist, .commonKeyCreator:
                if let value = try? await item.load(.stringValue), !value.isEmpty { artist = value }
            case .commonKeyAlbumName:
                if let value = try? await item.load(.stringValue), !value.isEmpty { album = value }
            case .commonKeyArtwork:
                if let data = try? await item.load(.dataValue) { artwork = data }
            default:
                break
            }
        }

        return Metadata(title: title, artist: artist, album: album, duration: duration, artwork: artwork)
    }
}
