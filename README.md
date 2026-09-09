# OmniMusik

An iOS music client that unifies Apple Music and locally-owned audio into a single
library, queue, and search experience — with a real-time effects chain for local files.

> **Status:** in development. Week 1 of a 4-week MVP.

## Why this project is interesting

The hard problem isn't the UI. It's that Apple Music and local audio are two
fundamentally incompatible playback systems:

| | Apple Music | Local MP3 |
|---|---|---|
| Playback | `ApplicationMusicPlayer` (opaque, system-owned) | `AVAudioEngine` (full sample access) |
| Audio graph access | None — DRM protected | Complete |
| Effects | Impossible | Real-time DSP |
| Seek / queue control | Delegated to system player | Direct |

OmniMusik unifies them behind a single `PlaybackProvider` protocol, with an
orchestration layer that hands off between engines at track boundaries. Effects are
necessarily local-only — Apple Music audio is never decrypted, decoded, or processed.

## Architecture

```
OmniMusik/
├── Domain/          Track, TrackSource, AudioEdit — pure value types, no framework deps
├── Playback/        PlaybackProvider protocol
│                    ├── LocalPlaybackProvider      (AVAudioEngine)
│                    └── AppleMusicPlaybackProvider  (MusicKit)
│                    └── PlaybackCoordinator         (cross-provider queue + handoff)
├── Library/         Import, metadata extraction, SwiftData persistence
├── Studio/          AVAudioEngine effects graph — time/pitch, reverb, EQ, trim, export
├── Search/          Fan-out search across local index + MusicKit catalog
└── UI/              SwiftUI views, MVVM view models
```

**Pattern:** adapter/strategy around incompatible external systems, with a
non-destructive edit model for audio processing (edits are stored as parameters and
applied at render time rather than baked into files).

## Requirements

- iOS 17+
- Xcode 16+
- Apple Developer Program membership (MusicKit is a paid-tier App Service)
- An active Apple Music subscription (required to test catalog playback)

## Setup

1. Register an App ID at [developer.apple.com](https://developer.apple.com/account/resources)
   with the **MusicKit** App Service enabled.
2. Set the project's bundle identifier to match that App ID.
3. Build and run.

## Roadmap

- **Week 1** — local library: import, metadata, persistence, playback
- **Week 2** — MP3 Studio: time/pitch, reverb, EQ, trim, offline render export
- **Week 3** — MusicKit: auth, catalog search, library, native playback; provider abstraction
- **Week 4** — unification: cross-source library, universal search, Omni playlists, queue, polish

### Deferred (post-MVP)
Spotify integration · Spring Boot sync backend · React web companion · Android
