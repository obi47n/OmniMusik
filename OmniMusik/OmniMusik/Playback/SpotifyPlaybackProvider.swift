//
//  SpotifyPlaybackProvider.swift
//  OmniMusik
//
//  Playback for Spotify, via SPTAppRemote.
//
//  This is a *remote control*, not a player. The Spotify app decodes and outputs the
//  audio; this process issues commands and receives state. That is the same shape as
//  Apple Music's `ApplicationMusicPlayer` and the reason `supportsAudioEffects` is
//  false for both — there is no buffer here to route through the effects chain.
//
//  Two consequences worth understanding before reading further:
//
//  Position is *pushed*, not polled. `SPTAppRemote` reports a player state when
//  something changes and says nothing in between, so a scrubber that asks "where are
//  we now" has to extrapolate from the last known position and the time elapsed
//  since — the same technique `MPNowPlayingInfoCenter` uses, for the same reason.
//
//  Connecting requires the Spotify app. If it is not running, `connect()` fails and
//  the way in is `authorizeAndPlayURI`, which wakes it. That is why `play()` has two
//  paths rather than one.
//

import Foundation
import SpotifyiOS
import UIKit

@MainActor
final class SpotifyPlaybackProvider: NSObject, PlaybackProvider {

    let source: TrackSource = .spotify
    var onTrackFinished: (@MainActor () -> Void)?

    private let accessToken: () async throws -> String

    /// Which path a play took.
    ///
    /// Structured rather than a string, because one case is user-facing: waking
    /// Spotify switches apps, and an unexplained switch reads as a glitch.
    enum Handoff {
        /// Played through the existing connection. Nothing visible happened.
        case playedInPlace(reconnected: Bool)

        /// Spotify had been suspended by iOS and had to be woken, which foregrounds
        /// it. Unavoidable — see DECISIONS.md.
        case wokeSpotify

        case disconnected(reason: String)
    }

    /// Reports which path `play()` took. Reasoning about this from the outside was
    /// wrong three times; this reports what actually happened.
    var onHandoff: ((Handoff) -> Void)?

