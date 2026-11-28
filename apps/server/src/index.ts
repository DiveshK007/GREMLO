// The Gremlo API: a plain Node HTTP server. Each route group lives in its own module under routes/ and answers its own
// paths or returns NOT_HANDLED; shared state, the store and the request helpers are in state.ts.
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { network, vault } from "./chain.ts";
import type { Loose } from "./json.ts";
import { HttpError, toHttp } from "./register.ts";
import { errMsg, housekeeping as stateHousekeeping, NOT_HANDLED, REQUIRE_SIGNED } from "./state.ts";
import { cors } from "./web.ts";
import * as campaigns from "./routes/campaigns.ts";
import * as diagnostics from "./routes/diagnostics.ts";
import * as gallery from "./routes/gallery.ts";
import * as health from "./routes/health.ts";
import * as park from "./routes/park.ts";
import * as pets from "./routes/pets.ts";
import * as relay from "./routes/relay.ts";
import * as settle from "./routes/settle.ts";

const routes = [health, pets, campaigns, settle, park, relay, gallery, diagnostics];

async function route(req: IncomingMessage) {
  const url = new URL(req.url ?? "/", "http://x");
  for (const r of routes) {
    const result = await r.handle(req, { pathname: url.pathname, searchParams: url.searchParams });
    if (result !== NOT_HANDLED) return result;
  }
  throw new HttpError(404, "not found");
}

// The in-memory limit maps and replay sets only ever grew; every module trims its own every 10 minutes.
setInterval(() => {
  const now = Date.now();
  stateHousekeeping(now);
  pets.housekeeping();
  for (const r of [campaigns, settle, park, relay, gallery, diagnostics]) r.housekeeping(now);
}, 10 * 60_000).unref();

const reply = (res: ServerResponse, status: number, body: unknown) => {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};

const port = Number(process.env.PORT ?? 8787);
// Loopback by default. Expose it (HOST=0.0.0.0) only with REQUIRE_SIGNED=1 and TRUST_PROXY=1 set, as in fly.toml.
const host = process.env.HOST ?? "127.0.0.1";
if (host !== "127.0.0.1" && !REQUIRE_SIGNED) throw new Error("refusing to listen publicly without REQUIRE_SIGNED=1: unpaired pets could spend AI credits");
createServer((req, res) => {
  if (cors(req, res)) return;
  const where = `${req.method} ${new URL(req.url ?? "/", "http://x").pathname}`;
  route(req).then(
    (body: Loose) => {
      // a route result: JSON to send, or { redirect | httpStatus | file | pipe }
      if (body?.redirect) {
        res.writeHead(302, { Location: body.redirect });
        res.end();
        return;
      }
      if (body?.httpStatus) {
        reply(res, body.httpStatus, body.body);
        return;
      }
      if (body?.pipe) {
        res.writeHead(200, { "content-type": "application/json" });
        body.pipe(res).catch((e: unknown) => {
          console.error(`${where}: ${errMsg(e)}`);
          res.destroy();
        });
        return;
      }
      if (body?.file) {
        res.writeHead(200, { "content-type": body.type, "cache-control": "public, max-age=3600" });
        res.end(body.file);
        return;
      }
      reply(res, 200, body);
    },
    (e) => {
      const { status, message } = toHttp(e);
      if (!(e instanceof HttpError)) console.error(`${where}: ${errMsg(e)}`); // the real reason stays in the log
      reply(res, status, { error: message });
    },
  );
}).listen(port, host, () => console.log(`server on ${host}:${port}, vault ${vault} on NEAR ${network}`));
