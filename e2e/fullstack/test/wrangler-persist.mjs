import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { unstable_startWorker as startWorker } from "wrangler";

const FULLSTACK_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

export const REPO_ROOT = path.resolve(FULLSTACK_ROOT, "../..");

/** Isolated dirs for local wrangler/workerd (wiped by test harness before e2e runs). */
export const PLATFORM_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/platform");
/** Separate persist for CLI D1 migrations (minimal Miniflare) — never shared with startWorker. */
export const D1_SEED_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/d1-seed");
export const HARNESS_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/harness");
export const REGISTRY_DIR = path.join(FULLSTACK_ROOT, ".wrangler/registry");
export const ABO_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/abo");

const D1_OBJECT_DIR = "v3/d1/miniflare-D1DatabaseObject";

/** Env for all wrangler CLI + dev subprocesses in e2e fullstack stacks. */
export function wranglerLocalEnv(extra = {}) {
  return {
    ...process.env,
    WRANGLER_REGISTRY_PATH: REGISTRY_DIR,
    ...extra,
  };
}

export function runWranglerSync(args, { cwd = REPO_ROOT, env = {} } = {}) {
  const result = spawnSync("npx", ["wrangler", ...args], {
    cwd,
    env: wranglerLocalEnv(env),
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(
      `wrangler ${args.join(" ")} failed (${result.status}): ${result.stderr || result.stdout}`,
    );
  }
  return result.stdout;
}

export function copyD1SqliteTree(fromPersist, toPersist) {
  const fromDir = path.join(fromPersist, D1_OBJECT_DIR);
  const toDir = path.join(toPersist, D1_OBJECT_DIR);
  if (!existsSync(fromDir)) {
    throw new Error(`D1 seed directory missing: ${fromDir}`);
  }
  mkdirSync(toDir, { recursive: true });
  for (const name of readdirSync(fromDir)) {
    if (!name.endsWith(".sqlite") || name.startsWith("metadata")) {
      continue;
    }
    cpSync(path.join(fromDir, name), path.join(toDir, name));
  }
}

/**
 * Apply platform D1 migrations without corrupting startWorker persist.
 *
 * `wrangler d1 migrations apply` spins a minimal Miniflare against `--persist-to`.
 * Running that against the same tree as `unstable_startWorker` leaves internal
 * SQLite (_cf_ALARM) incompatible and workerd fatals when platform + harness start.
 * Migrations run on D1_SEED_PERSIST; a brief platform boot creates layout on
 * PLATFORM_PERSIST; migrated D1 files are copied into the live persist tree.
 */
export async function preparePlatformD1({
  platformConfig,
  env = "development",
  database = "ai-platform-development",
  platformPort = 8787,
} = {}) {
  if (!platformConfig) {
    throw new Error("preparePlatformD1 requires platformConfig");
  }
  mkdirSync(REGISTRY_DIR, { recursive: true });
  runWranglerSync([
    "d1",
    "migrations",
    "apply",
    database,
    "--local",
    "--env",
    env,
    "--config",
    platformConfig,
    "--persist-to",
    D1_SEED_PERSIST,
  ]);

  const platformWorker = await startWorker({
    config: platformConfig,
    env,
    dev: {
      server: { hostname: "127.0.0.1", port: platformPort },
      inspector: false,
      persist: PLATFORM_PERSIST,
      registry: REGISTRY_DIR,
    },
  });
  await platformWorker.ready;
  await platformWorker.dispose();
  await new Promise((resolve) => setTimeout(resolve, 300));

  copyD1SqliteTree(D1_SEED_PERSIST, PLATFORM_PERSIST);
}

export function platformD1DatabaseFile() {
  const dir = path.join(PLATFORM_PERSIST, D1_OBJECT_DIR);
  if (!existsSync(dir)) {
    throw new Error(`Missing platform D1 dir: ${dir}`);
  }
  for (const name of readdirSync(dir)) {
    if (name.endsWith(".sqlite") && !name.startsWith("metadata")) {
      return path.join(dir, name);
    }
  }
  throw new Error(`No platform D1 sqlite under ${dir}`);
}

/**
 * Mutate platform D1 before any startWorker (uses seed persist + copy).
 * Never run `wrangler d1 execute` against PLATFORM_PERSIST while workers use it.
 */
export function execPlatformD1Sql(
  sql,
  {
    platformConfig,
    env = "development",
    database = "ai-platform-development",
  } = {},
) {
  const config = platformConfig ?? path.join(REPO_ROOT, "ai-platform/wrangler.toml");
  runWranglerSync([
    "d1",
    "execute",
    database,
    "--local",
    "--env",
    env,
    "--config",
    config,
    "--persist-to",
    D1_SEED_PERSIST,
    "--command",
    sql,
  ]);
  copyD1SqliteTree(D1_SEED_PERSIST, PLATFORM_PERSIST);
}

export function queryPlatformD1One(sql) {
  const db = new DatabaseSync(platformD1DatabaseFile());
  try {
    const stmt = db.prepare(sql);
    if (typeof stmt.all === "function") {
      const rows = stmt.all();
      return rows[0] ?? null;
    }
    stmt.run();
    return null;
  } finally {
    db.close();
  }
}
