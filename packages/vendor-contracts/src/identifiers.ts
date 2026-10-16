import { sha256Hex } from "./canonical.js";

const CROCKFORD_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

const textEncoder = new TextEncoder();

function crockfordEncode(bytes: Uint8Array): string {
  let buffer = 0;
  let bitsInBuffer = 0;
  let output = "";

  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bitsInBuffer += 8;
    while (bitsInBuffer >= 5) {
      bitsInBuffer -= 5;
      const index = (buffer >> bitsInBuffer) & 0x1f;
      output += CROCKFORD_ALPHABET[index];
    }
  }

  if (bitsInBuffer > 0) {
    const index = (buffer << (5 - bitsInBuffer)) & 0x1f;
    output += CROCKFORD_ALPHABET[index];
  }

  return output;
}

function crockfordPrefix8(hashBytes: Uint8Array): string {
  return crockfordEncode(hashBytes).slice(0, 8);
}

async function sha256Utf8Hex(value: string): Promise<string> {
  return sha256Hex(textEncoder.encode(value));
}

export function ulid(timestampMs: number, random80: Uint8Array): string {
  if (!Number.isInteger(timestampMs) || timestampMs < 0) {
    throw new TypeError("Invalid ULID timestamp");
  }
  if (random80.byteLength !== 10) {
    throw new TypeError("random80 must be 10 bytes");
  }
  const timestamp = BigInt(timestampMs);
  if (timestamp >> 48n !== 0n) {
    throw new TypeError("timestampMs exceeds 48 bits");
  }

  const bytes = new Uint8Array(16);
  let ts = timestamp;
  for (let i = 5; i >= 0; i--) {
    bytes[i] = Number(ts & 0xffn);
    ts >>= 8n;
  }
  bytes.set(random80, 6);
  return crockfordEncode(bytes);
}

export async function subscriptionRef(orgId: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(`sub-ref:${orgId}`),
  );
  return `AIC-${crockfordPrefix8(new Uint8Array(digest))}`;
}

export async function paymentId(
  providerId: string,
  providerTransactionRef: string,
): Promise<string> {
  return sha256Utf8Hex(`payment:${providerId}:${providerTransactionRef}`);
}

export async function grantIdPaid(paymentIdValue: string): Promise<string> {
  return sha256Utf8Hex(`grant:paid:${paymentIdValue}`);
}

export async function grantIdComp(operatorActionId: string): Promise<string> {
  return sha256Utf8Hex(`grant:comp:${operatorActionId}`);
}

export async function grantIdTransfer(
  transferId: string,
  n: number,
): Promise<string> {
  return sha256Utf8Hex(`grant:transfer:${transferId}:${n}`);
}

export function coverageEventId(
  installationId: string,
  clinicSeq: number,
): string {
  return `${installationId}:${clinicSeq}`;
}

export function humanRef(
  kind: "CK" | "PAY" | "REV" | "GR",
  recordId: string,
): string {
  return `${kind}-${recordId.slice(-8)}`;
}
