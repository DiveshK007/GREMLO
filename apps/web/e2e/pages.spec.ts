import { mkdirSync } from "node:fs";
import { expect, test } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

// Every page loads in light and dark at 1440 and 390 with no console errors and no serious axe findings.
// Full-page screenshots go to E2E_SHOTS (default /tmp/gremlo-e2e) for a person to look over.
const SHOTS = process.env.E2E_SHOTS ?? "/tmp/gremlo-e2e";
mkdirSync(SHOTS, { recursive: true });

const pet = process.env.E2E_PET; // a registered pet name, to also check /me with a real pet
const pages = ["/", "/pet", "/me", "/pair", "/park", "/gallery", "/brand", "/money", "/live", ...(pet ? [`/me?pet=${pet}`] : [])];

for (const path of pages) {
  test(path, async ({ page }, info) => {
    const theme = info.project.use.colorScheme === "dark" ? "dark" : "light";
    await page.addInitScript((t) => { try { localStorage.setItem("gremlo.theme", t); } catch {} }, theme);
    const errors: string[] = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    page.on("pageerror", (e) => errors.push(e.message));

    const res = await page.goto(path, { waitUntil: "networkidle" });
    expect(res?.status(), "HTTP status").toBeLessThan(400);
    expect(await page.evaluate(() => document.documentElement.dataset.theme ?? "")).toBe(theme);
    await page.screenshot({ path: `${SHOTS}/${path.replace(/[/?=]+/g, "_") || "_"}-${info.project.name}.png`, fullPage: true });

    const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]).analyze();
    const bad = axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
    const report = bad.map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(" ")).slice(0, 4).join(", ")}`);
    expect.soft(errors, "console errors").toEqual([]);
    expect.soft(report, "axe serious/critical").toEqual([]);
    // the page must fit the viewport: no sideways scroll at 390
    expect.soft(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "no horizontal scroll").toBe(true);
  });
}
