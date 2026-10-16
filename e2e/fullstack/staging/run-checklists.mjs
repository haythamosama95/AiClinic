import { readFile, access } from "node:fs/promises";
import { constants } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

// H-STG unit harness (P8.1): node e2e/fullstack/staging/run-checklists.mjs

const REPO_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);
const STAGING_DIR = path.join(REPO_ROOT, "e2e/fullstack/staging");
const PLATFORM_CONFIG = path.join(REPO_ROOT, "ai-platform/wrangler.toml");
const ABO_WORKER = path.join(REPO_ROOT, "abo/src/worker.ts");
const HEARTBEAT_MONITOR = path.join(REPO_ROOT, "ops/staging/heartbeat-monitor.mjs");
const ABO_CRON_DISABLED_FIXTURE = path.join(
  REPO_ROOT,
  "ops/staging/fixtures/abo-cron-disabled.json",
);
const AUDIT_WATCHER = path.join(REPO_ROOT, "ops/staging/audit-watcher.mjs");
const DEPLOY_AND_SECRET_FIXTURE = path.join(
  REPO_ROOT,
  "ops/staging/fixtures/deploy-and-secret.json",
);
const NFR_08 = path.join(REPO_ROOT, "ops/staging/nfr-08.md");

const failures = [];

function fail(id, message) {
  failures.push(`${id}: ${message}`);
}

async function assertReadable(filePath, label) {
  try {
    await access(filePath, constants.R_OK);
  } catch {
    fail(label, `missing file ${path.relative(REPO_ROOT, filePath)}`);
    return false;
  }
  return true;
}

function parseTomlSection(lines, sectionHeader) {
  const props = {};
  const start = lines.findIndex((line) => line.trim() === sectionHeader);
  if (start === -1) {
    return props;
  }
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

function parseEnvStagingBlock(tomlText, label) {
  const lines = tomlText.split("\n");
  if (!lines.some((line) => line.trim() === "[env.staging]")) {
    fail(label, `${label} must declare [env.staging]`);
    return null;
  }
  return {
    ...parseTomlSection(lines, "[env.staging]"),
    ...parseTomlSection(lines, "[env.staging.vars]"),
  };
}

function assertMinuteBranchCallsPingHeartbeat(workerSource, id) {
  const minuteMatch =
    /if \(cron === "\* \* \* \* \*"\) \{([\s\S]*?)\n\s+return;\n\s+\}/m.exec(
      workerSource,
    );
  if (!minuteMatch) {
    fail(id, "abo/src/worker.ts must have * * * * * cron branch");
    return;
  }
  if (!/pingHeartbeat\s*\(/u.test(minuteMatch[1])) {
    fail(id, "minute cron branch in abo/src/worker.ts must call pingHeartbeat");
  }
}

function runScript(scriptPath, fixturePath, id) {
  const result = spawnSync(process.execPath, [scriptPath, fixturePath], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  if (result.error) {
    fail(id, `failed to run ${path.relative(REPO_ROOT, scriptPath)}: ${result.error.message}`);
    return null;
  }
  if (result.status !== 0) {
    fail(
      id,
      `${path.relative(REPO_ROOT, scriptPath)} exited ${result.status}: ${result.stderr || result.stdout}`,
    );
    return null;
  }
  return result.stdout;
}

async function runE2EP81_01(workerSource) {
  const id = "E2E-P8.1-01";
  const checklistPath = path.join(STAGING_DIR, "p8-1-01.checklist.md");
  if (!(await assertReadable(checklistPath, id))) {
    return;
  }
  if (!(await assertReadable(HEARTBEAT_MONITOR, id))) {
    return;
  }
  if (!(await assertReadable(ABO_CRON_DISABLED_FIXTURE, id))) {
    return;
  }

  assertMinuteBranchCallsPingHeartbeat(workerSource, id);

  const stdout = runScript(HEARTBEAT_MONITOR, ABO_CRON_DISABLED_FIXTURE, id);
  if (stdout === null) {
    return;
  }
  if (stdout.trim() !== "AL-21") {
    fail(id, `heartbeat monitor stdout must be AL-21 only; got ${JSON.stringify(stdout.trim())}`);
  }
}

async function runE2EP81_02() {
  const id = "E2E-P8.1-02";
  const checklistPath = path.join(STAGING_DIR, "p8-1-02.checklist.md");
  if (!(await assertReadable(checklistPath, id))) {
    return;
  }
  if (!(await assertReadable(AUDIT_WATCHER, id))) {
    return;
  }
  if (!(await assertReadable(DEPLOY_AND_SECRET_FIXTURE, id))) {
    return;
  }

  const stdout = runScript(AUDIT_WATCHER, DEPLOY_AND_SECRET_FIXTURE, id);
  if (stdout === null) {
    return;
  }
  const lines = stdout.trim().split("\n");
  if (lines.length !== 2 || lines[0] !== "AL-21" || lines[1] !== "AL-21") {
    fail(
      id,
      `audit watcher stdout must be AL-21 repeated per event; got ${JSON.stringify(stdout.trim())}`,
    );
  }
}

async function runE2EP81_03(workerSource) {
  const id = "E2E-P8.1-03";
  const checklistPath = path.join(STAGING_DIR, "p8-1-03.checklist.md");
  if (!(await assertReadable(checklistPath, id))) {
    return;
  }
  if (!(await assertReadable(NFR_08, id))) {
    return;
  }

  const checklistText = await readFile(checklistPath, "utf8");
  const requiredPhrases = [
    "public.get_ai_status",
    'DURATION_SCALE = "staging"',
    "ops/staging/nfr-08.md",
    "Monthly (1 month, runs 30 minutes",
    "Quarterly (3 months, runs 90 minutes",
    "Annual (12 months, runs 6 hours",
    "POST /v1/checkouts",
    "Paymob test card",
    "30 seconds",
  ];
  for (const phrase of requiredPhrases) {
    if (!checklistText.includes(phrase)) {
      fail(id, `p8-1-03.checklist.md must name ${JSON.stringify(phrase)}`);
    }
  }

  const platformToml = await readFile(PLATFORM_CONFIG, "utf8");
  const stagingProps = parseEnvStagingBlock(platformToml, "ai-platform/wrangler.toml");
  if (stagingProps && stagingProps.DURATION_SCALE !== "staging") {
    fail(
      id,
      'ai-platform/wrangler.toml [env.staging] must set DURATION_SCALE = "staging"',
    );
  }

  assertMinuteBranchCallsPingHeartbeat(workerSource, id);
}

async function main() {
  const workerSource = await readFile(ABO_WORKER, "utf8");

  await runE2EP81_01(workerSource);
  await runE2EP81_02();
  await runE2EP81_03(workerSource);

  if (failures.length > 0) {
    console.error("run-checklists.mjs failed:");
    for (const message of failures) {
      console.error(`  - ${message}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log("run-checklists.mjs passed: E2E-P8.1-01, E2E-P8.1-02, E2E-P8.1-03");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
