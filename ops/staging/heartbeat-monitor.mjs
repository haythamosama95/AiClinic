import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

// R9-RT2 (01 §3.8 D-6, 02 §5): one dead-man's-switch check per stream. Each producer pings its own
// configured URL, so no stream can refresh another:
// - abo_minute: abo/src/worker.ts minute cron, HEARTBEAT_URL_MINUTE (5-minute window)
// - platform_5min: ai-platform/src/alert/index.ts pingPlatformHeartbeat, HEARTBEAT_URL_PLATFORM (15 minutes)
// - abo_daily_digest: abo/src/worker.ts digest hook, HEARTBEAT_URL_DIGEST (26 hours)
// - audit_watcher: the outside-account audit-log watcher (2 hours)
// The live monitor is external. This file classifies a supplied snapshot of per-stream last_seen
// times against the current UTC time. A replayed or stale snapshot therefore cannot show health.

export const STREAM_WINDOWS_MS = Object.freeze({
  abo_minute: 5 * 60 * 1000,
  platform_5min: 15 * 60 * 1000,
  abo_daily_digest: 26 * 60 * 60 * 1000,
  audit_watcher: 2 * 60 * 60 * 1000,
});

const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/u;

// Returns the streams that are absent, malformed, in the future, or older than their window.
// Each of those fails closed to AL-21.
export function classifyStreams(lastSeen, nowMs) {
  const missing = [];
  for (const [stream, windowMs] of Object.entries(STREAM_WINDOWS_MS)) {
    const raw = lastSeen && typeof lastSeen === "object" ? lastSeen[stream] : undefined;
    if (typeof raw !== "string" || !ISO_UTC.test(raw)) {
      missing.push(stream);
      continue;
    }
    const seenMs = Date.parse(raw);
    if (!Number.isFinite(seenMs) || seenMs > nowMs || nowMs - seenMs > windowMs) {
      missing.push(stream);
    }
  }
  return missing;
}

// R9-RT2 live check for launch-check condition 8 (01 §3.8 D-6). The external dead-man's-switch
// monitor is not chosen in the repository, so this function is the adapter contract only. The
// monitor client (ops/launch/live-sources.mjs) GETs a snapshot of the form
//   { environment, checks: [{ stream, window_seconds, status }], destinations: [string] }
// and this function accepts it only when:
// - each of the four streams appears exactly once with its D-6 window, and every check is "up";
// - at least two distinct destinations are configured on the monitor's own channel.
// Anything else (missing check, wrong window, down status, one destination, malformed body) is not live.
export const MONITOR_MIN_DESTINATIONS = 2;

export function checkMonitorSnapshot(snapshot) {
  const notLive = { environment: null, live: false };
  if (snapshot === null || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    return notLive;
  }
  const environment = typeof snapshot.environment === "string" ? snapshot.environment : null;
  if (environment === null || environment.length === 0) {
    return notLive;
  }
  if (!Array.isArray(snapshot.checks) || !Array.isArray(snapshot.destinations)) {
    return { environment, live: false };
  }

  const streams = Object.keys(STREAM_WINDOWS_MS);
  const seen = new Map();
  for (const check of snapshot.checks) {
    if (check === null || typeof check !== "object") {
      return { environment, live: false };
    }
    if (seen.has(check.stream)) {
      return { environment, live: false };
    }
    seen.set(check.stream, check);
  }
  for (const stream of streams) {
    const check = seen.get(stream);
    if (
      check === undefined ||
      check.window_seconds !== STREAM_WINDOWS_MS[stream] / 1000 ||
      check.status !== "up"
    ) {
      return { environment, live: false };
    }
  }
  if (seen.size !== streams.length) {
    return { environment, live: false };
  }

  const destinations = new Set(
    snapshot.destinations.filter((item) => typeof item === "string" && item.length > 0),
  );
  if (destinations.size < MONITOR_MIN_DESTINATIONS) {
    return { environment, live: false };
  }
  return { environment, live: true };
}

async function main() {
  const fixturePath = process.argv[2];
  if (!fixturePath) {
    process.exit(1);
  }

  const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
  const missing = classifyStreams(fixture.last_seen, Date.now());

  if (missing.length > 0) {
    console.log("AL-21");
  }
  console.error(
    "heartbeat-monitor offline classification of a supplied snapshot; live monitoring is external (01 §3.8 D-6).",
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    process.exit(1);
  });
}
