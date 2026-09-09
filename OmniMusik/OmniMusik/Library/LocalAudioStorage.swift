//
//  LocalAudioStorage.swift
//  OmniMusik
//
//  Owns the on-disk location of imported audio.
//
//  Imported files are copied into the app's Application Support directory rather
//  than referenced in place. Files chosen through the document picker arrive as
//  security-scoped URLs that are only valid for the duration of the picker callback
//  and may point into iCloud Drive or another app's container — holding onto one
//  and hoping it still resolves next launch is how a library quietly fills with
//  dead entries. Copying makes OmniMusik the owner of every byte it plays.
//

import Foundation

enum LocalAudioStorage {
    /// Directory holding imported audio. Created lazily on first access.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Audio", isDirectory: true)
    }

    /// Application Support is not guaranteed to exist on a fresh install, unlike
    /// Documents — creating it is the caller's responsibility, not the system's.
    static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func url(forFileName fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func fileExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forFileName: fileName).path)
    }

    static func delete(fileName: String) throws {
        let url = url(forFileName: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// A collision-free file name preserving the original extension.
    ///
    /// Two files can legitimately share a name ("track01.mp3" from two albums), so
    /// stored names are UUID-based and the human-readable title lives in metadata.
    static func uniqueFileName(for originalName: String) -> String {
        let ext = (originalName as NSString).pathExtension
        let base = UUID().uuidString
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
