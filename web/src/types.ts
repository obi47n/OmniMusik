/**
 * The wire contract, shared with the iOS client and the Spring Boot service.
 *
 * These names are not stylistic choices. Swift derives coding keys from property
 * names and encodes string-backed enums by their raw value, so `sourceID` and
 * `appleMusic` are part of the contract. Renaming either to a JavaScript convention
 * would break decoding on device, and nowhere else.
 */

export type TrackSource = 'local' | 'appleMusic' | 'spotify'

export interface PlaylistEntry {
  id: string
  source: TrackSource
  /** Capitalised to match Swift's property name. Not a typo. */
  sourceID: string
  /**
   * Snapshot taken when the track was added.
   *
   * The web client depends on this more than either other client does: local files
   * live on somebody's phone, so the browser can never resolve them. Without the
   * snapshot every local track in a playlist would render as a blank row here.
   */
  title: string
  artist: string
  duration: number
}

export interface Playlist {
  id: string
  name: string
  entries: PlaylistEntry[]
  createdAt: string
  updatedAt: string
  /** Concurrency token. Send back what you last read, or the write is refused. */
  version: number
}

export interface Account {
  id: string
  subject: string
  email: string | null
  displayName: string | null
  createdAt: string
}

const SOURCE_LABELS: Record<TrackSource, string> = {
  local: 'Local',
  appleMusic: 'Apple Music',
  spotify: 'Spotify',
}

/**
 * A lookup rather than a conditional.
 *
 * The previous `source === 'local' ? 'Local' : 'Apple Music'` silently labelled every
 * new source as Apple Music. A Record keyed by the union makes TypeScript refuse to
 * compile until a new source is named — the nearest thing here to Swift's exhaustive
 * switch, which is what caught the same omission on the client.
 */
export const sourceLabel = (source: TrackSource): string =>
  SOURCE_LABELS[source] ?? source

export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '--:--'
  const total = Math.round(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const pad = (n: number) => n.toString().padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}

export function totalDuration(playlist: Playlist): number {
  return playlist.entries.reduce((sum, entry) => sum + entry.duration, 0)
}

/** True when the playlist genuinely mixes sources — the case worth surfacing. */
export function isCrossSource(playlist: Playlist): boolean {
  return new Set(playlist.entries.map((e) => e.source)).size > 1
}


/**
 * The colour a playlist's tile takes, matching the iOS app exactly.
 *
 * Same djb2 hash over the same input, so one playlist is the same colour on both
 * clients — which is the point: a person recognises a playlist by its tile, and a
 * tile that changes colour between devices is worse than no colour at all.
 *
 * Two details make them agree. Swift's `UUID.uuidString` is uppercase while JSON
 * carries lowercase, so the id is upper-cased before hashing. And SwiftUI's
 * `Color(hue:saturation:brightness:)` is HSB while CSS `hsl()` is HSL, so the fixed
 * 0.55/0.62 there converts to roughly 38%/45% here.
 */
export function playlistTint(id: string): string {
  let hash = 5381n
  for (const byte of new TextEncoder().encode(id.toUpperCase())) {
    hash = BigInt.asUintN(64, hash * 33n + BigInt(byte))
  }
  const hue = Number(hash % 360n)
  return `hsl(${hue}, 38%, 45%)`
}
