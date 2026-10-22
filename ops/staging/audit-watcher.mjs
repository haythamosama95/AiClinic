import { closeSync, existsSync, fsyncSync, openSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { httpGet, REQUEST_TIMEOUT_MS, SourceError, schemaError } from "../launch/live-http.mjs";
import { loadTargetDescriptor } from "../launch/target.mjs";

// R9-RT2 (01 §3.8 D-6, 02 §5): the outside-account audit watcher.
// Live mode (`--state <file> --target <file>`), run hourly by the external scheduler:
// - reads Cloudflare audit logs with the K-10 read-only token (GET only), paging from
//   `since - OVERLAP` in ascending order;
// - keeps a state file (cursor, per-event state, 7-day retention) written atomically under an
//   exclusive lockfile;
// - sends each matched event to the monitor's own alert channel with a `sending` mark before the
//   POST, and marks it `delivered` only after a 2xx; the cursor advances only past pages whose
//   events are all acknowledged;
// - sends a heartbeat only after a fully successful run.
// The positional form `audit-watcher.mjs <fixture>` remains the offline classifier of a supplied
// event list. It never reads the token and never reports a live result.

export const OVERLAP_MS = 15 * 60 * 1000;
export const RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
export const ACQUISITION_ALERT_DEDUP_MS = 60 * 60 * 1000;
export const CLASSES = Object.freeze(["deploy", "secret", "d1_export", "access_policy"]);
export const UNCLASSIFIED = "unclassified";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_CLASS_TABLE = path.join(HERE, "audit-classes.json");
const CF_API_BASE = "https://api.cloudflare.com/client/v4";
const PAGE_SIZE = 100;
const MAX_PAGES = 1000;
const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/u;
const OFFLINE_CLASSES = new Set(CLASSES);

export class WatcherError extends Error {
  constructor(message, reason) {
    super(message);
    this.name = "WatcherError";
    this.reason = reason;
  }
}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const isIso = (value) => typeof value === "string" && ISO_UTC.test(value) && Number.isFinite(Date.parse(value));

// ---- class table ----------------------------------------------------------------------------

export function parseClassTable(text) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new WatcherError("class table is not valid JSON", "class-table");
  }
  if (!isObject(parsed) || !Array.isArray(parsed.entries)) {
    throw new WatcherError("class table has no entries list", "class-table");
  }
  const entries = parsed.entries.map((entry) => {
    if (
      !isObject(entry) ||
      typeof entry.resource_type !== "string" ||
      typeof entry.action_type !== "string" ||
      !CLASSES.includes(entry.class)
    ) {
      throw new WatcherError("class table entry is not valid", "class-table");
    }
    return Object.freeze({
      resource_type: entry.resource_type,
      action_type: entry.action_type,
      class: entry.class,
    });
  });
  if (entries.length === 0) {
    throw new WatcherError(
      "class table is empty: the audit watcher fails closed until the staging capture fills ops/staging/audit-classes.json",
      "class-table-empty",
    );
  }
  return Object.freeze(entries);
}

export function loadClassTable(file = DEFAULT_CLASS_TABLE) {
  return parseClassTable(readFileSync(file, "utf8"));
}

export function classifyEvent(event, table) {
  const hit = table.find(
    (entry) => entry.resource_type === event.resource_type && entry.action_type === event.action_type,
  );
  return hit === undefined ? UNCLASSIFIED : hit.class;
}

export function watchedResourceIds(target) {
  return new Set([...target.script_names, ...target.d1_database_ids, ...target.access_app_ids]);
}

// ---- atomic state file and lock -----------------------------------------------------------

// Temporary file, fsync, rename. A fault before the rename leaves the previous file intact.
export function writeFileAtomic(file, text, hooks = {}) {
  const tmp = `${file}.tmp-${process.pid}`;
  let fd;
  try {
    fd = openSync(tmp, "w");
    writeFileSync(fd, text);
    hooks.beforeFsync?.();
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    hooks.beforeRename?.(text);
    renameSync(tmp, file);
  } catch (error) {
    if (fd !== undefined) {
      try {
        closeSync(fd);
      } catch {
        // The original error is more useful than a close failure.
      }
    }
    try {
      unlinkSync(tmp);
    } catch {
      // Nothing to remove.
    }
    throw error;
  }
  try {
    const dirFd = openSync(path.dirname(file), "r");
    try {
      fsyncSync(dirFd);
    } finally {
      closeSync(dirFd);
    }
  } catch {
    // Directory fsync is best effort on platforms that do not support it.
  }
}

