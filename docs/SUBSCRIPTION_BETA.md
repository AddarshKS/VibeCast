# ChatGPT Subscription Beta

Each tester connects their own ChatGPT account through the official local Codex app-server. This uses that account's Codex allowance, not the publisher's subscription and not an OpenAI API key. Account entitlement and limits still apply. ChatGPT subscriptions do not provide general-purpose API credits.

## Tester setup

1. Install the [Codex CLI](https://learn.chatgpt.com/docs/cli). This integration was tested against version 0.141.0. VibeCast does not download or install executables automatically.
2. The publisher adds the tester's Spotify account to the app's allowlist. Spotify Premium is required for playback control.
3. Open VibeCast Settings and connect Spotify.
4. Enable Cast Magic, leave AI connection on **ChatGPT subscription**, and press **Sign in with ChatGPT**. Complete the browser flow using that tester's account.
5. Confirm the connected account and allowance appear. Leave Model on **Account default**, or choose an available model.
6. Try `make me a soft rock playlist`. The result should be a private Spotify playlist containing matched, real tracks. It does not autoplay.

VibeCast finds Codex in `~/.local/bin`, `/opt/homebrew/bin`, or `/usr/local/bin`. Other installations can be selected under Settings > Advanced > Codex executable, then saved. Keep the VibeCast service address empty for the standalone subscription beta. A configured service URL also changes Spotify's token exchange path, independently of AI selection.

Disconnect ChatGPT affects only VibeCast's sign-in. It does not log the tester out of their normal Codex app or CLI. Spotify and ChatGPT have separate disconnect controls.

## Cost boundary

- No publisher API key is needed for this mode. Neither API endpoint is used as an automatic fallback.
- Subscription mode rejects API-key-authenticated Codex sessions.
- Included allowance must be available and non-exhausted before generation. Missing usage data or an exhausted window stops the request.
- Usage is shared with the tester's other Codex activity. The preflight is not a reservation of allowance; another concurrent Codex task can consume it. VibeCast does not buy credits, request a paid tier, or guarantee additional provider usage beyond the account's included limits.
- Switching manually to **OpenAI API key** or **VibeCast service** is a different, separately billed path. The UI labels these explicitly.

## Integration boundaries

VibeCast starts `codex app-server` on a private stdio pipe. Its isolated `CODEX_HOME`, read-only sandbox, disabled execution/integration features, and rejected approval requests are intended for playlist planning only. The real macOS `HOME` is preserved for login Keychain access. The model receives no Spotify results, tokens, or history. Responses must pass the shared playlist schema and local validation before Spotify matching begins.

CLI 0.141.0 does not support the newer documented `tools.view_image` setting or a restricted read-root policy. Read-only is not an OS-level guarantee against all filesystem reads. This beta accepts only the local user's own brief, with no external documents or connector inputs. Re-audit tool isolation before broad distribution or upgrading the runtime.

The app uses ephemeral threads and stops the child runtime after each operation, including errors or cancellation. Disconnect uses the app-server logout method. Do not reuse this bridge as an internet-facing AI service. Keep CLI compatibility and security checks in the beta release checklist.

## Validation

```sh
./script/swift.sh test
VIBECAST_TEST_CODEX=1 ./script/swift.sh test --filter SubscriptionTests
```

The optional smoke test uses a temporary unauthenticated home and never generates a model response. Automated tests cover login actions and structured output with a fake RPC transport. Browser sign-in, real allowance reporting, live generation, Spotify creation, and listening quality still require manual acceptance on each release candidate.

Official references: [app-server authentication and lifecycle](https://learn.chatgpt.com/docs/app-server), [Codex authentication](https://learn.chatgpt.com/docs/auth), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
