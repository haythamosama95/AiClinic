import { validateReceipt } from "./receipt.js";

const RESULT_NAMES = new Set([
  "ok",
  "applied",
  "already_applied",
  "conflict",
  "rejected",
  "transient",
]);

const TRANSIENT_DETAILS = new Set([
  "unavailable",
  "unknown_kid",
  "awaiting_transfer",
  "transfer_pending",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function fail(): { ok: false } {
  return { ok: false };
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

export function validateResultEnvelope(
  value: unknown,
): { ok: true } | { ok: false } {
  if (!isRecord(value)) {
    return fail();
  }

  const baseKeys = ["contract_version", "result", "code", "detail"];
  const result = value.result;
  if (typeof result !== "string" || !RESULT_NAMES.has(result)) {
    return fail();
  }

  const needsReceipt =
    result === "applied" || result === "already_applied";
  const allowedKeys = needsReceipt ? [...baseKeys, "receipt"] : baseKeys;
  if (!hasOnlyKeys(value, allowedKeys)) {
    return fail();
  }

  if (!Number.isInteger(value.contract_version)) {
    return fail();
  }
  if (typeof value.code !== "string" || typeof value.detail !== "string") {
    return fail();
  }

  if (result === "transient") {
    if (typeof value.detail !== "string" || !TRANSIENT_DETAILS.has(value.detail)) {
      return fail();
    }
  }

  if (needsReceipt) {
    if (validateReceipt(value.receipt).ok !== true) {
      return fail();
    }
  }

  return { ok: true };
}
