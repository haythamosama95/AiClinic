import {
  validateReceipt,
  verifyReceiptSignature,
} from "vendor-contracts";

export type DurableGrantRequest = {
  grant_id: string;
  org_id: string;
  envelope_sha256: string;
  envelope: string;
};

type PlatformPublicKey = { kid: string; public_key: string };

function parsePlatformPublicKeys(json: string): PlatformPublicKey[] {
  try {
    const parsed = JSON.parse(json) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((value): value is PlatformPublicKey =>
      typeof value === "object" && value !== null &&
      typeof (value as PlatformPublicKey).kid === "string" &&
      typeof (value as PlatformPublicKey).public_key === "string"
    );
  } catch {
    return [];
  }
}

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) return null;
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

async function importEd25519PublicKey(value: string): Promise<CryptoKey | null> {
  const raw = base64UrlDecode(value);
  if (raw === null) return null;
  try {
    return await crypto.subtle.importKey(
      "raw", raw, { name: "Ed25519" }, false, ["verify"],
    );
  } catch {
    return null;
  }
}

/** Validate and authenticate the platform's original receipt against its durable request. */
export async function validateGrantReceipt(input: {
  platformPublicKeys: string;
  request: DurableGrantRequest;
  receipt: unknown;
}): Promise<input is { platformPublicKeys: string; request: DurableGrantRequest; receipt: Record<string, unknown> }> {
  if (validateReceipt(input.receipt).ok !== true) return false;
  const receipt = input.receipt as Record<string, unknown>;
  let envelope: Record<string, unknown>;
  try {
    const parsed = JSON.parse(input.request.envelope) as unknown;
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return false;
    envelope = parsed as Record<string, unknown>;
  } catch {
    return false;
  }
  if (
    receipt.grant_id !== input.request.grant_id ||
    receipt.org_id !== input.request.org_id ||
    receipt.envelope_sha256 !== input.request.envelope_sha256 ||
    receipt.contract_version !== envelope.contract_version ||
    receipt.result !== "applied" ||
    !Array.isArray(receipt.term_ids) || receipt.term_ids.length === 0 ||
    !receipt.term_ids.every((value) => typeof value === "string" && value.length > 0) ||
    !Number.isInteger(receipt.ledger_seq) || Number(receipt.ledger_seq) <= 0 ||
    typeof receipt.kid !== "string"
  ) return false;

  const key = parsePlatformPublicKeys(input.platformPublicKeys)
    .find((candidate) => candidate.kid === receipt.kid);
  if (key === undefined) return false;
  const publicKey = await importEd25519PublicKey(key.public_key);
  return publicKey !== null && await verifyReceiptSignature({ receipt, publicKey });
}
