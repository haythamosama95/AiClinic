import { validateCoverageSnapshot } from "./coverage-snapshot.js";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;

const FEED_EVENT_KEYS = [
  "event_id",
  "feed_seq",
  "org_id",
  "installation_id",
  "binding_epoch",
  "clinic_seq",
  "kind",
  "at",
  "snapshot",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function fail(): { ok: false } {
  return { ok: false };
}

function isUuid(value: unknown): boolean {
  return typeof value === "string" && UUID_RE.test(value);
}

function hasOnlyKeys(
  obj: Record<string, unknown>,
  keys: readonly string[],
): boolean {
  const allowed = new Set(keys);
  for (const key of Object.keys(obj)) {
    if (!allowed.has(key)) {
      return false;
    }
  }
  return true;
}

export function validateFeedEvent(
  value: unknown,
): { ok: true } | { ok: false } {
  if (!isRecord(value) || !hasOnlyKeys(value, FEED_EVENT_KEYS)) {
    return fail();
  }
  if (typeof value.event_id !== "string") {
    return fail();
  }
  if (!Number.isInteger(value.feed_seq)) {
    return fail();
  }
  if (!isUuid(value.org_id) || !isUuid(value.installation_id)) {
    return fail();
  }
  if (
    !Number.isInteger(value.binding_epoch) ||
    !Number.isInteger(value.clinic_seq)
  ) {
    return fail();
  }
  if (typeof value.kind !== "string" || typeof value.at !== "string") {
    return fail();
  }
  if (validateCoverageSnapshot(value.snapshot).ok !== true) {
    return fail();
  }
  return { ok: true };
}