// The fixed operator instruction for a held lock. A stale lockfile (no run active) refuses every
// run until an operator removes it, so the instruction is printed on stderr with a nonzero exit.
export function lockHeldLine(lockPath) {
  return `lock-held: remove ${lockPath} after confirming no run is active`;
}

export function acquireLock(lockPath) {
  let fd;
  try {
    fd = openSync(lockPath, "wx");
  } catch (error) {
    if (error.code === "EEXIST") {
      const held = new WatcherError("another audit watcher run holds the lock", "locked");
      held.lockPath = lockPath;
      throw held;
    }
    throw error;
  }
  try {
    writeFileSync(fd, `${process.pid}\n`);
  } finally {
    closeSync(fd);
  }
  return () => {
    try {
      unlinkSync(lockPath);
    } catch {
      // Already removed.
    }
  };
}

function validateState(state, accountId) {
  if (!isObject(state) || state.version !== 1) {
    throw new WatcherError("state file is corrupt", "state-corrupt");
  }
  if (state.account_id !== accountId) {
    throw new WatcherError("state file belongs to another account", "state-account-mismatch");
  }
  const cursor = state.cursor;
  if (
    !isObject(cursor) ||
    !isIso(cursor.since) ||
    !Array.isArray(cursor.boundary_ids) ||
    !cursor.boundary_ids.every((id) => typeof id === "string") ||
    !isObject(state.events) ||
    (state.last_acquisition_alert_at !== null && state.last_acquisition_alert_at !== undefined && !isIso(state.last_acquisition_alert_at))
  ) {
    throw new WatcherError("state file is corrupt", "state-corrupt");
  }
  for (const entry of Object.values(state.events)) {
    if (!isObject(entry) || !["sending", "delivered"].includes(entry.state) || !isIso(entry.at)) {
      throw new WatcherError("state file is corrupt", "state-corrupt");
    }
  }
  return state;
}

// Returns null when the file is missing. Throws WatcherError when it is corrupt or belongs to another account.
export function readState(file, accountId) {
  if (!existsSync(file)) {
    return null;
  }
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(file, "utf8"));
  } catch {
    throw new WatcherError("state file is corrupt", "state-corrupt");
  }
  return validateState(parsed, accountId);
}

function emptyState(accountId, sinceIso) {
  return {
    version: 1,
    account_id: accountId,
    cursor: { since: sinceIso, boundary_ids: [] },
    events: {},
    last_acquisition_alert_at: null,
  };
}

const serialize = (state) => `${JSON.stringify(state, null, 2)}\n`;

// Operator action: the only way to start a cursor. A valid existing state is never overwritten. A
// corrupt or wrong-account file is moved aside for forensics first.
export function initCursor({ statePath, lockPath = `${statePath}.lock`, accountId, sinceIso, nowMs, hooks }) {
  if (!isIso(sinceIso)) {
    throw new WatcherError("--init-cursor requires an ISO-8601 UTC time", "init-arg");
  }
  const release = acquireLock(lockPath);
  try {
    try {
      if (readState(statePath, accountId) !== null) {
        throw new WatcherError("state file is valid; refusing to re-initialize the cursor", "state-exists");
      }
    } catch (error) {
      if (!(error instanceof WatcherError) || error.reason === "state-exists") {
        throw error;
      }
      renameSync(statePath, `${statePath}.corrupt-${nowMs}`);
    }
    writeFileAtomic(statePath, serialize(emptyState(accountId, sinceIso)), hooks);
  } finally {
    release();
  }
}

// ---- audit API read (GET only) -------------------------------------------------------------

function parseEvent(raw) {
  if (
    !isObject(raw) ||
    typeof raw.id !== "string" ||
    raw.id.length === 0 ||
    !isIso(raw.when) ||
    !isObject(raw.action) ||
    typeof raw.action.type !== "string" ||
    !isObject(raw.resource) ||
    typeof raw.resource.type !== "string" ||
    typeof raw.resource.id !== "string"
  ) {
    throw new SourceError("audit", "malformed-event");
  }
  return Object.freeze({
    id: raw.id,
    when: raw.when,
    action_type: raw.action.type,
    resource_type: raw.resource.type,
    resource_id: raw.resource.id,
  });
}

