import { canonicalize, sha256Hex } from "./canonical.js";
import { verifyCompactJws } from "./jws.js";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
const HEX64_RE = /^[0-9a-f]{64}$/u;

const PAID_MONTH_COUNTS = new Set([1, 3, 12]);
const ADJUSTMENT_KEYS = new Set(["plan", "add_allowance", "extend_days"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function fail(): { ok: false } {
  return { ok: false };
}

function placementNotSupported(): { ok: false; code: "placement_not_supported" } {
  return { ok: false, code: "placement_not_supported" };
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

function validatePlan(value: unknown): boolean {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.plan_id === "string" &&
    Number.isInteger(value.plan_version) &&
    hasOnlyKeys(value, ["plan_id", "plan_version"])
  );
}

function validateGrace(
  value: unknown,
  sourceKind: string,
): boolean {
  if (!isRecord(value)) {
    return false;
  }
  if (
    !hasOnlyKeys(value, ["days", "cap_rule"]) ||
    !Number.isInteger(value.days) ||
    typeof value.cap_rule !== "string"
  ) {
    return false;
  }
  if (sourceKind === "paid") {
    return value.days <= 7 && value.cap_rule === "proportional";
  }
  return true;
}

function validateApproval(value: unknown): boolean {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.credential_id === "string" &&
    typeof value.assertion === "string"
  );
}

function validateEvidence(value: unknown): boolean {
  if (!isRecord(value)) {
    return false;
  }
  if (!hasOnlyKeys(value, ["content_sha256", "approvals"])) {
    return false;
  }
  if (!isHex64(value.content_sha256)) {
    return false;
  }
  if (!Array.isArray(value.approvals) || value.approvals.length < 1) {
    return false;
  }
  return value.approvals.every((item) => validateApproval(item));
}

function validateSource(value: unknown): string | null {
  if (!isRecord(value) || typeof value.kind !== "string") {
    return null;
  }
  const kind = value.kind;
  if (kind !== "paid" && kind !== "complimentary" && kind !== "transfer") {
    return null;
  }
  if (typeof value.ref !== "string") {
    return null;
  }
  if (kind === "paid") {
    if (
      !hasOnlyKeys(value, ["kind", "ref"]) ||
      "operator_email" in value ||
      "reason" in value
    ) {
      return null;
    }
    return kind;
  }
  if (
    !hasOnlyKeys(value, ["kind", "ref", "operator_email", "reason"]) ||
    typeof value.operator_email !== "string" ||
    typeof value.reason !== "string"
  ) {
    return null;
  }
  return kind;
}

function validateDuration(
  value: unknown,
  sourceKind: string,
): boolean {
  if (!isRecord(value)) {
    return false;
  }
  if (!hasOnlyKeys(value, ["unit", "count"]) || !Number.isInteger(value.count)) {
    return false;
  }
  if (sourceKind === "paid") {
    return value.unit === "month" && PAID_MONTH_COUNTS.has(value.count);
  }
  if (sourceKind === "complimentary") {
    return value.unit === "month" || value.unit === "day";
  }
  if (sourceKind === "transfer") {
    return typeof value.unit === "string";
  }
  return false;
}

function validateAdjustment(
  value: unknown,
  plan: unknown,
): boolean {
  if (!isRecord(value)) {
    return false;
  }
  for (const key of Object.keys(value)) {
    if (!ADJUSTMENT_KEYS.has(key)) {
      return false;
    }
  }
  if ("plan" in value && !validatePlan(value.plan)) {
    return false;
  }
  if (
    "add_allowance" in value &&
    !Number.isInteger(value.add_allowance)
  ) {
    return false;
  }
  if (
    "extend_days" in value &&
    !Number.isInteger(value.extend_days)
  ) {
    return false;
  }
  if ("plan" in value && plan !== undefined) {
    const adjustmentPlan = value.plan;
    const envelopePlan = plan;
    if (
      !isRecord(adjustmentPlan) ||
      !isRecord(envelopePlan) ||
      adjustmentPlan.plan_id !== envelopePlan.plan_id ||
      adjustmentPlan.plan_version !== envelopePlan.plan_version
    ) {
      return false;
    }
  }
  return true;
}

export function validateGrantEnvelope(
  value: unknown,
):
  | { ok: true }
  | { ok: false; code?: "placement_not_supported" } {
  if (!isRecord(value)) {
    return fail();
  }

  if (value.placement === "immediate" || value.placement === "replace") {
    return placementNotSupported();
  }
  if (value.placement !== "queue") {
    return fail();
  }

  const kind = value.kind;
  if (kind !== "term" && kind !== "term_adjustment") {
    return fail();
  }

  const baseKeys = [
    "contract_version",
    "grant_id",
    "org_id",
    "kind",
    "placement",
    "source",
    "plan",
    "duration",
    "allowance_credits",
    "grace",
    "evidence",
  ];
  const allowedKeys = [...baseKeys];
  if (kind === "term_adjustment") {
    allowedKeys.push("adjustment");
  }
  if ("ceiling_override" in value) {
    allowedKeys.push("ceiling_override");
  }
  if ("paid_at" in value) {
    allowedKeys.push("paid_at");
  }
  if (kind === "term" && "adjustment" in value) {
    return fail();
  }
  if (kind === "term_adjustment" && !("adjustment" in value)) {
    return fail();
  }
  if (!hasOnlyKeys(value, allowedKeys)) {
    return fail();
  }

  if (!Number.isInteger(value.contract_version)) {
    return fail();
  }
  if (!isHex64(value.grant_id) || !isUuid(value.org_id)) {
    return fail();
  }

  const sourceKind = validateSource(value.source);
  if (sourceKind === null) {
    return fail();
  }

  if (sourceKind === "paid") {
    if (typeof value.paid_at !== "string") {
      return fail();
    }
  } else if ("paid_at" in value) {
    return fail();
  }

  if (!validatePlan(value.plan)) {
    return fail();
  }
  if (!validateDuration(value.duration, sourceKind)) {
    return fail();
  }
  if (
    !Number.isInteger(value.allowance_credits) ||
    value.allowance_credits < 1
  ) {
    return fail();
  }
  if (!validateGrace(value.grace, sourceKind)) {
    return fail();
  }
  if (!validateEvidence(value.evidence)) {
    return fail();
  }

  if (
    "ceiling_override" in value &&
    Array.isArray((value.evidence as Record<string, unknown>).approvals) &&
    (value.evidence as { approvals: unknown[] }).approvals.length < 2
  ) {
    return fail();
  }

  if (
    kind === "term_adjustment" &&
    !validateAdjustment(value.adjustment, value.plan)
  ) {
    return fail();
  }

  return { ok: true };
}

export async function grantEnvelopeHash(envelope: unknown): Promise<string> {
  return sha256Hex(canonicalize(envelope));
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
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
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

export async function verifyGrantSignature(input: {
  envelope: unknown;
  jws: string;
  publicKey: CryptoKey;
  kid: string;
}): Promise<boolean> {
  const jwsValid = await verifyCompactJws({
    jws: input.jws,
    publicKey: input.publicKey,
    kid: input.kid,
  });
  if (!jwsValid) {
    return false;
  }
  const payloadBytes = payloadBytesFromJws(input.jws);
  if (payloadBytes === null) {
    return false;
  }
  return bytesEqual(payloadBytes, canonicalize(input.envelope));
}
