import { createHash, createHmac, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

export const redirectURI = "http://127.0.0.1:43821/callback";
const schema = JSON.parse(readFileSync(new URL("../../Sources/VibeCast/Resources/PlaylistPlan.schema.json", import.meta.url), "utf8"));
const instructions = readFileSync(new URL("../../Sources/VibeCast/Resources/PlaylistPlanner.txt", import.meta.url), "utf8");
const hash = value => createHash("sha256").update(value).digest("hex");

export class ServiceError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function configuration(env = process.env) {
  for (const name of ["SPOTIFY_CLIENT_ID", "OPENAI_API_KEY", "IDENTITY_SALT", "ALLOWED_SPOTIFY_USERS"]) {
    if (!env[name]?.trim()) throw new Error(`Missing ${name}`);
  }
  if (!/^[a-f0-9]{32}$/i.test(env.SPOTIFY_CLIENT_ID)) throw new Error("Invalid Spotify client ID");
  if (env.IDENTITY_SALT.length < 32) throw new Error("IDENTITY_SALT must contain at least 32 random characters");
  const allowed = new Set(env.ALLOWED_SPOTIFY_USERS.split(",").map(s => s.trim()).filter(Boolean));
  if (!allowed.size) throw new Error("At least one beta user must be configured");
  if (allowed.has("*") && env.PUBLIC_ACCESS_APPROVED !== "true") {
    throw new Error("Public access requires explicit PUBLIC_ACCESS_APPROVED=true after Spotify approval");
  }
  const positive = (name, fallback) => {
    const n = Number(env[name] ?? fallback);
    if (!Number.isSafeInteger(n) || n < 1 || n > 100000) throw new Error(`Invalid ${name}`);
    return n;
  };
  return {
    clientID: env.SPOTIFY_CLIENT_ID, apiKey: env.OPENAI_API_KEY, salt: env.IDENTITY_SALT,
    allowed,
    model: env.OPENAI_MODEL || "gpt-4.1-mini",
    userDaily: positive("USER_DAILY_LIMIT", 10), globalDaily: positive("GLOBAL_DAILY_LIMIT", 100),
    dbPath: env.DATABASE_PATH || "./data/vibecast.sqlite"
  };
}

export function validatePlan(value) {
  const plain = v => v !== null && typeof v === "object" && !Array.isArray(v);
  const exactKeys = (v, keys) => Object.keys(v).sort().join(",") === keys.sort().join(",");
  const text = (v, max, empty = false) => typeof v === "string" && v.length <= max && (empty || v.trim().length > 0);
  if (!plain(value) || !exactKeys(value, ["name", "description", "tracks"]) ||
      !text(value.name, 100) || !text(value.description, 280, true) ||
      !Array.isArray(value.tracks) || value.tracks.length < 12 || value.tracks.length > 20 ||
      !value.tracks.every(t => plain(t) && exactKeys(t, ["title", "artist"]) && text(t.title, 150) && text(t.artist, 150))) {
    throw new ServiceError(502, "The curator returned an incomplete playlist. Try again.");
  }
  return value;
}

export class Store {
  constructor(path, now = () => Date.now()) {
    this.now = now;
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode=WAL;
      PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS sessions (digest TEXT PRIMARY KEY, subject TEXT NOT NULL, expires INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS counters (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL);
    `);
  }
  createSession(subject, lifetimeSeconds) {
    this.cleanup();
    const token = randomBytes(32).toString("base64url");
    const lifetime = Math.max(60, Math.min(lifetimeSeconds, 3600));
    this.db.prepare("INSERT INTO sessions VALUES (?, ?, ?)").run(hash(token), subject, this.now() + lifetime * 1000);
    return token;
  }
  subject(token) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new ServiceError(401, "Reconnect Spotify to continue.");
    const session = this.db.prepare("SELECT subject FROM sessions WHERE digest = ? AND expires > ?").get(hash(token), this.now());
    if (!session) throw new ServiceError(401, "Reconnect Spotify to continue.");
    return session.subject;
  }
  revoke(token) { this.db.prepare("DELETE FROM sessions WHERE digest = ?").run(hash(token)); }
  charge(limits) {
    this.cleanup();
    this.db.exec("BEGIN IMMEDIATE");
    try {
      for (const { key, limit, period } of limits) {
        const epoch = Math.floor(this.now() / period);
        const bucket = `${key}:${epoch}`;
        const row = this.db.prepare("SELECT count FROM counters WHERE bucket = ?").get(bucket);
        if ((row?.count ?? 0) >= limit) throw new ServiceError(429, "Usage limit reached. Try again later.");
        this.db.prepare(`INSERT INTO counters VALUES (?, 1, ?)
          ON CONFLICT(bucket) DO UPDATE SET count = count + 1`).run(bucket, (epoch + 1) * period);
      }
      this.db.exec("COMMIT");
    } catch (error) { this.db.exec("ROLLBACK"); throw error; }
  }
  cleanup() {
    this.db.prepare("DELETE FROM sessions WHERE expires <= ?").run(this.now());
    this.db.prepare("DELETE FROM counters WHERE expires <= ?").run(this.now());
  }
  close() { this.db.close(); }
}

export function createService(config, store, fetcher = fetch) {
  let activePlans = 0;
  const subjectID = id => createHmac("sha256", config.salt).update(id).digest("hex");

  async function upstream(url, init, label) {
    let response;
    try {
      response = await fetcher(url, { ...init, redirect: "error", signal: AbortSignal.timeout(45000) });
    } catch { throw new ServiceError(502, `${label} couldn't be reached. Try again.`); }
    if (!response.ok) {
      if (response.status === 429) throw new ServiceError(429, `${label} is busy. Try again later.`);
      if (label === "Spotify" && [400, 401, 403].includes(response.status)) {
        throw new ServiceError(response.status === 403 ? 403 : 401, "Reconnect Spotify and check beta access.");
      }
      throw new ServiceError(502, `${label} couldn't complete this request.`);
    }
    try { return await response.json(); }
    catch { throw new ServiceError(502, `${label} returned an invalid response.`); }
  }

  async function token(fields) {
    if (!fields || typeof fields !== "object" || Array.isArray(fields) || fields.client_id !== config.clientID) {
      throw new ServiceError(400, "Invalid app configuration.");
    }
    const body = new URLSearchParams({ client_id: config.clientID });
    if (fields.grant_type === "authorization_code") {
      if (fields.redirect_uri !== redirectURI || !/^[A-Za-z0-9._~-]{43,128}$/.test(fields.code_verifier ?? "") ||
          typeof fields.code !== "string" || fields.code.length < 1 || fields.code.length > 4096) {
        throw new ServiceError(400, "Invalid sign-in request.");
      }
      body.set("grant_type", "authorization_code");
      body.set("redirect_uri", redirectURI);
      body.set("code", fields.code);
      body.set("code_verifier", fields.code_verifier);
    } else if (fields.grant_type === "refresh_token") {
      if (typeof fields.refresh_token !== "string" || fields.refresh_token.length < 1 || fields.refresh_token.length > 4096) {
        throw new ServiceError(400, "Invalid refresh request.");
      }
      body.set("grant_type", "refresh_token");
      body.set("refresh_token", fields.refresh_token);
    } else { throw new ServiceError(400, "Unsupported grant type."); }

    const result = await upstream("https://accounts.spotify.com/api/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: body.toString()
    }, "Spotify");
    if (typeof result.access_token !== "string" || !Number.isInteger(result.expires_in) || result.expires_in <= 0) {
      throw new ServiceError(502, "Spotify returned an invalid session.");
    }
    const profile = await upstream("https://api.spotify.com/v1/me", {
      headers: { Authorization: `Bearer ${result.access_token}` }
    }, "Spotify");
    if (typeof profile.id !== "string" || !profile.id) throw new ServiceError(502, "Spotify returned an invalid profile.");
    if (!config.allowed.has("*") && !config.allowed.has(profile.id)) throw new ServiceError(403, "This account isn't in the VibeCast beta.");
    // Only an opaque session and usage counters are persisted. Spotify credentials are returned to the Mac.
    const session = store.createSession(subjectID(profile.id), result.expires_in);
    return { access_token: result.access_token, refresh_token: result.refresh_token,
      scope: result.scope, expires_in: result.expires_in, vibecast_session: session };
  }

  async function plan(bearer, body) {
    const subject = store.subject(bearer);
    if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).join(",") !== "prompt" ||
        typeof body.prompt !== "string" || !body.prompt.trim() || body.prompt.length > 600) {
      throw new ServiceError(400, "Send a musical request of 1 to 600 characters.");
    }
    if (activePlans >= 4) throw new ServiceError(429, "The curator is busy. Try again shortly.");
    store.charge([
      { key: `user:${subject}:hour`, limit: 5, period: 3600000 },
      { key: `user:${subject}:day`, limit: config.userDaily, period: 86400000 },
      { key: "global:day", limit: config.globalDaily, period: 86400000 }
    ]);
    activePlans++;
    try {
      const result = await upstream("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: { Authorization: `Bearer ${config.apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model: config.model, store: false, max_output_tokens: 4000,
          instructions, input: body.prompt,
          text: { format: { type: "json_schema", name: "playlist_plan", strict: true, schema } }
        })
      }, "Cast Magic");
      const content = result.output?.filter(o => o.type === "message").flatMap(o => o.content ?? []);
      const text = content?.find(c => c.type === "output_text")?.text;
      if (result.status !== "completed" || typeof text !== "string") {
        throw new ServiceError(502, "The curator couldn't finish this playlist.");
      }
      let value;
      try { value = JSON.parse(text); } catch { throw new ServiceError(502, "The curator returned an invalid playlist."); }
      return validatePlan(value);
    } finally { activePlans--; }
  }

  return {
    token, plan,
    logout: bearer => { store.subject(bearer); store.revoke(bearer); },
    anonymousLimit: address => store.charge([
      { key: `ip:${subjectID(address)}`, limit: 30, period: 300000 },
      { key: "auth:global", limit: 300, period: 3600000 }
    ])
  };
}
