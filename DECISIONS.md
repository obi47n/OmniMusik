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

## Scope: Apple Music only for the MVP, Spotify deferred (SUPERSEDED)

> Spotify was added as a third source. See "Spotify: added as a third source" below.
> Kept because the extensibility claim it makes was tested by that addition.

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

## Hosting: App Runner over Fargate, deliberately (SUPERSEDED 2026-09-09)

> Overtaken by the platform. AWS closed App Runner to new services on 2026-04-30,
> and this account can no longer create one. See "Hosting: ECS Express Mode" below.
> Kept because the reasoning -- managed runtime on purpose, and knowing when you
> would move -- is exactly what carried over.

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

**No NAT gateway.** A VPC connector routes all of the service's outbound traffic
through the VPC, and the usual fix is a NAT gateway at roughly $32/month. Rejected
after asking what the API actually needs to reach outside the VPC: exactly one thing,
Cognito's JWKS endpoint. A single interface endpoint serves that for about $7, and the
VPC ends up with no public subnets and no internet gateway at all.

That cuts the idle cost from roughly $60/month to $25, which matters for a project
that will never have users. But the reason it is recorded here is the reasoning rather
than the saving: enumerate what genuinely needs to leave a network, then buy only
that, instead of reaching for the general-purpose default.

**Not left running.** For a portfolio the cheapest deployment is an absent one —
`terraform apply` before a demo, `terraform destroy` after, at roughly $1/day. The
Terraform, the CI and a recording are what a reviewer actually reads; a live endpoint
nobody visits earns almost nothing. Allow 10-15 minutes for the apply, nearly all of
it RDS.

The Lambda rejection above is also weaker than when it was written: Java SnapStart has
closed much of the cold-start gap that made it a non-starter. It stays rejected on
effort — a rewrite of a working, tested service — rather than on latency.

## Hosting: ECS Express Mode, because App Runner closed

Not a choice so much as a consequence. AWS stopped accepting new App Runner
services on 2026-04-30; the existing one here was `CREATE_FAILED` for an unrelated
reason (below), replacing it means creating one, and the console's create button is
disabled on this account. The API had to run somewhere else.

AWS points at ECS Express Mode, and it is the same bargain App Runner offered: hand
over an image and a port, and the platform runs the load balancer, target groups,
TLS, and scaling. What it does not offer is a Terraform resource -- the AWS provider
has none at any version -- so the split is deliberate: everything the service depends
on (cluster, roles, subnets, security groups, log group) is Terraform and in state,
and the service itself is one idempotent script, `scripts/deploy-api.sh`, that looks
every input up by name. The script needs no Terraform state, which is what lets CI
run it.

**What it cost: the network.** App Runner supplied its own public endpoint and
reached into the VPC through a connector, so the VPC had no public subnets and no
internet gateway -- a property the earlier entry was proud of. Express Mode puts an
Application Load Balancer *in* the VPC, and a load balancer the internet can reach
has to live in a subnet the internet can reach. So the VPC gained an internet gateway
and two public subnets.

The tasks run in those public subnets with public addresses, rather than in the
private ones behind a NAT gateway. That is the same reasoning as the NAT decision,
applied again: a NAT gateway is $32/month to let tasks pull an image and write logs,
and an address plus a security group that admits only the load balancer costs
nothing. The tasks are addressable but not reachable. The Cognito interface endpoint
is gone with the NAT-free design it served -- tasks with a route to the internet
reach Cognito directly, and $7/month for a private path to a public endpoint no
longer buys anything.

**Two things found only by deploying.** The production profile validates the schema
(`ddl-auto=validate`) and nothing created it, so the first container crash-looped on
`missing table [app_user]` until Flyway and a hand-written V1 migration existed --
the config file's own comment had predicted this. And Spring Boot 4 splits
autoconfiguration into one module per technology, so `flyway-core` alone put Flyway
on the classpath with nothing to start it: no migration, no error, and the first sign
was Hibernate refusing a schema nothing had built. `spring-boot-flyway` is the
missing piece.

