//
//  OfflineRenderer.swift
//  OmniMusik
//
//  Bakes an `AudioEdit` into a new audio file.
//
//  Everything in the Studio is non-destructive: edits are a value type applied at
//  render time, and the imported file is never touched. That is the right default,
//  but it means an edit only exists inside OmniMusik. Export is what makes a
//  slowed-and-reverbed version into a file you can send someone.
//
//  Implemented with AVAudioEngine's manual rendering mode rather than
//  AVAssetExportSession, because the effects are an engine graph. An export
//  session can trim and transcode but has no way to apply an `AVAudioUnitTimePitch`
//  or a reverb node. The graph here is deliberately identical to the one in
//  `LocalPlaybackProvider` — if the two drifted, exports would stop sounding like
//  what was auditioned, which is the one thing an export must never do.
//
//  Rendering is CPU-bound and runs far faster than real time, so it is kept off
//  the main actor entirely and reports progress back to callers.
//

import AVFoundation
import Foundation

enum OfflineRenderError: LocalizedError {
    case sourceMissing
    case unsupportedFormat
    case emptyRange
    case engineFailure(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing: "The audio file for this track is missing."
        case .unsupportedFormat: "This audio format can't be exported."
        case .emptyRange: "The trim range leaves nothing to export."
        case .engineFailure(let detail): "Render failed: \(detail)"
        case .writeFailed(let detail): "Could not write the exported file: \(detail)"
        }
    }
}

enum OfflineRenderer {

    /// Where finished exports live.
    ///
    /// Documents rather than Application Support: exports are user-facing artifacts
    /// meant to be shared out of the app, and Documents is the directory the system
    /// share sheet and Files integration expect to read from.
    static var exportDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }

    /// Renders `track` with `edit` applied, returning the written file.
    ///
    /// Synchronous and CPU-bound by design — call it from a detached task. Progress
    /// is reported as 0...1 and is called on the rendering thread, so callers must
    /// hop to the main actor before touching UI state.
    static func render(
        track: Track,
        edit: AudioEdit,
        progress: ((Double) -> Void)? = nil
    ) throws -> URL {
        guard track.source == .local else { throw OfflineRenderError.sourceMissing }

        let sourceURL = LocalAudioStorage.url(forFileName: track.sourceID)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw OfflineRenderError.sourceMissing
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw OfflineRenderError.unsupportedFormat
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else { throw OfflineRenderError.unsupportedFormat }

        // Trim bounds, resolved the same way the player resolves them so an export
        // covers exactly the region that was audible.
        let totalFrames = file.length
        let startFrame = min(max(0, AVAudioFramePosition(max(0, edit.trimStart) * sampleRate)), totalFrames)
        let endFrame = min(
            max(startFrame, edit.trimEnd.map { AVAudioFramePosition($0 * sampleRate) } ?? totalFrames),
            totalFrames
        )
        let audibleFrames = endFrame - startFrame
        guard audibleFrames > 0 else { throw OfflineRenderError.emptyRange }

        // MARK: Graph — must mirror LocalPlaybackProvider

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let reverb = AVAudioUnitReverb()

        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(reverb)

        configureEQ(eq, with: edit)
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = min(max(0, edit.reverbMix), 100)
        timePitch.rate = min(max(0.25, edit.speed), 4.0)
        timePitch.pitch = min(max(-2_400, edit.pitch), 2_400)

        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        // MARK: Output length

        // A rate change stretches or compresses the timeline: N source frames at
        // rate r produce N/r output frames. Getting this wrong truncates every
        // slowed export, which is the most-used preset in the app.
        let stretched = Double(audibleFrames) / Double(timePitch.rate)

        // Reverb keeps sounding after the last input sample. Without a tail the
        // export ends on an abrupt cut that was not audible during playback.
        let tailSeconds: Double = reverb.wetDryMix > 0 ? 2.5 : 0.05
        let outputFrames = AVAudioFramePosition(stretched + tailSeconds * sampleRate)

        // MARK: Render

        let maxFrames: AVAudioFrameCount = 4096
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
        } catch {
            throw OfflineRenderError.engineFailure(error.localizedDescription)
        }

        player.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(audibleFrames),
            at: nil
        )

        do {
            try engine.start()
        } catch {
            throw OfflineRenderError.engineFailure(error.localizedDescription)
        }
        player.play()

        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        let outputURL = try prepareOutputURL(for: track)
        let output: AVAudioFile
        do {
            output = try AVAudioFile(
                forWriting: outputURL,
                settings: encoderSettings(sampleRate: sampleRate, channels: format.channelCount)
            )
        } catch {
            throw OfflineRenderError.writeFailed(error.localizedDescription)
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw OfflineRenderError.engineFailure("Could not allocate a render buffer.")
        }

        while engine.manualRenderingSampleTime < outputFrames {
            let remaining = outputFrames - engine.manualRenderingSampleTime
            let toRender = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))

            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(toRender, to: buffer)
            } catch {
                throw OfflineRenderError.engineFailure(error.localizedDescription)
            }

            switch status {
            case .success:
                do {
                    try output.write(from: buffer)
                } catch {
                    throw OfflineRenderError.writeFailed(error.localizedDescription)
                }
            case .insufficientDataFromInputNode:
                // No input node in this graph, so this should not occur. Treated as
                // end-of-stream rather than an error.
                return outputURL
            case .cannotDoInCurrentContext:
                // The engine asked to be called again later. Yielding briefly is
                // the documented response.
                continue
            case .error:
                throw OfflineRenderError.engineFailure("The engine reported a render error.")
            @unknown default:
                throw OfflineRenderError.engineFailure("Unrecognized render status.")
            }

            progress?(min(1, Double(engine.manualRenderingSampleTime) / Double(outputFrames)))
        }

        progress?(1)
        return outputURL
    }

    // MARK: - Private

    private static func configureEQ(_ eq: AVAudioUnitEQ, with edit: AudioEdit) {
        let specs: [(Float, AVAudioUnitEQFilterType, Float)] = [
            (100, .lowShelf, edit.eq.lowGain),
            (1_000, .parametric, edit.eq.midGain),
            (8_000, .highShelf, edit.eq.highGain)
        ]
        for (index, spec) in specs.enumerated() where index < eq.bands.count {
            let band = eq.bands[index]
            band.filterType = spec.1
            band.frequency = spec.0
            band.bandwidth = 1.0
            band.gain = min(max(-24, spec.2), 24)
            band.bypass = false
        }
    }

    /// AAC in an .m4a container: broadly playable, and small enough to actually
    /// send to someone, which is the point of exporting.
    private static func encoderSettings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels
        ]
    }

    /// A readable, collision-free destination.
    ///
    /// Unlike imported files — which are UUID-named because their titles live in
    /// metadata — an export is going to leave the app and be seen as a file name,
    /// so it is built from the track title.
    private static func prepareOutputURL(for track: Track) throws -> URL {
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let safeTitle = track.title
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeTitle.isEmpty ? "Export" : safeTitle

        var candidate = exportDirectory.appendingPathComponent("\(base) (OmniMusik).m4a")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = exportDirectory.appendingPathComponent("\(base) (OmniMusik) \(counter).m4a")
            counter += 1
        }
        return candidate
    }
}
