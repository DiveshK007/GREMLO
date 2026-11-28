import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanDiagnostics } from "./diagnostics.ts";

const good = {
  version: "1.1.0",
  os: "15.2",
  arch: "arm64",
  counts: { viewRefused: 3, thinkFailed: 0 },
  crashes: [{ type: "EXC_BREAKPOINT", signal: "SIGTRAP", frames: ["Gremlo: Backend.render()", "AppKit: -[NSApplication run]"] }],
};

test("diagnostics: a report keeps exactly the allowed fields and drops zero counts", () => {
  const r = cleanDiagnostics({ ...good, pet: "mochi", path: "/Users/someone", counts: { ...good.counts, promptText: 9 } });
  assert.deepEqual(r, {
    version: "1.1.0",
    os: "15.2",
    arch: "arm64",
    counts: { viewRefused: 3 },
    crashes: [{ type: "EXC_BREAKPOINT", signal: "SIGTRAP", frames: ["Gremlo: Backend.render()", "AppKit: -[NSApplication run]"] }],
  });
});

test("diagnostics: anything that could carry personal data is refused, not trimmed", () => {
  assert.throws(() => cleanDiagnostics({ ...good, crashes: [{ type: "EXC_BAD_ACCESS", frames: ["/Users/someone/secret.swift:12"] }] }), /frame/);
  assert.throws(() => cleanDiagnostics({ ...good, version: "1.1.0 (mochi's Mac)" }), /version/);
  assert.throws(() => cleanDiagnostics({ ...good, arch: "ppc" }), /arch/);
  assert.throws(() => cleanDiagnostics({ ...good, counts: { viewRefused: -1 } }), /viewRefused/);
  assert.throws(() => cleanDiagnostics({ ...good, crashes: Array(6).fill(good.crashes[0]) }), /at most 5/);
});
