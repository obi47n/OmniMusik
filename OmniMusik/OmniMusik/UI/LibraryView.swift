//
//  LibraryView.swift
//  OmniMusik
//
//  The local library. In week 4 this becomes the unified library with a source
//  filter; the row and selection behavior are already source-agnostic so that
//  change is additive.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlaybackCoordinator.self) private var coordinator

    @Query(sort: \LocalTrackEntity.dateAdded, order: .reverse)
    private var entities: [LocalTrackEntity]

    @State private var isImporting = false
    @State private var importFailures: [String] = []
    @State private var isProcessingImport = false
    @State private var studioTarget: LocalTrackEntity?

    private var tracks: [Track] { entities.map(\.asTrack) }

    private var editMap: [UUID: AudioEdit] {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0.edit) })
    }

    var body: some View {
        Group {
            if entities.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .disabled(isProcessingImport)
            }

            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    loadSamples()
                } label: {
                    Label("Load Samples", systemImage: "testtube.2")
                }
                .disabled(isProcessingImport)
            }
            #endif
        }
        .overlay {
            if isProcessingImport {
                ProgressView("Importing…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.mp3, .wav, .mpeg4Audio, .aiff, .audio],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(item: $studioTarget) { entity in
            StudioView(entity: entity)
        }
        .alert("Some files couldn't be imported", isPresented: .constant(!importFailures.isEmpty)) {
            Button("OK") { importFailures.removeAll() }
        } message: {
            Text(importFailures.joined(separator: "\n"))
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Music Yet", systemImage: "music.note.list")
        } description: {
            Text("Import MP3s from your device to build your library.")
        } actions: {
            VStack(spacing: 12) {
                Button("Import Music") { isImporting = true }
                    .buttonStyle(.borderedProminent)
                #if DEBUG
                Button("Load Sample Tracks") { loadSamples() }
                    .buttonStyle(.bordered)
                #endif
            }
        }
    }

    private var trackList: some View {
        List {
            ForEach(entities) { entity in
                TrackRow(
                    track: entity.asTrack,
                    isCurrent: coordinator.currentTrack?.id == entity.id,
                    isPlaying: coordinator.isPlaying,
                    isEdited: !entity.edit.isIdentity
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await coordinator.play(entity.asTrack, in: tracks, edits: editMap) }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        studioTarget = entity
                    } label: {
                        Label("Studio", systemImage: "slider.horizontal.3")
                    }
                    .tint(.purple)
                }
                .contextMenu {
                    Button {
                        studioTarget = entity
                    } label: {
                        Label("Open in Studio", systemImage: "slider.horizontal.3")
                    }
                    if !entity.edit.isIdentity {
                        Button(role: .destructive) {
                            entity.edit = .identity
                            coordinator.updateEdit(.identity, for: entity.id)
                            try? context.save()
                        } label: {
                            Label("Clear Effects", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    #if DEBUG
    private func loadSamples() {
        isProcessingImport = true
        Task {
            let failures = await SampleLibrary.loadSamples(into: context)
            isProcessingImport = false
            importFailures = failures
        }
    }
    #endif

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else {
            if case .failure(let error) = result {
                importFailures = [error.localizedDescription]
            }
            return
        }

        isProcessingImport = true
        Task {
            var failures: [String] = []
            for url in urls {
                do {
                    let entity = try await TrackImporter.importTrack(from: url)
                    context.insert(entity)
                } catch {
                    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    failures.append("\(url.lastPathComponent): \(reason)")
                }
            }
            try? context.save()
            isProcessingImport = false
            importFailures = failures
        }
    }

    /// Removes the database row and the backing audio file. Deleting only the row
    /// would silently leak the file — invisible to the user and unbounded over time.
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let entity = entities[index]
            if coordinator.currentTrack?.id == entity.id {
                Task { await coordinator.stopPlayback() }
            }
            try? LocalAudioStorage.delete(fileName: entity.fileName)
            context.delete(entity)
        }
        try? context.save()
    }
}

// MARK: - Row

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    var isEdited = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(data: track.artworkData)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                HStack(spacing: 4) {
                    if isEdited {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Text(track.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(track.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
