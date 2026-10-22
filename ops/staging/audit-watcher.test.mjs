import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

// R9-RT2 (01 §3.8 D-6): audit watcher tests. The audit API, the alert receiver and the heartbeat
// are in-process fakes. No live token is used.

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const watcherScript = path.join(here, "audit-watcher.mjs");
const targetFixture = path.join(repoRoot, "ops", "launch", "fixtures", "target-test.json");
const shippedClassTable = path.join(here, "audit-classes.json");

const watcher = await import(pathToFileURL(watcherScript).href);
const { loadTargetDescriptor } = await import(pathToFileURL(path.join(repoRoot, "ops", "launch", "target.mjs")).href);

const {
  ACQUISITION_ALERT_DEDUP_MS,
  OVERLAP_MS,
  byWhenThenId,
  lockHeldLine,
  initCursor,
  loadClassTable,
  parseClassTable,
  runWatch,
  watchedResourceIds,
  writeFileAtomic,
} = watcher;

const NOW = Date.parse("2026-10-22T12:00:00Z");
const T0 = NOW - 2 * 60 * 60 * 1000;
const MIN = 60 * 1000;
const ALERT_URL = "https://alert.example.test/ingest";
const HEARTBEAT_URL = "https://heartbeat.example.test/audit-watcher";
const TABLE = parseClassTable(
  JSON.stringify({
    entries: [
      { resource_type: "worker", action_type: "deploy", class: "deploy" },
      { resource_type: "worker", action_type: "secret_put", class: "secret" },
      { resource_type: "d1", action_type: "export", class: "d1_export" },
      { resource_type: "access_app", action_type: "edit", class: "access_policy" },
    ],
  }),
);

const target = await loadTargetDescriptor(targetFixture);
const ACCOUNT = target.cloudflare_account_id;
const WATCHED = watchedResourceIds(target);

const iso = (ms) => new Date(ms).toISOString();
const ev = (id, ms, resourceId = "abo-worker", actionType = "deploy", resourceType = "worker") => ({
  id,
  when: iso(ms),
  action: { type: actionType },
  resource: { type: resourceType, id: resourceId },
});

// 240 events, three per minute, so timestamps are shared across the page 1 / page 2 boundary.
// Every fourth event is on an unwatched worker. Every third watched event is a secret_put.
function baseDataset() {
  const events = [];
  for (let i = 0; i < 240; i += 1) {
    const when = T0 + Math.floor(i / 3) * MIN;
    const resource = i % 4 === 0 ? "unwatched-worker" : ["abo-worker", "platform-worker", "d1-test-1"][i % 3];
    const action = i % 3 === 0 ? "secret_put" : "deploy";
    const type = resource === "d1-test-1" ? "d1" : "worker";
    events.push(ev(`evt-${i}`, when, resource, action, type));
  }
  return events;
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

function jsonReply(clock, body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", date: new Date(clock.now()).toUTCString() },
  });
}

function makeAudit(clock, events, options = {}) {
  const state = { failPages: new Set(options.failPages ?? []), malformed: options.malformed ?? false };
  state.handle = (url) => {
    const page = Number(url.searchParams.get("page") ?? "1");
    const since = Date.parse(url.searchParams.get("since"));
    if (state.failPages.has(page)) {
      return new Response("error", { status: 500, headers: { date: new Date(clock.now()).toUTCString() } });
    }
    if (state.malformed) {
      return jsonReply(clock, { success: true, result: [{ id: "x" }], result_info: { total_pages: 1 } });
    }
    const all = events
      .filter((item) => Date.parse(item.when) >= since)
      .sort((a, b) => a.when.localeCompare(b.when) || a.id.localeCompare(b.id));
    const total = all.length;
    const slice = all.slice((page - 1) * 100, page * 100);
    return jsonReply(clock, {
      success: true,
      result: slice,
      result_info: { page, per_page: 100, count: slice.length, total_count: total, total_pages: Math.max(1, Math.ceil(total / 100)) },
    });
  };
  return state;
}

function makeAlerts(options = {}) {
  const state = { calls: [], options };
  state.handle = (init) => {
    const body = JSON.parse(init.body);
    const status = options.failOnEventId && body.event_id === options.failOnEventId ? 500 : 202;
    state.calls.push({ body, status });
    return new Response("", { status });
  };
  return state;
}

