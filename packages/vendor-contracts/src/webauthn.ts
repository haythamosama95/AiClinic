import { hexToBytes } from "./base64url.js";
import { sha256Hex } from "./canonical.js";
import { operationChallenge } from "./operation.js";

export type Assertion = {
  alg: string;
  authenticatorData: Uint8Array;
  clientDataJSON: Uint8Array;
  signature: Uint8Array;
};

const textEncoder = new TextEncoder();

function fail(): { ok: false } {
  return { ok: false };
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

function parseClientDataJson(bytes: Uint8Array): {
  type: string;
  challenge: string;
  origin: string;
} | null {
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    const value = JSON.parse(text) as unknown;
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return null;
    }
    const record = value as Record<string, unknown>;
    if (
      typeof record.type !== "string" ||
      typeof record.challenge !== "string" ||
      typeof record.origin !== "string"
    ) {
      return null;
    }
    return {
      type: record.type,
      challenge: record.challenge,
      origin: record.origin,
    };
  } catch {
    return null;
  }
}

function derEcdsaDerToRaw(der: Uint8Array): Uint8Array | null {
  if (der.length < 8 || der[0] !== 0x30) {
    return null;
  }
  let offset = 2;
  if (der[offset] !== 0x02) {
    return null;
  }
  offset += 1;
  const rLen = der[offset];
  offset += 1;
  if (offset + rLen > der.length) {
    return null;
  }
  let r = der.slice(offset, offset + rLen);
  offset += rLen;
  if (der[offset] !== 0x02) {
    return null;
  }
  offset += 1;
  const sLen = der[offset];
  offset += 1;
  if (offset + sLen > der.length) {
    return null;
  }
  let s = der.slice(offset, offset + sLen);
  if (r.length > 32 && r[0] === 0x00) {
    r = r.slice(1);
  }
  if (s.length > 32 && s[0] === 0x00) {
    s = s.slice(1);
  }
  if (r.length > 32 || s.length > 32) {
    return null;
  }
  const raw = new Uint8Array(64);
  raw.set(r, 32 - r.length);
  raw.set(s, 64 - s.length);
  return raw;
}

function leftPadInteger(bytes: Uint8Array): Uint8Array {
  let start = 0;
  while (
    start < bytes.length - 1 &&
    bytes[start] === 0 &&
    bytes[start + 1] < 0x80
  ) {
    start += 1;
  }
  let trimmed = bytes.slice(start);
  if (trimmed[0] >= 0x80) {
    trimmed = new Uint8Array([0, ...trimmed]);
  }
  return trimmed;
}

export function derEcdsaRawToDer(raw: Uint8Array): Uint8Array {
  if (raw.byteLength !== 64) {
    throw new TypeError("ECDSA raw signature must be 64 bytes");
  }
  const r = leftPadInteger(raw.slice(0, 32));
  const s = leftPadInteger(raw.slice(32, 64));
  const innerLen = 2 + r.length + 2 + s.length;
  const out = new Uint8Array(2 + innerLen);
  out[0] = 0x30;
  out[1] = innerLen;
  out[2] = 0x02;
  out[3] = r.length;
  out.set(r, 4);
  const sOffset = 4 + r.length;
  out[sOffset] = 0x02;
  out[sOffset + 1] = s.length;
  out.set(s, sOffset + 2);
  return out;
}

export async function verifyAssertion(input: {
  assertion: Assertion;
  operation: unknown;
  rpId: string;
  origin: string;
  publicKey: CryptoKey;
}): Promise<{ ok: true } | { ok: false }> {
  const clientData = parseClientDataJson(input.assertion.clientDataJSON);
  if (clientData === null) {
    return fail();
  }
  if (clientData.type !== "webauthn.get") {
    return fail();
  }
  if (clientData.origin !== input.origin) {
    return fail();
  }
  const expectedChallenge = await operationChallenge(input.operation);
  if (clientData.challenge !== expectedChallenge) {
    return fail();
  }

  const rpIdHashHex = await sha256Hex(textEncoder.encode(input.rpId));
  const rpIdHash = hexToBytes(rpIdHashHex);
  if (input.assertion.authenticatorData.byteLength < 33) {
    return fail();
  }
  if (
    !bytesEqual(
      input.assertion.authenticatorData.slice(0, 32),
      rpIdHash,
    )
  ) {
    return fail();
  }
  const flags = input.assertion.authenticatorData[32];
  if ((flags & 0x01) === 0 || (flags & 0x04) === 0) {
    return fail();
  }

  const clientDataHashHex = await sha256Hex(input.assertion.clientDataJSON);
  const clientDataHash = hexToBytes(clientDataHashHex);
  const signedData = new Uint8Array(
    input.assertion.authenticatorData.byteLength + clientDataHash.byteLength,
  );
  signedData.set(input.assertion.authenticatorData, 0);
  signedData.set(clientDataHash, input.assertion.authenticatorData.byteLength);

  const alg = input.assertion.alg;
  if (alg === "ES256") {
    const rawSig = derEcdsaDerToRaw(input.assertion.signature);
    if (rawSig === null) {
      return fail();
    }
    const verified = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      input.publicKey,
      rawSig,
      signedData,
    );
    return verified ? { ok: true } : fail();
  }
  if (alg === "EdDSA") {
    const verified = await crypto.subtle.verify(
      { name: "Ed25519" },
      input.publicKey,
      input.assertion.signature,
      signedData,
    );
    return verified ? { ok: true } : fail();
  }
  return fail();
}

export async function parseRegistrationAttestation(
  attestation: { alg: string; publicKey: Uint8Array },
): Promise<
  | { ok: true; alg: "ES256" | "EdDSA"; publicKey: CryptoKey }
  | { ok: false }
> {
  if (attestation.alg === "ES256") {
    try {
      const publicKey = await crypto.subtle.importKey(
        "spki",
        attestation.publicKey,
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["verify"],
      );
      return { ok: true, alg: "ES256", publicKey };
    } catch {
      return fail();
    }
  }
  if (attestation.alg === "EdDSA") {
    if (attestation.publicKey.byteLength !== 32) {
      return fail();
    }
    try {
      const publicKey = await crypto.subtle.importKey(
        "raw",
        attestation.publicKey,
        { name: "Ed25519" },
        true,
        ["verify"],
      );
      return { ok: true, alg: "EdDSA", publicKey };
    } catch {
      return fail();
    }
  }
  return fail();
}
