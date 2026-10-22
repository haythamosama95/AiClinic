import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

// R9-RT1 (01 §3.8 D-6) and R9-RT2 condition 8: live launch-check tests. Every network call goes to
// an in-process fake fetch. No live credential is used.

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const launchScript = path.join(here, "launch-check.mjs");
const targetFixture = path.join(here, "fixtures", "target-test.json");

const launch = await import(pathToFileURL(launchScript).href);
const { validateTarget } = await import(pathToFileURL(path.join(here, "target.mjs")).href);
const sources = await import(pathToFileURL(path.join(here, "live-sources.mjs")).href);
const monitor = await import(pathToFileURL(path.join(repoRoot, "ops", "staging", "heartbeat-monitor.mjs")).href);
const MIGRATION = path.join(repoRoot, "backend", "supabase", "migrations", "20261022120000_rm35_launch_state_reader.sql");
const VERSION_FILE = path.join(repoRoot, "packages", "vendor-contracts", "src", "version.ts");
const NIL_INSTALLATION = "00000000-0000-0000-0000-000000000000";

const { acquire, evaluateLive, MAX_AGE_MS } = launch;
const { createLiveSources, BACKEND_STATE_KEYS, CHANNEL_KEYS } = sources;
const { checkMonitorSnapshot } = monitor;

const NOW = Date.parse("2026-10-22T12:00:00Z");
const target = validateTarget(JSON.parse(readFileSync(targetFixture, "utf8")));
const ACCOUNT = target.cloudflare_account_id;
const LINE = [
  "No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists",
  "`workers_dev` and preview URLs are off",
  "Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package",
  "AL-23 is clear. The ABO's key self-check passes.",
  "At least two operator credentials are active",
  "The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set.",
  "The platform holds no terms (clinic DOs) or grants (D1).",
  "The audit watcher and the heartbeat monitor are live.",
  "No published, canary or active routing policy row lacks a content digest.",
];

// The routing digest failure line carries the failing policy ids; compare it by its fixed prefix.
const baseLine = (line) => (line.startsWith(LINE[8]) ? LINE[8] : line);

// A channel map with every CHANNEL_KEYS name set to value, with optional per-key overrides.
function channelMap(value = 1, overrides = {}) {
  return { ...Object.fromEntries(CHANNEL_KEYS.map((key) => [key, value])), ...overrides };
}

function makeClock(start = NOW) {
  let current = start;
  return {
    now: () => current,
    set: (value) => {
      current = value;
    },
  };
}

function fullEnv() {
  return {
    LAUNCH_CHECK_CF_TOKEN: "cf-test-token",
    LAUNCH_CHECK_ACCESS_TOKEN: "access-test-token",
    LAUNCH_CHECK_DB_URL: "postgres://postgres.abcdefghijklmnop@db.abcdefghijklmnop.supabase.co:5432/postgres",
    LAUNCH_CHECK_MONITOR_KEY: "monitor-test-key",
  };
}

function goodMonitorSnapshot(overrides = {}) {
  return {
    environment: target.environment,
    checks: [
      { stream: "abo_minute", window_seconds: 300, status: "up" },
      { stream: "platform_5min", window_seconds: 900, status: "up" },
      { stream: "abo_daily_digest", window_seconds: 93600, status: "up" },
      { stream: "audit_watcher", window_seconds: 7200, status: "up" },
    ],
    destinations: ["destination-a", "destination-b"],
    ...overrides,
  };
}

function reply(clock, body, { status = 200, dateOffsetMs = 0, noDate = false, raw } = {}) {
  const headers = new Headers({ "content-type": "application/json" });
  if (!noDate) {
    headers.set("date", new Date(clock.now() + dateOffsetMs).toUTCString());
  }
  const text = raw !== undefined ? raw : JSON.stringify(body);
  return new Response(text, { status, headers });
}

