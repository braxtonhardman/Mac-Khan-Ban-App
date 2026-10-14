# ChatGPT profile connection

Profile → Accounts → ChatGPT opens a page inside the existing settings modal, preserving the shared glass header and back navigation on Mac and iPhone. Continue with ChatGPT starts OpenAI's public-client registration flow with PKCE, a fresh state and nonce, and an installation-specific host ID. Optional ChatGPT plan usage is off by default. Its scopes, including renewable access, are requested only when the toggle is enabled; identity-only sign-in requests openid/profile/email. The task details view includes a GPT button for sending that task’s description and displaying a streamed response.

The browser returns to an IPv4 loopback listener bound only to 127.0.0.1 on an ephemeral port. On Mac the default browser opens; on iPhone an in-app Safari browser keeps Tierin in the foreground while the listener runs. The listener starts before authorization, buffers fast callbacks, bounds concurrent connections, closes them on cancellation, and expires after three minutes. The iPhone Safari redirect path needs live device verification before merge.

Only RS256 identity tokens from OpenAI's discovery/JWKS endpoints are accepted. Signature, issuer, audience, authorized party for multiple audiences, expiry, nonce and subject are checked before saving identity. Callback state, URI and issued client ID are validated, and duplicate parameters rejected. OpenAI error bodies and authorization URLs are never logged.

Tokens and the host ID use device-local, non-synchronizing Keychain records. They are never placed in SwiftData or the shared iCloud profile. Disconnect attempts remote refresh-token revocation, clears local tokens, and reports unconfirmed remote revocation. Verified client/account mappings are retained for reauthorization. One account is connected at a time; after disconnecting, choose a saved registration or “Use another ChatGPT account.” The active session and registration list are saved atomically in one Keychain item. Reconnect must match the selected verified account. Access token expiry is saved; reconnect renews the connection. Expired sessions currently require an explicit reconnect before inference; automatic refresh-token rotation is not implemented.

Validation: CI compiles iPhone and Mac targets and runs offline PKCE, callback, form encoding, RSA signature, tampering, identity-claim, saved-registration and early-callback checks. Live sign-in, cancellation, restart, revocation and Safari redirects still need verification on iPhone and Mac. No real credentials are used in CI.

References:
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

This follows the documented open-source/local application preview. Eligibility and production/commercial availability must be confirmed before distributing this connection beyond testing.

## Live Mac verification — October 13, 2026

- Identity-only dynamic registration returned `invalid_client` in both Brave and Chrome. The endpoint, installation ID, PKCE, and loopback callback matched the documented flow.
- Enabling the existing opt-in plan-use toggle reached OpenAI’s consent screen in the default browser. After user approval, callback handling, token exchange, signed identity validation, and Keychain persistence succeeded. Settings showed Connected again after quitting and reopening Tierin. Reconnect completed through the default browser with no displayed error and retained the connected account.
- The browser selector was removed at the user’s request; sign-in always uses the default browser. Plan access remains opt-in. The identity-only failure remains a known issue; this is not a claim that every sign-in path works.
- No AI requests were run and no task content was sent. iPhone live verification, disconnect/revocation, and commercial distribution approval remain outstanding.

## Task description requests

Choose a model under Profile → Accounts → ChatGPT and save with the checkmark. The available models come from the connected account. The selected model is stored in the SwiftData profile and participates in existing iCloud sync; account credentials remain device-local.

Tap GPT beside Edit in the task header. Tasks without subtasks send their description, falling back to title and status if the description is blank. Tasks with subtasks run one request per subtask, sequentially in depth-first display order. Each request includes the parent title, description and ordered subtask hierarchy, with an instruction to address the selected subtask only. Completed subtasks remain included and labeled. The payload is captured when GPT is clicked. Project names, tags and unrelated workspace data are excluded.

An observable run tracker keeps requests alive when the response view closes, while the app is running. Task cards keep the compact completed-subtask count. When a run exists, a View GPT response link opens its review directly; no GPT or completed-subtask progress bar appears on board cards. Subtask rows include the same response link beside their status tag and jump to the selected subtask in review. Subtask badges reuse the tag style: Queued, Running, Success · Ready for review, Failed and Stopped. GPT responses never automatically mark SwiftData tasks complete. In View responses, each finished response offers Accept & Complete. Acceptance saves the matching task as Done, then changes its run badge to Accepted; failed saves leave the response unaccepted and restore the prior task status. Partial or failed responses cannot be accepted. This accepts written output, not repository file changes. Task completion persists through SwiftData; the response and acceptance badge persist in device-local history. Retry unfinished keeps successful responses and resumes at the failed item before processing remaining queued items. Repeated clicks open the existing run rather than sending duplicate requests. Stop explicitly cancels; Clear run removes the saved result so the next GPT click can capture updated task content and model settings.

Runs, ordered prompt snapshots, response text and acceptance state are saved atomically under Application Support/Tierin/ChatGPT/history.json and restored after restarting. Streaming output is checkpointed, with immediate saves on completion, acceptance and clearing, plus a flush when the app becomes inactive. History is local to each device and is not synced through iCloud. Credentials remain in Keychain. Interrupted runs reopen as stopped with partial output preserved; requests are never resent automatically. An unreadable archive is preserved and a visible error reports storage failures. iOS background suspension can interrupt requests. Clicking GPT closes the task detail stack on Mac and iPhone and shows the same workspace-top Connecting… banner. Actual response text changes it to Sent to ChatGPT, which dismisses after two seconds. Failures display a five-second error banner. Reopen the task and choose View responses to review output, stop, or retry. Missing models, disconnected accounts and network failures appear in the response view and run state.

Requests use the documented public Responses endpoint with `store: false` and `stream: true`. Partial output is not treated as complete until `response.completed`; usage failures, interruptions, and incomplete responses remain errors. No inference request is automatically retried.

Local request/stream tests (no account or network needed):

```sh
swiftc -parse-as-library Sources/ProjectBoard/ChatGPTOAuth.swift Sources/ProjectBoard/TaskGPTClient.swift Tests/ChatGPTConnectionTests/TaskGPTTests.swift -o /tmp/TierinTaskGPTTests
/tmp/TierinTaskGPTTests
```

Reference: https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference

The ChatGPT profile page shows the saved history file size on this device and a confirmed Clear GPT history action. Clearing deletes prompts, responses and review state without changing tasks or the account connection. Clearing is disabled while requests are running.
