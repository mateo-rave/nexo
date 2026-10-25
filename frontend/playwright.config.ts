import { defineConfig, devices } from "@playwright/test";

// Pruebas de extremo a extremo del frontend (docs/qa/test-strategy.md). Se
// ejecutan en CI contra el build de producción (vite preview) conectado al
// Supabase local y desechable del workflow, nunca contra nexo-dev. El build
// debe hacerse antes con VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY.
export default defineConfig({
    testDir: "./e2e",
    timeout: 60_000,
    expect: { timeout: 15_000 },
    fullyParallel: false,
    workers: 1,
    retries: 0,
    reporter: [["list"]],
    use: {
        baseURL: "http://127.0.0.1:4173",
        trace: "off",
        screenshot: "off",
    },
    projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
    webServer: {
        command: "npm run preview -- --host 127.0.0.1 --port 4173 --strictPort",
        url: "http://127.0.0.1:4173",
        reuseExistingServer: false,
        timeout: 60_000,
    },
});