function routeFor(clock, options = {}) {
  const o = {
    workersDev: false,
    accountId: ACCOUNT,
    operatorBearer: false,
    activeCreds: 2,
    controlRoute: false,
    truncateSecrets: false,
    aboStatus: 200,
    aboSkewMs: 0,
    aboNonJson: false,
    aboTimeout: false,
    aboNoDate: false,
    rpId: target.ops_host,
    probeStatus: 404,
    entitleStatus: 404,
    overrideStatus: 404,
    channelVersions: channelMap(1),
    platformChannelVersions: channelMap(1),
    // Merged into the ABO launch-state body. An undefined value leaves that field absent.
    launchStateOverrides: {},
    monitor: goodMonitorSnapshot(),
    ...options,
  };
  const cfPrefix = `/accounts/${ACCOUNT}`;

  return (url, page) => {
    if (url.hostname === "api.cloudflare.com") {
      const p = url.pathname.replace("/client/v4", "");
      if (p === cfPrefix) {
        return reply(clock, { success: true, result: { id: o.accountId } });
      }
      if (/\/workers\/scripts\/[^/]+\/subdomain$/u.test(p)) {
        return reply(clock, { success: true, result: { enabled: o.workersDev, previews_enabled: false } });
      }
      if (/\/workers\/scripts\/[^/]+\/secrets$/u.test(p)) {
        const names = [{ name: "DATABASE_URL" }];
        if (o.operatorBearer) {
          names.push({ name: "OPERATOR_BEARER_TOKEN" });
        }
        if (o.truncateSecrets) {
          if (page === 1) {
            return reply(clock, {
              success: true,
              result: names.slice(0, 1),
              result_info: { page: 1, per_page: 100, count: 1, total_count: 2, total_pages: 2 },
            });
          }
          return reply(clock, {
            success: true,
            result: [],
            result_info: { page: 2, per_page: 100, count: 0, total_count: 2, total_pages: 2 },
          });
        }
        return reply(clock, {
          success: true,
          result: names,
          result_info: { page: 1, per_page: 100, count: names.length, total_count: names.length, total_pages: 1 },
        });
      }
      if (p === `/zones/${target.zone_id}/workers/routes`) {
        const routes = o.controlRoute
          ? [{ pattern: "ops.example.test/control/*" }]
          : [{ pattern: "api.example.test/clinic*" }];
        return reply(clock, {
          success: true,
          result: routes,
          result_info: { page: 1, per_page: 100, count: routes.length, total_count: routes.length, total_pages: 1 },
        });
      }
      return reply(clock, { success: false, result: null }, { status: 404 });
    }

    if (url.hostname === target.ops_host) {
      if (o.aboTimeout) {
        return Object.assign(new Error("timed out"), { name: "TimeoutError" });
      }
      const opts = { status: o.aboStatus, dateOffsetMs: o.aboSkewMs, noDate: o.aboNoDate };
      if (o.aboNonJson) {
        return reply(clock, null, { ...opts, raw: "<html>not json</html>" });
      }
      if (url.pathname === "/ops/ceremony-context") {
        return reply(clock, { rp_id: o.rpId }, opts);
      }
      if (url.pathname === "/ops/registries") {
        return reply(
          clock,
          {
            issuer_keys: [{ kid: "issuer-1", public_key: "pk-issuer-1" }],
            service_keys: [{ key_id: "service-1" }],
            operator_credentials: Array.from({ length: o.activeCreds }, (_, i) => ({ id: `op-${i}`, active: true })),
          },
          opts,
        );
      }
      if (url.pathname === "/ops/launch-state") {
        return reply(
          clock,
          {
            abo_signing_kid: "kid-test-1",
            issuer_keys_pinned: true,
            al_23_active: false,
            term_count: 0,
            grant_count: 0,
            channel_versions: o.channelVersions,
            platform_channel_versions: o.platformChannelVersions,
            key_self_check_passes: true,
            key_self_check_checked_at: "2026-10-22T11:55:00Z",
            platform_signing_key_set: true,
            platform_signing_kid: "platform-kid-1",
            legacy_routing_policy_ids: [],
            ...o.launchStateOverrides,
          },
          opts,
        );
      }
      return reply(clock, null, { ...opts, status: 404, raw: "" });
    }

    if (url.hostname === target.platform_host) {
      if (url.pathname === "/control/") {
        return reply(clock, null, { status: o.probeStatus, raw: "", dateOffsetMs: 0 });
      }
      if (url.pathname === `/control/installations/${NIL_INSTALLATION}/entitle`) {
        return reply(clock, null, { status: o.entitleStatus, raw: "", dateOffsetMs: 0 });
      }
      if (url.pathname === `/control/installations/${NIL_INSTALLATION}/override`) {
        return reply(clock, null, { status: o.overrideStatus, raw: "", dateOffsetMs: 0 });
      }
      return reply(clock, null, { status: 404, raw: "" });
    }

    if (url.hostname === "monitor.example.test") {
      return reply(clock, o.monitor);
    }
    return reply(clock, { error: "unexpected host" }, { status: 500 });
  };
}

