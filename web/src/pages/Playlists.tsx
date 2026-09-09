import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import {
  formatDuration,
  isCrossSource,
  playlistTint,
  totalDuration,
  type Playlist,
} from '../types'

/** The same top-left-to-bottom-right gradient the iOS tiles use. */
function coverFor(playlist: Playlist): string {
  const tint = playlistTint(playlist.id)
  return `linear-gradient(135deg, ${tint}, color-mix(in srgb, ${tint} 45%, transparent))`
}

export function Playlists() {
  const { getAccessToken } = useAuth()
  const [playlists, setPlaylists] = useState<Playlist[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [newName, setNewName] = useState('')
  const [busy, setBusy] = useState(false)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    try {
      setPlaylists(await api.listPlaylists(getAccessToken))
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load playlists.')
    }
  }, [getAccessToken])

  useEffect(() => {
    void load()
  }, [load])

  // The phone pushes edits on its own, so this page goes stale rather than wrong:
  // what it shows was true when it loaded. Refreshing is therefore a read, not a
  // sync -- there is nothing on this side waiting to go anywhere.
  async function refresh() {
    setRefreshing(true)
    try {
      await load()
    } finally {
      setRefreshing(false)
    }
  }

  async function create() {
    const name = newName.trim()
    if (!name) return
    setBusy(true)
    try {
      // The client picks the id, matching the iOS client and making the upload
      // idempotent if the response is lost.
      await api.upsertPlaylist(getAccessToken, crypto.randomUUID(), {
        name,
        entries: [],
        expectedVersion: null,
      })
      setNewName('')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not create the playlist.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <div className="notice">
        <h3>Playback lives on iOS</h3>
        <p>
          Local files are on your phone, and Apple Music on the web needs MusicKit JS.
          This is a control plane: build and reorder playlists here, play them there.
        </p>
      </div>

      <header className="bar" style={{ borderBottom: 'none', marginBottom: 14, paddingTop: 0 }}>
        <h2>Playlists</h2>
        <div className="row-actions">
          <button onClick={() => void refresh()} disabled={refreshing}>
            {refreshing ? 'Refreshing…' : 'Refresh'}
          </button>
          <input
            type="text"
            placeholder="New playlist name"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void create()
            }}
          />
          <button className="primary" onClick={() => void create()} disabled={busy || !newName.trim()}>
            Create
          </button>
        </div>
      </header>

      {error && (
        <div className="notice warn">
          <h3>Something went wrong</h3>
          <p>{error}</p>
        </div>
      )}

      {playlists === null && <p className="muted">Loading…</p>}

      {playlists?.length === 0 && (
        <div className="center">
          <h1>No playlists yet</h1>
          <p>Create one here, or build it on your phone — they are the same list.</p>
        </div>
      )}

      {playlists && playlists.length > 0 && (
        <ul className="grid">
          {playlists.map((playlist) => (
            <li key={playlist.id}>
              <Link to={`/playlists/${playlist.id}`} className="tile-link">
                <div className="tile-cover" style={{ background: coverFor(playlist) }} />
                <div className="tile-name">{playlist.name}</div>
                <div className="tile-sub">
                  <span>
                    {playlist.entries.length === 0
                      ? 'Empty'
                      : `${playlist.entries.length} ${playlist.entries.length === 1 ? 'track' : 'tracks'} · ${formatDuration(totalDuration(playlist))}`}
                  </span>
                  {isCrossSource(playlist) && <span className="badge">MIXED</span>}
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  )
}
