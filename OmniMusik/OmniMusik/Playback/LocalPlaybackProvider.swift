//
//  LocalPlaybackProvider.swift
//  OmniMusik
//
//  AVAudioEngine-backed playback for locally owned audio, with the Studio's
//  effects chain attached.
//
//  Graph:  player → timePitch → EQ → reverb → mainMixer
//
//  Effects divide into two kinds, and the distinction drives the whole design:
//
//    Parametric (speed, pitch, reverb, EQ) mutate live nodes. Setting them mid-
//    playback is safe and takes effect on the next render cycle, which is what
//    makes dragging a slider feel immediate.
//
//    Structural (trim) changes *what is scheduled*, so it requires tearing down
//    the current schedule and rebuilding it. Handled separately, and only when
//    the bounds actually moved — rescheduling on every slider tick would stutter.
//
//  Positions in this class are trim-relative: a track trimmed to start at 0:30
//  reports 0:00 at its first audible sample. The UI never has to know the file's
//  absolute timeline, and the scrubber's range is always 0...duration.
//

import AVFoundation
import Foundation

@MainActor
final class LocalPlaybackProvider: PlaybackProvider {

    let source: TrackSource = .local
    var onTrackFinished: (@MainActor () -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 3)
    private let reverb = AVAudioUnitReverb()

    private var audioFile: AVAudioFile?
    private var sampleRate: Double = 44_100
    private var isActive = false

    private var edit: AudioEdit = .identity

    /// Absolute frame bounds of the audible region. `trimEndFrame` is exclusive.
    private var trimStartFrame: AVAudioFramePosition = 0
    private var trimEndFrame: AVAudioFramePosition = 0

    /// Trim-relative frame the current schedule began at. `playerTime` resets to
    /// zero on every `stop()`, and seeking is stop-and-reschedule, so absolute
    /// position is only recoverable as `seekFrame + playerTime.sampleTime`.
    private var seekFrame: AVAudioFramePosition = 0

    /// Invalidates in-flight completion handlers. `scheduleSegment`'s callback also
    /// fires when playback is cancelled by `stop()`, which during a seek or trim
    /// change would advance the queue out from under the transition in progress.
    private var scheduleGeneration = 0

    private var playing = false
    var isPlaying: Bool { playing }

    private var audibleLength: AVAudioFramePosition { max(0, trimEndFrame - trimStartFrame) }
    var duration: TimeInterval { sampleRate > 0 ? Double(audibleLength) / sampleRate : 0 }

    // MARK: - Init

    init() {
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(eqNode)
        engine.attach(reverb)
        configureEQBands()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
    }

    private func configureEQBands() {
        let specs: [(frequency: Float, type: AVAudioUnitEQFilterType)] = [
            (100, .lowShelf), (1_000, .parametric), (8_000, .highShelf)
        ]
        for (index, spec) in specs.enumerated() where index < eqNode.bands.count {
            let band = eqNode.bands[index]
            band.filterType = spec.type
            band.frequency = spec.frequency
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    // MARK: - Position

    /// Trim-relative playback position.
    ///
    /// `playerTime.sampleTime` counts source frames the player has rendered, so it
    /// advances faster than wall clock when `timePitch.rate > 1`. That is exactly
    /// what the scrubber wants — position within the file — and it stays correct
    /// under rate changes. Wall-clock time remaining, if ever displayed, is
    /// `(duration - currentTime) / rate`.
    var currentTime: TimeInterval {
        guard audioFile != nil, sampleRate > 0 else { return 0 }
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return min(Double(seekFrame) / sampleRate, duration)
        }
        let elapsed = Double(seekFrame + playerTime.sampleTime) / sampleRate
        return min(max(0, elapsed), duration)
    }

    // MARK: - PlaybackProvider

    func load(_ track: Track) async throws {
        try await load(track, edit: .identity)
    }

    func load(_ track: Track, edit newEdit: AudioEdit) async throws {
        guard track.source == .local else {
            throw PlaybackError.sourceMismatch(expected: .local, got: track.source)
        }

        teardown()

        let url = LocalAudioStorage.url(forFileName: track.sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PlaybackError.fileNotFound(track.title)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw PlaybackError.unsupportedFormat
        }

        let format = file.processingFormat
        guard format.sampleRate > 0, file.length > 0 else {
            throw PlaybackError.unsupportedFormat
        }

        audioFile = file
        sampleRate = format.sampleRate
        edit = newEdit
        isActive = true
        recomputeTrimBounds()

        guard audibleLength > 0 else {
            throw PlaybackError.engineFailure("Trim range leaves nothing to play.")
        }

        try activateSession()
        connectGraph(format: format)
        applyParametricEffects()
        scheduleSegment(fromRelativeFrame: 0)
    }

    func play() async throws {
        guard isActive else { return }
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            throw PlaybackError.engineFailure(error.localizedDescription)
        }
        playerNode.play()
        playing = true
    }