**Jib instead of a Dockerfile.** There is no container runtime on the machine that
first deployed this, and there does not need to be: Jib builds the layers and pushes
them straight to ECR from Maven. It also layers dependencies, resources and classes
separately by construction, which is what the Dockerfile's stage ordering had been
reaching for by hand. One image-build path, used locally and in CI.

**The destroy-when-idle posture survives**, with one change: it now applies to
everything. There is nothing left that cannot be recreated -- which was the quiet
risk with App Runner once it stopped accepting new services.

## Playlists: identifier pairs with a snapshot, not tracks and not relationships

A playlist must hold a local file and an Apple Music track in one ordered list, but
those live in different worlds. Local tracks are SwiftData rows; Apple Music tracks
are not persisted at all, because caching a catalog that changes underneath you means
serving stale copies of someone else's data.

Considered a SwiftData relationship to `LocalTrackEntity`. Rejected because it would
quietly restrict playlists to local files -- the exact thing the feature exists to
avoid -- and because relationships are unordered, so preserving playlist order would
mean an explicit position column and re-numbering siblings on every move.

Considered storing `Track` values directly. Rejected because a `Track` for a remote
source is only meaningful while that source can be reached.

So an entry is `(source, sourceID)` plus a denormalized snapshot of title, artist,
and duration, encoded as JSON. The snapshot is the part worth defending: without it,
a playlist of Apple Music tracks becomes blank rows the moment the subscription
lapses. A playlist should be able to describe itself without a server's permission.

The tradeoff, stated plainly: entries are opaque to the query engine, so a future
"which playlists contain this track" screen needs a scan or a secondary index. That
is a fair price for ordering and cross-source support.

Duplicates are permitted. A set that opens and closes on the same record is a real
thing, so each entry carries its own identity and the "add unless present" policy
lives at the call site rather than buried in the model.

## Export: manual rendering, not AVAssetExportSession

`AVAssetExportSession` can trim and transcode, but it has no way to apply an
`AVAudioUnitTimePitch` or a reverb node -- the effects are an engine graph, so the
export has to run that graph. AVAudioEngine's offline manual rendering mode does,
far faster than real time.

The renderer's graph is deliberately a copy of `LocalPlaybackProvider`'s. That
duplication is accepted on purpose: if the two drifted, exports would stop sounding
like what was auditioned, which is the one thing an export must never do. A shared
graph-builder would be tidier and is the obvious refactor if a third consumer ever
appears.

Two failure modes here are silent rather than loud, which is why both are tested:
output length must be `sourceFrames / rate` or every slowed export is truncated and
still plays, and a reverb tail must be appended or the file ends on a cut that was
never audible during playback.

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

## Spotify: added as a third source; Web Playback SDK deferred

The earlier entry deferred Spotify on the grounds that it proves the same
architectural point as Apple Music at roughly the same cost. That still holds, with
one thing it did not weigh: Apple Music is blocked on account provisioning with no
date, and a Spotify developer account is free and instant. A second real source that
can actually be built converts "I designed for extensibility" into "I extended it".

It also independently validates the split rather than contradicting it. `SPTAppRemote`
remote-controls the Spotify app and exposes no samples -- the SDK's own description is
limited to "authorization, getting metadata... and issuing playback commands" -- so
`supportsAudioEffects` is false for Spotify too, for the same structural reason as
Apple Music. A third source that behaves like the second is evidence the model is
right.

Costs accepted: the Spotify app must be installed and the account must be Premium,
and `SpotifyiOS` via SPM becomes the iOS app's first third-party dependency.

