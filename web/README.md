# OmniMusik Web

React + TypeScript control plane for OmniMusik playlists.

```bash
npm install
cp .env.example .env.local   # fill in from the Terraform outputs
npm run dev                  # http://localhost:5173
npm run build
```

## What this is, and what it deliberately is not

This client **cannot play audio**, and says so on screen rather than shipping a dead
transport bar. That is a structural constraint, not a missing feature:

- Local files live on the phone. Streaming them here would mean uploading owned audio
  to a server, which `DECISIONS.md` rejects — it turns a music tool into a file-hosting
  service, with the storage bill and licensing exposure that implies.
- Apple Music on the web needs MusicKit JS, which is blocked on the same App Service
  provisioning that blocks the iOS integration.

So it is a control plane: sign in, build and reorder playlists, and let the phone play
them. When MusicKit JS becomes available it slots in as a playback layer without
changing anything here.

## Notes on the implementation

**Auth is the same flow as iOS.** Authorization code with PKCE against the Cognito
Hosted UI, against the same user pool, so Sign in with Apple appears here the moment
it is configured there — with no change to this codebase. A browser can no more keep
a client secret than an app binary can, which is why the app client is public and PKCE
is doing the real work.

**Tokens are in `sessionStorage`, and that is a tradeoff worth naming.** Anything
JavaScript can read, an XSS payload can read. The fix that actually works is a
backend-for-frontend holding tokens in an httpOnly cookie; that is the right answer
for a product handling anything sensitive. Here the blast radius is a playlist, and
`sessionStorage` at least dies with the tab.

**Conflicts are surfaced, not resolved silently.** A playlist edited on the phone
while a tab is open cannot be saved over. The API answers `409` with its current
state attached, and the UI asks which version to keep. Retrying with the new version
number would be last-write-wins with extra steps.

**The wire types mirror Swift exactly** — `sourceID`, `local`, `appleMusic`. Swift
derives coding keys from property names and encodes string enums by raw value, so
renaming them to JavaScript convention would break the phone and nothing else.

## Troubleshooting

If `npm run build` fails with a missing `@rolldown/binding-*` module, npm skipped an
optional platform dependency. Reinstall, or install the binding for your platform
directly. Vite 8 also wants Node 20.19+; it builds on 20.18 but warns.
