//
//  PlaybackCoordinator.swift
//  OmniMusik
//
//  The single playback surface the UI talks to.
//
//  Owns one provider per source, routes each track to the provider that can play
//  it, and handles handoff when consecutive tracks in a queue belong to different
//  engines. Views observe this object and never touch a provider directly — which
//  is what lets the Apple Music provider arrive in week 3 without any view changing.
//

import Foundation
import Observation

@MainActor
@Observable
final class PlaybackCoordinator {

    // MARK: - Observable state

    private(set) var currentTrack: Track?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// Surfaced to the UI as an alert. Playback failures are routine — a deleted
    /// file, a trim range with nothing in it — and shouldn't be fatal.
    var errorMessage: String?

    private(set) var queue: [Track] = []
    private(set) var queueIndex = 0

    /// Effects state for the current track, so the Studio opens showing what's
    /// actually applied rather than defaults.
    private(set) var currentEdit: AudioEdit = .identity

    // MARK: - Providers

    private let localProvider = LocalPlaybackProvider()

    /// Injected rather than constructed here, because it needs a Spotify access
    /// token and the coordinator has no business knowing how one is obtained.
    /// Absent until a Spotify connection exists, which is what routing checks.
    private var spotifyProvider: SpotifyPlaybackProvider?

    /// Most recent Spotify handoff note, shown in Now Playing in debug builds.
    private(set) var spotifyDiagnostic: String?
    private var activeProvider: (any PlaybackProvider)?

    /// Saved edits for the tracks in the queue.
    ///
    /// The coordinator has no `ModelContext` on purpose — it shouldn't know that
    /// local tracks happen to be SwiftData-backed while Apple Music tracks aren't.
    /// The view layer, which does own that context, supplies edits when it sets a
    /// queue, and the coordinator just carries them.
    private var queueEdits: [UUID: AudioEdit] = [:]

    /// Position polling. AVAudioEngine has no periodic time observer and MusicKit's
    /// differs in shape, so the coordinator polls uniformly rather than having each
    /// provider push on its own schedule.
    private var ticker: Task<Void, Never>?

    private let sessionObserver = AudioSessionObserver()

    /// Whether playback was running when an interruption began, so it is only
    /// resumed afterwards if it was actually playing before.
    private var wasPlayingBeforeInterruption = false

    // MARK: - Init

    init() {
        localProvider.onTrackFinished = { [weak self] in
            self?.advanceAfterCompletion()
        }
        configureRemoteCommands()
        configureSessionHandling()
    }

    /// Supplies the Spotify provider once a connection exists.
    ///
    /// Called by the app on launch and after connecting, rather than the coordinator
    /// reaching for a source: routing stays a lookup, and a provider that cannot work
    /// is simply absent rather than present-and-failing.
    func attachSpotifyProvider(_ provider: SpotifyPlaybackProvider?) {
        spotifyProvider?.onTrackFinished = nil
        // Replacing the provider is the one place the old connection is genuinely
        // finished with, so it is released rather than left dangling.
        spotifyProvider?.releaseConnection()
        spotifyProvider = provider
        provider?.onTrackFinished = { [weak self] in
            self?.advanceAfterCompletion()
        }
        provider?.onDiagnostic = { [weak self] note in
            self?.spotifyDiagnostic = note
        }
    }