async function readPage({ fetchImpl, clock, readToken, accountId, fromIso, page }) {
  const url =
    `${CF_API_BASE}/accounts/${accountId}/audit_logs` +
    `?since=${encodeURIComponent(fromIso)}&direction=asc&per_page=${PAGE_SIZE}&page=${page}`;
  const { body } = await httpGet({
    source: "audit",
    fetchImpl,
    url,
    headers: { authorization: `Bearer ${readToken}` },
    clock,
  });
  if (!isObject(body) || body.success !== true || !Array.isArray(body.result)) {
    throw schemaError("audit");
  }
  const events = body.result.map(parseEvent);
  const info = body.result_info;
  let hasMore;
  if (info === undefined) {
    hasMore = body.result.length === PAGE_SIZE;
  } else if (isObject(info) && Number.isSafeInteger(info.total_pages)) {
    hasMore = page < info.total_pages;
  } else {
    throw schemaError("audit");
  }
  return { events, hasMore };
}

// ---- alert channel and heartbeat ----------------------------------------------------------

// Codes and ids only (TB-9). Returns true only for a 2xx answer from the monitor's alert input.
async function postAlert(fetchImpl, url, body) {
  try {
    const response = await fetchImpl(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      redirect: "error",
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    return response.status >= 200 && response.status < 300;
  } catch {
    return false;
  }
}

async function pingHeartbeat(fetchImpl, url) {
  try {
    const response = await fetchImpl(url, {
      method: "GET",
      redirect: "error",
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    return response.status >= 200 && response.status < 300;
  } catch {
    return false;
  }
}

// ---- the run ------------------------------------------------------------------------------

// Orders by the parsed instant, then by id. Numeric time order avoids locale collation on ISO strings
// whose fractional-second lengths differ.
export const byWhenThenId = (a, b) => {
  const delta = Date.parse(a.when) - Date.parse(b.when);
  if (delta !== 0) {
    return delta;
  }
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
};

function pruneEvents(state, nowMs) {
  for (const [id, entry] of Object.entries(state.events)) {
    if (nowMs - Date.parse(entry.at) > RETENTION_MS) {
      delete state.events[id];
    }
  }
}

export async function runWatch({
  statePath,
  lockPath = `${statePath}.lock`,
  accountId,
  readToken,
  alertUrl,
  heartbeatUrl,
  table,
  watched,
  fetchImpl = globalThis.fetch,
  clock,
  overlapMs = OVERLAP_MS,
  hooks = {},
}) {
  let release;
  try {
    release = acquireLock(lockPath);
  } catch (error) {
    if (error instanceof WatcherError) {
      return { status: "refused", reason: error.reason };
    }
    throw error;
  }

  try {
    const nowIso = () => new Date(clock.now()).toISOString();
    const post = (body) => postAlert(fetchImpl, alertUrl, body);
    const persist = (state) => writeFileAtomic(statePath, serialize(state), hooks);

    let state;
    try {
      state = readState(statePath, accountId);
    } catch (error) {
      if (!(error instanceof WatcherError)) {
        throw error;
      }
      await post({ code: "AL-21", reason: "state-invalid" });
      return { status: "refused", reason: error.reason };
    }
    if (state === null) {
      await post({ code: "AL-21", reason: "state-missing" });
      return { status: "refused", reason: "state-missing" };
    }

    pruneEvents(state, clock.now());
    const fromIso = new Date(Date.parse(state.cursor.since) - overlapMs).toISOString();

    // Acquisition failure: no cursor change beyond acknowledged pages, no heartbeat, and at most one
    // audit-acquisition alert per hour.
    const acquisitionFailure = async (reason) => {
      const last = state.last_acquisition_alert_at;
      if (!last || clock.now() - Date.parse(last) >= ACQUISITION_ALERT_DEDUP_MS) {
        if (await post({ code: "AL-21", reason: "audit-acquisition" })) {
          state.last_acquisition_alert_at = nowIso();
        }
      }
      persist(state);
      return { status: "failed", reason };
    };

    for (let page = 1; ; page += 1) {
      if (page > MAX_PAGES) {
        return acquisitionFailure("incomplete-pagination");
      }
      let result;
      try {
        result = await readPage({ fetchImpl, clock, readToken, accountId, fromIso, page });
      } catch (error) {
        return acquisitionFailure(error?.reason ?? "audit-read");
      }

      const events = [...result.events].sort(byWhenThenId);
      for (const event of events) {
        if (!watched.has(event.resource_id)) {
          continue;
        }
        if (event.when === state.cursor.since && state.cursor.boundary_ids.includes(event.id)) {
          continue;
        }
        const prior = state.events[event.id];
        if (prior?.state === "delivered") {
          continue;
        }
        // Covers a fresh event and a `sending` event left by a crash: the event is sent again once.
        const cls = classifyEvent(event, table);
        state.events[event.id] = { state: "sending", at: nowIso(), class: cls };
        persist(state);
        const sent = await post({
          code: "AL-21",
          reason: cls === UNCLASSIFIED ? "unclassified" : "matched",
          class: cls,
          event_id: event.id,
        });
        if (!sent) {
          return { status: "failed", reason: "delivery" };
        }
        state.events[event.id] = { state: "delivered", at: nowIso(), class: cls };
        persist(state);
      }

      if (events.length > 0) {
        const maxWhen = events[events.length - 1].when;
        const boundaryIds = events.filter((event) => event.when === maxWhen).map((event) => event.id);
        const maxMs = Date.parse(maxWhen);
        const sinceMs = Date.parse(state.cursor.since);
        if (maxMs > sinceMs) {
          state.cursor = { since: maxWhen, boundary_ids: boundaryIds };
          persist(state);
        } else if (maxMs === sinceMs) {
          state.cursor = {
            since: state.cursor.since,
            boundary_ids: [...new Set([...state.cursor.boundary_ids, ...boundaryIds])],
          };
          persist(state);
        }
      }

      if (!result.hasMore) {
        break;
      }
    }

    persist(state);
    if (await pingHeartbeat(fetchImpl, heartbeatUrl)) {
      return { status: "ok" };
    }
    return { status: "failed", reason: "heartbeat" };
  } finally {
    release();
  }
}

// ---- offline classifier (positional fixture) -----------------------------------------------

async function runOfflineClassification(fixturePath) {
  const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
  const events = fixture.events ?? [];
  for (const event of events) {
    if (OFFLINE_CLASSES.has(event.class)) {
      console.log("AL-21");
    }
  }
  console.error("audit-watcher offline classification of a supplied event list; live acquisition needs --state and --target (01 §3.8 D-6).");
  return 0;
}

export async function runCli(argv, { env = process.env, fetchImpl = globalThis.fetch, clock = { now: () => Date.now() }, classTableFile } = {}) {
  try {
    if (argv.length > 0 && !argv[0].startsWith("--")) {
      return await runOfflineClassification(argv[0]);
    }

    const flags = {};
    for (let index = 0; index < argv.length; index += 2) {
      const name = argv[index];
      if (!["--state", "--target", "--init-cursor"].includes(name) || argv[index + 1] === undefined) {
        console.error("usage: audit-watcher.mjs --state <file> --target <file> [--init-cursor <ISO>]");
        return 1;
      }
      flags[name] = argv[index + 1];
    }
    if (!flags["--state"] || !flags["--target"]) {
      console.error("usage: audit-watcher.mjs --state <file> --target <file> [--init-cursor <ISO>]");
      return 1;
    }

    const missing = ["AUDIT_READ_TOKEN", "AUDIT_ALERT_URL", "AUDIT_HEARTBEAT_URL"].filter(
      (name) => typeof env[name] !== "string" || env[name].length === 0,
    );
    if (missing.length > 0) {
      console.error(`audit-watcher: missing environment variables: ${missing.join(", ")}. No run was made.`);
      return 1;
    }

    const target = await loadTargetDescriptor(flags["--target"]);
    const accountId = target.cloudflare_account_id;
    const statePath = flags["--state"];

    if (flags["--init-cursor"] !== undefined) {
      initCursor({ statePath, accountId, sinceIso: flags["--init-cursor"], nowMs: clock.now() });
      console.error("audit-watcher: cursor initialized. Run again without --init-cursor to poll.");
      return 0;
    }

    const table = loadClassTable(classTableFile);
    const result = await runWatch({
      statePath,
      accountId,
      readToken: env.AUDIT_READ_TOKEN,
      alertUrl: env.AUDIT_ALERT_URL,
      heartbeatUrl: env.AUDIT_HEARTBEAT_URL,
      table,
      watched: watchedResourceIds(target),
      fetchImpl,
      clock,
    });
    if (result.reason === "locked") {
      console.error(lockHeldLine(`${statePath}.lock`));
      return 1;
    }
    console.error(`audit-watcher: ${result.status}${result.reason ? ` (${result.reason})` : ""}`);
    return result.status === "ok" ? 0 : 1;
  } catch (error) {
    if (error instanceof WatcherError && error.reason === "locked") {
      console.error(lockHeldLine(error.lockPath));
      return 1;
    }
    console.error(`audit-watcher: ${error instanceof Error ? error.message : "run failed"}`);
    return 1;
  }
}

const isMain = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  runCli(process.argv.slice(2)).then(
    (code) => process.exit(code),
    () => process.exit(1),
  );
}
