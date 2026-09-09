import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { completeSignIn } from '../auth/cognito'
import { useAuth } from '../auth/AuthContext'

/** Redirect target for the hosted UI. Exchanges the code, then gets out of the way. */
export function Callback() {
  const { adopt } = useAuth()
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    completeSignIn(window.location.search)
      .then((tokens) => {
        if (cancelled) return
        adopt(tokens)
        // replace, not push: the callback URL carries a spent authorization code and
        // must not be reachable with the back button.
        navigate('/', { replace: true })
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Sign-in failed.')
      })
    return () => {
      cancelled = true
    }
  }, [adopt, navigate])

  return (
    <div className="center">
      <h1>{error ? 'Sign-in failed' : 'Signing in'}</h1>
      {error && <p>{error}</p>}
      {error && (
        <button onClick={() => navigate('/', { replace: true })}>Back</button>
      )}
    </div>
  )
}
