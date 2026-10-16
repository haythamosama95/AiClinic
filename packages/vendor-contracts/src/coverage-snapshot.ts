const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;

const TERM_BANDS = new Set(["ok", "75", "90", "exhausted"]);
const REASONS = new Set([
  "none",
  "expired",
  "grace_exhausted",
  "exhausted",
  "reversed",
  "transferred",
  "transfer_pending",
]);

const SNAPSHOT_KEYS = [
  "contract_version",
  "state",
  "suspended",
  "term",
  "queued_count",
  "held_count",
  "coverage_through",
  "binding_epoch",
  "clinic_seq",
] as const;

const TERM_KEYS = [
  "ref",
  "plan_display_name",
  "starts_at",
  "ends_at",
  "grace_ends_at",
  "allowance",
  "used",
  "band",
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

function validateTerm(value: unknown): boolean {
  if (!isRecord(value) || !hasOnlyKeys(value, TERM_KEYS)) {
    return false;
  }
  for (const key of ["ref", "plan_display_name", "starts_at", "ends_at", "grace_ends_at"]) {
    if (typeof value[key] !== "string") {
      return false;
    }
  }
  if (!Number.isInteger(value.allowance) || !Number.isInteger(value.used)) {
    return false;
  }
  return typeof value.band === "string" && TERM_BANDS.has(value.band);
}

export function validateCoverageSnapshot(
  value: unknown,
): { ok: true } | { ok: false } {
  if (!isRecord(value)) {
    return fail();
  }

  const keys = [...SNAPSHOT_KEYS];
  if ("reason" in value) {
    keys.push("reason");
  }
  if (!hasOnlyKeys(value, keys)) {
    return fail();
  }

  if (!Number.isInteger(value.contract_version)) {
    return fail();
  }
  if (typeof value.state !== "string") {
    return fail();
  }
  if ("reason" in value) {
    if (typeof value.reason !== "string" || !REASONS.has(value.reason)) {
      return fail();
    }
  }
  if (typeof value.suspended !== "boolean") {
    return fail();
  }
  if (value.term !== null && !validateTerm(value.term)) {
    return fail();
  }
  if (
    !Number.isInteger(value.queued_count) ||
    !Number.isInteger(value.held_count) ||
    !Number.isInteger(value.binding_epoch) ||
    !Number.isInteger(value.clinic_seq)
  ) {
    return fail();
  }
  if (typeof value.coverage_through !== "string") {
    return fail();
  }

  return { ok: true };
}
