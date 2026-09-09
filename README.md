# OmniMusik

An iOS music client that unifies Apple Music and locally owned audio into a single
library, queue, and search — with a real-time effects chain for local files.

> **Status:** active development. Local playback, the effects chain, cross-source
> playlists, universal search, and offline export are implemented. Apple Music is a
> deliberate stub pending App Service provisioning. See
> [What is actually built](#what-is-actually-built).

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
| Authentication | Scaffolded — no user pool provisioned yet |
| Apple Music | Deliberate stub; blocked on App Service provisioning |
| Backend, web client | Designed, not built |

Tests: 40 passing — unit coverage over the playlist rules, `AudioEdit` identity and
Codable round trips, and the renderer's timeline arithmetic, plus UI smoke tests that
drive each subsystem end to end.

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

Spotify integration · Spring Boot sync backend · React web companion · Android

Spotify is deferred rather than rejected: its SDK needs a custom dev client and its
own OAuth flow to prove the same architectural point the protocols already prove.
