import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { configuration, createService, redirectURI, ServiceError, Store, validatePlan } from "../src/service.mjs";
import { httpServer } from "../src/server.mjs";

const config = {
  clientID: "a".repeat(32), apiKey: "test-only-key", salt: "s".repeat(32),
  allowed: new Set(["alice"]), model: "test-model", userDaily: 10, globalDaily: 100
};
const plan = { name: "Evening", description: "For the road", tracks: Array.from({ length: 12 }, (_, i) => ({
  title: `Song ${i}`, artist: "Artist"
})) };
const authBody = { client_id: config.clientID, grant_type: "authorization_code", code: "code",
  code_verifier: "v".repeat(64), redirect_uri: redirectURI };
const json = value => new Response(JSON.stringify(value), { headers: { "content-type": "application/json" } });
const errorStatus = status => error => error instanceof ServiceError && error.status === status;

test("deployment configuration fails closed", () => {
  assert.throws(() => configuration({}), /Missing/);
  for (const users of ["*", " * ", "alice, *"]) {
    assert.throws(() => configuration({ SPOTIFY_CLIENT_ID: config.clientID, OPENAI_API_KEY: "key",
      IDENTITY_SALT: config.salt, ALLOWED_SPOTIFY_USERS: users }), /approval/);
  }
  assert.throws(() => configuration({ SPOTIFY_CLIENT_ID: config.clientID, OPENAI_API_KEY: "key",
    IDENTITY_SALT: config.salt, ALLOWED_SPOTIFY_USERS: " , " }), /At least one/);
});

test("sessions expire, are opaque, and logout revokes access", () => {
  let now = 1000;
  const store = new Store(":memory:", () => now);
  const token = store.createSession("alice", 60);
  assert.equal(token.length, 43);
  assert.equal(store.subject(token), "alice");
  assert.equal(store.db.prepare("SELECT digest FROM sessions").get().digest.includes(token), false);
  now += 60001;
  assert.throws(() => store.subject(token), errorStatus(401));
  const other = store.createSession("alice", 60);
  store.revoke(other);
  assert.throws(() => store.subject(other), errorStatus(401));
  store.close();
});

test("daily quotas persist across restart and charge atomically", () => {
  const dir = mkdtempSync(join(tmpdir(), "vibecast-"));
  const path = join(dir, "test.sqlite");
  try {
    let store = new Store(path, () => 1000);
    store.charge([{ key: "user:a", limit: 1, period: 86400000 }]);
    store.close();
    store = new Store(path, () => 1000);
    assert.throws(() => store.charge([{ key: "global", limit: 10, period: 86400000 },
      { key: "user:a", limit: 1, period: 86400000 }]), errorStatus(429));
    assert.equal(store.db.prepare("SELECT count FROM counters WHERE bucket = 'global:0'").get(), undefined);
    store.close();
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("OAuth exchanges against only the configured Spotify app and issues service session", async () => {
  const store = new Store(":memory:");
  const calls = [];
  const service = createService(config, store, async (url, options) => {
    calls.push([url, options]);
    return url.includes("/api/token") ? json({ access_token: "spotify-token", expires_in: 3600, refresh_token: "refresh" })
      : json({ id: "alice", display_name: "Private Name" });
  });
  const result = await service.token(authBody);
  assert.equal(result.access_token, "spotify-token");
  assert.ok(result.vibecast_session);
  assert.notEqual(store.subject(result.vibecast_session), "alice");
  assert.equal(new URLSearchParams(calls[0][1].body).get("client_id"), config.clientID);
  await assert.rejects(service.token({ ...authBody, client_id: "other" }), errorStatus(400));
  await assert.rejects(service.token({ ...authBody, redirect_uri: "https://evil.example/callback" }), errorStatus(400));
  assert.equal(calls.length, 2);
  store.close();
});

test("unapproved Spotify users never receive a service session", async () => {
  const store = new Store(":memory:");
  const service = createService(config, store, async url => url.includes("/api/token")
    ? json({ access_token: "token", expires_in: 3600 }) : json({ id: "not-allowed" }));
  await assert.rejects(service.token(authBody), errorStatus(403));
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM sessions").get().n, 0);
  store.close();
});

test("planning sends only user text to AI, limits output, and rejects catalog injection", async () => {
  const store = new Store(":memory:");
  const token = store.createSession("user-hash", 3600);
  let calls = 0;
  const service = createService(config, store, async (url, options) => {
    calls++;
    assert.equal(url, "https://api.openai.com/v1/responses");
    const body = JSON.parse(options.body);
    assert.equal(body.input, "A long drive");
    assert.equal(body.store, false);
    assert.equal(body.max_output_tokens, 4000);
    assert.equal(body.text.format.strict, true);
    assert.equal(JSON.stringify(body).includes("spotify-token"), false);
    return json({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: JSON.stringify(plan) }] }] });
  });
  assert.deepEqual(await service.plan(token, { prompt: "A long drive" }), plan);
  await assert.rejects(service.plan(token, { prompt: "A long drive", candidates: [] }), errorStatus(400));
  await assert.rejects(service.plan("", { prompt: "A long drive" }), errorStatus(401));
  assert.equal(calls, 1);
  store.close();
});

test("quota blocks upstream calls, including repeated sessions for same user", async () => {
  const store = new Store(":memory:");
  const token = store.createSession("same-user", 3600);
  let calls = 0;
  const service = createService({ ...config, userDaily: 1 }, store, async () => {
    calls++;
    return json({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: JSON.stringify(plan) }] }] });
  });
  await service.plan(token, { prompt: "Drive" });
  const newSession = store.createSession("same-user", 3600);
  await assert.rejects(service.plan(newSession, { prompt: "Drive" }), errorStatus(429));
  assert.equal(calls, 1);
  store.close();
});

test("invalid and incomplete model outputs never become playlist plans", async () => {
  assert.throws(() => validatePlan({ ...plan, tracks: [{ title: "Fake", artist: "Nobody" }] }), errorStatus(502));
  assert.throws(() => validatePlan({ ...plan, secret: "extra" }), errorStatus(502));
  const store = new Store(":memory:");
  const token = store.createSession("alice", 3600);
  const service = createService(config, store, async () => json({ status: "incomplete", output: [] }));
  await assert.rejects(service.plan(token, { prompt: "Drive" }), errorStatus(502));
  store.close();
});

test("HTTP boundary rejects browser origins, invalid bodies, and unknown endpoints", async () => {
  const store = new Store(":memory:");
  const server = httpServer(createService(config, store, async () => { throw new Error("Should not call upstream"); }));
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(base + "/health")).status, 200);
    assert.equal((await fetch(base + "/v1/token", { method: "POST", headers: { origin: "https://evil.example" } })).status, 403);
    assert.equal((await fetch(base + "/v1/plan", { method: "POST", body: "{}" })).status, 415);
    assert.equal((await fetch(base + "/v1/plan", { method: "POST", headers: { "content-type": "application/json" }, body: "{" })).status, 400);
    assert.equal((await fetch(base + "/v1/plan", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ prompt: "A".repeat(9000) }) })).status, 413);
    assert.equal((await fetch(base + "/unknown", { method: "POST" })).status, 404);
  } finally {
    await new Promise(resolve => server.close(resolve));
    store.close();
  }
});
