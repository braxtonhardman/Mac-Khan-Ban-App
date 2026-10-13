# ChatGPT profile connection

Profile → Accounts → ChatGPT opens a page inside the existing settings modal, preserving the shared glass header and back navigation on Mac and iPhone. Continue with ChatGPT starts OpenAI's public-client registration flow with PKCE, a fresh state and nonce, and an installation-specific host ID. Optional ChatGPT plan usage is off by default. Its scopes, including renewable access, are requested only when the toggle is enabled; identity-only sign-in requests openid/profile/email. This PR establishes profile connection; task generation and inference are not included.

The browser returns to an IPv4 loopback listener bound only to 127.0.0.1 on an ephemeral port. On Mac the default browser opens; on iPhone an in-app Safari browser keeps Tierin in the foreground while the listener runs. The listener starts before authorization, buffers fast callbacks, bounds concurrent connections, closes them on cancellation, and expires after three minutes. The iPhone Safari redirect path needs live device verification before merge.

Only RS256 identity tokens from OpenAI's discovery/JWKS endpoints are accepted. Signature, issuer, audience, authorized party for multiple audiences, expiry, nonce and subject are checked before saving identity. Callback state, URI and issued client ID are validated, and duplicate parameters rejected. OpenAI error bodies and authorization URLs are never logged.

Tokens and the host ID use device-local, non-synchronizing Keychain records. They are never placed in SwiftData or the shared iCloud profile. Disconnect attempts remote refresh-token revocation, clears local tokens, and reports unconfirmed remote revocation. Verified client/account mappings are retained for reauthorization. One account is connected at a time; after disconnecting, choose a saved registration or “Use another ChatGPT account.” The active session and registration list are saved atomically in one Keychain item. Reconnect must match the selected verified account. Access token expiry is saved; reconnect renews the connection. A future inference implementation must add serialized refresh-token rotation before using these credentials.

Validation: CI compiles iPhone and Mac targets and runs offline PKCE, callback, form encoding, RSA signature, tampering, identity-claim, saved-registration and early-callback checks. Live sign-in, cancellation, restart, revocation and Safari redirects still need verification on iPhone and Mac. No real credentials are used in CI.

References:
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

This follows the documented open-source/local application preview. Eligibility and production/commercial availability must be confirmed before distributing this connection beyond testing.
