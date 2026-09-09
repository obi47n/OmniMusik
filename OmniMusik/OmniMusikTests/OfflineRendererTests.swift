//
//  OfflineRendererTests.swift
//  OmniMusikTests
//
//  Coverage for baking an edit into a file.
//
//  The property that matters most is duration under a rate change. A rate of 0.85
//  stretches the timeline, and getting the output length wrong truncates every
//  slowed export — which is the most-used preset in the app. That failure is
//  silent: the file plays, it just stops early.
//
//  Renders the DEBUG sample fixtures, which are only present in Debug builds.
//

import AVFoundation
import Foundation
import Testing
@testable import OmniMusik

// Serialized: Swift Testing runs cases in parallel by default, and these each
// spin up an AVAudioEngine in offline rendering mode while writing into one
// shared storage directory. Run concurrently they intermittently interfere --
// this suite passed alone and failed alongside its siblings before serializing.
@Suite("OfflineRenderer", .serialized)
struct OfflineRendererTests {

    /// Copies a bundled fixture into the storage directory the renderer reads from
    /// and returns a Track pointing at it.
    private func stagedFixture() throws -> Track? {
        guard let source = Bundle.main.url(forResource: "01_full_metadata", withExtension: "mp3") else {
            return nil
        }
        try LocalAudioStorage.ensureDirectoryExists()

        let fileName = "rendertest-\(UUID().uuidString).mp3"
        let destination = LocalAudioStorage.url(forFileName: fileName)
        try FileManager.default.copyItem(at: source, to: destination)

        let file = try AVAudioFile(forReading: destination)
        let duration = Double(file.length) / file.processingFormat.sampleRate

        return Track(
            title: "Render Fixture",
            artist: "Tests",
            duration: duration,
            source: .local,
            sourceID: fileName
        )
    }

    private func cleanUp(_ track: Track, _ output: URL?) {
        try? LocalAudioStorage.delete(fileName: track.sourceID)
        if let output { try? FileManager.default.removeItem(at: output) }
    }

    private func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    @Test("An unedited export produces a playable file of roughly the same length")
    func identityExportPreservesDuration() throws {
        guard let track = try stagedFixture() else { return }
        var output: URL?
        defer { cleanUp(track, output) }

        let url = try OfflineRenderer.render(track: track, edit: .identity)
        output = url

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "m4a")

        let rendered = try duration(of: url)
        // A short tail is added even with no reverb, so allow a little slack.
        #expect(abs(rendered - track.duration) < 0.5)
    }

    @Test("Halving the speed roughly doubles the exported length")
    func slowedExportStretchesTimeline() throws {
        guard let track = try stagedFixture() else { return }
        var output: URL?
        defer { cleanUp(track, output) }

        var edit = AudioEdit.identity
        edit.speed = 0.5

        let url = try OfflineRenderer.render(track: track, edit: edit)
        output = url

        let rendered = try duration(of: url)
        let expected = track.duration / 0.5

        // The tolerance is wide because the encoder pads to a frame boundary and a
        // tail is appended. The assertion that matters is that the export is not
        // truncated back to the source length.
        #expect(rendered > track.duration * 1.5, "A slowed export must not be cut to the source length.")
        #expect(abs(rendered - expected) < 1.0)
    }

    @Test("Trimming exports only the audible region")
    func trimmedExportCoversOnlyTheTrimmedRange() throws {
        guard let track = try stagedFixture(), track.duration > 4 else { return }
        var output: URL?
        defer { cleanUp(track, output) }

        var edit = AudioEdit.identity
        edit.trimStart = 1
        edit.trimEnd = 3

        let url = try OfflineRenderer.render(track: track, edit: edit)
        output = url

        let rendered = try duration(of: url)
        #expect(abs(rendered - 2.0) < 0.5, "Expected the two-second trimmed region, got \(rendered).")
    }

    @Test("A trim range that selects nothing is rejected rather than writing an empty file")
    func emptyTrimRangeThrows() throws {
        guard let track = try stagedFixture() else { return }
        defer { cleanUp(track, nil) }

        var edit = AudioEdit.identity
        edit.trimStart = 5
        edit.trimEnd = 5

        #expect(throws: OfflineRenderError.self) {
            _ = try OfflineRenderer.render(track: track, edit: edit)
        }
    }

    @Test("Apple Music tracks cannot be exported")
    func remoteTracksAreRejected() {
        let remote = Track(
            title: "Streamed",
            artist: "Someone",
            duration: 200,
            source: .appleMusic,
            sourceID: "12345"
        )

        #expect(throws: OfflineRenderError.self) {
            _ = try OfflineRenderer.render(track: remote, edit: .identity)
        }
    }
}
