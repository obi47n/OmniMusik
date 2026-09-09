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

## Repository layout

```
OmniMusik/   iOS app (Swift, SwiftUI, SwiftData, AVAudioEngine)
backend/     Spring Boot 4 sync API (Java 21, H2 locally, Postgres in prod)
web/         React + TypeScript control plane (Vite)
infra/       Terraform: Cognito, RDS, ECR, App Runner
docs/        Interview study notes
```

Build commands, since the toolchain here is not discoverable:

- iOS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...`
  (`xcode-select` points at CommandLineTools on this machine)
- Backend: `cd backend && ./mvnw test`
- Web: `cd web && npm run build`
- Infra: `terraform -chdir=infra validate` (terraform is not installed globally)

## Architecture

```
Domain/     Track, TrackSource, AudioEdit, Playlist — no framework imports
Playback/   PlaybackProvider protocol + LocalPlaybackProvider (AVAudioEngine)
            PlaybackCoordinator — routes tracks to providers, owns queue
            NowPlayingCenter, AudioSessionObserver
Library/    MusicSource protocol + LocalMusicSource / AppleMusicSource
            SwiftData persistence, file-owning storage, import
            LibraryStore, PlaylistStore, PlaylistEntity
Search/     SearchService (concurrent fan-out), SearchView
Studio/     Effects UI, waveform analysis and rendering, OfflineRenderer
Auth/       AuthProvider interface, Cognito implementation, Keychain store
UI/         Library, Playlists, Now Playing, Queue, mini player, Theme
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
- Playlists store `(source, sourceID)` pairs plus a **denormalized snapshot**, not
  `Track` values and not SwiftData relationships. A relationship would have to point
  at `LocalTrackEntity`, which would make cross-source playlists impossible; the
  snapshot is what lets a playlist describe itself when its source cannot answer.
  Entries are encoded JSON because order is the point and relationships are
  unordered.
- The offline renderer's graph must stay **identical** to `LocalPlaybackProvider`'s.
  If they drift, exports stop sounding like what was auditioned. Output length is
  `sourceFrames / rate` plus a reverb tail — get it wrong and slowed exports are
  silently truncated.
- `UIBackgroundModes` comes from an explicit `OmniMusik/Info.plist`, not from
  `INFOPLIST_KEY_UIBackgroundModes`. Xcode's generated-plist mechanism honors only
  a fixed whitelist of `INFOPLIST_KEY_*` settings and `UIBackgroundModes` is not on
  it, so that setting resolves in `-showBuildSettings` and is then silently dropped
  from the built plist. That was the cause of playback dying on lock. The partial
  plist sits at SRCROOT, outside the synchronized folder so Xcode does not treat it
  as a resource; `GENERATE_INFOPLIST_FILE` stays `YES` and merges on top of it.

## Cross-component contracts

The wire format is shared by three codebases and two of the couplings are invisible
until runtime:

- `TrackSource` serializes as `local` / `appleMusic`, and the entry field is
  `sourceID`. Swift derives coding keys from property names and encodes string-backed
  enums by raw value, so Java or JavaScript naming conventions break the phone and
  nothing else. There is a backend test asserting the exact strings.
- Timestamps are ISO-8601. Swift's default `JSONDecoder` reads a `Date` as seconds
  since the **2001** Apple epoch, so the iOS client must use `.iso8601` or every date
  silently lands in 2001.
- Playlist writes are version-checked. Clients send the version they last read; a
  mismatch is a 409 carrying the server's current state so the client can merge.

Toolchain notes that cost time to rediscover: Spring Boot 4 uses Jackson 3
(`tools.jackson`, though annotations stayed on `com.fasterxml`) and moved
`@AutoConfigureMockMvc` to `org.springframework.boot.webmvc.test.autoconfigure`.
TypeScript 6 enables `erasableSyntaxOnly`, which rejects constructor parameter
properties.

## Conventions

- Comments explain *why*, not what. Long-form where a decision is non-obvious.
- No emoji anywhere in code or docs.
- Search results are grouped by source, never interleaved — there is no common
  relevance scale between a filename match and Apple's catalog ranking.
- The UI is OmniMusik's own. Do not imitate another app's interface.
- Never fabricate data the app cannot compute (no fake BPM or key detection).

## State

Working on device: local library and import, metadata extraction, SwiftData
persistence, AVAudioEngine playback, the effects chain, the signal-chain Studio.

Smoke-tested in simulator by `OmniMusikUITests` (7 cases): waveform rendering,
unified library, search fan-out, cross-source playlists end to end, queue view,
account screen.

Unit-tested by `OmniMusikTests` (33 cases): playlist rules, `AudioEdit` identity and
Codable round trips, `PlaylistEntry` coding, offline renderer timeline arithmetic.
The renderer suite is `.serialized` — parallel offline engines sharing one directory
interfere.

Not done: MusicKit integration (blocked), backend, web client, demo materials.
Background audio on lock is fixed but needs device confirmation.

When adding UI tests: `accessibilityIdentifier` propagates to every descendant and an
identifier on a container silently overwrites a more specific one on a child. Keep at
most one per subtree. SwiftUI also labels a `Menu` "More" and puts the image
identifier on the child, so name such controls explicitly. The element hierarchy in
the `.xcresult` bundle is the fastest way to diagnose a query that should match and
does not.

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

`SampleAudio/` contains synthesized DEBUG-only fixtures (tagged, untagged,
artwork-less, unicode) because Save to Files is broken in the iOS 18 simulator.
`EXCLUDED_SOURCE_FILE_NAMES = "*.mp3"` on the app target's Release configuration
keeps them out of release bundles; the UI smoke tests depend on them being present
in Debug.

Building from the command line needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
— `xcode-select` points at CommandLineTools on this machine.