function serve(clock, options) {
  const calls = [];
  const route = routeFor(clock, options);
  const fetchImpl = async (url, init = {}) => {
    const parsed = new URL(url);
    const page = Number(parsed.searchParams.get("page") ?? "1");
    calls.push({ url: parsed.href, method: init.method ?? "GET" });
    const response = route(parsed, page);
    if (response instanceof Error) {
      throw response;
    }
    return response;
  };
  return { fetchImpl, calls };
}

function backendJson(options = {}) {
  return JSON.stringify({
    database_name: options.databaseName ?? target.backend_database,
    contract_versions: options.contractVersions ?? { abo: 1 },
    set_ai_availability_present: options.setAiAvailability ?? false,
  });
}

async function acquireWith(options = {}, { clock = makeClock(), env = fullEnv(), runPsql } = {}) {
  const server = serve(clock, options);
  const live = createLiveSources({
    env,
    fetchImpl: server.fetchImpl,
    runPsql: runPsql ?? (async () => backendJson(options)),
  });
  const runStart = clock.now();
  const result = await acquire(target, live, clock);
  return { ...result, clock, runStart, calls: server.calls };
}

async function evaluateWith(options = {}) {
  const clock = makeClock();
  const result = await acquireWith(options, { clock });
  return {
    failures: evaluateLive(result.observations, target, result.runStart, clock.now(), MAX_AGE_MS),
    errors: result.errors,
    calls: result.calls,
  };
}

// The value of one observation from a full acquisition, with the source's target_id and source.
async function observed(options, key) {
  const result = await acquireWith(options);
  return result.observations.find((item) => item.key === key);
}

test("R9-RT1 fresh target-bound observations from fake sources pass only when every condition holds", async () => {
  const { failures, errors } = await evaluateWith();
  assert.deepEqual(errors, []);
  assert.deepEqual(failures, []);
});

test("R9-RT1 the four former gap reads are live: no gap observations are needed, and a missing field drops the ABO source", async () => {
  const complete = await evaluateWith();
  assert.deepEqual(complete.failures, []);

  // Without platform_signing_key_set the ABO body is malformed, so every ABO-backed condition fails
  // closed. The probe, Cloudflare and monitor conditions are unaffected.
  const absent = await evaluateWith({ launchStateOverrides: { platform_signing_key_set: undefined } });
  assert.deepEqual(absent.errors, [{ source: "abo", reason: "schema-mismatch" }]);
  // FR06 / FV-P4: the routing digest condition also comes from the ABO, so it fails closed too.
  assert.deepEqual(absent.failures.map(baseLine), [LINE[2], LINE[3], LINE[4], LINE[5], LINE[6], LINE[8]]);
});

test("R9-RT1 workers_dev flipping to true changes the result with no local file edited", async () => {
  const { failures } = await evaluateWith({ workersDev: true });
  assert.deepEqual(failures, [LINE[1]]);
});

test("R9-RT1 a revoked operator credential (count 1) fails the credential condition", async () => {
  const { failures } = await evaluateWith({ activeCreds: 1 });
  assert.deepEqual(failures, [LINE[4]]);
});

test("R9-RT1 OPERATOR_BEARER_TOKEN present on a worker fails the /control and bearer condition", async () => {
  const { failures } = await evaluateWith({ operatorBearer: true });
  assert.deepEqual(failures, [LINE[0]]);
});

test("R9-RT1 a /control route on the platform probe fails the /control condition", async () => {
  const { failures } = await evaluateWith({ probeStatus: 200 });
  assert.deepEqual(failures, [LINE[0]]);
});

