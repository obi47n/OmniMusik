//
//  SampleLibrary.swift
//  OmniMusik
//
//  Debug-only fixtures.
//
//  Getting audio into the iOS Simulator's Files app is unreliable — "Save to Files"
//  has been broken in iOS 18+ simulators since 2024 — so the document picker can't
//  be exercised there at all. These bundled files make the library testable in the
//  simulator without depending on that path.
//
//  They deliberately route through `TrackImporter` rather than constructing entities
//  directly, so the copy step, metadata extraction, and artwork decoding all run
//  exactly as they do for a real import. A fixture loader that skipped that would
//  test nothing worth testing.
//
//  Fixtures (each a distinct pitch, so which track is playing is audible):
//    01  full tags + embedded artwork          A4  440Hz
//    02  tags, no artwork                      C5  523Hz   -> artwork placeholder
//    03  no tags at all                        E5  659Hz   -> filename fallback
//    04  unicode + very long title             G5  784Hz   -> truncation, encoding
//
//  All are 6-9 seconds, which makes end-of-track auto-advance quick to verify.
//

#if DEBUG

import Foundation
import SwiftData

enum SampleLibrary {

    /// Imports every bundled fixture. Safe to call repeatedly — duplicates are
    /// skipped by title so the library doesn't fill up on each tap.
    @MainActor
    static func loadSamples(into context: ModelContext) async -> [String] {
        var failures: [String] = []

        let existing = Set(
            ((try? context.fetch(FetchDescriptor<LocalTrackEntity>())) ?? []).map(\.title)
        )

        for url in bundledSampleURLs() {
            do {
                let entity = try await TrackImporter.importTrack(from: url)
                guard !existing.contains(entity.title) else {
                    try? LocalAudioStorage.delete(fileName: entity.fileName)
                    continue
                }
                context.insert(entity)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append("\(url.lastPathComponent): \(reason)")
            }
        }

        try? context.save()
        return failures
    }

    /// Xcode's synchronized folders may flatten resources into the bundle root or
    /// preserve the subdirectory depending on how the group is configured, so both
    /// locations are checked rather than assuming one.
    private static func bundledSampleURLs() -> [URL] {
        let nested = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: "SampleAudio") ?? []
        let flat = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil) ?? []
        let all = nested.isEmpty ? flat : nested
        return all.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

#endif
