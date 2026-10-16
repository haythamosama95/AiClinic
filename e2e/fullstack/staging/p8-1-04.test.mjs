import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";

// H-STG unit harness (P8.1 US2): node --test e2e/fullstack/staging/p8-1-04.test.mjs

const REPO_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);
const PLATFORM_CONFIG = path.join(REPO_ROOT, "ai-platform/wrangler.toml");
const ABO_CONFIG = path.join(REPO_ROOT, "abo/wrangler.toml");
const ABO_WORKER = path.join(REPO_ROOT, "abo/src/worker.ts");
const ABO_OPS = path.join(REPO_ROOT, "abo/src/ops/index.ts");

function parseEnvStagingBlock(tomlText, label) {
  const lines = tomlText.split("\n");
  const start = lines.findIndex((line) => line.trim() === "[env.staging]");
  assert.notEqual(
    start,
    -1,
    `${label} must declare [env.staging]`,
  );

  const props = {};
  for (let i = start + 1; i < lines.length; i += 1) {
    const trimmed = lines[i].trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    if (trimmed.startsWith("[")) {
      break;
    }
    const match = /^([A-Za-z0-9_]+)\s*=\s*(.+)$/.exec(trimmed);
    if (match) {
      props[match[1]] = match[2].trim().replace(/^"|"$/g, "");
    }
  }
  return props;
}

function assertStagingHostnameFlags(props, label) {
  assert.equal(
    props.workers_dev,
    "false",
    `${label} [env.staging] must set workers_dev = false`,
  );
  assert.equal(
    props.preview_urls,
    "false",
    `${label} [env.staging] must set preview_urls = false`,
  );
}

test("E2E-P8.1-04", async () => {
  const platformToml = await readFile(PLATFORM_CONFIG, "utf8");
  const aboToml = await readFile(ABO_CONFIG, "utf8");
  const workerSource = await readFile(ABO_WORKER, "utf8");
  const opsSource = await readFile(ABO_OPS, "utf8");

  assertStagingHostnameFlags(
    parseEnvStagingBlock(platformToml, "ai-platform/wrangler.toml"),
    "ai-platform/wrangler.toml",
  );
  assertStagingHostnameFlags(
    parseEnvStagingBlock(aboToml, "abo/wrangler.toml"),
    "abo/wrangler.toml",
  );

  assert.match(
    workerSource,
    /if \(host === env\.OPS_HOST && path\.startsWith\("\/ops\/"\)\)/u,
    "abo/src/worker.ts fetch must route OPS_HOST /ops/* to handleOps",
  );
  assert.match(
    workerSource,
    /return handleOps\(request, env, path\);/u,
    "abo/src/worker.ts fetch must call handleOps for the ops host",
  );
  assert.match(
    workerSource,
    /import \{ handleOps as dispatchOps/u,
    "abo/src/worker.ts must import handleOps as dispatchOps from ops/index.js",
  );
  assert.match(
    workerSource,
    /return dispatchOps\(request, env, path, versionGate\.version\);/u,
    "abo/src/worker.ts handleOps must call dispatchOps",
  );
  assert.match(
    opsSource,
    /await verifyOpsAccess\(env, request\)/u,
    "abo/src/ops/index.ts handleOps must call verifyOpsAccess",
  );
});
