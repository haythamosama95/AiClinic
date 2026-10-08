import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
);
const launchCheckScript = path.join(repoRoot, "ops", "launch", "launch-check.mjs");
const fixturesDir = path.join(repoRoot, "ops", "launch", "fixtures");

const FAILED_CONDITION_LINES = [
  "No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists",
  "`workers_dev` and preview URLs are off",
  "Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package",
  "AL-23 is clear. The ABO's key self-check passes.",
  "At least two operator credentials are active",
  "The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set.",
  "Platform D1 holds no terms or grants.",
  "The audit watcher and the heartbeat monitor are live.",
];

function runLaunchCheck(fixturePath) {
  return spawnSync(process.execPath, [launchCheckScript, fixturePath], {
    cwd: repoRoot,
    encoding: "utf8",
  });
}

function stdoutLines(stdout) {
  return stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

test("E2E-P8.3-01", () => {
  const fixturePath = path.join(fixturesDir, "production-like.json");
  const result = runLaunchCheck(fixturePath);

  assert.equal(result.status, 0, result.stderr || result.stdout);

  for (const line of FAILED_CONDITION_LINES) {
    assert.ok(
      !result.stdout.includes(line),
      `stdout must not contain failed-condition line: ${line}`,
    );
  }
});

test("E2E-P8.3-02", () => {
  const workersDevFixture = path.join(fixturesDir, "workers-dev-enabled.json");
  const workersDevResult = runLaunchCheck(workersDevFixture);

  assert.notEqual(workersDevResult.status, 0, workersDevResult.stderr || workersDevResult.stdout);
  assert.deepEqual(
    stdoutLines(workersDevResult.stdout),
    ["`workers_dev` and preview URLs are off"],
  );

  const singleOperatorFixture = path.join(
    fixturesDir,
    "single-operator-credential.json",
  );
  const singleOperatorResult = runLaunchCheck(singleOperatorFixture);

  assert.notEqual(
    singleOperatorResult.status,
    0,
    singleOperatorResult.stderr || singleOperatorResult.stdout,
  );
  assert.deepEqual(
    stdoutLines(singleOperatorResult.stdout),
    ["At least two operator credentials are active"],
  );
});
