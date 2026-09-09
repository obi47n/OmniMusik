# OmniMusik — working notes

iOS app unifying Apple Music and locally owned audio into one library, queue, and
search, with a real-time effects chain for local files.

Context: a portfolio project. The owner is a software engineer targeting Apple and
other big-tech roles, building this to anchor technical interview discussion.
Architecture quality matters more than feature count — a well-argued abstraction is
worth more here than another screen.

## Constraints

- **iOS 18 deployment target.** Do not use iOS 26+ API (`.tabViewBottomAccessory`
  was caught once already). Check availability before reaching for anything new.
- **Bundle ID `com.obinnaduruaku.OmniMusik`** must match the registered App ID.
- **MusicKit is blocked** — the developer account is too new for the App Service to
  be enabled. `AppleMusicSource` is a deliberate stub reporting "not connected".
  Expected to clear within days.
- **Effects can never apply to Apple Music.** That audio is DRM-protected and played
  by a system-owned player with no sample access. This is structural, not a TODO.
- Swift 5 language mode, SwiftData, Observation (`@Observable`, not
  `ObservableObject`).

## Architecture

```
Domain/     Track, TrackSource, AudioEdit — no framework imports, deliberately
Playback/   PlaybackProvider protocol + LocalPlaybackProvider (AVAudioEngine)
            PlaybackCoordinator — routes tracks to providers, owns queue
            NowPlayingCenter, AudioSessionObserver
Library/    MusicSource protocol + LocalMusicSource / AppleMusicSource
            SwiftData persistence, file-owning storage, import, LibraryStore
Search/     SearchService (concurrent fan-out), SearchView
Studio/     Effects UI, waveform analysis and rendering
UI/         Library, Now Playing, mini player, Theme
```

**Two protocols, deliberately separate.** `PlaybackProvider` answers "how is this
played"; `MusicSource` answers "where do tracks come from". They do not map
one-to-one — a source can be browsable while playback is unavailable (lapsed
subscription), and a provider can play tracks a source no longer lists. Do not
merge them.

**Non-obvious decisions, with reasons — preserve these:**

- Seeking is stop-and-reschedule with a **generation counter**. `scheduleSegment`'s
  completion also fires on cancellation; without the counter a seek reads as
  end-of-track and skips forward.
- Positions in `LocalPlaybackProvider` are **trim-relative**. The UI never sees the
  file's absolute timeline.
- Imported files are **copied**, never referenced. Security-scoped picker URLs do
  not survive the callback.
- Local tracks come from `@Query` (live); remote sources are fetched into
  `LibraryStore`. The unified library is a merge of one reactive and N fetched
  sources. That asymmetry is intentional.
- `MPNowPlayingInfoCenter` is published on **transitions only, never on the position
  timer** — it extrapolates from elapsed + rate. The Studio's speed feeds the rate,
  or the lock screen drifts from what is audible.
- Audio session is reactivated on every `play()`, not just load — interruptions
  deactivate it and iOS does not hand it back.
- Effects split into **parametric** (live node mutation) and **structural** (trim,
  requires reschedule). Only trim reschedules, only when bounds actually move.
- `UIBackgroundModes` comes from an explicit `OmniMusik/Info.plist`, not from
  `INFOPLIST_KEY_UIBackgroundModes`. Xcode's generated-plist mechanism honors only
  a fixed whitelist of `INFOPLIST_KEY_*` settings and `UIBackgroundModes` is not on
  it, so that setting resolves in `-showBuildSettings` and is then silently dropped
  from the built plist. That was the cause of playback dying on lock. The partial
  plist sits at SRCROOT, outside the synchronized folder so Xcode does not treat it
  as a resource; `GENERATE_INFOPLIST_FILE` stays `YES` and merges on top of it.

## Conventions

- Comments explain *why*, not what. Long-form where a decision is non-obvious.
- No emoji anywhere in code or docs.
- Search results are grouped by source, never interleaved — there is no common
  relevance scale between a filename match and Apple's catalog ranking.
- The UI is OmniMusik's own. Do not imitate another app's interface.
- Never fabricate data the app cannot compute (no fake BPM or key detection).

## State

Done: local library and import, metadata extraction, SwiftData persistence,
AVAudioEngine playback, the effects chain, the signal-chain Studio with waveform
rendering, lock screen and remote commands, interruption and route-change handling,
unified library with source filtering, universal search fan-out.

Smoke-verified on an iOS 18 simulator by `OmniMusikUITests`, five cases passing:
sample tracks persist and list, tapping a track starts playback and docks the mini
player, the Studio presents and renders its signal chain (so waveform analysis runs),
search produces Apple Music's unavailability note (so the fan-out completed and
failure isolation held), and the account screen reports itself unconfigured.

Not done: unit tests (nothing covers the generation counter, trim arithmetic, or
credential refresh), offline render export, MusicKit integration, Omni playlists
(cross-source), queue view, backend, web client, README and demo materials.

When adding UI tests: `accessibilityIdentifier` propagates to every descendant and an
identifier on a container silently overwrites a more specific one on a child. Keep at
most one per subtree. The element hierarchy in the `.xcresult` bundle is the fastest
way to diagnose a query that should match and does not.

## Open bugs

None known.

## Interview notes

`docs/interview-notes.html` is a living study document for interview preparation:
the pitch, the architecture arguments and their rejected alternatives, audio-engine
deep dives, debugging war stories, and a status ledger separating what runs on
device from what merely compiles.

Published at https://claude.ai/code/artifact/f4b69ae6-fc9c-477a-b3d9-92eb0f566fa4

Keep it current as the project changes. The status ledger is the part that matters
most and the part that goes stale fastest -- it exists so nothing gets overclaimed
in an interview, which only works if it is true.

## Notes

`_to_delete/` holds discards from a sandbox that could not delete files, including a
`project.pbxproj` backup. Safe to remove.

`SampleAudio/` contains synthesized DEBUG-only fixtures (tagged, untagged,
artwork-less, unicode) because Save to Files is broken in the iOS 18 simulator.
They ship in release builds too — strip them before archiving.
