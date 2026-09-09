import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { api, ConflictError } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import {
  formatDuration,
  moveEntryOnto,
  sourceLabel,
  type Playlist,
  type PlaylistEntry,
} from '../types'

/**
 * One playlist, editable.
 *
 * The conflict path is the interesting part of this screen. A playlist edited on the
 * phone while this tab was open cannot be saved over silently, so a refused write
 * surfaces the server's version and asks which one to keep — rather than retrying
 * with the new version number, which would be last-write-wins with extra steps.
 */
export function PlaylistDetail() {
  const { id = '' } = useParams()
  const { getAccessToken } = useAuth()
  const navigate = useNavigate()

  const [playlist, setPlaylist] = useState<Playlist | null>(null)
  const [entries, setEntries] = useState<PlaylistEntry[]>([])
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [conflict, setConflict] = useState<Playlist | null>(null)
  const [busy, setBusy] = useState(false)
  const [refreshing, setRefreshing] = useState(false)

  // Which row is in the air, and which one it is currently over. Both are ids
  // rather than indices: the list reorders under the pointer while a drag is in
  // progress, so an index captured at drag start stops meaning anything.
  const [draggingID, setDraggingID] = useState<string | null>(null)
  const [dropTargetID, setDropTargetID] = useState<string | null>(null)

  const adopt = useCallback((next: Playlist) => {
    setPlaylist(next)
    setEntries(next.entries)
    setName(next.name)
  }, [])

  const load = useCallback(async () => {
    try {
      adopt(await api.getPlaylist(getAccessToken, id))
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load this playlist.')
    }
  }, [adopt, getAccessToken, id])

  useEffect(() => {
    void load()
  }, [load])

  const dirty =
    playlist !== null &&
    (name !== playlist.name ||
      entries.length !== playlist.entries.length ||
      entries.some((entry, index) => entry.id !== playlist.entries[index]?.id))

  async function save() {
    if (!playlist) return
    setBusy(true)
    try {
      const saved = await api.upsertPlaylist(getAccessToken, playlist.id, {
        name: name.trim() || playlist.name,
        entries,
        expectedVersion: playlist.version,
      })
      adopt(saved)
      setConflict(null)
      setError(null)
    } catch (e) {
      if (e instanceof ConflictError) {
        // The 409 carried the server's current state, so there is enough here to
        // show what changed without another request.
        setConflict(e.current)
      } else {
        setError(e instanceof Error ? e.message : 'Could not save.')
      }
    } finally {
      setBusy(false)
    }
  }

  function endDrag() {
    setDraggingID(null)
    setDropTargetID(null)
  }

  function dropOnto(targetID: string) {
    if (draggingID) setEntries(moveEntryOnto(entries, draggingID, targetID))
    endDrag()
  }

  function move(index: number, delta: number) {
    const target = index + delta
    if (target < 0 || target >= entries.length) return
    const next = [...entries]
    ;[next[index], next[target]] = [next[target], next[index]]
    setEntries(next)
  }

  async function remove() {
    if (!playlist) return
    setBusy(true)
    try {
      await api.deletePlaylist(getAccessToken, playlist.id)
      navigate('/', { replace: true })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete.')
      setBusy(false)
    }
  }

  async function refresh() {
    setRefreshing(true)
    try {
      await load()
    } finally {
      setRefreshing(false)
    }
  }

  if (error && !playlist) {
    return (
      <div className="center">
        <h1>Playlist unavailable</h1>
        <p>{error}</p>
        <button onClick={() => navigate('/')}>Back to playlists</button>
      </div>
    )
  }

  if (!playlist) return <p className="muted">Loading…</p>

  return (
    <>
      {conflict && (
        <div className="notice warn">
          <h3>Changed on another device</h3>
          <p>
            This playlist was edited elsewhere while you had it open — it is now
            &ldquo;{conflict.name}&rdquo; with {conflict.entries.length}{' '}
            {conflict.entries.length === 1 ? 'track' : 'tracks'}. Load their version to
            start from it, or keep editing and save again to overwrite.
          </p>
          <div className="row-actions" style={{ marginTop: 10 }}>
            <button onClick={() => { adopt(conflict); setConflict(null) }}>
              Load their version
            </button>
            <button
              onClick={() => {
                // Adopting only the version keeps this client's edits and makes the
                // next save win. Explicit, and chosen by a person.
                setPlaylist({ ...playlist, version: conflict.version })
                setConflict(null)
              }}
            >
              Keep mine
            </button>
          </div>
        </div>
      )}

      {error && (
        <div className="notice warn">
          <h3>Something went wrong</h3>
          <p>{error}</p>
        </div>
      )}

      <Link to="/" className="back">
        &larr; All playlists
      </Link>

      <header className="bar" style={{ borderBottom: 'none', paddingTop: 0 }}>
        <input type="text" value={name} onChange={(e) => setName(e.target.value)} aria-label="Playlist name" />
        <div className="row-actions">
          {/*
            Re-reads the server, which is where a track added on the phone arrives.
            Disabled while there are unsaved edits rather than warning about them:
            this is a read that replaces everything on screen, so offering it next to
            work someone has not saved is offering to discard that work.
          */}
          <button
            onClick={() => void refresh()}
            disabled={busy || refreshing || dirty}
            title={dirty ? 'Save or discard your changes first' : undefined}
          >
            {refreshing ? 'Refreshing…' : 'Refresh'}
          </button>
          <button className="primary" onClick={() => void save()} disabled={busy || !dirty}>
            {busy ? 'Saving…' : dirty ? 'Save' : 'Saved'}
          </button>
          <button className="danger" onClick={() => void remove()} disabled={busy}>
            Delete
          </button>
        </div>
      </header>

      {entries.length === 0 ? (
        <div className="center">
          <h1>Nothing here yet</h1>
          <p>Add tracks from your phone — the library lives on the device.</p>
        </div>
      ) : (
        <ul className="list">
          {entries.map((entry, index) => (
            <li
              className={[
                'card',
                'draggable-row',
                draggingID === entry.id ? 'dragging' : '',
                dropTargetID === entry.id && draggingID !== entry.id ? 'drop-target' : '',
              ]
                .filter(Boolean)
                .join(' ')}
              key={entry.id}
              draggable
              onDragStart={(e) => {
                setDraggingID(entry.id)
                // Firefox starts no drag at all unless data is set, and the effect
                // has to say "move" or the cursor offers a copy that never happens.
                e.dataTransfer.effectAllowed = 'move'
                e.dataTransfer.setData('text/plain', entry.id)
              }}
              onDragOver={(e) => {
                // Without this the browser refuses the drop -- silently, and the row
                // simply springs back.
                e.preventDefault()
                e.dataTransfer.dropEffect = 'move'
                if (dropTargetID !== entry.id) setDropTargetID(entry.id)
              }}
              onDrop={(e) => {
                e.preventDefault()
                dropOnto(entry.id)
              }}
              onDragEnd={endDrag}
            >
              <span className="drag-handle" aria-hidden="true">
                ⠿
              </span>
              <div className="card-main">
                <div className="card-title">{entry.title}</div>
                <div className="card-sub">
                  <span>{entry.artist}</span>
                  <span className="badge plain">{sourceLabel(entry.source)}</span>
                  <span>{formatDuration(entry.duration)}</span>
                </div>
              </div>
              <div className="row-actions">
                <button className="icon" onClick={() => move(index, -1)} disabled={index === 0} aria-label="Move up">
                  ↑
                </button>
                <button
                  className="icon"
                  onClick={() => move(index, 1)}
                  disabled={index === entries.length - 1}
                  aria-label="Move down"
                >
                  ↓
                </button>
                <button
                  className="icon danger"
                  onClick={() => setEntries(entries.filter((e) => e.id !== entry.id))}
                  aria-label={`Remove ${entry.title}`}
                >
                  Remove
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  )
}
