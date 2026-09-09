/**
 * Proof Key for Code Exchange (RFC 7636), the browser half.
 *
 * Deliberately the same flow the iOS client runs against the same user pool. A
 * browser cannot keep a client secret any more than an app binary can, so the
 * Cognito app client is public and PKCE is what stops an intercepted authorization
 * code from being redeemable.
 */

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = ''
  bytes.forEach((b) => {
    binary += String.fromCharCode(b)
  })
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** 32 random bytes lands inside the spec's 43-128 character window once encoded. */
export function createVerifier(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return base64UrlEncode(bytes)
}

export async function challengeFor(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))
  return base64UrlEncode(new Uint8Array(digest))
}

/** Reads a JWT payload for display. Verification is the API's job, not ours. */
export function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const segments = token.split('.')
  if (segments.length !== 3) return null
  try {
    const padded = segments[1].replace(/-/g, '+').replace(/_/g, '/')
    return JSON.parse(atob(padded)) as Record<string, unknown>
  } catch {
    return null
  }
}
