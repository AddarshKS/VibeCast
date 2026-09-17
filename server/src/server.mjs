import { createServer } from "node:http";
import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { configuration, createService, ServiceError, Store } from "./service.mjs";

async function readJSON(request) {
  if (request.headers["content-type"]?.split(";")[0] !== "application/json") {
    throw new ServiceError(415, "Expected application/json.");
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 8192) throw new ServiceError(413, "Request too large.");
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new ServiceError(400, "Invalid JSON."); }
}

export function httpServer(service) {
  const server = createServer(async (request, response) => {
    response.setHeader("Content-Type", "application/json");
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("X-Content-Type-Options", "nosniff");
    const reply = (status, value) => {
      response.statusCode = status;
      response.end(JSON.stringify(value));
    };
    try {
      if (request.method === "GET" && request.url === "/health") return reply(200, { status: "ok" });
      if (request.method !== "POST") throw new ServiceError(405, "Method not allowed.");
      // The native client never sends Origin; prevent browser-based use of these credential endpoints.
      if (request.headers.origin) throw new ServiceError(403, "Use the VibeCast app.");
      const bearer = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(request.headers.authorization ?? "")?.[1] ?? "";
      if (request.url === "/v1/token") {
        service.anonymousLimit(request.socket.remoteAddress ?? "unknown");
        return reply(200, await service.token(await readJSON(request)));
      }
      if (request.url === "/v1/plan") return reply(200, await service.plan(bearer, await readJSON(request)));
      if (request.url === "/v1/logout") { service.logout(bearer); return reply(200, { ok: true }); }
      throw new ServiceError(404, "Not found.");
    } catch (error) {
      const status = error instanceof ServiceError ? error.status : 500;
      reply(status, { error: status === 500 ? "The service couldn't complete that request." : error.message });
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.maxHeadersCount = 30;
  server.keepAliveTimeout = 5000;
  return server;
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? "")).href) {
  const config = configuration();
  mkdirSync(dirname(config.dbPath), { recursive: true, mode: 0o700 });
  const store = new Store(config.dbPath);
  const server = httpServer(createService(config, store));
  server.listen(Number(process.env.PORT || 8787), process.env.HOST || "127.0.0.1", () => {
    console.log("VibeCast service listening.");
  });
  const stop = () => { server.close(() => { store.close(); process.exit(0); }); };
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
}