function world(clock, { events, audit: auditOptions, alerts: alertOptions } = {}) {
  const audit = makeAudit(clock, events ?? baseDataset(), auditOptions);
  const alerts = makeAlerts(alertOptions);
  const heartbeat = { count: 0 };
  const auditMethods = [];
  const fetchImpl = async (url, init = {}) => {
    const parsed = new URL(url);
    if (init.method === "POST") {
      return alerts.handle(init);
    }
    if (parsed.hostname === "api.cloudflare.com") {
      auditMethods.push(init.method ?? "GET");
      return audit.handle(parsed);
    }
    if (url === HEARTBEAT_URL) {
      heartbeat.count += 1;
      return new Response("", { status: 200 });
    }
    throw new Error(`unexpected request to ${url}`);
  };
  return { audit, alerts, heartbeat, auditMethods, fetchImpl };
}

function setup() {
  const dir = mkdtempSync(path.join(tmpdir(), "audit-watcher-rm35-"));
  return { dir, statePath: path.join(dir, "audit-state.json"), cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

function opts(env, clock, fetchImpl, statePath, table = TABLE, watched = WATCHED) {
  return {
    statePath,
    accountId: ACCOUNT,
    readToken: "read-test-token",
    alertUrl: ALERT_URL,
    heartbeatUrl: HEARTBEAT_URL,
    table,
    watched,
    fetchImpl,
    clock,
    overlapMs: OVERLAP_MS,
    ...env,
  };
}

function readJson(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

function initState(statePath, sinceMs, clock) {
  initCursor({ statePath, accountId: ACCOUNT, sinceIso: iso(sinceMs), nowMs: clock.now() });
}

function successfulDeliveries(alerts) {
  const counts = new Map();
  for (const call of alerts.calls) {
    if (call.status >= 200 && call.status < 300) {
      counts.set(call.body.event_id, (counts.get(call.body.event_id) ?? 0) + 1);
    }
  }
  return counts;
}

test("R9-RT2 paged audit read delivers each watched event once across shared boundaries and sends one heartbeat", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const w = world(clock);
    initState(s.statePath, T0 - 60 * MIN, clock);
    const result = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(result.status, "ok");
    assert.ok(w.auditMethods.length >= 3, "several pages were read");

    const expected = baseDataset().filter((item) => WATCHED.has(item.resource.id));
    assert.equal(w.alerts.calls.length, expected.length);
    assert.deepEqual(
      w.alerts.calls.map((call) => call.body.event_id).sort(),
      expected.map((item) => item.id).sort(),
      "no watched event was missed or duplicated, and no unwatched event alerted",
    );
    assert.equal(w.heartbeat.count, 1);
    assert.equal(readJson(s.statePath).cursor.since, iso(T0 + 79 * MIN));
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 a late event inside the overlap window is delivered on the next run", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const events = baseDataset();
    const w = world(clock, { events });
    initState(s.statePath, T0 - 60 * MIN, clock);
    await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    const before = w.alerts.calls.length;

    events.push(ev("late-1", T0 + 75 * MIN, "abo-worker", "deploy"));
    clock.set(NOW + 5 * MIN);
    const second = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(second.status, "ok");
    assert.equal(w.alerts.calls.length, before + 1);
    assert.equal(w.alerts.calls[w.alerts.calls.length - 1].body.event_id, "late-1");
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 an alert failure on the Nth call loses no event and duplicates none on retry", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const events = ["a", "b", "c", "d", "e"].map((id, index) => ev(id, T0 + (index + 1) * MIN));
    const w = world(clock, { events, alerts: { failOnEventId: "c" } });
    initState(s.statePath, T0, clock);
    const first = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.deepEqual([first.status, first.reason], ["failed", "delivery"]);
    assert.equal(w.heartbeat.count, 0, "no heartbeat after a delivery failure");
    assert.equal(readJson(s.statePath).cursor.since, iso(T0), "the cursor did not move past the unacknowledged page");

    w.alerts.options.failOnEventId = undefined;
    const second = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(second.status, "ok");
    const counts = successfulDeliveries(w.alerts);
    assert.deepEqual([...counts.keys()].sort(), ["a", "b", "c", "d", "e"]);
    for (const [id, count] of counts) {
      assert.equal(count, 1, `event ${id} delivered exactly once`);
    }
    assert.equal(w.heartbeat.count, 1);
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 the cursor never passes an unacknowledged event on a later page", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const events = baseDataset();
    const failEvent = "evt-202";
    const failingWorld = world(clock, { events, alerts: { failOnEventId: failEvent } });
    initState(s.statePath, T0 - 60 * MIN, clock);
    const first = await runWatch(opts({}, clock, failingWorld.fetchImpl, s.statePath));
    assert.equal(first.status, "failed");
    const failing = events.find((item) => item.id === failEvent);
    const cursor = readJson(s.statePath).cursor;
    assert.ok(Date.parse(cursor.since) < Date.parse(failing.when), "cursor stays before the failed event's time");
    assert.equal(failingWorld.heartbeat.count, 0);

    failingWorld.alerts.options.failOnEventId = undefined;
    const second = await runWatch(opts({}, clock, failingWorld.fetchImpl, s.statePath));
    assert.equal(second.status, "ok");
    const counts = successfulDeliveries(failingWorld.alerts);
    for (const item of events.filter((candidate) => WATCHED.has(candidate.resource.id))) {
      assert.equal(counts.get(item.id), 1, `${item.id} delivered exactly once`);
    }
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 a crash after an event is delivered but before it is recorded re-sends that event exactly once", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const events = ["a", "b", "c"].map((id, index) => ev(id, T0 + (index + 1) * MIN));
    const w = world(clock, { events });
    let armed = true;
    const crashingHooks = {
      beforeRename: (text) => {
        const parsed = JSON.parse(text);
        if (armed && parsed.events?.b?.state === "delivered") {
          armed = false;
          throw new Error("power loss");
        }
      },
    };
    initState(s.statePath, T0, clock);
    await assert.rejects(
      runWatch({ ...opts({}, clock, w.fetchImpl, s.statePath), hooks: crashingHooks }),
      /power loss/u,
    );
    assert.equal(readJson(s.statePath).events.b.state, "sending", "the crash left the event in sending");

    const second = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(second.status, "ok");
    const posts = new Map();
    for (const call of w.alerts.calls) {
      posts.set(call.body.event_id, (posts.get(call.body.event_id) ?? 0) + 1);
    }
    assert.equal(posts.get("b"), 2, "b was sent once before the crash and once on retry");
    assert.equal(posts.get("a"), 1);
    assert.equal(posts.get("c"), 1);
    assert.equal(readJson(s.statePath).events.b.state, "delivered");
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 an atomic state write leaves the previous file intact when a fault hits before the rename", () => {
  const s = setup();
  try {
    writeFileAtomic(s.statePath, "version-1\n");
    assert.throws(
      () =>
        writeFileAtomic(s.statePath, "version-2\n", {
          beforeRename: () => {
            throw new Error("injected fault");
          },
        }),
      /injected fault/u,
    );
    assert.equal(readFileSync(s.statePath, "utf8"), "version-1\n");
    assert.deepEqual(readdirSync(s.dir).filter((name) => name.includes(".tmp-")), []);

    assert.throws(
      () =>
        writeFileAtomic(s.statePath, "version-3\n", {
          beforeFsync: () => {
            throw new Error("fsync fault");
          },
        }),
      /fsync fault/u,
    );
    assert.equal(readFileSync(s.statePath, "utf8"), "version-1\n");
    assert.deepEqual(readdirSync(s.dir).filter((name) => name.includes(".tmp-")), []);
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 an exclusive lockfile refuses a concurrent run before any read or send", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const w = world(clock);
    initState(s.statePath, T0, clock);
    writeFileSync(`${s.statePath}.lock`, "99999\n");
    const result = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.deepEqual(result, { status: "refused", reason: "locked" });
    assert.equal(w.auditMethods.length, 0);
    assert.equal(w.alerts.calls.length, 0);
    assert.equal(w.heartbeat.count, 0);
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 a missing or corrupt state file refuses, alerts, and reads nothing; --init-cursor then starts it", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const w = world(clock);
    const missing = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.deepEqual(missing, { status: "refused", reason: "state-missing" });
    assert.equal(w.auditMethods.length, 0);
    assert.equal(w.alerts.calls.length, 1);
    assert.equal(w.alerts.calls[0].body.reason, "state-missing");

    writeFileSync(s.statePath, "{not json");
    const corrupt = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.deepEqual(corrupt, { status: "refused", reason: "state-corrupt" });
    assert.equal(w.auditMethods.length, 0);

    initCursor({ statePath: s.statePath, accountId: ACCOUNT, sinceIso: iso(T0), nowMs: clock.now() });
    assert.ok(existsSync(`${s.statePath}.corrupt-${clock.now()}`), "the corrupt file was kept for forensics");
    const ok = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(ok.status, "ok");
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 a state file that belongs to another account is refused", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const w = world(clock);
    writeFileSync(
      s.statePath,
      JSON.stringify({
        version: 1,
        account_id: "f".repeat(32),
        cursor: { since: iso(T0), boundary_ids: [] },
        events: {},
        last_acquisition_alert_at: null,
      }),
    );
    const result = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.deepEqual(result, { status: "refused", reason: "state-account-mismatch" });
    assert.equal(w.auditMethods.length, 0);
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 --init-cursor never overwrites a valid state file", () => {
  const s = setup();
  try {
    const clock = makeClock();
    initState(s.statePath, T0, clock);
    assert.throws(
      () => initCursor({ statePath: s.statePath, accountId: ACCOUNT, sinceIso: iso(NOW), nowMs: clock.now() }),
      (error) => error.reason === "state-exists",
    );
    assert.equal(readJson(s.statePath).cursor.since, iso(T0));
    assert.throws(
      () => initCursor({ statePath: s.statePath, accountId: ACCOUNT, sinceIso: "yesterday", nowMs: clock.now() }),
      (error) => error.reason === "init-arg",
    );
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 an audit read failure alerts at most once per hour and never sends a heartbeat", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const w = world(clock, { audit: { failPages: [1] } });
    initState(s.statePath, T0, clock);
    const first = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(first.status, "failed");
    assert.equal(first.reason, "http-500");
    assert.equal(w.alerts.calls.length, 1);
    assert.equal(w.alerts.calls[0].body.reason, "audit-acquisition");
    assert.equal(w.heartbeat.count, 0);

    clock.set(NOW + 10 * MIN);
    await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(w.alerts.calls.length, 1, "a second failure inside the hour is not re-alerted");

    clock.set(NOW + ACQUISITION_ALERT_DEDUP_MS + MIN);
    await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(w.alerts.calls.length, 2, "one more alert after the hour");
    assert.equal(w.heartbeat.count, 0);
    assert.equal(readJson(s.statePath).cursor.since, iso(T0), "the cursor did not advance on acquisition failure");
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 a malformed audit page is an acquisition failure with no heartbeat", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const w = world(clock, { audit: { malformed: true } });
    initState(s.statePath, T0, clock);
    const result = await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.equal(result.status, "failed");
    assert.equal(w.alerts.calls[0].body.reason, "audit-acquisition");
    assert.equal(w.heartbeat.count, 0);
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 an unmapped action on a watched resource raises an unclassified alert", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const events = [ev("u-1", T0 + MIN, "abo-worker", "secret_put")];
    const w = world(clock, { events });
    const deployOnly = parseClassTable(
      JSON.stringify({ entries: [{ resource_type: "worker", action_type: "deploy", class: "deploy" }] }),
    );
    initState(s.statePath, T0, clock);
    const result = await runWatch(opts({}, clock, w.fetchImpl, s.statePath, deployOnly));
    assert.equal(result.status, "ok");
    assert.equal(w.alerts.calls.length, 1);
    assert.equal(w.alerts.calls[0].body.reason, "unclassified");
    assert.equal(w.alerts.calls[0].body.class, "unclassified");
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 the class table loader fails closed while the shipped table is empty", () => {
  assert.throws(() => loadClassTable(shippedClassTable), /class table is empty/u);
  assert.throws(() => parseClassTable(JSON.stringify({ entries: [] })), /class table is empty/u);
  assert.throws(() => parseClassTable(JSON.stringify({ entries: [{ resource_type: "x", action_type: "y", class: "other" }] })), /not valid/u);
  assert.equal(parseClassTable(JSON.stringify({ entries: [{ resource_type: "a", action_type: "b", class: "deploy" }] })).length, 1);
});

test("R9-RT2 every audit read is a GET", async () => {
  const s = setup();
  try {
    const clock = makeClock();
    const w = world(clock);
    initState(s.statePath, T0 - 60 * MIN, clock);
    await runWatch(opts({}, clock, w.fetchImpl, s.statePath));
    assert.ok(w.auditMethods.length > 0);
    assert.ok(w.auditMethods.every((method) => method === "GET"));
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 CLI spawn: live mode without the read token exits 1 and names only the variables", () => {
  const s = setup();
  try {
    const result = spawnSync(
      process.execPath,
      [watcherScript, "--state", s.statePath, "--target", targetFixture],
      { cwd: repoRoot, encoding: "utf8", env: {} },
    );
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /AUDIT_READ_TOKEN/u);
    assert.equal(existsSync(s.statePath), false);
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 CLI spawn: the shipped empty class table stops the live run before any state or network use", () => {
  const s = setup();
  try {
    const result = spawnSync(
      process.execPath,
      [watcherScript, "--state", s.statePath, "--target", targetFixture],
      {
        cwd: repoRoot,
        encoding: "utf8",
        env: {
          AUDIT_READ_TOKEN: "read-test-token",
          AUDIT_ALERT_URL: ALERT_URL,
          AUDIT_HEARTBEAT_URL: HEARTBEAT_URL,
        },
      },
    );
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /class table is empty/u);
    assert.equal(existsSync(s.statePath), false);
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 CLI spawn: --init-cursor rejects a non-ISO time and creates the cursor for a valid one", () => {
  const s = setup();
  try {
    const env = { AUDIT_READ_TOKEN: "read-test-token", AUDIT_ALERT_URL: ALERT_URL, AUDIT_HEARTBEAT_URL: HEARTBEAT_URL };
    const bad = spawnSync(
      process.execPath,
      [watcherScript, "--state", s.statePath, "--target", targetFixture, "--init-cursor", "yesterday"],
      { cwd: repoRoot, encoding: "utf8", env },
    );
    assert.equal(bad.status, 1);
    assert.equal(existsSync(s.statePath), false);

    const good = spawnSync(
      process.execPath,
      [watcherScript, "--state", s.statePath, "--target", targetFixture, "--init-cursor", iso(T0)],
      { cwd: repoRoot, encoding: "utf8", env },
    );
    assert.equal(good.status, 0, good.stderr);
    const state = readJson(s.statePath);
    assert.equal(state.account_id, ACCOUNT);
    assert.equal(state.cursor.since, iso(T0));
  } finally {
    s.cleanup();
  }
});

test("R9-RT2 stale lockfile refuses with an operator instruction", async () => {
  const s = setup();
  const errors = [];
  const originalError = console.error;
  try {
    const clock = makeClock();
    const w = world(clock);
    initState(s.statePath, T0, clock);
    const lockPath = `${s.statePath}.lock`;
    writeFileSync(lockPath, "99999\n");
    const classTableFile = path.join(s.dir, "classes.json");
    writeFileSync(classTableFile, JSON.stringify({
      entries: [
        { resource_type: "worker", action_type: "deploy", class: "deploy" },
        { resource_type: "worker", action_type: "secret_put", class: "secret" },
        { resource_type: "d1", action_type: "export", class: "d1_export" },
        { resource_type: "access_app", action_type: "edit", class: "access_policy" },
      ],
    }));
    console.error = (...args) => errors.push(args.join(" "));
    const code = await watcher.runCli(["--state", s.statePath, "--target", targetFixture], {
      env: { AUDIT_READ_TOKEN: "read-test-token", AUDIT_ALERT_URL: ALERT_URL, AUDIT_HEARTBEAT_URL: HEARTBEAT_URL },
      fetchImpl: w.fetchImpl,
      clock,
      classTableFile,
    });
    assert.equal(code, 1);
    assert.deepEqual(errors, [`lock-held: remove ${lockPath} after confirming no run is active`]);
    assert.equal(errors[0], lockHeldLine(lockPath));
    assert.equal(w.auditMethods.length, 0);
    assert.equal(existsSync(lockPath), true, "the watcher must not remove a lock it did not create");
  } finally {
    console.error = originalError;
    s.cleanup();
  }
});

test("R9-RT2 same-second events order by parsed time then id", () => {
  const events = [
    { id: "b", when: "2026-10-22T12:00:00.5Z" },
    { id: "a2", when: "2026-10-22T12:00:00Z" },
    { id: "c", when: "2026-10-22T12:00:00.25Z" },
    { id: "a", when: "2026-10-22T12:00:00Z" },
    { id: "d", when: "2026-10-22T12:00:01Z" },
  ];
  assert.deepEqual(
    [...events].sort(byWhenThenId).map((event) => event.id),
    ["a", "a2", "c", "b", "d"],
  );
});

test("R9-RT2 the positional offline classifier still prints AL-21 per class event of a supplied fixture", () => {
  const result = spawnSync(process.execPath, [watcherScript, path.join(here, "fixtures", "deploy-and-secret.json")], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim(), "AL-21\nAL-21");
});
