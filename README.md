# OmniMusik

An iOS music client that unifies Apple Music, Spotify and locally owned audio into a
single library, queue, search and playlists — with a real-time effects chain for
local files.

> **Status:** active development. iOS local playback, the effects chain, cross-source
> playlists, universal search, and offline export are implemented; the sync API and
> web control plane are deployed on AWS. Apple Music is a deliberate stub pending
> App Service provisioning. See
> [What is actually built](#what-is-actually-built).

## Repository layout

| Directory | What it is |
|---|---|
| `OmniMusik/` | The iOS app — Swift, SwiftUI, SwiftData, AVAudioEngine |
| `backend/` | Spring Boot 4 sync API — [README](backend/README.md) |
| `web/` | React + TypeScript control plane — [README](web/README.md) |
| `infra/` | Terraform for Cognito, RDS, ECR, ECS, CloudFront — [README](infra/README.md) |
| `docs/` | [System design](docs/system-design.html) with diagrams, the [wiki](docs/wiki/Home.md) of URLs and identifiers, and interview study notes |

## Why this project is interesting

The hard problem isn't the UI. Apple Music and local audio are not variations on one
playback system — they are two incompatible ones:

| | Apple Music | Local file |
|---|---|---|
| Player | `ApplicationMusicPlayer`, system-owned | `AVAudioEngine`, ours |
| Sample access | None — DRM protected | Complete |
| Effects | Structurally impossible | Real-time DSP |
| Clock | Opaque, not shared | Frame-accurate |
| Seek and queue | Delegated to the system | Direct |

OmniMusik hides that split from the UI without pretending it does not exist. Effects
are necessarily local-only: Apple Music audio is never decrypted, decoded, or
processed, and the domain model encodes that as a property of the source rather than
leaving it as a comment.

## Architecture

Two protocols, deliberately kept apart:

- **`PlaybackProvider`** — *how* a track is played. `LocalPlaybackProvider` wraps
  `AVAudioEngine`.
- **`MusicSource`** — *where* tracks come from. `LocalMusicSource` reads SwiftData;
  `AppleMusicSource` will query the catalog.

They are separate because they do not line up one-to-one. A source can be browsable
while playback is unavailable — a lapsed subscription still lets you see the catalog
— and a provider can play tracks a source no longer lists. Merging them would force
those states into one interface that lies about at least one of them.

```
Domain/     Track, TrackSource, AudioEdit, Playlist — no framework imports
Playback/   PlaybackProvider + LocalPlaybackProvider (AVAudioEngine)
            PlaybackCoordinator — routes tracks to providers, owns the queue
            NowPlayingCenter, AudioSessionObserver
Library/    MusicSource + LocalMusicSource / AppleMusicSource
            SwiftData persistence, file-owning storage, import
            LibraryStore, PlaylistStore
Search/     SearchService — concurrent fan-out with per-source failure isolation
Studio/     Effects UI, waveform analysis, OfflineRenderer
Auth/       AuthProvider interface, Cognito implementation, Keychain token store
UI/         Library, Playlists, Now Playing, Queue, mini player, Theme
```

### The signal chain

```
playerNode → timePitch → eqNode → reverb → mainMixer
```

The Studio's layout mirrors this node order, so the interface is a picture of the
architecture. The graph is reconnected per file: sample rate and channel count vary
between imports, and a graph wired for 44.1 kHz stereo misbehaves silently on a
48 kHz mono file.

### Decisions worth reading

Recorded in [`DECISIONS.md`](DECISIONS.md), including the paths considered and
rejected. A few that shape the code:

- **Seeking is stop-and-reschedule with a generation counter.** `scheduleSegment`'s
  completion handler also fires on cancellation; without the counter a seek reads as
  end-of-track and skips forward.
- **Positions are trim-relative.** A track trimmed to start at 0:30 reports 0:00 at
  its first audible sample, so the UI never sees the file's absolute timeline.
- **Effects split into parametric and structural.** Speed, pitch, reverb, and EQ
  mutate live nodes; trim changes what is scheduled and requires a reschedule — done
  only when the bounds actually move.
- **Playlists store `(source, sourceID)` plus a snapshot,** not tracks and not
  relationships. A playlist built while subscribed stays legible after the
  subscription lapses.
- **The unified library merges one reactive source with N fetched ones.** Local
  tracks come from `@Query` and stay live; remote sources are fetched. The asymmetry
  is intentional.

## What is actually built

| Area | State |
|---|---|
| Local import, metadata, artwork, SwiftData persistence | Working on device |
| AVAudioEngine playback, seek, auto-advance, queue | Working on device |
| Studio effects — speed, pitch, reverb, 3-band EQ, trim | Working on device |
| Waveform analysis and rendering, unified library, universal search | Smoke-tested in simulator |
| Cross-source playlists, queue view | Smoke-tested in simulator |
| Offline render export | Unit-tested |
| Lock screen, remote commands, interruption handling | Implemented; background audio needs device confirmation |
| Sync API — auth, accounts, playlist CRUD, conflict handling | **Deployed** on ECS Express Mode; 17 integration tests pass; health, auth boundary and CORS verified against the live endpoint |
| Web control plane — sign-in, playlist editing, conflict UX | **Deployed** to CloudFront, pointed at the live API |
| iOS sync client — decision table, API client, conflict surfacing | Unit-tested; syncs automatically against the deployed API |
| Terraform for the whole stack | **Applied** — everything except the ECS Express service itself, which has no Terraform resource and is one script |
| iOS and web sign-in | Configured against a live Cognito pool; OAuth flow verified in a browser |
| Apple Music | Deliberate stub; blocked on App Service provisioning |

Tests: 86 on iOS (74 unit tests over the playlist rules, `AudioEdit` identity and
Codable round trips, the renderer's timeline arithmetic, the sync decision table,
the sync epoch, source connection states, the queue-advance rule and the drag
reorder, plus 12 UI tests driving each subsystem end to end) and 17 on the backend
(sync semantics, ownership isolation, the epoch, and the wire format the iOS client
depends on).

The iOS UI suite runs serially by design — the shared scheme sets
`parallelizable="NO"`, because parallel simulator clones made it flaky.

Deployed. The API runs on ECS Express Mode behind a managed load balancer with TLS,
the web client is on CloudFront, and both clients talk to the live API. App Runner
was the original target; AWS closed it to new services and the move is recorded in
`DECISIONS.md`.

## Requirements

- iOS 18+
- Xcode 16+
- Apple Developer Program membership (MusicKit is a paid-tier App Service)
- An active Apple Music subscription, to test catalog playback

## Setup

```bash
git clone <this repo>
open OmniMusik/OmniMusik.xcodeproj
```

Build and run. The local library, effects chain, playlists, and export all work with
no account and no network.

To enable Apple Music, register an App ID with the **MusicKit** App Service enabled
and set the bundle identifier to match. To enable sign-in, fill in
`Auth/CognitoConfiguration.swift` from your Terraform outputs — until then the
account screen reports itself unconfigured rather than offering a button that cannot
work.

In Debug builds, **Load Sample Tracks** seeds four synthesized fixtures (tagged,
untagged, artwork-less, unicode), because Save to Files is broken in the iOS 18
simulator. They are excluded from Release builds.

## Deferred

Android · Spotify's Web Playback SDK in the browser

Android is out because Apple Music has no playback SDK there. The Web Playback SDK
is a deliberate rejection rather than a gap: it would make the web client a real
player for exactly one source, and "playback is iOS-only except Spotify" is a line
with no principled answer behind it. See `DECISIONS.md`.

## Where everything is

Every URL, identifier, role and command lives in the [wiki](docs/wiki/Home.md).
