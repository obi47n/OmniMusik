//
//  Theme.swift
//  OmniMusik
//
//  Design tokens.
//
//  The Studio commits to a dark surface regardless of system appearance. Waveforms
//  need contrast against a dark ground to be readable, and every serious audio
//  editor — Logic, the editing views in GarageBand — makes the same call. The rest
//  of the app stays appearance-adaptive and picks up the purple accent from the
//  asset catalog.
//

import SwiftUI

enum Theme {

    // MARK: - Accent

    static let accent = Color.accentColor

    /// Fixed purple for surfaces that are always dark, where the adaptive accent
    /// would resolve to the darker light-mode variant and lose contrast.
    static let accentOnDark = Color(red: 0.710, green: 0.482, blue: 1.000)

    // MARK: - Studio surfaces (always dark)

    /// Page ground. Near-black rather than pure black so elevated cards read as
    /// lifted rather than floating in a void.
    static let studioBackground = Color(red: 0.055, green: 0.055, blue: 0.063)

    /// Cards, controls, parameter rows.
    static let studioCard = Color(red: 0.110, green: 0.110, blue: 0.122)

    /// Pressed or secondary card state.
    static let studioCardRaised = Color(red: 0.157, green: 0.157, blue: 0.173)

    static let studioPrimaryText = Color.white
    static let studioSecondaryText = Color(white: 0.62)
    static let studioTertiaryText = Color(white: 0.38)

    /// Waveform bars outside the current playback position.
    static let waveformInactive = Color(white: 0.30)
    static let waveformActive = Color(white: 0.92)

    // MARK: - Metrics

    static let cardRadius: CGFloat = 14
    static let pillRadius: CGFloat = 22
}

extension Font {
    /// Numeric readouts throughout the Studio. Monospacing keeps values from
    /// shifting horizontally as they change, which is most of why the reference
    /// design feels precise rather than jumpy.
    static func studioValue(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func studioLabel(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium)
    }
}
