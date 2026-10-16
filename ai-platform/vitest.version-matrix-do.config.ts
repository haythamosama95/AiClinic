import path from "node:path";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { kCurrentWorker } from "miniflare";
import { unstable_getMiniflareWorkerOptions } from "wrangler";
import { pinWorkerdCompatibilityDate } from "./test/pin-workerd-compatibility-date";
import { defineConfig } from "vitest/config";

const rootDir = path.dirname(fileURLToPath(import.meta.url));
// Keep in sync with workerd 1.20261012.1 in package-lock.json.
const compatibilityDate = pinWorkerdCompatibilityDate("2026-10-12");
const variantDir = path.resolve(rootDir, "../e2e/fullstack/test/variant");
const platformWorkerNConfig = path.join(variantDir, "platform-worker-n.toml");
const platformDoReceiverConfig = path.join(variantDir, "platform-do-receiver.toml");

const doReceiverConfig = unstable_getMiniflareWorkerOptions(
  platformDoReceiverConfig,
  "development",
);

// Miniflare's secondary workers consume JavaScript modules directly; unlike
// the primary worker configured through `wrangler.configPath`, they do not go
// through Wrangler's TypeScript bundling or TOML alias resolution. Build the
// receiver with Wrangler so its vendor-contracts alias stays at platform DO
// version 2, then remove the temporary bundle when the Vitest process exits.
const doReceiverBundleDir = mkdtempSync(
  path.join(os.tmpdir(), "ai-platform-version-matrix-do-"),
);
const wranglerCli = path.join(rootDir, "node_modules/wrangler/bin/wrangler.js");
try {
  execFileSync(
    process.execPath,
    [
      wranglerCli,
      "deploy",
      "--dry-run",
      "--outdir",
      doReceiverBundleDir,
      "--config",
      platformDoReceiverConfig,
      "--env",
      "development",
    ],
    {
      cwd: rootDir,
      env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
      stdio: "ignore",
    },
  );
} catch (error) {
  rmSync(doReceiverBundleDir, { recursive: true, force: true });
  throw error;
}
process.on("exit", () => {
  rmSync(doReceiverBundleDir, { recursive: true, force: true });
});

export default defineConfig({
  plugins: [
    cloudflareTest({
      main: "./src/worker.ts",
      wrangler: {
        configPath: platformWorkerNConfig,
        environment: "development",
      },
      miniflare: {
        compatibilityDate,
        // Share the migration-applied test database with the DO receiver
        // worker, whose Wrangler config uses this same stable ID.
        d1Databases: {
          DB: "11111111-1111-1111-1111-111111111111",
        },
        r2Buckets: ["R2"],
        ratelimits: {
          RATE_LIMITER_INSTALLATION: {
            simple: { limit: 600, period: 60 },
          },
          RATE_LIMITER_INSTALLATION_ACTOR: {
            simple: { limit: 120, period: 60 },
          },
          RATE_LIMITER_INSTALLATION_CAPABILITY: {
            simple: { limit: 300, period: 60 },
          },
        },
        bindings: {
          TEST_CLOCK: "1",
          DURATION_SCALE: "staging",
          ACCESS_TEAM_DOMAIN: "access.test",
          ACCESS_AUD: "vendor-access-aud",
          WEBAUTHN_RP_ID: "ops.vendor.test",
          WEBAUTHN_ORIGIN: "https://ops.vendor.test",
          HEARTBEAT_URL: "https://heartbeat.test/ping",
          ALERT_EMAIL_TO: "alerts@clinic.invalid",
          ISSUER_ID: "issuer-test",
          PLATFORM_SIGNING_KEY:
            '{"kid":"platform-test","pkcs8":"MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk","public_key":"GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0"}',
        },
        serviceBindings: {
          VENDOR: { name: kCurrentWorker, entrypoint: "VendorEntrypoint" },
        },
        workers: [
          {
            ...doReceiverConfig.workerOptions,
            // Match Wrangler's env-specific script_name used by the DO
            // binding in platform-do-receiver.toml.
            name: "ai-platform-do-receiver-development",
            compatibilityDate,
            modules: true,
            scriptPath: path.join(doReceiverBundleDir, "worker.js"),
            modulesRoot: doReceiverBundleDir,
            modulesRules: doReceiverConfig.workerOptions.modulesRules.map(
              (rule) =>
                // Wrangler emits imported prompt markdown beside worker.js
                // using hashed root-level filenames. Extend its terminal
                // Text rule because Miniflare ignores later rules of a type
                // after a non-fallthrough rule.
                rule.type === "Text" && !rule.fallthrough
                  ? { ...rule, include: [...rule.include, "**/*.md"] }
                  : rule,
            ),
          },
        ],
      },
    }),
  ],
  test: {
    include: ["test/version-matrix/worker-do.system.test.ts"],
    fileParallelism: false,
    testTimeout: 120_000,
    setupFiles: ["./test/setup-isolate-config-cache.ts", "./test/setup-network.ts"],
    // Retry once for transient Workers runtime/storage cleanup failures. See
    // the longer comment in vitest.workers.config.ts for why retries are safe
    // with the campaign governor's stats.
    retry: 1,
  },
});
