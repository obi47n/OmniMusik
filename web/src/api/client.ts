import { config } from '../config'
import type { Playlist } from '../types'

/**
 * Typed access to the API.
 *
 * Every call takes a token getter rather than reading storage itself, so the refresh
 * rule stays in `AuthContext` and this layer has no opinion about sessions.
 */

export class ApiError extends Error {
  // Declared as fields rather than constructor parameter properties: TypeScript 6
  // enables erasableSyntaxOnly, which rejects the shorthand because it emits code
  // rather than being pure type syntax.
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

/**
 * Raised when a write is refused because the playlist moved on underneath us.
 *
 * Carries the server's current state, which the API returns with the 409 precisely so
 * the client can merge without another round trip.
 */
export class ConflictError extends ApiError {
  readonly current: Playlist

  constructor(current: Playlist) {
    super(409, 'This playlist was changed on another device.')
    this.current = current
  }
}

type TokenGetter = () => Promise<string | null>

async function request<T>(
  path: string,
  getToken: TokenGetter,
  init: RequestInit = {},
): Promise<T> {
  const token = await getToken()
  if (!token) throw new ApiError(401, 'Not signed in.')

  const response = await fetch(`${config.apiBaseUrl}${path}`, {
    ...init,
    headers: {
      ...init.headers,
      Authorization: `Bearer ${token}`,
      ...(init.body ? { 'Content-Type': 'application/json' } : {}),
    },
  })

  if (response.status === 204) return undefined as T

  if (response.status === 409) {
    const body = (await response.json()) as { current?: Playlist; message?: string }
    if (body.current) throw new ConflictError(body.current)
    throw new ApiError(409, body.message ?? 'Conflict.')
  }

  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as { message?: string } | null
    throw new ApiError(response.status, body?.message ?? `Request failed (${response.status}).`)
  }

  return (await response.json()) as T
}

export const api = {
  listPlaylists: (getToken: TokenGetter) => request<Playlist[]>('/api/v1/playlists', getToken),

  getPlaylist: (getToken: TokenGetter, id: string) =>
    request<Playlist>(`/api/v1/playlists/${id}`, getToken),

  /**
   * Creates or replaces. `expectedVersion` is null on a create and required on an
   * update; omitting it against an existing playlist is refused rather than allowed
   * to clobber an edit this client never read.
   */
  upsertPlaylist: (
    getToken: TokenGetter,
    id: string,
    body: { name: string; entries: Playlist['entries']; expectedVersion: number | null },
  ) =>
    request<Playlist>(`/api/v1/playlists/${id}`, getToken, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  deletePlaylist: (getToken: TokenGetter, id: string) =>
    request<void>(`/api/v1/playlists/${id}`, getToken, { method: 'DELETE' }),
}