test("R9-RT1 a probe answer other than 404 or 2xx is a source error, not evidence", async () => {
  const { failures, errors } = await evaluateWith({ probeStatus: 500 });
  assert.deepEqual(errors, [{ source: "probe", reason: "http-500" }]);
  assert.deepEqual(failures, [LINE[0]]);
});

test("R9-RT1 a route pattern on /control conflicts with a clean probe and fails closed", async () => {
  const { failures } = await evaluateWith({ controlRoute: true });
  assert.deepEqual(failures, [LINE[0]]);
});

test("R9-RT1 observations older than MAX_AGE or from before the run start are never used", async () => {
  const clock = makeClock();
  const result = await acquireWith({}, { clock });
  const staleCloudflare = result.observations.map((item) =>
    item.source === "cloudflare"
      ? { ...item, observed_at: new Date(NOW - 10 * 60 * 1000).toISOString() }
      : item,
  );
  assert.deepEqual(
    evaluateLive(staleCloudflare, target, result.runStart, clock.now(), MAX_AGE_MS),
    [LINE[0], LINE[1]],
  );
  const replayed = result.observations.map((item) => ({
    ...item,
    observed_at: new Date(NOW - 60 * 60 * 1000).toISOString(),
  }));
  assert.ok(
    evaluateLive(replayed, target, NOW, clock.now(), MAX_AGE_MS).length > 0,
    "a replayed earlier-run observation cannot satisfy this run",
  );
  const future = result.observations.map((item) => ({
    ...item,
    observed_at: new Date(NOW + 60 * 1000).toISOString(),
  }));
  assert.ok(evaluateLive(future, target, result.runStart, clock.now(), MAX_AGE_MS).length > 0);
});

test("R9-RT1 a Date header skewed by more than 60 seconds discards that source; 30 seconds is accepted", async () => {
  const skewed = await evaluateWith({ aboSkewMs: 2 * 60 * 1000 });
  assert.deepEqual(skewed.errors, [{ source: "abo", reason: "clock-skew" }]);
  assert.ok(skewed.failures.includes(LINE[4]));
  assert.ok(skewed.failures.includes(LINE[5]));

  const tolerated = await evaluateWith({ aboSkewMs: 30 * 1000 });
  assert.deepEqual(tolerated.errors, []);
  assert.deepEqual(tolerated.failures, []);
});

test("R9-RT1 a Cloudflare account id that differs from the target discards its observations", async () => {
  const { failures } = await evaluateWith({ accountId: "f".repeat(32) });
  assert.deepEqual(failures, [LINE[0], LINE[1]]);
});

test("R9-RT1 an ABO RP id that differs from the target host discards the ABO observations", async () => {
  const { failures } = await evaluateWith({ rpId: "other.example.test" });
  assert.deepEqual(failures.map(baseLine), [LINE[2], LINE[3], LINE[4], LINE[5], LINE[6], LINE[8]]);
});

test("R9-RT1 a source that returns 401 fails its conditions with a fixed reason", async () => {
  const { failures, errors } = await evaluateWith({ aboStatus: 401 });
  assert.deepEqual(errors, [{ source: "abo", reason: "http-401" }]);
  assert.ok(failures.includes(LINE[4]));
});

test("R9-RT1 a truncated paginated Cloudflare list fails as incomplete-pagination", async () => {
  const { failures, errors } = await evaluateWith({ truncateSecrets: true });
  assert.deepEqual(errors, [{ source: "cloudflare", reason: "incomplete-pagination" }]);
  assert.ok(failures.includes(LINE[1]));
});

test("R9-RT1 non-JSON, timeout and missing-Date ABO responses each fail closed with their own reason", async () => {
  assert.deepEqual((await evaluateWith({ aboNonJson: true })).errors, [{ source: "abo", reason: "non-json" }]);
  assert.deepEqual((await evaluateWith({ aboTimeout: true })).errors, [{ source: "abo", reason: "timeout" }]);
  assert.deepEqual((await evaluateWith({ aboNoDate: true })).errors, [{ source: "abo", reason: "no-date-header" }]);
});

