//
//  AudioEdit.swift
//  OmniMusik
//
//  A non-destructive description of an effects chain.
//
//  Edits are stored as parameters, never baked into the source file. The original
//  import stays pristine; the effect graph applies these values at render time, and
//  export renders a new file rather than mutating the old one. That makes every edit
//  reversible and keeps a single audio file backing any number of edited variants.
//

import Foundation

/// Parametric EQ settings. Three bands is enough to be musically useful without
/// turning the UI into a mixing console.
struct EQSettings: Codable, Hashable, Sendable {
    /// Gain in dB, clamped to ±24 by the effect node.
    var lowGain: Float = 0
    var midGain: Float = 0
    var highGain: Float = 0

    static let flat = EQSettings()
    var isFlat: Bool { self == .flat }
}

/// The complete effect state for one local track.
struct AudioEdit: Codable, Hashable, Sendable {
    /// Playback rate multiplier. 1.0 is unmodified; below 1.0 is the "slowed" effect.
    var speed: Float = 1.0

    /// Pitch shift in cents (100 cents = 1 semitone).
    ///
    /// Separate from `speed` on purpose: `AVAudioUnitTimePitch` decouples them, so
    /// slowing a track without the tape-style pitch drop is possible — which is
    /// exactly what the "slowed + reverb" treatment expects.
    var pitch: Float = 0

    /// Reverb wet/dry mix, 0–100.
    var reverbMix: Float = 0

    var eq: EQSettings = .flat

    /// Trim bounds in seconds. `trimEnd == nil` means "play to the end of file".
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval?

    static let identity = AudioEdit()

    /// Whether this edit would audibly change anything. Lets the engine skip
    /// reconfiguring the graph, and lets the UI show an "edited" badge honestly.
    var isIdentity: Bool {
        speed == 1.0 && pitch == 0 && reverbMix == 0 && eq.isFlat
            && trimStart == 0 && trimEnd == nil
    }
}

extension AudioEdit {
    /// Preset: the slowed + reverb treatment, as a starting point users can adjust.
    static let slowedReverb = AudioEdit(speed: 0.85, pitch: 0, reverbMix: 40)

    /// Preset: sped up, pitch compensated upward to match.
    static let spedUp = AudioEdit(speed: 1.25, pitch: 0, reverbMix: 0)
}
