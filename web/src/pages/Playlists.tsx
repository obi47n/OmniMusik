import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import { formatDuration, isCrossSource, totalDuration, type Playlist } from '../types'

export function Playlists() {
  const { getAccessToken } = useAuth()
  const [playlists, setPlaylists] = useState<Playlist[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [newName, setNewName] = useState('')
  const [busy, setBusy] = useState(false)

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
        <ul className="list">
          {playlists.map((playlist) => (
            <li className="card" key={playlist.id}>
              <div className="card-main">
                <div className="card-title">
                  <Link to={`/playlists/${playlist.id}`}>{playlist.name}</Link>
                </div>
                <div className="card-sub">
                  <span>
                    {playlist.entries.length === 0
                      ? 'Empty'
                      : `${playlist.entries.length} ${playlist.entries.length === 1 ? 'track' : 'tracks'} · ${formatDuration(totalDuration(playlist))}`}
                  </span>
                  {isCrossSource(playlist) && <span className="badge">MIXED</span>}
                </div>
              </div>
              <Link to={`/playlists/${playlist.id}`}>
                <button>Open</button>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  )
}
