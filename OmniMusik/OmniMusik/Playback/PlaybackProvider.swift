//
//  PlaybackProvider.swift
//  OmniMusik
//
//  The abstraction that makes OmniMusik possible.
//
//  Apple Music and local audio are not variations on one playback system — they are
//  two incompatible ones. Local files run through an AVAudioEngine graph we own
//  sample-by-sample. Apple Music runs through ApplicationMusicPlayer, a system-owned
//  player that exposes transport controls and nothing else: no buffers, no taps, no
//  effects, no shared clock.
//
//  Rather than leak that split into every view, each system is wrapped in a provider
//  satisfying this protocol, and `PlaybackCoordinator` orchestrates handoff between
//  them at track boundaries. The UI talks to the coordinator and never learns which
//  engine is running.
//
//  Everything here is @MainActor: providers drive observable UI state, and the cost
//  of hopping actors for transport controls is irrelevant next to the clarity of
//  having exactly one place playback state can be mutated.
//

import Foundation

@MainActor
protocol PlaybackProvider: AnyObject {
    /// Which source this provider handles. `PlaybackCoordinator` routes on this.
    var source: TrackSource { get }

    /// Position within the current track, in seconds.
    ///
    /// Polled rather than published: AVAudioEngine has no built-in periodic time
    /// observer, and a provider pushing updates at its own cadence would fight the
    /// coordinator's display-linked timer.
    var currentTime: TimeInterval { get }

    /// Duration of the loaded track, or 0 when nothing is loaded.
    var duration: TimeInterval { get }

    var isPlaying: Bool { get }

    /// Whether this provider decodes audio inside our process.
    ///
    /// True for the AVAudioEngine graph; false for anything that remote-controls
    /// another player. It decides who owns the audio session, and therefore what an
    /// interruption notification *means*.
    ///
    /// When a remote provider is active, another app legitimately owns audio, and
    /// iOS reports that to us as an interruption. Treating it as one and pausing is
    /// how OmniMusik ends up interrupting the very playback it just started.
    var rendersAudioInProcess: Bool { get }

    /// Prepare a track for playback without starting it.
    /// Throws if the track cannot be resolved or the source rejects it.
    func load(_ track: Track) async throws

    func play() async throws
    func pause()

    /// Stop and release the loaded track. Providers must be safe to `stop()` when
    /// nothing is loaded — the coordinator calls it defensively during handoff.
    func stop()

    func seek(to time: TimeInterval) async

    /// Invoked when the current track finishes on its own.
    ///
    /// Must NOT fire for stops the coordinator initiated, or advancing the queue
    /// would race with the handoff already in flight.
    var onTrackFinished: (@MainActor () -> Void)? { get set }
}

/// Errors surfaced from providers, kept source-agnostic so the UI can present them
/// without switching on which engine failed.
enum PlaybackError: LocalizedError {
    case fileNotFound(String)
    case unsupportedFormat
    case engineFailure(String)
    case notAuthorized
    case sourceMismatch(expected: TrackSource, got: TrackSource)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            "Couldn't find the audio file for \(name). It may have been moved or deleted."
        case .unsupportedFormat:
            "This audio format isn't supported."
        case .engineFailure(let detail):
            "Audio engine error: \(detail)"
        case .notAuthorized:
            "OmniMusik needs permission to access your music library."
        case .sourceMismatch(let expected, let got):
            "Internal routing error: \(expected.displayName) provider received a \(got.displayName) track."
        }
    }
}