test("R9-RT1 a backend error, malformed output, or contract mismatch fails the backend conditions", async () => {
  const failing = await acquireWith({}, {
    runPsql: async () => {
      throw Object.assign(new Error("psql failed"), { reason: "backend-error" });
    },
  });
  assert.deepEqual(failing.errors.map((item) => item.reason), ["backend-error"]);

  const malformed = await acquireWith({}, { runPsql: async () => "not json" });
  assert.deepEqual(malformed.errors, [{ source: "backend", reason: "schema-mismatch" }]);

  const mismatch = await evaluateWith({ contractVersions: { abo: 2 } });
  assert.deepEqual(mismatch.failures, [LINE[2]]);
});

test("R9-RT1 backend source refuses a database URL for another Supabase project", async () => {
  const calls = [];
  const runPsql = async (url) => {
    calls.push(url);
    return backendJson({});
  };
  const other = [
    "postgres://postgres.zyxwvutsrqponmlk@db.zyxwvutsrqponmlk.supabase.co:5432/postgres",
    "postgres://postgres.abcdefghijklmnopq@db.abcdefghijklmnopq.supabase.co:5432/postgres",
    "postgres://postgres@db.abcdefghijklmnop.supabase.co.evil.test:5432/postgres",
    "postgres://postgres@db.zyxwvutsrqponmlk.supabase.co:5432/postgres",
    "not a url",
  ];
  for (const dbUrl of other) {
    const source = sources.createBackendSource({
      env: { ...fullEnv(), LAUNCH_CHECK_DB_URL: dbUrl },
      runPsql,
    });
    await assert.rejects(source.observe(target, makeClock()), (error) => {
      assert.equal(error.source, "backend");
      assert.equal(error.reason, "target-mismatch");
      return true;
    });
  }
  assert.deepEqual(calls, [], "psql must not be invoked for a URL that names another project");
});

test("R9-RT1 backend source accepts the URL for the target project", async () => {
  const calls = [];
  const runPsql = async (url) => {
    calls.push(url);
    return backendJson({});
  };
  const byHost = sources.createBackendSource({
    env: { ...fullEnv(), LAUNCH_CHECK_DB_URL: "postgres://reader@db.abcdefghijklmnop.supabase.co:5432/postgres" },
    runPsql,
  });
  const byUser = sources.createBackendSource({
    env: { ...fullEnv(), LAUNCH_CHECK_DB_URL: "postgres://postgres.abcdefghijklmnop@localhost:5432/postgres" },
    runPsql,
  });
  assert.ok(Array.isArray(await byHost.observe(target, makeClock())));
  assert.ok(Array.isArray(await byUser.observe(target, makeClock())));
  assert.equal(calls.length, 2);
});

test("R9-RT1 a monitor check that is down or has one destination fails condition 8", async () => {
  const down = await evaluateWith({
    monitor: goodMonitorSnapshot({
      checks: [
        { stream: "abo_minute", window_seconds: 300, status: "down" },
        { stream: "platform_5min", window_seconds: 900, status: "up" },
        { stream: "abo_daily_digest", window_seconds: 93600, status: "up" },
        { stream: "audit_watcher", window_seconds: 7200, status: "up" },
      ],
    }),
  });
  assert.deepEqual(down.failures, [LINE[7]]);

  const oneDestination = await evaluateWith({
    monitor: goodMonitorSnapshot({ destinations: ["destination-a"] }),
  });
  assert.deepEqual(oneDestination.failures, [LINE[7]]);
});

test("R9-RT1 a monitor source without its URL or key is a fixed not-configured error", async () => {
  const clock = makeClock();
  const env = { ...fullEnv(), LAUNCH_CHECK_MONITOR_KEY: "" };
  const result = await acquireWith({}, { clock, env });
  assert.ok(result.errors.some((item) => item.source === "monitor" && item.reason === "not-configured"));
  assert.equal(result.calls.some((call) => call.url.startsWith("https://monitor")), false);
});

test("R9-RT1 backend launch_state keys match the live source parser", () => {
  const sql = readFileSync(MIGRATION, "utf8");
  const body = sql.match(/RETURN jsonb_build_object\(([\s\S]*?)\n  \);/u)?.[1];
  assert.ok(body, "the migration must return a jsonb_build_object");
  const sqlKeys = [...body.matchAll(/^\s*'([a-z_]+)'\s*,/gmu)].map((match) => match[1]);
  assert.deepEqual([...sqlKeys].sort(), [...BACKEND_STATE_KEYS].sort());
});

