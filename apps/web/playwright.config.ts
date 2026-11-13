import { defineConfig, devices } from "@playwright/test";

// Page checks against the app the owner already runs (`npm run dev` here, `npm start` in apps/server).
// No webServer on purpose: these never start the app.
export default defineConfig({
  testDir: "e2e",
  timeout: 60_000,
  workers: 2,
  reporter: "list",
  use: { baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3000", ...devices["Desktop Chrome"] },
  projects: [
    { name: "light-1440", use: { colorScheme: "light", viewport: { width: 1440, height: 900 } } },
    { name: "dark-1440", use: { colorScheme: "dark", viewport: { width: 1440, height: 900 } } },
    { name: "light-390", use: { colorScheme: "light", viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true } },
    { name: "dark-390", use: { colorScheme: "dark", viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true } },
  ],
});
