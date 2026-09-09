/**
 * Runtime configuration, supplied at build time by Vite.
 *
 * None of these are secrets: the Cognito app client is public and secured by PKCE,
 * exactly as on iOS. Copy `.env.example` to `.env.local` and fill in the Terraform
 * outputs.
 */
export const config = {
  cognitoDomain: import.meta.env.VITE_COGNITO_DOMAIN ?? '',
  clientId: import.meta.env.VITE_COGNITO_CLIENT_ID ?? '',
  apiBaseUrl: import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8080',
  redirectUri: `${window.location.origin}/callback`,
  scopes: ['openid', 'email', 'profile'],
}

/**
 * Whether this build has enough configuration to sign in.
 *
 * Mirrors `AuthProvider.isConfigured` on iOS: an unconfigured checkout should
 * explain itself rather than offer a button that cannot work.
 */
export const isConfigured = (): boolean =>
  config.cognitoDomain !== '' &&
  config.clientId !== '' &&
  !config.cognitoDomain.includes('REPLACE_ME')
