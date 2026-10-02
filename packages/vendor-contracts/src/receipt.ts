import { canonicalize } from "./canonical.js";
import { verifyCompactJws } from "./jws.js";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
const HEX64_RE = /^[0-9a-f]{64}$/u;

const RECEIPT_BASE_KEYS = [
  "contract_version",
  "installation_id",
  "org_id",
  "result",
  "term_ids",
  "applied_at",
  "ledger_seq",
  "envelope_sha256",
  "kid",
  "signature",
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

function isHex64(value: unknown): boolean {
  return typeof value === "string" && HEX64_RE.test(value);
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

function validateTermIds(value: unknown): boolean {
  if (!Array.isArray(value)) {
    return false;
  }
  return value.every((item) => typeof item === "string");
}

export function validateReceipt(
  value: unknown,
): { ok: true } | { ok: false } {
  if (!isRecord(value)) {
    return fail();
  }

  const hasGrant = "grant_id" in value;
  const hasReversal = "reversal_id" in value;
  if (hasGrant === hasReversal) {
    return fail();
  }

  const keys = [
    ...RECEIPT_BASE_KEYS,
    hasGrant ? "grant_id" : "reversal_id",
  ];
  if (!hasOnlyKeys(value, keys)) {
    return fail();
  }

  if (!Number.isInteger(value.contract_version)) {
    return fail();
  }
  const idValue = hasGrant ? value.grant_id : value.reversal_id;
  if (!isHex64(idValue)) {
    return fail();
  }
  if (!isUuid(value.installation_id) || !isUuid(value.org_id)) {
    return fail();
  }
  if (typeof value.result !== "string") {
    return fail();
  }
  if (!validateTermIds(value.term_ids)) {
    return fail();
  }
  if (typeof value.applied_at !== "string") {
    return fail();
  }
  if (!Number.isInteger(value.ledger_seq)) {
    return fail();
  }
  if (!isHex64(value.envelope_sha256)) {
    return fail();
  }
  if (typeof value.kid !== "string" || typeof value.signature !== "string") {
    return fail();
  }

  return { ok: true };
}

export function receiptSigningBytes(receipt: unknown): Uint8Array {
  if (!isRecord(receipt)) {
    throw new TypeError("Invalid receipt");
  }
  const { signature: _signature, ...withoutSignature } = receipt;
  void _signature;
  return canonicalize(withoutSignature);
}

function payloadBytesFromJws(jws: string): Uint8Array | null {
  const parts = jws.split(".");
  if (parts.length !== 3) {
    return null;
  }
  const payloadSegment = parts[1];
  if (!payloadSegment) {
    return null;
  }
  if (!/^[A-Za-z0-9_-]*$/u.test(payloadSegment)) {
    return null;
  }
  const base64 = payloadSegment.replace(/-/g, "+").replace(/_/g, "/");
  const padded =
    base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    return Uint8Array.from(Buffer.from(padded, "base64"));
  } catch {
    return null;
  }
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) {
    return false;
  }
  for (let i = 0; i < a.byteLength; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

export async function verifyReceiptSignature(input: {
  receipt: unknown;
  publicKey: CryptoKey;
}): Promise<boolean> {
  if (!isRecord(input.receipt)) {
    return false;
  }
  const { signature, kid } = input.receipt;
  if (typeof signature !== "string" || typeof kid !== "string") {
    return false;
  }
  const jwsValid = await verifyCompactJws({
    jws: signature,
    publicKey: input.publicKey,
    kid,
  });
  if (!jwsValid) {
    return false;
  }
  const payloadBytes = payloadBytesFromJws(signature);
  if (payloadBytes === null) {
    return false;
  }
  return bytesEqual(payloadBytes, receiptSigningBytes(input.receipt));
}
