# Running locally

Three processes, any subset of which is useful on its own. The phone works with
nothing else running; the web client needs the API; the API needs nothing.

## Backend

```bash
cd backend
./mvnw test                 # 17 integration tests, H2 in memory
./mvnw spring-boot:run      # http://localhost:8080
```

Local runs use H2 **on disk** at `backend/data/omnimusik.mv.db` (gitignored), so a
restart keeps its data. It used to be in-memory, and every rebuild emptied a database
two clients were syncing against — the phone then read the absence as N deletions.
The sync epoch exists because of that, and the file does too.

Token validation is real even locally: the resource server fetches Cognito's signing
keys from the production pool on first request. A request without a token gets 401;
`GET /actuator/health` needs none.

Useful checks:

```bash
curl localhost:8080/actuator/health          # {"status":"UP"}
curl -i localhost:8080/api/v1/playlists      # 401 without a token
curl -i localhost:8080/api/v1/sync/epoch     # 401; the epoch a client compares against
```

## Web client

```bash
cd web
npm ci
npm run dev                 # http://localhost:5173
npm run build               # type-check + production bundle into dist/
```

Configuration is `web/.env.local` (gitignored; copy `.env.example`). Vite reads it
**at startup only** — change `VITE_API_BASE_URL` and restart the dev server, or it
keeps talking to the old API. It currently points at the production API; set it to
`http://localhost:8080` to work against a local backend.

Sign-in goes through the real Cognito hosted UI either way. React StrictMode
double-invokes effects in development, which would consume the single-use OAuth
code twice; the callback page memoises the exchange at module level for that reason.

## The phone

Open `OmniMusik/OmniMusik.xcodeproj` in Xcode, or build from the terminal as in
[Deploying](Deploying.md#the-phone). `DEVELOPER_DIR` must point at Xcode.app.

Which API it talks to is `baseURLString` in `OmniMusik/Library/APIConfiguration.swift`:

| `baseURLString` | Debug build | Release build |
|---|---|---|
| a URL | that URL | that URL |
| `REPLACE_ME` | the Mac's backend at `http://Obis-MacBook-Air.local:8080` | sync reports itself unconfigured |

The Bonjour name rather than a LAN address: it survives DHCP, and `.local` names are
covered by the `NSAllowsLocalNetworking` ATS exception where a raw private IP may not
be. Phone and Mac must be on the same network.

Spotify requires the Spotify app installed and a Premium account; connect it from the
Account tab. Apple Music is a stub until the developer account's App Service clears.

## Tests

```bash
# iOS: 74 unit + 12 UI. The UI suite is serial by design; do not re-enable parallel.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd OmniMusik
xcodebuild -project OmniMusik.xcodeproj -scheme OmniMusik \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Backend: 17
cd backend && ./mvnw test

# Web: type-check
cd web && npx tsc --noEmit
```

Debug builds ship four synthesised sample tracks (`SampleAudio/`) because Save to
Files is broken in the iOS 18 simulator; the UI tests depend on them and Release
builds exclude them.

## Pulling logs off the phone

`HandoffLog` (DEBUG only) writes timestamped lines to `Documents/handoff.log` in the
app container, for the Spotify handoff path that cannot be observed on screen:

```bash
xcrun devicectl device copy from --device 34635B4F-CC7B-476A-9556-8BDD271328B8 \
  --domain-type appDataContainer --domain-identifier com.obinnaduruaku.OmniMusik \
  --source Documents/handoff.log --destination ./handoff.log
```
