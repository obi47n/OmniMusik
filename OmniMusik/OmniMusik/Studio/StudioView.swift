//
//  StudioView.swift
//  OmniMusik
//
//  The MP3 Studio.
//
//  Laid out as a signal chain: the waveform at the top is the source, and each
//  module below is a stage the audio passes through on its way to the output —
//  in the same order as the AVAudioEngine graph that actually renders it
//  (player → time/pitch → EQ → reverb). Connectors between modules carry the accent
//  once anything upstream is altering the signal, so the chain lights up from the
//  top down and a glance tells you what the file is being put through.
//
//  Editing is non-destructive. Every control writes into an `AudioEdit`, which the
//  engine applies at render time; the imported file is never modified, so Cancel
//  and Reset both genuinely restore the original.
//

import SwiftData
import SwiftUI

struct StudioView: View {
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entity: LocalTrackEntity

    @State private var edit = AudioEdit.identity
    @State private var originalEdit = AudioEdit.identity
    @State private var peaks: [Float] = []
    @State private var didLoad = false
    @State private var isComparing = false

    private var isCurrent: Bool { coordinator.currentTrack?.id == entity.id }

    var body: some View {
        ZStack {
            Theme.studioBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    titleBlock
                    sourceCard
                    chainSection
                    resetButton
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
        }
        .preferredColorScheme(.dark)
        .task { await loadState() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { cancel() }
                .font(.studioLabel(15))
                .foregroundStyle(Theme.studioSecondaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Theme.studioCard, in: Capsule())

            Spacer()

            Button("Save") { save() }
                .font(.studioLabel(15).weight(.semibold))
                .foregroundStyle(Theme.studioBackground)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Theme.accentOnDark, in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.studioBackground)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(entity.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.studioPrimaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(entity.artist)
                .font(.studioLabel(14))
                .foregroundStyle(Theme.studioSecondaryText)

            HStack(spacing: 8) {
                metaChip(Track.timeFormatter(entity.duration))
                metaChip(fileExtension)
                if !edit.isIdentity { metaChip("EDITED", highlighted: true) }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func metaChip(_ text: String, highlighted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .kerning(0.5)
            .foregroundStyle(highlighted ? Theme.accentOnDark : Theme.studioSecondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                highlighted ? Theme.accentOnDark.opacity(0.12) : Theme.studioCard,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }

    private var fileExtension: String {
        let ext = (entity.fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "AUDIO" : ext
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(spacing: 14) {
            WaveformView(
                peaks: peaks,
                progress: playheadFraction,
                trimStart: trimStartFraction,
                trimEnd: trimEndFraction,
                onScrub: scrub
            )
            .frame(height: 128)

            HStack {
                Text(Track.timeFormatter(isCurrent ? coordinator.currentTime : 0))
                Spacer()
                Text(Track.timeFormatter(trimmedDuration))
            }
            .font(.studioValue(12))
            .foregroundStyle(Theme.studioTertiaryText)

            transport
        }
        .padding(16)
        .background(Theme.studioCard, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var transport: some View {
        HStack(spacing: 10) {
            transportButton("gobackward", label: "Restart") {
                Task { await coordinator.seek(to: 0) }
            }

            Button {
                Task { await togglePlayback() }
            } label: {
                Image(systemName: isCurrent && coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.studioBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.accentOnDark, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            // Hold to hear the file with every effect bypassed. The reference point
            // an audio editor needs most is the untreated original, and reaching it
            // by resetting sliders would destroy the state you're comparing against.
            Text("A/B")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(isComparing ? Theme.studioBackground : Theme.studioSecondaryText)
                .frame(width: 62, height: 46)
                .background(
                    isComparing ? Theme.accentOnDark : Theme.studioCardRaised,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                    isComparing = pressing
                    coordinator.updateEdit(pressing ? .identity : edit, for: entity.id)
                }, perform: {})
                .disabled(!isCurrent || edit.isIdentity)
                .opacity(!isCurrent || edit.isIdentity ? 0.4 : 1)
        }
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.studioPrimaryText)
                .frame(width: 62, height: 46)
                .background(Theme.studioCardRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    // MARK: - Chain

    private var chainSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SIGNAL CHAIN")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1.4)
                    .foregroundStyle(Theme.studioTertiaryText)
                Spacer()
                presetMenu
            }
            .padding(.bottom, 12)

            ChainModule(title: "TIME", isEngaged: timeEngaged, summary: timeSummary) {
                VStack(spacing: 14) {
                    ChainSlider(
                        label: "Speed",
                        value: binding(\.speed),
                        range: 0.5...2.0,
                        origin: 1.0,
                        display: String(format: "%.2fx", edit.speed)
                    )
                    ChainSlider(
                        label: "Pitch",
                        value: Binding(
                            get: { edit.pitch / 100 },
                            set: { var next = edit; next.pitch = $0 * 100; update(next) }
                        ),
                        range: -12...12,
                        origin: 0,
                        display: String(format: "%+.1f st", edit.pitch / 100)
                    )
                }
            }

            ChainConnector(isLive: timeEngaged)

            ChainModule(title: "TONE", isEngaged: !edit.eq.isFlat, summary: nil) {
                VStack(spacing: 14) {
                    ChainSlider(label: "Low", value: eqBinding(\.lowGain), range: -12...12,
                                origin: 0, display: String(format: "%+.1f dB", edit.eq.lowGain))
                    ChainSlider(label: "Mid", value: eqBinding(\.midGain), range: -12...12,
                                origin: 0, display: String(format: "%+.1f dB", edit.eq.midGain))
                    ChainSlider(label: "High", value: eqBinding(\.highGain), range: -12...12,
                                origin: 0, display: String(format: "%+.1f dB", edit.eq.highGain))
                }
            }

            ChainConnector(isLive: timeEngaged || !edit.eq.isFlat)

            ChainModule(title: "SPACE", isEngaged: edit.reverbMix > 0,
                        summary: edit.reverbMix > 0 ? "medium hall" : nil) {
                ChainSlider(
                    label: "Reverb",
                    value: binding(\.reverbMix),
                    range: 0...100,
                    origin: 0,
                    display: String(format: "%.0f%%", edit.reverbMix)
                )
            }
        }
    }

    private var presetMenu: some View {
        Menu {
            Button("Slowed + Reverb") { applyPreset(.slowedReverb) }
            Button("Sped Up") { applyPreset(.spedUp) }
        } label: {
            HStack(spacing: 4) {
                Text("Presets").font(.studioLabel(12))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.accentOnDark)
        }
    }

    private var resetButton: some View {
        Button {
            update(.identity)
        } label: {
            Text("Reset to Original")
                .font(.studioLabel(14))
                .foregroundStyle(edit.isIdentity ? Theme.studioTertiaryText : Theme.studioSecondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Theme.studioCard, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .disabled(edit.isIdentity)
    }

    // MARK: - Derived

    private var timeEngaged: Bool { edit.speed != 1.0 || edit.pitch != 0 }

    private var timeSummary: String? {
        guard timeEngaged else { return nil }
        return String(format: "%.2fx", edit.speed)
    }

    private var trimmedDuration: TimeInterval {
        (edit.trimEnd ?? entity.duration) - edit.trimStart
    }

    /// Playhead as a fraction of the *whole* file. The coordinator reports
    /// trim-relative time, so the trim offset is added back — otherwise the head
    /// would sit at the left edge of the waveform whenever a start trim is set.
    private var playheadFraction: Double {
        guard entity.duration > 0, isCurrent else { return 0 }
        return min(max(0, (edit.trimStart + coordinator.currentTime) / entity.duration), 1)
    }

    private var trimStartFraction: Binding<Double> {
        Binding(
            get: { entity.duration > 0 ? edit.trimStart / entity.duration : 0 },
            set: { var next = edit; next.trimStart = $0 * entity.duration; update(next) }
        )
    }

    private var trimEndFraction: Binding<Double> {
        Binding(
            get: { entity.duration > 0 ? (edit.trimEnd ?? entity.duration) / entity.duration : 1 },
            set: {
                var next = edit
                let seconds = $0 * entity.duration
                // Store nil rather than the exact duration so "no end trim" stays
                // distinguishable from "trimmed to the very end".
                next.trimEnd = seconds >= entity.duration - 0.05 ? nil : seconds
                update(next)
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<AudioEdit, Float>) -> Binding<Float> {
        Binding(
            get: { edit[keyPath: keyPath] },
            set: { var next = edit; next[keyPath: keyPath] = $0; update(next) }
        )
    }

    private func eqBinding(_ keyPath: WritableKeyPath<EQSettings, Float>) -> Binding<Float> {
        Binding(
            get: { edit.eq[keyPath: keyPath] },
            set: { var next = edit; next.eq[keyPath: keyPath] = $0; update(next) }
        )
    }

    // MARK: - Actions

    private func loadState() async {
        if !didLoad {
            // Prefer live engine state over what's on disk: if this track is
            // playing, the coordinator holds the truth.
            let starting = isCurrent ? coordinator.currentEdit : entity.edit
            edit = starting
            originalEdit = starting
            didLoad = true
        }
        peaks = await WaveformGenerator.peaks(forFileNamed: entity.fileName)
    }

    private func togglePlayback() async {
        if isCurrent {
            await coordinator.togglePlayPause()
        } else {
            await coordinator.play(entity.asTrack, in: [entity.asTrack], edits: [entity.id: edit])
        }
    }

    private func scrub(_ fraction: Double) {
        guard isCurrent else { return }
        let absolute = fraction * entity.duration
        Task { await coordinator.seek(to: max(0, absolute - edit.trimStart)) }
    }

    private func applyPreset(_ preset: AudioEdit) {
        // Presets set time and space but leave trim alone — trim belongs to this
        // specific file, not to the treatment being applied to it.
        var next = preset
        next.trimStart = edit.trimStart
        next.trimEnd = edit.trimEnd
        update(next)
    }

    private func update(_ next: AudioEdit) {
        edit = next
        coordinator.updateEdit(next, for: entity.id)
    }

    private func save() {
        entity.edit = edit
        try? context.save()
        dismiss()
    }

    private func cancel() {
        coordinator.updateEdit(originalEdit, for: entity.id)
        dismiss()
    }
}