    func pause() {
        guard isActive else { return }
        playerNode.pause()
        playing = false
    }

    func stop() { teardown() }

    func seek(to time: TimeInterval) async {
        guard isActive else { return }

        let target = min(max(0, time), duration)
        let frame = AVAudioFramePosition(target * sampleRate)
        let resume = playing

        // Invalidate before stopping: stop() triggers the pending completion.
        scheduleGeneration += 1
        playerNode.stop()
        playing = false

        guard frame < audibleLength else {
            seekFrame = audibleLength
            finishTrack()
            return
        }

        scheduleSegment(fromRelativeFrame: frame)
        if resume { try? await play() }
    }

    // MARK: - Studio

    /// Current effect state, so the Studio can open showing what's actually applied.
    var currentEdit: AudioEdit { edit }

    /// Applies an edit to live playback.
    ///
    /// Parametric changes take effect on the next render cycle. A trim change
    /// reschedules, preserving the listening position where possible so adjusting
    /// the end bound doesn't yank playback back to the start.
    func apply(_ newEdit: AudioEdit) {
        let trimMoved = newEdit.trimStart != edit.trimStart || newEdit.trimEnd != edit.trimEnd
        edit = newEdit
        applyParametricEffects()
        guard isActive, trimMoved else { return }

        let positionBefore = currentTime + Double(trimStartFrame) / sampleRate
        recomputeTrimBounds()

        guard audibleLength > 0 else {
            scheduleGeneration += 1
            playerNode.stop()
            playing = false
            return
        }

        // Re-anchor the old absolute position inside the new bounds.
        let relative = positionBefore - Double(trimStartFrame) / sampleRate
        let clamped = min(max(0, relative), duration)
        Task { await seek(to: clamped) }
    }

    private func applyParametricEffects() {
        timePitch.rate = min(max(0.25, edit.speed), 4.0)
        timePitch.pitch = min(max(-2_400, edit.pitch), 2_400)
        reverb.wetDryMix = min(max(0, edit.reverbMix), 100)

        let gains = [edit.eq.lowGain, edit.eq.midGain, edit.eq.highGain]
        for (index, gain) in gains.enumerated() where index < eqNode.bands.count {
            eqNode.bands[index].gain = min(max(-24, gain), 24)
        }
    }

    private func recomputeTrimBounds() {
        guard let file = audioFile else { return }
        let total = file.length
        let start = AVAudioFramePosition(max(0, edit.trimStart) * sampleRate)
        let end = edit.trimEnd.map { AVAudioFramePosition($0 * sampleRate) } ?? total

        trimStartFrame = min(max(0, start), total)
        trimEndFrame = min(max(trimStartFrame, end), total)
    }

    // MARK: - Private

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw PlaybackError.engineFailure("Audio session: \(error.localizedDescription)")
        }
    }

    /// Reconnected per file: sample rate and channel count vary between imports, and
    /// a graph wired for 44.1kHz stereo misbehaves silently on a 48kHz mono file.
    private func connectGraph(format: AVAudioFormat) {
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: eqNode, format: format)
        engine.connect(eqNode, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
    }

    private func scheduleSegment(fromRelativeFrame frame: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        let remaining = audibleLength - frame
        guard remaining > 0 else { return }

        scheduleGeneration += 1
        let generation = scheduleGeneration
        seekFrame = frame

        playerNode.scheduleSegment(
            file,
            startingFrame: trimStartFrame + frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.scheduleGeneration == generation, self.playing else { return }
                self.finishTrack()
            }
        }
    }

    private func finishTrack() {
        playing = false
        onTrackFinished?()
    }

    private func teardown() {
        scheduleGeneration += 1
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        playing = false
        isActive = false
        seekFrame = 0
        trimStartFrame = 0
        trimEndFrame = 0
        audioFile = nil
        edit = .identity
    }
}
