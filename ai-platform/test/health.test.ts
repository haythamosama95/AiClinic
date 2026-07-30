import path from "node:path";
import { fileURLToPath } from "node:url";
import { unstable_dev, type Unstable_DevWorker } from "wrangler";
import { afterEach, describe, expect, it } from "vitest";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG_PATH = path.join(ROOT, "wrangler.toml");
const SCRIPT_PATH = path.join(ROOT, "src", "worker.ts");
const ENVIRONMENTS = ["development", "staging", "production"] as const;

const DEV_OPTIONS = {
  compatibilityDate: "2026-05-03",
  local: true,
  inspect: false,
  logLevel: "error" as const,
  experimental: { disableExperimentalWarning: true, disableDevRegistry: true },
};

describe("health_returns_build_and_environment_identity", () => {
  const workers: Unstable_DevWorker[] = [];

  afterEach(async () => {
    await Promise.all(workers.splice(0).map((worker) => worker.stop()));
  });

  for (const environment of ENVIRONMENTS) {
    it(`reports build and environment identity for ${environment}`, async () => {
      const worker = await unstable_dev(SCRIPT_PATH, {
        ...DEV_OPTIONS,
        config: CONFIG_PATH,
        env: environment,
      });
      workers.push(worker);

      const response = await worker.fetch("http://127.0.0.1/health");
      expect(response.status).toBe(200);

      const body = (await response.json()) as {
        build?: string;
        environment?: string;
      };

      expect(body.build).toBe("local");
      expect(body.environment).toBe(environment);
      expect(body.build).not.toBe(body.environment);
    }, 30_000);
  }
});
