import { beginSignIn } from '../auth/cognito'
import { isConfigured } from '../config'

export function Login() {
  if (!isConfigured()) {
    // Mirrors the iOS account screen: an unconfigured build explains itself rather
    // than offering a button that cannot work.
    return (
      <div className="center">
        <h1>Sign-in not configured</h1>
        <p>
          Copy <code>.env.example</code> to <code>.env.local</code> and fill in the Cognito
          values from your Terraform outputs, then restart the dev server.
        </p>
      </div>
    )
  }

  return (
    <div className="center">
      <h1>OmniMusik on the web</h1>
      <p>
        Sign in to manage the playlists that sync with your phone. Playback stays on
        iOS — see below for why.
      </p>
      <button className="primary" onClick={() => void beginSignIn()}>
        Sign In
      </button>
    </div>
  )
}
