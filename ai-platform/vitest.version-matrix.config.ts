import path from "node:path";
import { fileURLToPath } from "node:url";
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { kCurrentWorker } from "miniflare";
import { pinWorkerdCompatibilityDate } from "./test/pin-workerd-compatibility-date";
import { defineConfig } from "vitest/config";

const rootDir = path.dirname(fileURLToPath(import.meta.url));
const platformNPlus1Config = path.resolve(
  rootDir,
  "../e2e/fullstack/test/variant/platform-n-plus-1.toml",
);

export default defineConfig({
  plugins: [
    cloudflareTest({
      main: "./src/worker.ts",
      wrangler: {
        configPath: platformNPlus1Config,
        environment: "development",
      },
      miniflare: {
        // Keep in sync with workerd 1.20261012.1 in package-lock.json.
        compatibilityDate: pinWorkerdCompatibilityDate("2026-10-12"),
        d1Databases: ["DB"],
        r2Buckets: ["R2"],
        ratelimits: {
          RATE_LIMITER_INSTALLATION: {
            namespace_id: "1001",
            simple: { limit: 600, period: 60 },
          },
          RATE_LIMITER_INSTALLATION_ACTOR: {
            namespace_id: "1002",
            simple: { limit: 120, period: 60 },
          },
          RATE_LIMITER_INSTALLATION_CAPABILITY: {
            namespace_id: "1003",
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
      },
    }),
  ],
  test: {
    include: ["test/version-matrix/channels.system.test.ts"],
    fileParallelism: false,
    testTimeout: 120_000,
    setupFiles: ["./test/setup-isolate-config-cache.ts", "./test/setup-network.ts"],
    // Retry once for transient Workers runtime/storage cleanup failures. See
    // the longer comment in vitest.workers.config.ts for why retries are safe
    // with the campaign governor's stats.
    retry: 1,
  },
});
