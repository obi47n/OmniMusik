import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { completeSignIn, type Tokens } from '../auth/cognito'
import { useAuth } from '../auth/AuthContext'

/**
 * The single in-flight code exchange, keyed by the query string that started it.
 *
 * Module scope on purpose. React StrictMode deliberately invokes effects twice in
 * development, and an OAuth callback cannot tolerate that: the first exchange
 * consumes the PKCE state and verifier from sessionStorage and redeems the
 * authorization code, so the second finds no state and reports "the sign-in response
 * did not match the request that started it" -- after the sign-in had in fact
 * succeeded. Worse, the first run's tokens were discarded, because StrictMode's
 * cleanup had already flagged it cancelled.
 *
 * Sharing one promise means the exchange happens once and whichever invocation is
 * still mounted receives the result. A component-level ref would also survive the
 * double-invoke, but not a genuine remount, and an authorization code is single-use.
 */
let pendingExchange: Promise<Tokens> | null = null
let pendingKey: string | null = null

function exchangeOnce(search: string): Promise<Tokens> {
  if (pendingKey !== search || pendingExchange === null) {
    pendingKey = search
    pendingExchange = completeSignIn(search)
  }
  return pendingExchange
}

/** Redirect target for the hosted UI. Exchanges the code, then gets out of the way. */
export function Callback() {
  const { adopt } = useAuth()
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    exchangeOnce(window.location.search)
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
      {error && <button onClick={() => navigate('/', { replace: true })}>Back</button>}
    </div>
  )
}
