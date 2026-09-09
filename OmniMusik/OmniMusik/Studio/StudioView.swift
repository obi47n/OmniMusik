//
//  StudioView.swift
//  OmniMusik
//
//  The MP3 Studio: real-time effects for locally owned audio.
//
//  Editing is non-destructive. Nothing here touches the imported file — every
//  control writes into an `AudioEdit`, which the engine applies at render time and
//  SwiftData stores as parameters. Reset genuinely restores the original because
//  the original was never modified.
//
//  Changes apply to live playback as they're dragged, but persist only on dismiss:
//  encoding JSON on every slider tick would mean hundreds of writes per adjustment
//  for no benefit.
//

import SwiftData
import SwiftUI

struct StudioView: View {
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entity: LocalTrackEntity

    @State private var edit = AudioEdit.identity
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                presetsSection
                timeSection
                spaceSection
                toneSection
                trimSection
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { update(.identity) }
                        .disabled(edit.isIdentity)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
        .onAppear {
            // Prefer what's actually loaded in the engine over what's on disk: if
            // this track is playing, the coordinator holds the live state.
            guard !didLoad else { return }
            edit = coordinator.currentTrack?.id == entity.id ? coordinator.currentEdit : entity.edit
            didLoad = true
        }
        .onDisappear(perform: persist)
    }

    // MARK: - Sections

    private var presetsSection: some View {
        Section {
            HStack(spacing: 10) {
                presetButton("Slowed + Reverb", preset: .slowedReverb)
                presetButton("Sped Up", preset: .spedUp)
            }
        } header: {
            Text("Presets")
        } footer: {
            Text(entity.title).font(.footnote)
        }
    }

    private var timeSection: some View {
        Section("Time") {
            labeledSlider(
                "Speed",
                value: Binding(
                    get: { edit.speed },
                    set: { value in var next = edit; next.speed = value; update(next) }
                ),
                range: 0.5...2.0,
                display: String(format: "%.2fx", edit.speed)
            )

            // Pitch is stored in cents but shown in semitones — cents are the unit
            // AVAudioUnitTimePitch takes, semitones are the unit musicians think in.
            labeledSlider(
                "Pitch",
                value: Binding(
                    get: { edit.pitch / 100 },
                    set: { semitones in var next = edit; next.pitch = semitones * 100; update(next) }
                ),
                range: -12...12,
                display: String(format: "%+.1f st", edit.pitch / 100)
            )
        }
    }

    private var spaceSection: some View {
        Section {
            labeledSlider(
                "Reverb",
                value: Binding(
                    get: { edit.reverbMix },
                    set: { value in var next = edit; next.reverbMix = value; update(next) }
                ),
                range: 0...100,
                display: String(format: "%.0f%%", edit.reverbMix)
            )
        } header: {
            Text("Space")
        } footer: {
            Text("Medium hall, mixed against the dry signal.")
        }
    }

    private var toneSection: some View {
        Section("Tone") {
            eqSlider("Low", keyPath: \.lowGain)
            eqSlider("Mid", keyPath: \.midGain)
            eqSlider("High", keyPath: \.highGain)
        }
    }

    private var trimSection: some View {
        Section {
            labeledSlider(
                "Start",
                value: Binding(
                    get: { edit.trimStart },
                    set: { value in
                        var next = edit
                        next.trimStart = min(value, (next.trimEnd ?? entity.duration) - 1)
                        update(next)
                    }
                ),
                range: 0...max(entity.duration - 1, 1),
                display: Track.timeFormatter(edit.trimStart)
            )

            labeledSlider(
                "End",
                value: Binding(
                    get: { edit.trimEnd ?? entity.duration },
                    set: { value in
                        var next = edit
                        next.trimEnd = value >= entity.duration ? nil : max(value, next.trimStart + 1)
                        update(next)
                    }
                ),
                range: 1...entity.duration,
                display: Track.timeFormatter(edit.trimEnd ?? entity.duration)
            )
        } header: {
            Text("Trim")
        } footer: {
            Text("Trimming reschedules playback, so the position may jump slightly.")
        }
    }

    // MARK: - Components

    private func presetButton(_ title: String, preset: AudioEdit) -> some View {
        Button(title) {
            // Presets set time and space but leave trim alone — trim is a property
            // of this specific file, not of the treatment being applied.
            var next = preset
            next.trimStart = edit.trimStart
            next.trimEnd = edit.trimEnd
            update(next)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func eqSlider(_ title: String, keyPath: WritableKeyPath<EQSettings, Float>) -> some View {
        labeledSlider(
            title,
            value: Binding(
                get: { edit.eq[keyPath: keyPath] },
                set: { value in var next = edit; next.eq[keyPath: keyPath] = value; update(next) }
            ),
            range: -12...12,
            display: String(format: "%+.1f dB", edit.eq[keyPath: keyPath])
        )
    }

    // MARK: - Plumbing

    private func update(_ next: AudioEdit) {
        edit = next
        coordinator.updateEdit(next, for: entity.id)
    }

    private func persist() {
        entity.edit = edit
        try? context.save()
    }
}
