import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
);
const launchCheckScript = path.join(repoRoot, "ops", "launch", "launch-check.mjs");
const heartbeatMonitorScript = path.join(repoRoot, "ops", "staging", "heartbeat-monitor.mjs");
const fixturesDir = path.join(repoRoot, "ops", "launch", "fixtures");
const staleFixture = path.join(repoRoot, "ops", "staging", "fixtures", "abo-cron-disabled.json");

const { classifyStreams, STREAM_WINDOWS_MS } = await import(
  pathToFileURL(heartbeatMonitorScript).href
);

const FAILED_CONDITION_LINES = [
  "No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists",
  "`workers_dev` and preview URLs are off",
  "Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package",
  "AL-23 is clear. The ABO's key self-check passes.",
  "At least two operator credentials are active",
  "The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set.",
  "The platform holds no terms (clinic DOs) or grants (D1).",
  "The audit watcher and the heartbeat monitor are live.",
];

function runLaunchCheck(fixturePath) {
  return spawnSync(process.execPath, [launchCheckScript, "--offline", fixturePath], {
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

function withTempSnapshot(mutate, body) {
  const dir = mkdtempSync(path.join(tmpdir(), "launch-check-rm35-"));
  try {
    const snapshot = JSON.parse(
      readFileSync(path.join(fixturesDir, "production-like.json"), "utf8"),
    );
    mutate(snapshot);
    const file = path.join(dir, "snapshot.json");
    writeFileSync(file, JSON.stringify(snapshot));
    return body(runLaunchCheck(file));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("E2E-P8.3-01 R9-RT1: offline evaluation of a complete snapshot never exits 0", () => {
  const fixturePath = path.join(fixturesDir, "production-like.json");
  const result = runLaunchCheck(fixturePath);

  assert.notEqual(result.status, 0, "an offline snapshot must never report a launch pass");
  assert.deepEqual(stdoutLines(result.stdout), []);
  assert.match(result.stderr, /never reports a launch pass/u);
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

test("R9-RT1 live mode without the read-only target adapter fails closed with no condition output", () => {
  const result = spawnSync(process.execPath, [launchCheckScript], {
    cwd: repoRoot,
    encoding: "utf8",
  });

  assert.equal(result.status, 1);
  assert.deepEqual(stdoutLines(result.stdout), []);
  assert.match(result.stderr, /cannot be confirmed/u);
});

test("R9-RT1 absent or non-exact false flags fail their condition", () => {
  withTempSnapshot(
    (snapshot) => {
      delete snapshot.control_route;
      snapshot.workers_dev = "false";
    },
    (result) => {
      assert.notEqual(result.status, 0);
      assert.deepEqual(stdoutLines(result.stdout), [
        FAILED_CONDITION_LINES[0],
        FAILED_CONDITION_LINES[1],
      ]);
    },
  );
});

test("R9-RT1 operator credential count must be a safe integer of at least two", () => {
  withTempSnapshot(
    (snapshot) => {
      delete snapshot.active_operator_credentials;
    },
    (result) => {
      assert.deepEqual(stdoutLines(result.stdout), [FAILED_CONDITION_LINES[4]]);
    },
  );
  withTempSnapshot(
    (snapshot) => {
      snapshot.active_operator_credentials = "2";
    },
    (result) => {
      assert.deepEqual(stdoutLines(result.stdout), [FAILED_CONDITION_LINES[4]]);
    },
  );
});

test("R9-RT1 term and grant counts must be exact zero integers", () => {
  withTempSnapshot(
    (snapshot) => {
      snapshot.platform_d1_terms = 1;
    },
    (result) => {
      assert.deepEqual(stdoutLines(result.stdout), [FAILED_CONDITION_LINES[6]]);
    },
  );
  withTempSnapshot(
    (snapshot) => {
      snapshot.platform_d1_grants = "0";
    },
    (result) => {
      assert.deepEqual(stdoutLines(result.stdout), [FAILED_CONDITION_LINES[6]]);
    },
  );
});

const NOW = Date.parse("2026-10-22T12:00:00Z");
const minutesAgo = (minutes) => new Date(NOW - minutes * 60 * 1000).toISOString();
const hoursAgo = (hours) => minutesAgo(hours * 60);

test("R9-RT2 the D-6 miss windows are 5 minutes, 15 minutes, 26 hours and 2 hours", () => {
  assert.deepEqual(
    { ...STREAM_WINDOWS_MS },
    {
      abo_minute: 5 * 60 * 1000,
      platform_5min: 15 * 60 * 1000,
      abo_daily_digest: 26 * 60 * 60 * 1000,
      audit_watcher: 2 * 60 * 60 * 1000,
    },
  );
});

test("R9-RT2 a missing stream is detected while the surviving streams are fresh", () => {
  const missing = classifyStreams(
    {
      platform_5min: minutesAgo(1),
      abo_daily_digest: hoursAgo(1),
      audit_watcher: minutesAgo(30),
    },
    NOW,
  );
  assert.deepEqual(missing, ["abo_minute"]);
});

test("R9-RT2 each stream expires by its own window", () => {
  const fresh = {
    abo_minute: minutesAgo(4),
    platform_5min: minutesAgo(14),
    abo_daily_digest: hoursAgo(25),
    audit_watcher: hoursAgo(1),
  };
  assert.deepEqual(classifyStreams(fresh, NOW), []);
  assert.deepEqual(
    classifyStreams({ ...fresh, platform_5min: minutesAgo(16) }, NOW),
    ["platform_5min"],
  );
  assert.deepEqual(
    classifyStreams({ ...fresh, abo_daily_digest: hoursAgo(27) }, NOW),
    ["abo_daily_digest"],
  );
  assert.deepEqual(
    classifyStreams({ ...fresh, audit_watcher: hoursAgo(3) }, NOW),
    ["audit_watcher"],
  );
});

test("R9-RT2 a replayed old snapshot cannot prove health", () => {
  const old = hoursAgo(48);
  assert.deepEqual(
    classifyStreams(
      { abo_minute: old, platform_5min: old, abo_daily_digest: old, audit_watcher: old },
      NOW,
    ),
    ["abo_minute", "platform_5min", "abo_daily_digest", "audit_watcher"],
  );
});

test("R9-RT2 malformed and future timestamps fail closed", () => {
  const fresh = {
    abo_minute: minutesAgo(1),
    platform_5min: minutesAgo(1),
    abo_daily_digest: minutesAgo(1),
    audit_watcher: minutesAgo(1),
  };
  for (const bad of ["not-a-date", "2026-10-22 11:59:00", minutesAgo(-5), 1234]) {
    assert.deepEqual(
      classifyStreams({ ...fresh, abo_minute: bad }, NOW),
      ["abo_minute"],
      `timestamp ${JSON.stringify(bad)} must fail closed`,
    );
  }
});

test("R9-RT2 the offline monitor prints AL-21 for the absent abo_minute stream in the staging fixture", () => {
  const result = spawnSync(process.execPath, [heartbeatMonitorScript, staleFixture], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), "AL-21");
});

test("R9-RT1 launch-state 503 fails the terms condition", async () => {
  const { createAboSource } = await import(
    pathToFileURL(path.join(repoRoot, "ops", "launch", "live-sources.mjs")).href
  );
  const { acquire, evaluateLive } = await import(pathToFileURL(launchCheckScript).href);
  const { validateTarget } = await import(
    pathToFileURL(path.join(repoRoot, "ops", "launch", "target.mjs")).href
  );
  const target = validateTarget(
    JSON.parse(readFileSync(path.join(fixturesDir, "target-test.json"), "utf8")),
  );
  const nowMs = Date.parse("2026-10-22T12:00:00Z");
  const clock = { now: () => nowMs };
  const date = new Date(nowMs).toUTCString();
  const json = (body) =>
    new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json", date },
    });
  const fetchImpl = async (url) => {
    if (url.endsWith("/ops/ceremony-context")) {
      return json({ rp_id: target.ops_host });
    }
    if (url.endsWith("/ops/registries")) {
      return json({
        issuer_keys: [{ kid: "issuer-test" }],
        service_keys: [{ kid: "service-test" }],
        operator_credentials: [{ active: true }, { active: true }],
      });
    }
    if (url.endsWith("/ops/launch-state")) {
      return new Response("", { status: 503, headers: { date } });
    }
    throw new Error(`unexpected fake request: ${url}`);
  };

  const { observations, errors } = await acquire(
    target,
    { abo: createAboSource({ env: {}, fetchImpl }) },
    clock,
  );

  assert.deepEqual(errors, [{ source: "abo", reason: "http-503" }]);
  assert.equal(observations.some((item) => item.key === "platform_d1_terms"), false);
  const failures = evaluateLive(observations, target, nowMs - 1000, nowMs);
  assert.ok(failures.includes(FAILED_CONDITION_LINES[6]));
});
