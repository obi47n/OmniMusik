//
//  AudioEditTests.swift
//  OmniMusikTests
//
//  Coverage for the edit value type and its round-trip through persistence.
//
//  `AudioEdit` is stored as encoded data on every track, so a Codable change that
//  silently drops a field would lose people's work with no error anywhere. That is
//  the failure this suite is here to catch.
//

import Foundation
import Testing
@testable import OmniMusik

@Suite("AudioEdit")
struct AudioEditTests {

    @Test("The identity edit reports itself as unmodified")
    func identityIsIdentity() {
        #expect(AudioEdit.identity.isIdentity)
        #expect(EQSettings.flat.isFlat)
    }

    @Test("Any single changed parameter makes an edit non-identity")
    func anyChangeBreaksIdentity() {
        var speed = AudioEdit.identity
        speed.speed = 1.25
        #expect(!speed.isIdentity)

        var pitch = AudioEdit.identity
        pitch.pitch = 200
        #expect(!pitch.isIdentity)

        var reverb = AudioEdit.identity
        reverb.reverbMix = 30
        #expect(!reverb.isIdentity)

        var eq = AudioEdit.identity
        eq.eq.lowGain = 3
        #expect(!eq.isIdentity)

        var trim = AudioEdit.identity
        trim.trimStart = 5
        #expect(!trim.isIdentity)
    }

    @Test("Presets are real edits, not accidentally identity")
    func presetsAreNotIdentity() {
        #expect(!AudioEdit.slowedReverb.isIdentity)
        #expect(!AudioEdit.spedUp.isIdentity)
        #expect(AudioEdit.slowedReverb.speed < 1.0)
        #expect(AudioEdit.spedUp.speed > 1.0)
    }

    @Test("An edit survives a JSON round trip unchanged")
    func codableRoundTripPreservesEveryField() throws {
        var original = AudioEdit.identity
        original.speed = 0.85
        original.pitch = -300
        original.reverbMix = 42
        original.eq = EQSettings(lowGain: 4, midGain: -2, highGain: 6)
        original.trimStart = 12.5
        original.trimEnd = 180.25

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEdit.self, from: data)

        #expect(decoded == original)
        #expect(decoded.trimEnd == 180.25)
        #expect(decoded.eq.midGain == -2)
    }

    @Test("An absent trim end round trips as absent, not as zero")
    func openEndedTrimRoundTrips() throws {
        var edit = AudioEdit.identity
        edit.trimStart = 3
        #expect(edit.trimEnd == nil)

        let decoded = try JSONDecoder().decode(
            AudioEdit.self,
            from: try JSONEncoder().encode(edit)
        )

        // A nil trim end means "play to the end of the file". Decoding it as 0
        // would silently trim every track to nothing.
        #expect(decoded.trimEnd == nil)
    }
}
