import { config } from '../config'
import { challengeFor, createVerifier } from './pkce'

/**
 * OAuth2 authorization-code flow with PKCE against the Cognito Hosted UI.
 *
 * The same flow as the iOS client, against the same user pool, so Sign in with Apple
 * appears here the moment it is configured there — with no change to this file.
 *
 * Tokens live in `sessionStorage`. That is a deliberate tradeoff and worth being able
 * to defend: any token reachable from JavaScript is reachable from an XSS payload.
 * The alternative that actually fixes this is a backend-for-frontend holding the
 * tokens in an httpOnly cookie, which is the right answer for a product handling
 * anything sensitive. Here the blast radius is a playlist, and sessionStorage at
 * least dies with the tab rather than persisting like localStorage.
 */

const VERIFIER_KEY = 'omnimusik.pkce.verifier'
const STATE_KEY = 'omnimusik.pkce.state'
const TOKENS_KEY = 'omnimusik.tokens'

export interface Tokens {
  accessToken: string
  refreshToken: string | null
  idToken: string | null
  /** Epoch milliseconds. Computed at receipt, so expiry is a plain comparison later. */
  expiresAt: number
}

export function loadTokens(): Tokens | null {
  const raw = sessionStorage.getItem(TOKENS_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw) as Tokens
  } catch {
    return null
  }
}

export function saveTokens(tokens: Tokens): void {
  sessionStorage.setItem(TOKENS_KEY, JSON.stringify(tokens))
}

export function clearTokens(): void {
  sessionStorage.removeItem(TOKENS_KEY)
}

/** Treated as expired slightly early so a token cannot lapse mid-request. */
export function isExpired(tokens: Tokens): boolean {
  return Date.now() >= tokens.expiresAt - 60_000
}

export async function beginSignIn(): Promise<void> {
  const verifier = createVerifier()
  const state = createVerifier()
  sessionStorage.setItem(VERIFIER_KEY, verifier)
  sessionStorage.setItem(STATE_KEY, state)

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: config.scopes.join(' '),
    state,
    code_challenge: await challengeFor(verifier),
    code_challenge_method: 'S256',
  })

  window.location.assign(`https://${config.cognitoDomain}/oauth2/authorize?${params}`)
}

export async function completeSignIn(search: string): Promise<Tokens> {
  const params = new URLSearchParams(search)

  // Cognito reports refusals as a query parameter on a successful redirect rather
  // than as a transport error, so this is the only place they surface.
  const error = params.get('error')
  if (error) {
    throw new Error(params.get('error_description') ?? error)
  }

  const expectedState = sessionStorage.getItem(STATE_KEY)
  if (!expectedState || params.get('state') !== expectedState) {
    throw new Error('The sign-in response did not match the request that started it.')
  }

  const code = params.get('code')
  const verifier = sessionStorage.getItem(VERIFIER_KEY)
  if (!code || !verifier) {
    throw new Error('The sign-in response was missing or malformed.')
  }

  sessionStorage.removeItem(STATE_KEY)
  sessionStorage.removeItem(VERIFIER_KEY)

  return exchange({
    grant_type: 'authorization_code',
    client_id: config.clientId,
    code,
    redirect_uri: config.redirectUri,
    code_verifier: verifier,
  })
}

export async function refresh(refreshToken: string): Promise<Tokens> {
  const tokens = await exchange({
    grant_type: 'refresh_token',
    client_id: config.clientId,
    refresh_token: refreshToken,
  })
  // Cognito omits the refresh token on a refresh response, so carry the original
  // forward rather than losing it.
  return { ...tokens, refreshToken: tokens.refreshToken ?? refreshToken }
}

export function signOutUrl(): string {
  const params = new URLSearchParams({
    client_id: config.clientId,
    logout_uri: window.location.origin,
  })
  return `https://${config.cognitoDomain}/logout?${params}`
}

async function exchange(fields: Record<string, string>): Promise<Tokens> {
  const response = await fetch(`https://${config.cognitoDomain}/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  })

  if (!response.ok) {
    throw new Error(`Token exchange failed (${response.status}).`)
  }

  const payload = (await response.json()) as {
    access_token: string
    refresh_token?: string
    id_token?: string
    expires_in: number
  }

  return {
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token ?? null,
    idToken: payload.id_token ?? null,
    expiresAt: Date.now() + payload.expires_in * 1000,
  }
}
