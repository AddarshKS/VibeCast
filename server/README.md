# VibeCast Service

A small Node service for the hosted Cast Magic experience. Uses built-in HTTP, cryptography, and SQLite; no package dependencies or client-embedded OpenAI key.

This server is optional. The [ChatGPT subscription beta](../docs/SUBSCRIPTION_BETA.md) runs through each tester's local Codex installation and needs neither this service nor an API key. The server never consumes a publisher's ChatGPT subscription.

## Configure

Create a private `.env` based on `.env.example`. It is ignored by Git. Register `http://127.0.0.1:43821/callback` in your Spotify app.

Required operator settings:

- `SPOTIFY_CLIENT_ID`: the same public app ID packaged in the Mac app.
- `OPENAI_API_KEY`: a dedicated OpenAI project key, stored only on the server.
- `IDENTITY_SALT`: at least 32 random characters. Keep it stable and secret across restarts; changing it resets pseudonymous usage identities.
- `ALLOWED_SPOTIFY_USERS`: comma-separated Spotify user IDs for your beta, also allowlisted in Spotify's dashboard.
- `DATABASE_PATH`: a writable persistent SQLite file.

Optional `OPENAI_MODEL` defaults to `gpt-4.1-mini`. Evaluate music quality before launch and change the model server-side as needed. Requests are capped at 600 characters, 20 song intents, and 4,000 output tokens. The service allows five attempts per user per hour, ten per day, 100 globally per day, and four concurrent AI calls by default. Set your OpenAI project budget as an independent control. Failed upstream requests count toward limits, bounding retry costs.

```sh
# From server/
node --env-file=.env src/server.mjs
npm test
```

The development app can use `http://127.0.0.1:8787` in Advanced settings. Release builds accept only HTTPS.

## Deploy

Build from the repository root:

```sh
docker build -f server/Dockerfile -t vibecast-service .
docker run --env-file server/.env -e HOST=0.0.0.0 -e DATABASE_PATH=/app/data/vibecast.sqlite \
  -p 127.0.0.1:8787:8787 -v vibecast-data:/app/data vibecast-service
```

Run one replica behind an HTTPS reverse proxy. Keep the volume persistent; ephemeral storage would reset sessions and quotas. The SQLite directory must be writable by the non-root container user. Back up the database privately. Do not expose the HTTP port directly to the Internet.

The server ignores forwarded client-IP headers. Authentication abuse limits therefore group users by the actual proxy address when deployed behind a proxy. Apply additional IP limits at the trusted reverse proxy. Do not change this to blindly trust client-supplied forwarded headers.

Endpoints:

| Route | Purpose |
| --- | --- |
| GET /health | Health probe; no credentials or configuration returned |
| POST /v1/token | Exchange PKCE authorization code or refresh token, bound to configured Spotify app |
| POST /v1/plan | Authenticated structured playlist plan; body contains only `prompt` |
| POST /v1/logout | Revoke this VibeCast session |

The gateway never accepts an arbitrary Spotify bearer token as proof of app membership. It performs the OAuth exchange itself, checks the user against the operator allowlist, and issues random, short-lived opaque sessions. Only session hashes, pseudonymous user IDs, expirations, and usage counters are stored. Spotify tokens are returned to the Mac, not stored on the server.

Do not log request bodies, Authorization headers, token responses, or raw upstream failures. Configure the reverse proxy to keep credentials out of logs too.

## Public access

`ALLOWED_SPOTIFY_USERS=*` is intentionally rejected unless `PUBLIC_ACCESS_APPROVED=true` is also explicitly set. This is an operator acknowledgement, **not Spotify approval**. Only use it after actual Spotify approval. No configuration flag can bypass Spotify's own restrictions.

No server is deployed by this repository. Supply a hosting account and production HTTPS origin, then package that origin into the Mac release.
