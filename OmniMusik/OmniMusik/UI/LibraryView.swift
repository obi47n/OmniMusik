//
//  LibraryView.swift
//  OmniMusik
//
//  The unified library.
//
//  Merges the reactive local library with fetched remote sources into one list,
//  filterable by source. Rows are source-agnostic; only the actions differ, since
//  a local track can be edited in the Studio and deleted while an Apple Music track
//  can be neither.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(LibraryStore.self) private var store

    @Query(sort: \LocalTrackEntity.dateAdded, order: .reverse)
    private var entities: [LocalTrackEntity]

    @State private var filter: SourceFilter = .all
    @State private var isImporting = false
    @State private var importFailures: [String] = []
    @State private var isProcessingImport = false
    @State private var studioTarget: LocalTrackEntity?
    @State private var addToPlaylistTarget: Track?

    enum SourceFilter: Hashable {
        case all
        case source(TrackSource)

        var title: String {
            switch self {
            case .all: "All"
            case .source(let source): source.displayName
            }
        }
    }

    private var filters: [SourceFilter] {
        [.all] + TrackSource.allCases.map { SourceFilter.source($0) }
    }

    private var entitiesByID: [UUID: LocalTrackEntity] {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
    }

    private var editMap: [UUID: AudioEdit] {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0.edit) })
    }

    private var allTracks: [Track] {
        entities.map(\.asTrack) + store.remoteTracks
    }

    private var visibleTracks: [Track] {
        switch filter {
        case .all: allTracks
        case .source(let source): allTracks.filter { $0.source == source }
        }
    }

    var body: some View {
        Group {
            if allTracks.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Library")
        .sheet(item: $addToPlaylistTarget) { track in
            AddToPlaylistView(track: track)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isImporting = true } label: {
                    Label("Import", systemImage: "plus")
                }
                .disabled(isProcessingImport)
            }

            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                Button { loadSamples() } label: {
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
        .task { await store.refresh() }
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

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            Picker("Source", selection: $filter) {
                ForEach(filters, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if visibleTracks.isEmpty {
                emptyFilterState
            } else {
                trackList
            }
        }
    }

    private var trackList: some View {
        List {
            ForEach(visibleTracks) { track in
                row(for: track)
            }

            if !store.notes.isEmpty {
                Section {
                    ForEach(Array(store.notes.keys), id: \.self) { source in
                        Label(store.notes[source] ?? "", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func row(for track: Track) -> some View {
        let entity = entitiesByID[track.id]

        TrackRow(
            track: track,
            isCurrent: coordinator.currentTrack?.id == track.id,
            isPlaying: coordinator.isPlaying,
            isEdited: !(editMap[track.id] ?? .identity).isIdentity
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await coordinator.play(track, in: visibleTracks, edits: editMap) }
        }
        // Studio and delete apply only to files we own. Apple Music tracks get a
        // plain row rather than disabled actions that imply a missing feature.
        .swipeActions(edge: .leading) {
            if let entity {
                Button { studioTarget = entity } label: {
                    Label("Studio", systemImage: "slider.horizontal.3")
                }
                .tint(Theme.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            if let entity {
                Button(role: .destructive) { delete(entity) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            Button { addToPlaylistTarget = track } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            if let entity {
                Button { studioTarget = entity } label: {
                    Label("Open in Studio", systemImage: "slider.horizontal.3")
                }
                if !entity.edit.isIdentity {
                    Button {
                        entity.edit = .identity
                        coordinator.updateEdit(.identity, for: entity.id)
                        try? context.save()
                    } label: {
                        Label("Clear Effects", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Music Yet", systemImage: "music.note.list")
        } description: {
            Text("Import MP3s from your device, or connect Apple Music.")
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

    private var emptyFilterState: some View {
        ContentUnavailableView {
            Label("Nothing Here", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No tracks from this source yet.")
        }
        .frame(maxHeight: .infinity)
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

    /// Removes the row and the backing file. Deleting only the row would leak the
    /// audio — invisible to the user and unbounded over time.
    private func delete(_ entity: LocalTrackEntity) {
        if coordinator.currentTrack?.id == entity.id {
            Task { await coordinator.stopPlayback() }
        }
        try? LocalAudioStorage.delete(fileName: entity.fileName)
        context.delete(entity)
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
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)

                HStack(spacing: 4) {
                    if isEdited {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
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
                    .foregroundStyle(Theme.accent)
            } else {
                Text(track.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
