import fs from "node:fs";
import os from "node:os";
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

interface EnvironmentBindings {
  workerName: string;
  d1DatabaseId: string;
  r2BucketName: string;
  durableObjectNamespaceId: string;
}

function readEnvironmentBindings(environment: string): EnvironmentBindings {
  const toml = fs.readFileSync(CONFIG_PATH, "utf8");
  const envPrefix = `env\\.${environment}`;

  const workerName = toml.match(
    new RegExp(`\\[${envPrefix}\\]\\s*\\nname = "([^"]+)"`),
  )?.[1];
  const d1DatabaseId = toml.match(
    new RegExp(
      `\\[\\[${envPrefix}\\.d1_databases\\]\\][\\s\\S]*?database_id = "([^"]+)"`,
    ),
  )?.[1];
  const r2BucketName = toml.match(
    new RegExp(
      `\\[\\[${envPrefix}\\.r2_buckets\\]\\][\\s\\S]*?bucket_name = "([^"]+)"`,
    ),
  )?.[1];
  const durableObjectBinding = toml.match(
    new RegExp(
      `\\[\\[${envPrefix}\\.durable_objects\\.bindings\\]\\][\\s\\S]*?name = "([^"]+)"`,
    ),
  )?.[1];
  const durableObjectClass = toml.match(
    new RegExp(
      `\\[\\[${envPrefix}\\.durable_objects\\.bindings\\]\\][\\s\\S]*?class_name = "([^"]+)"`,
    ),
  )?.[1];

  if (
    !workerName ||
    !d1DatabaseId ||
    !r2BucketName ||
    !durableObjectBinding ||
    !durableObjectClass
  ) {
    throw new Error(`Incomplete bindings for ${environment} in wrangler.toml`);
  }

  return {
    workerName,
    d1DatabaseId,
    r2BucketName,
    durableObjectNamespaceId: `${workerName}:${durableObjectBinding}:${durableObjectClass}`,
  };
}

function removeEnvironmentBinding(
  toml: string,
  environment: string,
  binding: "d1" | "r2" | "do",
): string {
  const patterns: Record<typeof binding, RegExp> = {
    d1: new RegExp(
      `\\n\\[\\[env\\.${environment}\\.d1_databases\\]\\][\\s\\S]*?(?=\\n\\[|\\n\\[\\[|$)`,
    ),
    r2: new RegExp(
      `\\n\\[\\[env\\.${environment}\\.r2_buckets\\]\\][\\s\\S]*?(?=\\n\\[|\\n\\[\\[|$)`,
    ),
    do: new RegExp(
      `\\n\\[\\[env\\.${environment}\\.durable_objects\\.bindings\\]\\][\\s\\S]*?(?=\\n\\[|\\n\\[\\[|$)`,
    ),
  };

  return toml.replace(patterns[binding], "\n");
}

function writeTemporaryConfig(
  environment: string,
  omit?: "d1" | "r2" | "do",
): { configPath: string; cleanup: () => void } {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ai-platform-a1-"));
  let toml = fs.readFileSync(CONFIG_PATH, "utf8");
  if (omit) {
    toml = removeEnvironmentBinding(toml, environment, omit);
  }
  const configPath = path.join(directory, "wrangler.toml");
  fs.writeFileSync(configPath, toml);
  return {
    configPath,
    cleanup: () => fs.rmSync(directory, { recursive: true, force: true }),
  };
}

async function expectStartupFailure(
  configPath: string,
  environment: string,
): Promise<void> {
  const worker = await unstable_dev(SCRIPT_PATH, {
    ...DEV_OPTIONS,
    config: configPath,
    env: environment,
  });

  try {
    const outcome = await Promise.race([
      worker.fetch("http://127.0.0.1/health").then((response) => ({
        kind: "response" as const,
        status: response.status,
      })),
      new Promise<{ kind: "timeout" }>((resolve) =>
        setTimeout(() => resolve({ kind: "timeout" }), 3_000),
      ),
    ]);

    expect(outcome.kind).toBe("timeout");
  } finally {
    await worker.stop().catch(() => undefined);
  }
}

describe("env_each_environment_deploys", () => {
  const workers: Unstable_DevWorker[] = [];

  afterEach(async () => {
    await Promise.all(workers.splice(0).map((worker) => worker.stop()));
  });

  for (const environment of ENVIRONMENTS) {
    it(`deploys ${environment} with its own D1, R2, and Durable Object bindings`, async () => {
      const bindings = readEnvironmentBindings(environment);

      const worker = await unstable_dev(SCRIPT_PATH, {
        ...DEV_OPTIONS,
        config: CONFIG_PATH,
        env: environment,
      });
      workers.push(worker);

      expect(bindings.d1DatabaseId).toBeTruthy();
      expect(bindings.r2BucketName).toBeTruthy();
      expect(bindings.durableObjectNamespaceId).toBeTruthy();
    }, 30_000);
  }
});

describe("env_no_binding_shared_between_environments", () => {
  it("does not share any D1 database id, R2 bucket name, or Durable Object namespace id", () => {
    const bindings = ENVIRONMENTS.map((environment) =>
      readEnvironmentBindings(environment),
    );

    const d1Ids = bindings.map((binding) => binding.d1DatabaseId);
    const r2Buckets = bindings.map((binding) => binding.r2BucketName);
    const durableObjectNamespaces = bindings.map(
      (binding) => binding.durableObjectNamespaceId,
    );

    expect(new Set(d1Ids).size).toBe(ENVIRONMENTS.length);
    expect(new Set(r2Buckets).size).toBe(ENVIRONMENTS.length);
    expect(new Set(durableObjectNamespaces).size).toBe(ENVIRONMENTS.length);
  });
});

describe("env_missing_required_binding_fails_at_startup", () => {
  for (const binding of ["d1", "r2", "do"] as const) {
    it(`fails at startup when the ${binding.toUpperCase()} binding is missing`, async () => {
      const { configPath, cleanup } = writeTemporaryConfig(
        "development",
        binding,
      );

      try {
        await expectStartupFailure(configPath, "development");
      } finally {
        cleanup();
      }
    }, 30_000);
  }
});
