# OmniMusik API

Spring Boot 4 service backing playlist sync for the iOS and web clients.

## Running locally

```bash
cd backend
./mvnw spring-boot:run
```

Starts on `:8080` against an in-memory H2 database, so it needs no infrastructure.
Every endpoint except the actuator health probes requires a bearer token.

```bash
./mvnw test
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/me` | The caller's account; provisions it on first call |
| `GET` | `/api/v1/playlists` | The caller's playlists, most recently updated first |
| `GET` | `/api/v1/playlists/{id}` | One playlist |
| `PUT` | `/api/v1/playlists/{id}` | Create or replace |
| `DELETE` | `/api/v1/playlists/{id}` | Delete |

## The parts worth explaining

**Create and update are one idempotent `PUT` under a client-chosen id.** Playlists
are created offline on a device that may not see the network for days, so they need
a stable identity from the moment they exist. A client-chosen UUID also makes a retry
after a lost response harmless instead of creating a duplicate — the single most
common sync failure, removed by construction.

**Writes are version-checked, not last-write-wins.** Two devices editing one playlist
is the normal case for this app: a set built on the phone is exactly the thing you
then reorder on the web. The client sends the version it last read; if the stored
version has moved on, the write is refused with `409` and **the server's current
state in the response body**, so the client can merge without a second round trip.
Answering with a bare 409 invites the client to retry blindly with the new version,
which is last-write-wins wearing a seatbelt.

A JPA `@Version` column additionally catches two requests racing inside the same
instant, which the explicit check cannot see.

**Another user's playlist answers `404`, not `403`.** A 403 would confirm the id
exists, turning the endpoint into an oracle for enumerating other people's data.

**Entries are stored as JSON in one column.** The same decision as the iOS client,
for the same reasons: order is the point of a playlist and relationships are
unordered, entries are never queried independently, and a relationship would have to
point at a local-track table, which would make cross-source playlists impossible. The
cost is that entries are opaque to SQL.

**The wire format matches Swift exactly.** `TrackSource` serialises as `local` and
`appleMusic`, and the entry field is `sourceID`, because Swift derives coding keys
from property names and encodes string-backed enums by raw value. Renaming either to
Java convention would break the client silently. Timestamps are ISO-8601, so the iOS
client must use `.iso8601` — Swift's default reads dates as seconds since 2001.

## Configuration

| Variable | Purpose |
|---|---|
| `COGNITO_ISSUER_URI` | Token issuer; the JWKS endpoint is discovered from it |
| `DB_HOST` `DB_PORT` `DB_NAME` `DB_USER` `DB_PASSWORD` | Postgres, `prod` profile only |
| `ALLOWED_ORIGINS` | Comma-separated CORS origins for the web client |

Nothing secret is committed. The `prod` profile reads everything from the environment.

`spring.jpa.hibernate.ddl-auto` is `update` in development and `validate` in `prod` —
letting Hibernate alter a live table is a liability. A real deployment adds Flyway;
`validate` is the honest placeholder until then.