**The Web Playback SDK is deferred, and this is a deliberate rejection rather than an
oversight.** It would let a browser play Spotify audio, making the web client a real
player for exactly one source. Rejected because it makes the source model inconsistent
for one service's convenience: "playback is iOS-only, and here is the structural
reason" is a clean line, while "playback is iOS-only except Spotify" invites a
follow-up with no principled answer. It also needs Premium in the browser. Worth
revisiting only if the web client's purpose changes from control plane to player.

## A mixed queue cannot cross into Spotify silently

Confirmed on device, after three failed attempts to fix it.

Playing a Spotify track requires the Spotify app to be resident. While local audio
plays, Spotify is paused and producing no audio, so iOS suspends it. A suspended app
cannot accept an `SPTAppRemote` connection, so the only remaining route is
`authorizeAndPlayURI`, which wakes Spotify and brings it to the foreground.

The asymmetry is the tell: Spotify to local is seamless, because local playback needs
nothing from another process. Local to Spotify is not, because it needs a process iOS
has already put to sleep.

Three fixes were attempted and none could have worked, which is worth recording so
they are not attempted again:

- **Warming the connection when a Spotify track is next.** Useless, because
  suspension happens *during* the local track, after the warm-up.
- **Holding the connection object open across handoffs.** Real improvement, but
  holding a connection does not stop the OS suspending the app at the other end.
- **Relinquishing the audio session on handoff.** A genuine bug, fixed, and unrelated
  to this one.

We do not control another app's lifecycle. There is no entitlement or background mode
that keeps a third-party app alive, and the only state that would -- Spotify actively
playing audio -- is precisely what cannot be true while something else plays.

**Rejected mitigation: keeping Spotify playing silently underneath.** It would work,
and it means two concurrent audio streams, Spotify reporting itself as playing, and a
volume the person did not ask for. Fighting the platform for a cosmetic gain.

What remains is honest product design rather than engineering: cross the boundary as
few times as possible, and explain the switch rather than let it surprise. This is the
same wall as the effects chain in another guise -- streaming audio lives in someone
else's process, and everything that follows from that is a constraint rather than a
bug.

## Crossing into Spotify from the lock screen: skip, and say so

The entry above establishes that waking a suspended Spotify needs the foreground.
This is what the queue does when it hits that case while the phone is locked.

Considered holding the track and notifying, so the person could unlock and resume
exactly where the playlist said. Built, then rejected on use: the music stops. A
queue that goes silent behind a lock screen reads as the app breaking, and the
notification arrives as a demand for attention to fix something rather than as
information. The playlist's order is worth defending, but not at the price of
silence — and the person who is not looking at their phone is precisely the one who
cannot act on the request.

So the queue skips to the next track it can actually start, bounded by the queue
length so a run of Spotify tracks terminates rather than spinning. The notification
becomes a report — which track was passed over, and why — delivered without sound,
under a fixed identifier so three skips replace one notification rather than
stacking three.

Notification permission is requested when a streaming service is connected, not at
launch and not at the moment of need. Launch asks for trust the app has not earned.
The moment of need does not work at all: it is behind a lock screen, and iOS does
not present a permission prompt to a backgrounded app, so the request fails and the
report is silently lost. Connecting Spotify is a foreground action and the first
moment the permission means anything, which makes it the right place to ask.

## Syncing is automatic, and the queue is the database

Sync originally ran only when someone pressed a button, which made the button the
feature. An edit made on the phone did not exist anywhere else until a person
remembered to press it, and the web client -- which has no way to know that -- simply
showed stale playlists and looked broken. Nobody should have to know a sync protocol
exists.

`PlaylistSyncScheduler` decides when; `PlaylistSyncService` still decides what. The
split matters because the "what" is the part that was already correct and already
tested, and it did not need touching.

**The scheduler holds no queue.** Every edited row already carries `hasLocalChanges`,
which survives a crash, a force-quit and a flat battery, and the sync service pushes
whatever carries it whenever it runs. So nothing in the scheduler is load-bearing for
correctness: a missed trigger delays an edit, it can never lose one. That is what
makes it safe to coalesce aggressively, and it is why the answer to "what if the
debounce is cancelled" is "nothing happens, the next trigger picks it up" rather than
a retry queue that would need its own persistence and its own tests.

