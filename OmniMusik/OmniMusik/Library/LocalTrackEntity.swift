//
//  LocalTrackEntity.swift
//  OmniMusik
//
//  SwiftData persistence for imported local tracks.
//
//  Kept separate from `Track` rather than making the domain type itself @Model.
//  Only local tracks are persisted — Apple Music tracks are fetched live from
//  MusicKit and caching them would mean holding stale copies of a catalog that
//  changes underneath us. A persistence type that only applies to one source has no
//  business being the type the whole app passes around.
//

import Foundation
import SwiftData

@Model
final class LocalTrackEntity {
    #Index<LocalTrackEntity>([\.dateAdded])

    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval

    /// File name inside `LocalAudioStorage.directory`. Not an absolute path: the
    /// app container is relocated between launches and installs, so a stored
    /// absolute URL resolves to nothing the next time the app opens.
    var fileName: String

    /// Artwork can be several hundred KB; `.externalStorage` keeps the blobs beside
    /// the store rather than inside its rows, so list queries stay fast.
    @Attribute(.externalStorage) var artworkData: Data?

    var dateAdded: Date

    /// Encoded `AudioEdit` for this track, or nil when unedited (week 2).
    var editData: Data?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval,
        fileName: String,
        artworkData: Data? = nil,
        dateAdded: Date = .now,
        editData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileName = fileName
        self.artworkData = artworkData
        self.dateAdded = dateAdded
        self.editData = editData
    }
}

extension LocalTrackEntity {
    /// Projection into the source-agnostic domain type the UI and providers consume.
    var asTrack: Track {
        Track(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            source: .local,
            sourceID: fileName,
            artworkData: artworkData
        )
    }

    var edit: AudioEdit {
        get {
            guard let editData,
                  let decoded = try? JSONDecoder().decode(AudioEdit.self, from: editData)
            else { return .identity }
            return decoded
        }
        set {
            editData = newValue.isIdentity ? nil : try? JSONEncoder().encode(newValue)
        }
    }
}
