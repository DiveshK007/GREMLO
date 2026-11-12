import { createConnection } from "node:net";
import { homedir } from "node:os";
import { join } from "node:path";
import { showHUD } from "@raycast/api";

// The same local socket the notchi CLI uses: one JSON request line in, one JSON reply line out.
const SOCKET = join(homedir(), "Library/Application Support/Notchi/notchi.sock");

type Reply = { ok: boolean; text: string; data?: Record<string, string> };

export function send(cmd: string, args: Record<string, string> = {}): Promise<Reply> {
  return new Promise((resolve) => {
    let buf = "";
    const c = createConnection(SOCKET, () => c.write(JSON.stringify({ cmd, args }) + "\n"));
    c.setTimeout(3000, () => { c.destroy(); resolve({ ok: false, text: "Notchi didn't answer" }); });
    c.on("data", (d) => (buf += d.toString()));
    c.on("end", () => {
      try { resolve(JSON.parse(buf)); } catch { resolve({ ok: false, text: "no answer from the app" }); }
    });
    c.on("error", () => resolve({ ok: false, text: "Notchi isn't running" }));
  });
}

export async function run(cmd: string, args: Record<string, string> = {}) {
  const r = await send(cmd, args);
  await showHUD(r.text);
}