test("R9-RT1 monitor requests go only to the descriptor host", async () => {
  const clock = makeClock();
  const env = { ...fullEnv(), LAUNCH_CHECK_MONITOR_URL: "https://evil.example.net/snapshot" };
  const result = await acquireWith({}, { clock, env });
  const monitorCalls = result.calls.filter((call) => call.url.includes("/snapshot"));
  assert.equal(monitorCalls.length, 1);
  assert.equal(new URL(monitorCalls[0].url).href, `https://${target.monitor_host}/snapshot`);
  assert.equal(result.calls.some((call) => new URL(call.url).hostname === "evil.example.net"), false);
  assert.equal(result.errors.some((item) => item.source === "monitor"), false);
});

test("R9-RT1 a probe error alone fails the /control condition even when the Cloudflare route list is clean", async () => {
  const { failures, errors } = await evaluateWith({ probeStatus: 503 });
  assert.deepEqual(errors, [{ source: "probe", reason: "http-503" }]);
  assert.deepEqual(failures, [LINE[0]]);
});

test("R9-RT1 two Cloudflare route observations that disagree leave the /control condition absent", () => {
  const clock = makeClock();
  const base = { environment: target.environment, observed_at: new Date(clock.now()).toISOString(), source: "cloudflare", target_id: ACCOUNT };
  const observations = [
    { ...base, key: "control_route_cf", value: false },
    { ...base, key: "control_route_cf", value: true },
    { ...base, key: "control_route", value: false, source: "probe", target_id: target.platform_host },
  ];
  assert.ok(evaluateLive(observations, target, NOW, clock.now(), MAX_AGE_MS).includes(LINE[0]));
});

test("R9-RT1 a conflicting duplicate observation is treated as absent", () => {
  const clock = makeClock();
  const base = { environment: target.environment, observed_at: new Date(clock.now()).toISOString() };
  const observations = [
    { ...base, key: "control_route", value: false, source: "probe", target_id: target.platform_host },
    { ...base, key: "control_route", value: true, source: "cloudflare", target_id: ACCOUNT },
  ];
  assert.ok(evaluateLive(observations, target, NOW, clock.now(), MAX_AGE_MS).includes(LINE[0]));
});

test("R9-RT1 channels_version passes only when all 18 values match and are one integer", async () => {
  // All 18 equal 1: the observed value is 1 and the channels condition does not fail.
  const allOnes = await observed({}, "channels_version");
  assert.equal(allOnes.value, 1);
  assert.equal(allOnes.source, "abo");
  assert.equal(allOnes.target_id, target.ops_host);
  assert.equal((await evaluateWith()).failures.includes(LINE[2]), false);

  // A null platform map is not an object, so the value is null and the condition fails.
  const platformNull = await evaluateWith({ platformChannelVersions: null });
  assert.equal((await observed({ platformChannelVersions: null }, "channels_version")).value, null);
  assert.ok(platformNull.failures.includes(LINE[2]));

  // Both sides are 2: one distinct value 2 is observed. The launch-check rule is channels_version === 1,
  // so the condition fails on the value, not on the disagreement.
  const twos = { channelVersions: channelMap(2), platformChannelVersions: channelMap(2) };
  assert.equal((await observed(twos, "channels_version")).value, 2);
  assert.ok((await evaluateWith(twos)).failures.includes(LINE[2]));

  // One platform value of 2 among 1s: two distinct values, so the value is null.
  const onePlatformTwo = { platformChannelVersions: channelMap(1, { platformDo: 2 }) };
  assert.equal((await observed(onePlatformTwo, "channels_version")).value, null);
  assert.ok((await evaluateWith(onePlatformTwo)).failures.includes(LINE[2]));

  // A missing key on the platform side: the key set differs from CHANNEL_KEYS, so the value is null.
  const { platformDo: _dropped, ...withoutOne } = channelMap(1);
  const missingKey = { platformChannelVersions: withoutOne };
  assert.equal((await observed(missingKey, "channels_version")).value, null);
  assert.ok((await evaluateWith(missingKey)).failures.includes(LINE[2]));

  // A string value is not a safe integer, so the value is null.
  const stringValue = { channelVersions: channelMap(1, { aboClinic: "1" }) };
  assert.equal((await observed(stringValue, "channels_version")).value, null);
  assert.ok((await evaluateWith(stringValue)).failures.includes(LINE[2]));
});

