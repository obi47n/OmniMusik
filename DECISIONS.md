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

## Backend and web app: after iOS, not alongside (SUPERSEDED 2026-09-09)

> Reversed. See "Web app as control plane" below. Kept because the constraint it
> identified — that nothing can play audio on web yet — still holds and still
> shapes the scope.

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

## Web app as control plane, not a player (supersedes the entry above)

The deferral above evaluated the web app on one axis: can it play audio. It cannot,
and that has not changed — Apple Music on web needs MusicKit JS behind the same
blocked account, and streaming owned local files would mean uploading them, which
is a rejected feature further down this file.

What that reasoning missed is that the web app's value here is not playback. This is
a portfolio aimed at big-tech roles, and a real backend, a real auth flow, and a real
cloud deployment demonstrate breadth an iOS-only project cannot, whether or not sound
comes out of the browser. Weighed on that axis the answer flips.

So the web client is scoped as a **control plane**: library browsing, cross-source
Omni playlist authoring, search, and account management. Playback stays iOS-only and
the web UI says so plainly rather than shipping a dead transport bar. MusicKit JS
becomes an additive playback layer once the account clears.

## Auth: Cognito user pool with Sign in with Apple federated

Sign in with Apple remains the intended primary button, as the superseded entry said.
What changed is what sits underneath it.

Going directly to Apple would hard-block on a Services ID and .p8 key, and this
account is already too new for one Apple service. A Cognito user pool decouples the
clients from that: email and password work today, Sign in with Apple federates in as
an identity provider once configured, and neither client changes when it does. It is
also AWS-native, which the hosting story already commits to.

`AuthProvider` is the thin interface the superseded entry called for. Nothing above
it — not `AuthController`, not the views — knows Cognito exists.

**No AWS SDK on iOS.** Sign-in is a plain OAuth2 authorization-code flow with PKCE
against the Cognito Hosted UI via `ASWebAuthenticationSession`. Amplify Swift is a
large dependency for two HTTP calls, the hosted UI renders the Sign in with Apple
button itself, and the React client runs the identical flow against the same pool —
one mental model across both clients instead of two SDKs to reconcile.

Signing in is optional. Local library, effects, and playback work with no account;
an account buys cross-device playlists and the web client. Gating owned files behind
a login would be a worse product and a worse interview answer.

## Hosting: App Runner over Fargate, deliberately

Chosen against a three-week budget with two clients still to build.

ECS Fargate is the more conventional answer and the one an interviewer expects, but
it means hand-wiring a VPC, ALB, target groups, and task definitions — days that do
not buy proportional signal. Lambda was rejected outright: Spring Boot cold starts on
Lambda are genuinely bad without GraalVM, and that build complexity costs more than
the idle savings are worth here.

The signal comes from the infrastructure being in Terraform, a container pipeline
into ECR, and being able to explain the tradeoff — "managed runtime on purpose, here
is when I would move to Fargate" reads as judgment. A half-finished Fargate setup
reads as time trouble.

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
