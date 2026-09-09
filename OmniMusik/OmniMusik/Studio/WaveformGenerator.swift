//
//  WaveformGenerator.swift
//  OmniMusik
//
//  Reduces an audio file to a fixed number of amplitude peaks for display.
//
//  A three-minute stereo track is roughly 16 million samples; a waveform view needs
//  a few hundred bars. This walks the file once in chunks, keeping the maximum
//  absolute amplitude per bucket, and normalizes the result so quiet recordings
//  still fill the display rather than rendering as a flat line.
//
//  Runs off the main actor — it is genuinely CPU-bound — and caches by file name,
//  since the Studio reopens the same track repeatedly and the file never changes
//  once imported.
//

import AVFoundation
import Foundation

actor WaveformCache {
    static let shared = WaveformCache()
    private var storage: [String: [Float]] = [:]

    func peaks(for fileName: String, buckets: Int) -> [Float]? {
        guard let cached = storage[key(fileName, buckets)] else { return nil }
        return cached
    }

    func store(_ peaks: [Float], for fileName: String, buckets: Int) {
        storage[key(fileName, buckets)] = peaks
    }

    private func key(_ fileName: String, _ buckets: Int) -> String { "\(fileName)#\(buckets)" }
}

enum WaveformGenerator {

    /// Peak amplitudes normalized to 0...1, one per bucket.
    /// Returns an empty array if the file can't be read — callers render a
    /// placeholder rather than treating it as an error worth surfacing.
    static func peaks(forFileNamed fileName: String, buckets: Int = 240) async -> [Float] {
        if let cached = await WaveformCache.shared.peaks(for: fileName, buckets: buckets) {
            return cached
        }

        // Only the file name crosses the isolation boundary; AVAudioFile is created
        // and consumed entirely inside the detached task.
        let computed = await Task.detached(priority: .userInitiated) { () -> [Float] in
            (try? analyze(fileName: fileName, buckets: buckets)) ?? []
        }.value

        if !computed.isEmpty {
            await WaveformCache.shared.store(computed, for: fileName, buckets: buckets)
        }
        return computed
    }

    private static func analyze(fileName: String, buckets: Int) throws -> [Float] {
        let url = LocalAudioStorage.url(forFileName: fileName)
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length

        guard totalFrames > 0, buckets > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768)
        else { return [] }

        let framesPerBucket = Double(totalFrames) / Double(buckets)
        var peaks = [Float](repeating: 0, count: buckets)
        let channelCount = Int(format.channelCount)
        var frameIndex: Int64 = 0

        while frameIndex < totalFrames {
            try file.read(into: buffer, frameCount: 32_768)
            let framesRead = Int(buffer.frameLength)
            guard framesRead > 0, let channels = buffer.floatChannelData else { break }

            for sample in 0..<framesRead {
                var magnitude: Float = 0
                for channel in 0..<channelCount {
                    magnitude = max(magnitude, abs(channels[channel][sample]))
                }
                let bucket = min(buckets - 1, Int(Double(frameIndex + Int64(sample)) / framesPerBucket))
                peaks[bucket] = max(peaks[bucket], magnitude)
            }
            frameIndex += Int64(framesRead)
        }

        // Normalize so a quietly-mastered file still fills the view.
        if let loudest = peaks.max(), loudest > 0 {
            for index in peaks.indices { peaks[index] /= loudest }
        }
        return peaks
    }
}
