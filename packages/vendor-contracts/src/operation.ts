import { base64UrlEncode, hexToBytes } from "./base64url.js";
import { canonicalize, sha256Hex } from "./canonical.js";

const OPERATION_KEYS = [
  "op",
  "params",
  "actor_email",
  "issued_at",
  "nonce",
  "contract_version",
] as const;

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

export function validateOperation(
  value: unknown,
): { ok: true } | { ok: false } {
  if (!isRecord(value) || !hasOnlyKeys(value, OPERATION_KEYS)) {
    return fail();
  }
  if (typeof value.op !== "string") {
    return fail();
  }
  if (!isRecord(value.params)) {
    return fail();
  }
  if (
    typeof value.actor_email !== "string" ||
    typeof value.issued_at !== "string" ||
    typeof value.nonce !== "string"
  ) {
    return fail();
  }
  if (!Number.isInteger(value.contract_version)) {
    return fail();
  }
  return { ok: true };
}

export async function operationChallenge(operation: unknown): Promise<string> {
  if (validateOperation(operation).ok !== true) {
    throw new TypeError("Invalid operation");
  }
  const hex = await sha256Hex(canonicalize(operation));
  return base64UrlEncode(hexToBytes(hex));
}
