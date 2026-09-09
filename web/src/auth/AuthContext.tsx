import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import {
  clearTokens,
  isExpired,
  loadTokens,
  refresh as refreshTokens,
  saveTokens,
  signOutUrl,
  type Tokens,
} from './cognito'
import { decodeJwtPayload } from './pkce'

/**
 * Owns the session, and is the only thing that knows how a token is renewed.
 *
 * The counterpart of `AuthController` on iOS, with the same rule in the same one
 * place: callers ask for a valid access token and never reason about expiry.
 */

interface AuthState {
  isSignedIn: boolean
  displayName: string | null
  email: string | null
  /** Returns a token guaranteed fresh at the moment it is returned. */
  getAccessToken: () => Promise<string | null>
  adopt: (tokens: Tokens) => void
  signOut: () => void
}

const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [tokens, setTokens] = useState<Tokens | null>(() => loadTokens())

  useEffect(() => {
    if (tokens) saveTokens(tokens)
  }, [tokens])

  const adopt = useCallback((next: Tokens) => {
    saveTokens(next)
    setTokens(next)
  }, [])

  const signOut = useCallback(() => {
    // Local state is cleared first and unconditionally: signing out must never
    // appear to fail because a network call did.
    clearTokens()
    setTokens(null)
    window.location.assign(signOutUrl())
  }, [])

  const getAccessToken = useCallback(async (): Promise<string | null> => {
    const current = loadTokens()
    if (!current) return null
    if (!isExpired(current)) return current.accessToken

    if (!current.refreshToken) {
      clearTokens()
      setTokens(null)
      return null
    }

    try {
      const renewed = await refreshTokens(current.refreshToken)
      saveTokens(renewed)
      setTokens(renewed)
      return renewed.accessToken
    } catch {
      // A rejected refresh means the grant is gone; no retry will bring it back.
      clearTokens()
      setTokens(null)
      return null
    }
  }, [])

  const claims = useMemo(
    () => (tokens?.idToken ? decodeJwtPayload(tokens.idToken) : null),
    [tokens],
  )

  const value = useMemo<AuthState>(
    () => ({
      isSignedIn: tokens !== null,
      displayName: (claims?.name as string) ?? (claims?.given_name as string) ?? null,
      email: (claims?.email as string) ?? null,
      getAccessToken,
      adopt,
      signOut,
    }),
    [tokens, claims, getAccessToken, adopt, signOut],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthState {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside an AuthProvider')
  return context
}
