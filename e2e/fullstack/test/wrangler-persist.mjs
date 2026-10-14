import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { unstable_startWorker as startWorker } from "wrangler";

const FULLSTACK_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

export const REPO_ROOT = path.resolve(FULLSTACK_ROOT, "../..");
const WRANGLER_CLI = path.join(
  FULLSTACK_ROOT,
  "node_modules/wrangler/bin/wrangler.js",
);

/** Isolated dirs for local wrangler/workerd (wiped by test harness before e2e runs). */
export const PLATFORM_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/platform");
/** Separate persist for CLI D1 migrations (minimal Miniflare) — never shared with startWorker. */
export const D1_SEED_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/d1-seed");
export const HARNESS_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/harness");
export const REGISTRY_DIR = path.join(FULLSTACK_ROOT, ".wrangler/registry");
export const ABO_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/abo");
export const ABO_D1_SEED_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/abo-d1-seed");
export const PAYMOB_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/paymob");

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
  const result = spawnSync(process.execPath, [WRANGLER_CLI, ...args], {
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
    const sourcePath = path.join(fromDir, name);
    const sourceDb = new DatabaseSync(sourcePath);
    try {
      const checkpoint = sourceDb.prepare("PRAGMA wal_checkpoint(TRUNCATE)").get();
      if (checkpoint?.busy !== 0) {
        throw new Error(`Could not checkpoint D1 seed ${sourcePath} before copying`);
      }
    } finally {
      sourceDb.close();
    }
    const targetPath = path.join(toDir, name);
    rmSync(`${targetPath}-wal`, { force: true });
    rmSync(`${targetPath}-shm`, { force: true });
    cpSync(sourcePath, targetPath);
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
  rmSync(D1_SEED_PERSIST, { recursive: true, force: true });
  mkdirSync(D1_SEED_PERSIST, { recursive: true });
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

/** Apply fixture SQL directly to the runtime D1 file. */
export function execPlatformD1Sql(sql) {
  const db = new DatabaseSync(platformD1DatabaseFile());
  try {
    db.exec(sql);
  } finally {
    db.close();
  }
}

/** Apply ABO migrations in an isolated CLI persist, then copy its app D1 DB. */
export async function prepareAboD1({
  aboConfig,
  env = "development",
  database = "abo-development",
} = {}) {
  if (!aboConfig) throw new Error("prepareAboD1 requires aboConfig");
  rmSync(ABO_PERSIST, { recursive: true, force: true });
  rmSync(ABO_D1_SEED_PERSIST, { recursive: true, force: true });
  mkdirSync(ABO_PERSIST, { recursive: true });
  mkdirSync(ABO_D1_SEED_PERSIST, { recursive: true });
  mkdirSync(REGISTRY_DIR, { recursive: true });
  runWranglerSync([
    "d1", "migrations", "apply", database, "--local", "--env", env,
    "--config", aboConfig, "--persist-to", ABO_D1_SEED_PERSIST,
  ]);
  copyD1SqliteTree(ABO_D1_SEED_PERSIST, ABO_PERSIST);
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