test("R9-RT1 a non-object channel_versions or a wrong platform field type drops the ABO source", async () => {
  const notObject = await evaluateWith({ launchStateOverrides: { channel_versions: [1, 2, 3] } });
  assert.deepEqual(notObject.errors, [{ source: "abo", reason: "schema-mismatch" }]);
  const wrongPlatformType = await evaluateWith({ launchStateOverrides: { platform_channel_versions: "1" } });
  assert.deepEqual(wrongPlatformType.errors, [{ source: "abo", reason: "schema-mismatch" }]);
});

test("R9-RT1 channel key set matches the vendor-contracts version file", () => {
  const body = readFileSync(VERSION_FILE, "utf8").match(/export const CHANNEL_VERSIONS = \{([\s\S]*?)\} as const;/u)?.[1];
  assert.ok(body, "version.ts must export CHANNEL_VERSIONS as a literal object");
  const fileKeys = [...body.matchAll(/^\s*([A-Za-z]+):/gmu)].map((match) => match[1]);
  assert.equal(CHANNEL_KEYS.length, 9);
  assert.deepEqual([...fileKeys].sort(), [...CHANNEL_KEYS].sort());
});

test("R9-RT1 key_self_check and platform_signing_key_set need an exact boolean", async () => {
  // Exact true passes. Exact false fails its own condition.
  assert.deepEqual((await evaluateWith()).failures, []);
  const selfCheckFalse = await evaluateWith({ launchStateOverrides: { key_self_check_passes: false } });
  assert.deepEqual(selfCheckFalse.failures, [LINE[3]]);
  const signingFalse = await evaluateWith({ launchStateOverrides: { platform_signing_key_set: false } });
  assert.deepEqual(signingFalse.failures, [LINE[5]]);

  // A truthy non-boolean is a schema mismatch: the whole ABO source drops, so both conditions fail.
  for (const overrides of [
    { key_self_check_passes: "true" },
    { key_self_check_passes: 1 },
    { platform_signing_key_set: "true" },
    { platform_signing_key_set: 1 },
  ]) {
    const result = await evaluateWith({ launchStateOverrides: overrides });
    assert.deepEqual(result.errors, [{ source: "abo", reason: "schema-mismatch" }], JSON.stringify(overrides));
    assert.ok(result.failures.includes(LINE[3]), JSON.stringify(overrides));
    assert.ok(result.failures.includes(LINE[5]), JSON.stringify(overrides));
  }
});

test("R9-RT1 manual_entitle_path is false only on 404 and true on 200, 401 or 405", async () => {
  const none = await observed({}, "manual_entitle_path");
  assert.equal(none.value, false);
  assert.equal(none.source, "probe");
  assert.equal(none.target_id, target.platform_host);

  for (const code of [200, 401, 405]) {
    const onEntitle = await observed({ entitleStatus: code }, "manual_entitle_path");
    assert.equal(onEntitle.value, true, `entitle ${code} must be true`);
    const onOverride = await observed({ overrideStatus: code }, "manual_entitle_path");
    assert.equal(onOverride.value, true, `override ${code} must be true`);
    assert.ok((await evaluateWith({ entitleStatus: code })).failures.includes(LINE[0]));
  }
});

test("R9-RT1 manual_entitle_path source error on 500 fails the condition", async () => {
  for (const options of [{ entitleStatus: 500 }, { overrideStatus: 503 }]) {
    const { failures, errors } = await evaluateWith(options);
    assert.equal(errors.length, 1, JSON.stringify(options));
    assert.equal(errors[0].source, "probe");
    assert.match(errors[0].reason, /^http-5\d\d$/u);
    assert.ok(failures.includes(LINE[0]), JSON.stringify(options));
    const result = await acquireWith(options);
    assert.equal(
      result.observations.some((item) => item.key === "manual_entitle_path"),
      false,
      "no manual_entitle_path observation is produced when a probe request fails",
    );
  }
});

