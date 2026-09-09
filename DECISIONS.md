# Decisions

Choices already made and the reasoning behind them, including paths considered and
rejected. Recorded so they don't get relitigated.

## Platform: native Swift/SwiftUI, iOS only

Considered React Native for a shared codebase with the eventual web app.

Rejected because Apple Music has no playback SDK on Android — MusicKit is Apple-only
— so "cross-platform" was never going to deliver real Apple Music playback there
anyway. React Native would also have meant bridging AVFoundation through native
modules for the entire effects chain, which is the most interesting part of the
project. Native Swift removes the bridge and keeps the audio work direct.

The web app will be a separate React/TypeScript codebase. Nothing is literally
shared. What ports is the domain model, which is why `Domain/` has no framework
imports.

## Scope: Apple Music only for the MVP, Spotify deferred

Spotify's native iOS SDK needs a custom dev client and its own OAuth flow, roughly
doubling the integration work for a second streaming source that proves the same
architectural point. The `PlaybackProvider` and `MusicSource` protocols exist so
Spotify is an additive change, not a refactor.

## Backend and web app: after iOS, not alongside

Considered building the Spring Boot backend, auth, and web client in parallel while
MusicKit was blocked.

Deferred because a web app cannot play anything yet: Apple Music on web needs
MusicKit JS (same blocked account, plus a Services ID and .p8 key), and local files
live on the phone, not the server. Building it now produces a shell that displays
metadata and plays silence. Meanwhile most of the remaining iOS work — unified
library, universal search, playlists — was never blocked at all.

Auth, when it happens: **Sign in with Apple**, behind a thin interface so another
provider can be added without a rewrite. It works on iOS and web, stores no
passwords, and is the right answer for an Apple-targeted portfolio. It needs the
same Developer Program membership as MusicKit.

## Studio design: signal chain, built rather than borrowed

An existing audio app's edit screen was used as a starting reference. Its useful
principles: dark ground, monospaced numerics, custom controls rather than stock
iOS sliders, discrete cards, one bright accent.

Its layout was deliberately not copied. Cloning a recognizable UI is a liability in
a portfolio — anyone who knows the original spots it. The signal-chain layout is
OmniMusik's own, and it mirrors the actual AVAudioEngine node order, so the
interface is a picture of the architecture.

Sliders fill outward from a neutral origin rather than from the left edge, because
effect parameters are deviations from an unmodified signal and distance-from-neutral
is the thing worth seeing at a glance.

## Rejected features

- **Stems / source separation.** A machine-learning project wearing a tab.
- **BPM and key detection.** Would require real analysis; showing invented values
  would be worse than showing nothing.
- **Uploading local audio to a server.** Turns a music tool into a file-hosting
  service, with the storage bill and licensing questions that implies.
- **Favorites and recently-played.** Cuttable; they add screens, not architecture.

## Cuttable if time runs short

Offline render export, and tests. What cannot be cut without the project ceasing to
be what it claims: Apple Music integration, cross-source playlists, and lock screen
controls.
