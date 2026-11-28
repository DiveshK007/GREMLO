// Opt-in diagnostics from the Mac (Settings, Privacy, "Send diagnostics", off by default): the app and macOS
// versions, the chip, how often each known failure happened, and crash signatures. Anything else is dropped, so a
// report can't carry a pet name, a path, a prompt or anything the agent did. No IP is stored.
import { bad } from "./register.ts";
import type { Body } from "./json.ts";

// the same list as GremloCore Diagnostics.Count
export const COUNTS = ["viewRefused", "viewNotSent", "thinkFailed", "serverUnreachable", "settleStuck", "parkFailed"] as const;
const short = (v: unknown, re: RegExp, what: string) => {
  const s = String(v ?? "");
  if (!re.test(s)) throw bad(`${what} is not in the expected form`);
  return s;
};

/** The one shape a report may have, rebuilt field by field; throws 400 on anything malformed. */
export function cleanDiagnostics(b: Body) {
  const version = short(b?.version, /^[0-9]{1,3}(\.[0-9]{1,3}){0,2}$|^source build$/, "version");
  const os = short(b?.os, /^[0-9]{1,2}(\.[0-9]{1,2}){0,2}$/, "os");
  const arch = short(b?.arch, /^(arm64|x86_64)$/, "arch");
  const counts: Record<string, number> = {};
  for (const k of COUNTS) {
    const n = Number((b?.counts as Record<string, unknown> | undefined)?.[k] ?? 0);
    if (!Number.isInteger(n) || n < 0 || n > 100_000) throw bad(`counts.${k} must be a whole number`);
    if (n) counts[k] = n;
  }
  const list = Array.isArray(b?.crashes) ? b.crashes : [];
  if (list.length > 5) throw bad("at most 5 crashes per report");
  const crashes = list.map((c: Body) => ({
    type: short(c?.type, /^[A-Z0-9_]{1,40}$/, "crash type"),
    signal: c?.signal == null ? null : short(c.signal, /^SIG[A-Z0-9]{1,10}$/, "crash signal"),
    // function names from the app's own code and Apple's frameworks; never a path or an argument
    frames: (Array.isArray(c?.frames) ? c.frames : []).slice(0, 12).map((f: unknown) => short(f, /^[A-Za-z0-9_$.:<>()[\], &*-]{1,160}$/, "frame")),
  }));
  return { version, os, arch, counts, crashes };
}