test("R9-RT1 manual_entitle_path probes are GET-only", async () => {
  const result = await acquireWith({});
  const probeCalls = result.calls.filter((call) => call.url.includes("/control/installations/"));
  assert.deepEqual(
    probeCalls.map((call) => call.url).sort(),
    [
      `https://${target.platform_host}/control/installations/${NIL_INSTALLATION}/entitle`,
      `https://${target.platform_host}/control/installations/${NIL_INSTALLATION}/override`,
    ].sort(),
  );
  for (const call of probeCalls) {
    assert.equal(call.method, "GET", `${call.url} must be a GET`);
  }
});

test("R9-RT1 recording fake: every request of a full acquisition is a GET to a pinned host", async () => {
  const clock = makeClock();
  const result = await acquireWith({}, { clock });
  assert.ok(result.calls.length > 0);
  for (const call of result.calls) {
    assert.equal(call.method, "GET", `${call.url} must be a GET`);
  }
  const hosts = new Set(result.calls.map((call) => new URL(call.url).hostname));
  assert.deepEqual([...hosts].sort(), [
    "api.cloudflare.com",
    "monitor.example.test",
    target.ops_host,
    target.platform_host,
  ].sort());
  assert.ok(result.calls.some((call) => call.url === `https://${target.platform_host}/control/`));
});

test("R9-RT1 the target descriptor rejects unknown fields, bad hosts and missing fields", () => {
  const raw = JSON.parse(readFileSync(targetFixture, "utf8"));
  assert.throws(() => validateTarget({ ...raw, api_token: "value" }), /unknown target field: api_token/u);
  assert.throws(() => validateTarget({ ...raw, ops_host: "https://ops.example.test" }), /ops_host/u);
  const { zone_id: _removed, ...missing } = raw;
  assert.throws(() => validateTarget(missing), /missing target field: zone_id/u);
});

test("R9-RT1 CLI spawn: live mode with no credentials exits nonzero, prints no condition, names only the variables", () => {
  const result = spawnSync(process.execPath, [launchScript, "--target", targetFixture], {
    cwd: repoRoot,
    encoding: "utf8",
    env: {},
  });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /LAUNCH_CHECK_CF_TOKEN/u);
  assert.match(result.stderr, /No result was produced/u);
});

test("R9-RT1 CLI spawn: an invalid target descriptor is rejected before any request", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "launch-live-rm35-"));
  try {
    const file = path.join(dir, "target.json");
    writeFileSync(file, JSON.stringify({ ...JSON.parse(readFileSync(targetFixture, "utf8")), api_token: "x" }));
    const result = spawnSync(process.execPath, [launchScript, "--target", file], {
      cwd: repoRoot,
      encoding: "utf8",
      env: fullEnv(),
    });
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /unknown target field: api_token/u);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("R9-RT1 CLI spawn: no evaluation mode exits nonzero and reports no result", () => {
  const result = spawnSync(process.execPath, [launchScript], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(result.status, 1);
  assert.deepEqual(result.stdout.trim(), "");
  assert.match(result.stderr, /cannot be confirmed/u);
});

test("R9-RT2 condition 8: the monitor snapshot is live only with the four D-6 windows, all up, and two destinations", () => {
  assert.deepEqual(checkMonitorSnapshot(goodMonitorSnapshot()), {
    environment: target.environment,
    live: true,
  });
  assert.equal(checkMonitorSnapshot(goodMonitorSnapshot({ destinations: ["one"] })).live, false);
  const wrongWindow = goodMonitorSnapshot();
  wrongWindow.checks[1].window_seconds = 600;
  assert.equal(checkMonitorSnapshot(wrongWindow).live, false);
  const duplicate = goodMonitorSnapshot();
  duplicate.checks[3] = { stream: "abo_minute", window_seconds: 300, status: "up" };
  assert.equal(checkMonitorSnapshot(duplicate).live, false);
  assert.equal(checkMonitorSnapshot("not an object").environment, null);
});

test("R9-RT2 condition 8: a missing stream check is not live while the other three are up", () => {
  const snapshot = goodMonitorSnapshot();
  snapshot.checks = snapshot.checks.filter((check) => check.stream !== "audit_watcher");
  assert.equal(checkMonitorSnapshot(snapshot).live, false);
});
