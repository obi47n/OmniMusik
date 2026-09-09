//
//  ExportSheet.swift
//  OmniMusik
//
//  Renders an edited track to a file and hands it to the share sheet.
//
//  Rendering runs on a detached task: it is CPU-bound and would otherwise block
//  the main actor, freezing the very progress bar it is reporting to.
//

import SwiftUI

/// A track plus the edit to bake into it. Identifiable so it can drive `.sheet(item:)`.
struct ExportRequest: Identifiable {
    let track: Track
    let edit: AudioEdit
    var id: UUID { track.id }
}

struct ExportSheet: View {
    let request: ExportRequest

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .rendering(0)

    private enum Phase {
        case rendering(Double)
        case finished(URL)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                ArtworkView(track: request.track, cornerRadius: 10)
                    .frame(width: 140, height: 140)

                VStack(spacing: 6) {
                    Text(request.track.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                content

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 32)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await run() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .rendering(let fraction):
            VStack(spacing: 10) {
                ProgressView(value: fraction)
                    .tint(Theme.accent)
                Text("Rendering \(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

        case .finished(let url):
            VStack(spacing: 14) {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.headline)

                ShareLink(item: url) {
                    Text("Share")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .foregroundStyle(.white)
                }

                Text("Saved to Files under OmniMusik / Exports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("ExportFinished")

        case .failed(let message):
            VStack(spacing: 8) {
                Label("Export Failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Names what is actually being baked in, so the export is not a black box.
    private var summary: String {
        var parts: [String] = []
        let edit = request.edit
        if edit.speed != 1.0 { parts.append(String(format: "%.2fx speed", edit.speed)) }
        if edit.pitch != 0 { parts.append(String(format: "%+.0f cents", edit.pitch)) }
        if edit.reverbMix > 0 { parts.append("\(Int(edit.reverbMix))% reverb") }
        if !edit.eq.isFlat { parts.append("EQ") }
        if edit.trimStart > 0 || edit.trimEnd != nil { parts.append("trimmed") }
        return parts.isEmpty ? "No effects — a straight copy" : parts.joined(separator: " · ")
    }

    private func run() async {
        let request = self.request

        // Detached so the render does not inherit the main actor.
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
            do {
                let url = try OfflineRenderer.render(track: request.track, edit: request.edit) { _ in
                    // Progress is intentionally not forwarded per-buffer: at these
                    // speeds it would post thousands of main-actor hops for a bar
                    // that finishes in under a second on a typical track.
                }
                return .success(url)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let url): phase = .finished(url)
        case .failure(let error):
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
