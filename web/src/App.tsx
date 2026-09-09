import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, useAuth } from './auth/AuthContext'
import { Callback } from './pages/Callback'
import { Login } from './pages/Login'
import { PlaylistDetail } from './pages/PlaylistDetail'
import { Playlists } from './pages/Playlists'
import './styles.css'

function Shell() {
  const { isSignedIn, displayName, email, signOut } = useAuth()

  return (
    <div className="shell">
      <header className="bar">
        <div className="brand">
          Omni<span>Musik</span>
        </div>
        {isSignedIn && (
          <div className="row-actions">
            <span className="who">{displayName ?? email ?? 'Signed in'}</span>
            <button onClick={signOut}>Sign Out</button>
          </div>
        )}
      </header>

      <Routes>
        <Route path="/callback" element={<Callback />} />
        <Route path="/" element={isSignedIn ? <Playlists /> : <Login />} />
        <Route
          path="/playlists/:id"
          element={isSignedIn ? <PlaylistDetail /> : <Navigate to="/" replace />}
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Shell />
      </AuthProvider>
    </BrowserRouter>
  )
}