    /// Fired just *before* Spotify is woken, so the UI can present the switch as
    /// something the app is doing rather than something happening to it. The wake is
    /// briefly delayed to let that land.
    var onWillWakeSpotify: (() -> Void)?

    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(
            clientID: SpotifyConfiguration.clientID,
            redirectURL: URL(string: SpotifyConfiguration.redirectURI)!
        )
        let remote = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.delegate = self
        return remote
    }()

    /// The track this provider was last asked to play, as a Spotify URI.
    private var currentURI: String?
    private var loadedDuration: TimeInterval = 0

    /// Last state Spotify reported, and when it arrived. Position between reports is
    /// extrapolated from these two.
    private var lastReportedPosition: TimeInterval = 0
    private var lastReportedAt: Date?
    private var playing = false

    /// Set while a play was requested before the connection existed, so the track
    /// starts as soon as the connection lands rather than being dropped.
    private var pendingPlayURI: String?

    /// Resumed by the connection delegates. `connect()` is delegate-driven, so this
    /// is what lets callers await it.
    private var connectionWaiters: [CheckedContinuation<Bool, Never>] = []

    init(accessToken: @escaping () async throws -> String) {
        self.accessToken = accessToken
        super.init()
    }

    /// Whether the Spotify app is present at all. Declared in
    /// `LSApplicationQueriesSchemes`, without which this always answers false.
    static var isSpotifyInstalled: Bool {
        guard let url = URL(string: "spotify:") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - PlaybackProvider

    var isPlaying: Bool { playing }

    /// The Spotify app decodes and outputs; this process only issues commands.
    let rendersAudioInProcess = false

    var duration: TimeInterval { loadedDuration }

    /// Extrapolated from the last reported position.
    ///
    /// Clamped to the track length so a delayed state report cannot run the scrubber
    /// past the end of the track.
    var currentTime: TimeInterval {
        guard let lastReportedAt else { return lastReportedPosition }
        guard playing else { return lastReportedPosition }
        let elapsed = Date().timeIntervalSince(lastReportedAt)
        return min(max(0, lastReportedPosition + elapsed), max(loadedDuration, 0))
    }

    func load(_ track: Track) async throws {
        guard track.source == .spotify else {
            throw PlaybackError.sourceMismatch(expected: .spotify, got: track.source)
        }
        guard Self.isSpotifyInstalled else {
            throw PlaybackError.engineFailure("Spotify needs to be installed to play its tracks.")
        }

        currentURI = "spotify:track:\(track.sourceID)"
        loadedDuration = track.duration
        lastReportedPosition = 0
        lastReportedAt = nil
        playing = false
    }

    /// Establishes the remote connection without bringing Spotify to the foreground.
    ///
    /// `connect()` succeeds silently whenever the Spotify app is alive, even in the
    /// background — which is the difference between OmniMusik owning the controls and
    /// bouncing the person into another app on every track. It fails when Spotify is
    /// not running at all, and only then is `authorizeAndPlayURI` needed.
    ///
    /// Worth calling when the app becomes active, so the connection already exists by
    /// the time somebody taps a track.
    @discardableResult
    func connectIfPossible() async -> Bool {
        guard Self.isSpotifyInstalled else { return false }
        if appRemote.isConnected { return true }
        guard let token = try? await accessToken() else { return false }

        appRemote.connectionParameters.accessToken = token
        appRemote.connect()

        return await withCheckedContinuation { continuation in
            connectionWaiters.append(continuation)

            // A deadline, because connect() is delegate-driven and there is no
            // guarantee a delegate ever fires -- Spotify not running is the obvious
            // case. Without this, play() waits forever, which is a worse failure
            // than switching apps: nothing happens and nothing explains why.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                self.settleConnectionWaiters(self.appRemote.isConnected)
            }
        }
    }

    /// Resumes everyone waiting on a connection attempt, exactly once each.
    private func settleConnectionWaiters(_ connected: Bool) {
        let waiters = connectionWaiters
        connectionWaiters = []
        for waiter in waiters { waiter.resume(returning: connected) }
    }

    func play() async throws {
        guard let uri = currentURI else { return }

        // Attach a fresh token every time. Spotify's tokens expire on the hour and a
        // stale one fails the connection with an error that reads like the app is
        // missing rather than the token being old.
        appRemote.connectionParameters.accessToken = try await accessToken()

        let wasConnected = appRemote.isConnected

        // Try the quiet path first: if Spotify is running at all, this connects
        // without a foreground switch and playback is driven entirely from here.
        if !appRemote.isConnected {
            await connectIfPossible()
        }

        if appRemote.isConnected {
            onHandoff?(.playedInPlace(reconnected: !wasConnected))
            appRemote.playerAPI?.play(uri, callback: nil)
            playing = true
            lastReportedAt = Date()
        } else {
            onHandoff?(.wokeSpotify)
            // Spotify is not running, so there is nothing to connect to. This wakes
            // it, which does switch apps -- unavoidable, and the only time it should
            // happen. Once connected, subsequent tracks take the path above.
            //
            // The completion reports whether Spotify could be started at all, which
            // is the one failure worth surfacing here: not installed, or installed
            // but not logged in. Swallowing it would leave a silent dead transport.
            pendingPlayURI = uri

            // Announce first, then pause long enough for the transition to be seen.
            // iOS is about to take the screen away; without this the switch arrives
            // with no explanation and reads as a glitch. The delay costs nothing
            // against the app launch that follows it.
            onWillWakeSpotify?()

            // Long enough for the transition to render and be read. It was 520ms,
            // which SwiftUI spent mostly fading the overlay in -- so the switch
            // often arrived while it was still appearing, and the animation looked
            // like it fired only sometimes. iOS is about to spend longer than this
            // launching Spotify anyway.
            try? await Task.sleep(for: .milliseconds(1100))

            let started = await appRemote.authorizeAndPlayURI(uri)
            if !started {
                pendingPlayURI = nil
                throw PlaybackError.engineFailure(
                    "Spotify could not be started. Check that the Spotify app is installed and signed in."
                )
            }
        }
    }

    func pause() {
        appRemote.playerAPI?.pause(nil)
        // Freeze the extrapolation at wherever we had got to.
        lastReportedPosition = currentTime
        lastReportedAt = nil
        playing = false
    }

    /// Stops playback but **keeps the remote connection**.
    ///
    /// The coordinator calls this on the outgoing provider at every handoff, so
    /// disconnecting here tore the connection down the moment an MP3 took over. iOS
    /// then suspends the idle Spotify app, `connect()` fails next time, and the only
    /// way back is `authorizeAndPlayURI` — which switches apps. Every single
    /// crossing from local audio to Spotify paid that price.
    ///
    /// Holding the connection open keeps the Spotify app resident, so returning to a
    /// Spotify track is silent. The connection is only surrendered when the person
    /// disconnects the service, which is `releaseConnection`.
    func stop() {
        appRemote.playerAPI?.pause(nil)
        currentURI = nil
        pendingPlayURI = nil
        loadedDuration = 0
        lastReportedPosition = 0
        lastReportedAt = nil
        playing = false
    }

    /// Actually surrenders the remote connection.
    ///
    /// Deliberately not part of `stop()`: ending a track and ending the relationship
    /// with the Spotify app are different things, and conflating them is what made
    /// every handoff expensive.
    func releaseConnection() {
        stop()
        if appRemote.isConnected { appRemote.disconnect() }
        settleConnectionWaiters(false)
    }

    func seek(to time: TimeInterval) async {
        let target = min(max(0, time), max(loadedDuration, 0))
        // SPTAppRemote works in milliseconds.
        appRemote.playerAPI?.seek(toPosition: Int(target * 1000), callback: nil)
        lastReportedPosition = target
        lastReportedAt = playing ? Date() : nil
    }
}