Three triggers, each for a different reason. A local edit debounces two seconds,
because adding five tracks is five writes in a few seconds and syncing each one means
five round trips to push what one would carry -- and five chances for the server to
move underneath the next, which surfaces a conflict to a person for something they
experienced as a single action. Returning to the foreground syncs immediately and
even with nothing to push, because that is the moment to *pull*: anything edited on
the web happened while this app was not running to hear about it. Leaving the screen
flushes under a background-task assertion, because a pending debounce is suspended
along with the app and might not resume before the next launch.

**Rejected: syncing on every write.** Simpler, and it is what the debounce exists to
avoid. It converts one user action into a burst of round trips whose only distinctive
outcome is a conflict report nobody can act on.

**Rejected: a timer.** Polling on an interval spends battery on an app that is idle
most of the time, and still cannot beat the foreground trigger to a change made
elsewhere.

The banner went quiet as a consequence. Reporting every background sync would put a
banner on screen every time someone added a track -- constant, uninformative, and the
fastest way to make the one banner that matters invisible. Progress and success are
now reported only for a sync somebody asked for; failures and conflicts show either
way, because both mean edits are not where the person thinks they are, which is true
regardless of who started it.

## A version number only means something inside the history that issued it

Found the hard way. The local backend ran on in-memory H2, so every rebuild emptied
the database -- and a rebuild is what happens constantly. The phone would then list
playlists, find none, and read that as N deletions: `PlaylistSync` returns
`deleteLocal` for a playlist the device synced at version 7 that the server no longer
has. Correct, so long as the absence is a deletion. Against a database that was
replaced, restored, or restarted, the same absence means those versions were never
that server's, and honouring it destroys playlists nobody deleted.

Nothing in the version numbers can tell those apart, which is why it is a separate
question asked before the decision table rather than another row in it.

The server now publishes an **epoch**: one persisted random value that changes exactly
when its history does. A client storing a different value knows its recorded versions
describe a history this server never had, forgets them, and pushes -- so every
playlist looks like one created locally and never uploaded. Deliberately not a
timestamp or a counter: it needs no ordering, only difference, and a random value
cannot collide with a meaningful one after a restore.

**Unverifiable is treated as replaced.** A device upgrading from a build with no
epochs holds versions and no way to say where they came from. It re-uploads, because
the two mistakes are not the same size: re-uploading a playlist the server already
has costs a request and produces a conflict a person can resolve, while deleting one
it does not have costs the playlist and nothing brings it back.

**Accepted cost.** After a restore from backup, a server that still holds the same
playlist ids meets clients whose recorded versions are gone, and `(remote .some,
synced nil)` is `conflict` -- so a restore produces a conflict per playlist rather
than a silent merge. Noisy, and correct: a restored database genuinely is a second
history under the same identity, and that is a person's call.

The local database moved to a file in the same change. "In-memory so it starts with no
infrastructure" was a real benefit, but a file needs no more infrastructure and does
not make every rebuild destructive.

## Rejected features

- **Stems / source separation.** A machine-learning project wearing a tab.
- **BPM and key detection.** Would require real analysis; showing invented values
  would be worse than showing nothing.
- **Uploading local audio to a server.** Turns a music tool into a file-hosting
  service, with the storage bill and licensing questions that implies.
- **Favorites and recently-played.** Cuttable; they add screens, not architecture.

## Cuttable if time runs short

Originally: offline render export, and tests. Both are now done, so neither is
available to cut.

What remains cuttable: the web client's polish, and the demo video.

What cannot be cut without the project ceasing to be what it claims: Apple Music
integration, cross-source playlists (done), and lock screen controls (done).
