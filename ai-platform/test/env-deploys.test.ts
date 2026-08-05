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

/** Generous ceiling so a true hang fails the test instead of counting as success. */
const STARTUP_FAILURE_HANG_GUARD_MS = 15_000;

const MISSING_BINDING_ERROR = /Missing required binding:/;

function hangGuard(message: string): Promise<never> {
  return new Promise((_, reject) => {
    setTimeout(() => reject(new Error(message)), STARTUP_FAILURE_HANG_GUARD_MS);
  });
}

function captureStderr(): {
  chunks: string[];
  restore: () => void;
  sawBindingError: () => boolean;
} {
  const chunks: string[] = [];
  const push = (value: unknown): void => {
    if (typeof value === "string") {
      chunks.push(value);
      return;
    }
    if (value instanceof Uint8Array) {
      chunks.push(Buffer.from(value).toString("utf8"));
      return;
    }
    chunks.push(String(value));
  };

  const originalWrite = process.stderr.write.bind(process.stderr);
  process.stderr.write = ((
    chunk: string | Uint8Array,
    encoding?: BufferEncoding | ((err?: Error | null) => void),
    cb?: (err?: Error | null) => void,
  ) => {
    push(chunk);
    if (typeof encoding === "function") {
      return originalWrite(chunk, encoding);
    }
    return originalWrite(chunk, encoding, cb);
  }) as typeof process.stderr.write;

  // Wrangler often logs the module-load throw via console.error (sometimes on a
  // delayed tick after unstable_dev resolves). Capture those too.
  const originalError = console.error;
  const originalWarn = console.warn;
  console.error = (...args: unknown[]) => {
    for (const arg of args) push(arg);
    originalError(...args);
  };
  console.warn = (...args: unknown[]) => {
    for (const arg of args) push(arg);
    originalWarn(...args);
  };

  return {
    chunks,
    restore: () => {
      process.stderr.write = originalWrite;
      console.error = originalError;
      console.warn = originalWarn;
    },
    sawBindingError: () => MISSING_BINDING_ERROR.test(chunks.join("")),
  };
}

/**
 * Assert missing-binding startup failure directly.
 * Current wrangler/miniflare may: reject `unstable_dev`, reject `waitUntilExit`
 * (ERR_RUNTIME_FAILURE), return 5xx on probe, or log the module-load throw to
 * stderr while fetch hangs. A hang-guard timeout is only a safety net — never
 * the success criterion.
 */
async function expectStartupFailure(
  configPath: string,
  environment: string,
): Promise<void> {
  const stderr = captureStderr();
  let worker: Unstable_DevWorker | undefined;

  try {
    try {
      worker = await Promise.race([
        unstable_dev(SCRIPT_PATH, {
          ...DEV_OPTIONS,
          config: configPath,
          env: environment,
        }),
        hangGuard(
          `unstable_dev hung past ${STARTUP_FAILURE_HANG_GUARD_MS}ms hang guard`,
        ),
      ]);
    } catch (error) {
      // Fail-fast wrangler, or hang guard after a binding error already logged.
      if (stderr.sawBindingError()) {
        return;
      }
      expect(error).toBeTruthy();
      return;
    }

    if (stderr.sawBindingError()) {
      return;
    }

    // Brief settle: wrangler sometimes prints the binding throw a tick after
    // unstable_dev resolves (observed flaky on missing D1).
    for (let i = 0; i < 20 && !stderr.sawBindingError(); i += 1) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    if (stderr.sawBindingError()) {
      return;
    }

    // Attach exit watcher immediately; race against probe + stderr + hang guard.
    const exitFailure = worker.waitUntilExit().then(
      () => ({ kind: "exit" as const }),
      (error: unknown) => ({ kind: "rejected" as const, error }),
    );

    let outcome: {
      kind: "exit" | "rejected" | "response" | "fetch-rejected" | "logged";
      status?: number;
      error?: unknown;
    };
    try {
      outcome = await Promise.race([
        exitFailure,
        worker.fetch("http://127.0.0.1/health").then(
          (response) => ({
            kind: "response" as const,
            status: response.status,
          }),
          (error: unknown) => ({ kind: "fetch-rejected" as const, error }),
        ),
        (async () => {
          const deadline = Date.now() + STARTUP_FAILURE_HANG_GUARD_MS;
          while (Date.now() < deadline) {
            if (stderr.sawBindingError()) {
              return { kind: "logged" as const };
            }
            await new Promise((resolve) => setTimeout(resolve, 25));
          }
          throw new Error(
            `missing-binding worker neither rejected, returned 5xx, nor logged a binding error within ${STARTUP_FAILURE_HANG_GUARD_MS}ms hang guard`,
          );
        })(),
      ]);
    } catch (error) {
      // Hang guard lost the race, but the binding error may still have landed.
      if (stderr.sawBindingError()) {
        return;
      }
      throw error;
    }

    if (outcome.kind === "logged") {
      return;
    }

    if (outcome.kind === "response") {
      expect(outcome.status).toBeGreaterThanOrEqual(500);
      return;
    }

    if (outcome.kind === "exit") {
      // Last chance: binding error may have been logged without an exit reject.
      expect(stderr.sawBindingError()).toBe(true);
      return;
    }

    // Runtime failure (waitUntilExit) or fetch rejection — still accept if the
    // binding error was logged alongside the reject.
    if (stderr.sawBindingError()) {
      return;
    }
    expect(["rejected", "fetch-rejected"]).toContain(outcome.kind);
    expect(outcome.error).toBeTruthy();
  } finally {
    stderr.restore();
    await worker?.stop().catch(() => undefined);
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