// MARK: - SPTAppRemoteDelegate

extension SpotifyPlaybackProvider: SPTAppRemoteDelegate {

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        MainActor.assumeIsolated {
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: nil)
            settleConnectionWaiters(true)

            // A play requested before the connection existed.
            if let uri = pendingPlayURI {
                pendingPlayURI = nil
                appRemote.playerAPI?.play(uri, callback: nil)
                playing = true
                lastReportedAt = Date()
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        MainActor.assumeIsolated {
            pendingPlayURI = nil
            playing = false
            lastReportedAt = nil
            settleConnectionWaiters(false)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        MainActor.assumeIsolated {
            onHandoff?(.disconnected(reason: error?.localizedDescription ?? "no reason given"))
            playing = false
            lastReportedAt = nil
            settleConnectionWaiters(false)
        }
    }
}

// MARK: - SPTAppRemotePlayerStateDelegate

extension SpotifyPlaybackProvider: SPTAppRemotePlayerStateDelegate {

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        MainActor.assumeIsolated {
            let position = TimeInterval(playerState.playbackPosition) / 1000
            let trackDuration = TimeInterval(playerState.track.duration) / 1000

            // Spotify is authoritative about the track it is playing, including when
            // the person changed it from the Spotify app itself.
            if trackDuration > 0 { loadedDuration = trackDuration }

            let wasPlaying = playing
            playing = !playerState.isPaused
            lastReportedPosition = position
            lastReportedAt = playing ? Date() : nil

            // End of track: Spotify reports a paused state back at position zero once
            // the track finishes. There is no explicit "finished" callback, so this
            // is the available signal -- and it must not fire for an ordinary pause,
            // which reports the position it stopped at rather than zero.
            if wasPlaying, playerState.isPaused, position == 0, trackDuration > 0 {
                onTrackFinished?()
            }
        }
    }
}
