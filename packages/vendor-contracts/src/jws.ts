import { canonicalize } from "./canonical.js";

const textEncoder = new TextEncoder();

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded =
    base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

function parseJsonUtf8(bytes: Uint8Array): unknown | null {
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return JSON.parse(text) as unknown;
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

function parseHeader(
  headerBytes: Uint8Array,
  expectedKid: string,
): boolean {
  const headerValue = parseJsonUtf8(headerBytes);
  if (headerValue === null || typeof headerValue !== "object" || Array.isArray(headerValue)) {
    return false;
  }
  const header = headerValue as Record<string, unknown>;
  if (header.alg !== "EdDSA" || header.kid !== expectedKid) {
    return false;
  }
  return bytesEqual(headerBytes, canonicalize({ alg: "EdDSA", kid: expectedKid }));
}

export async function signCompactJws(input: {
  payload: Uint8Array;
  privateKey: CryptoKey;
  kid: string;
}): Promise<string> {
  const headerBytes = canonicalize({ alg: "EdDSA", kid: input.kid });
  const headerSegment = base64UrlEncode(headerBytes);
  const payloadSegment = base64UrlEncode(input.payload);
  const signingInput = textEncoder.encode(`${headerSegment}.${payloadSegment}`);
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    input.privateKey,
    signingInput,
  );
  const signatureSegment = base64UrlEncode(new Uint8Array(signature));
  return `${headerSegment}.${payloadSegment}.${signatureSegment}`;
}

export async function verifyCompactJws(input: {
  jws: string;
  publicKey: CryptoKey;
  kid: string;
}): Promise<boolean> {
  const parts = input.jws.split(".");
  if (parts.length !== 3) {
    return false;
  }
  const [headerSegment, payloadSegment, signatureSegment] = parts;
  if (!headerSegment || !payloadSegment || !signatureSegment) {
    return false;
  }

  const headerBytes = base64UrlDecode(headerSegment);
  const payloadBytes = base64UrlDecode(payloadSegment);
  const signatureBytes = base64UrlDecode(signatureSegment);
  if (headerBytes === null || payloadBytes === null || signatureBytes === null) {
    return false;
  }

  if (!parseHeader(headerBytes, input.kid)) {
    return false;
  }

  const payloadValue = parseJsonUtf8(payloadBytes);
  if (payloadValue === null) {
    return false;
  }
  if (!bytesEqual(payloadBytes, canonicalize(payloadValue))) {
    return false;
  }

  const signingInput = textEncoder.encode(`${headerSegment}.${payloadSegment}`);
  return crypto.subtle.verify(
    { name: "Ed25519" },
    input.publicKey,
    signatureBytes,
    signingInput,
  );
}