    private func configureRemoteCommands() {
        NowPlayingCenter.shared.configure(with: .init(
            play: { [weak self] in Task { await self?.resume() } },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in Task { await self?.togglePlayPause() } },
            next: { [weak self] in Task { await self?.next() } },
            previous: { [weak self] in Task { await self?.previous() } },
            seek: { [weak self] time in Task { await self?.seek(to: time) } }
        ))
    }

    private func configureSessionHandling() {
        sessionObserver.onInterruptionBegan = { [weak self] in
            guard let self, self.ownsAudioSession else { return }
            self.wasPlayingBeforeInterruption = self.isPlaying
            self.pause()
        }
        sessionObserver.onInterruptionEnded = { [weak self] shouldResume in
            guard let self, self.ownsAudioSession,
                  shouldResume, self.wasPlayingBeforeInterruption else { return }
            Task { await self.resume() }
        }
        // Headphones pulled: pause rather than continue out of the speaker. Only our
        // own output — the Spotify app handles its own route changes, and pausing it
        // from here would fight whatever it already did.
        sessionObserver.onOutputDisconnected = { [weak self] in
            guard let self, self.ownsAudioSession else { return }
            self.pause()
        }
        sessionObserver.start()
    }

    // MARK: - Transport

    /// Starts `track`, using `tracks` as the surrounding queue and `edits` as the
    /// saved effect state for any of them that has one.
    func play(_ track: Track, in tracks: [Track], edits: [UUID: AudioEdit] = [:]) async {
        queue = tracks
        queueEdits = edits
        queueIndex = tracks.firstIndex(of: track) ?? 0
        await start(track)
    }

    func togglePlayPause() async {
        if isPlaying { pause() } else { await resume() }
    }

    func resume() async {
        guard let provider = activeProvider, !isPlaying else { return }
        do {
            try await provider.play()
            isPlaying = true
            startTicking()
            publishNowPlaying()

            // Prepare the next provider while this track plays, so a source change
            // at the boundary does not stall or bounce into another app.
            warmUpcomingProviderIfNeeded()
        } catch {
            present(error)
        }
    }

    func pause() {
        guard let provider = activeProvider, isPlaying else { return }
        provider.pause()
        isPlaying = false
        stopTicking()
        publishNowPlaying()
    }

    func next() async {
        guard !queue.isEmpty else { return }
        let target = queueIndex + 1
        guard target < queue.count else {
            await stopPlayback()
            return
        }
        queueIndex = target
        await start(queue[target])
    }

    /// Restarts the current track when more than three seconds in, otherwise steps
    /// back — the behavior every music player has trained users to expect.
    func previous() async {
        guard let provider = activeProvider else { return }
        if provider.currentTime > 3.0 || queueIndex == 0 {
            await seek(to: 0)
            return
        }
        queueIndex -= 1
        await start(queue[queueIndex])
    }

    func seek(to time: TimeInterval) async {
        guard let provider = activeProvider else { return }
        await provider.seek(to: time)
        currentTime = provider.currentTime
        publishNowPlaying()
    }

    func stopPlayback() async {
        activeProvider?.stop()
        activeProvider = nil
        currentTrack = nil
        currentEdit = .identity
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTicking()
        NowPlayingCenter.shared.clear()
    }

    // MARK: - Studio

    /// Applies an edit to the playing track. Parametric changes land on the next
    /// render cycle; a trim change reschedules and re-anchors the position.
    ///
    /// Persisting the edit is the caller's job — the coordinator holds it only for
    /// the life of the queue.
    func updateEdit(_ edit: AudioEdit, for trackID: UUID) {
        queueEdits[trackID] = edit
        guard currentTrack?.id == trackID else { return }
        currentEdit = edit
        (activeProvider as? LocalPlaybackProvider)?.apply(edit)
        duration = activeProvider?.duration ?? duration
        publishNowPlaying()
    }

    // MARK: - Routing

    private func provider(for source: TrackSource) -> (any PlaybackProvider)? {
        switch source {
        case .local:
            return localProvider
        case .appleMusic:
            return nil  // awaiting MusicKit provisioning
        case .spotify:
            return spotifyProvider
        }
    }

    /// Whether OmniMusik is the app currently producing audio.
    ///
    /// Session notifications are only ours to act on when this is true. While a
    /// remote provider is active another app owns audio by design, and iOS reports
    /// that as an interruption — acting on it means pausing playback we deliberately
    /// started somewhere else.
    private var ownsAudioSession: Bool {
        activeProvider?.rendersAudioInProcess ?? false
    }

    /// Warms the Spotify connection when a Spotify track is next in the queue.
    ///
    /// Establishing the remote connection takes a moment, and if the Spotify app is
    /// not running it needs a foreground switch. Doing it while the *current* track
    /// is still playing makes the handoff at the track boundary silent: by the time
    /// the queue reaches the Spotify track the connection already exists, so play()
    /// takes its quiet path instead of waking Spotify.
    ///
    /// Nothing can make it silent when Spotify is not running at all — no API lets a
    /// background app launch another one invisibly.
    private func warmUpcomingProviderIfNeeded() {
        let next = queueIndex + 1
        guard next < queue.count, queue[next].source == .spotify else { return }
        guard let spotifyProvider else { return }
        Task { await spotifyProvider.connectIfPossible() }
    }

    private func start(_ track: Track) async {
        guard let provider = provider(for: track.source) else {
            errorMessage = "\(track.source.displayName) playback isn't available yet."
            return
        }

        // Handoff: silence the outgoing engine before the incoming one loads, or
        // both briefly hold the audio session and the first frames get clipped.
        if let active = activeProvider, active !== provider {
            active.stop()

            // Moving to a provider that renders elsewhere means giving the audio
            // session back. Holding it while another app plays leaves two apps
            // contending, and iOS resolves that by interrupting one of them --
            // which arrived here as an interruption and paused the track we had
            // just started.
            if !provider.rendersAudioInProcess {
                (active as? LocalPlaybackProvider)?.relinquishSession()
            }
        }

        let edit = queueEdits[track.id] ?? .identity

        do {
            if let local = provider as? LocalPlaybackProvider {
                try await local.load(track, edit: edit)
            } else {
                try await provider.load(track)
            }

            activeProvider = provider
            currentTrack = track
            currentEdit = edit
            duration = provider.duration
            currentTime = 0

            try await provider.play()
            isPlaying = true
            startTicking()
            publishNowPlaying()
        } catch {
            present(error)
            isPlaying = false
            stopTicking()
        }
    }

    private func advanceAfterCompletion() {
        Task { await next() }
    }

    // MARK: - Position polling

    private func startTicking() {
        stopTicking()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let provider = self.activeProvider, self.isPlaying {
                    self.currentTime = provider.currentTime
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// Rate carries the Studio's speed setting: without it the lock screen
    /// scrubber extrapolates at 1.0 and drifts away from what is audible.
    private func publishNowPlaying() {
        NowPlayingCenter.shared.update(
            track: currentTrack,
            isPlaying: isPlaying,
            elapsed: currentTime,
            duration: duration,
            rate: currentEdit.speed
        )
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
