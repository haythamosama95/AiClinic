import { base64UrlEncode } from "./base64url.js";

const textEncoder = new TextEncoder();

export type AccessCertsDocument = {
  issuer: string;
  keys: Array<{
    kid: string;
    kty: "RSA";
    alg: "RS256";
    n: string;
    e: string;
  }>;
};

function fail(): { ok: false } {
  return { ok: false };
}

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded =
    base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    return Uint8Array.from(Buffer.from(padded, "base64"));
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

function audMatches(payloadAud: unknown, expectedAud: string): boolean {
  if (payloadAud === expectedAud) {
    return true;
  }
  if (Array.isArray(payloadAud)) {
    return payloadAud.some((entry) => entry === expectedAud);
  }
  return false;
}

export async function verifyAccessJwt(input: {
  jwt: string;
  certs: AccessCertsDocument;
  aud: string;
  nowSeconds: number;
}): Promise<{ ok: true; email: string } | { ok: false }> {
  const parts = input.jwt.split(".");
  if (parts.length !== 3) {
    return fail();
  }
  const [headerSegment, payloadSegment, signatureSegment] = parts;
  const headerBytes = base64UrlDecode(headerSegment);
  const payloadBytes = base64UrlDecode(payloadSegment);
  const signatureBytes = base64UrlDecode(signatureSegment);
  if (headerBytes === null || payloadBytes === null || signatureBytes === null) {
    return fail();
  }

  const headerValue = parseJsonUtf8(headerBytes);
  if (
    headerValue === null ||
    typeof headerValue !== "object" ||
    Array.isArray(headerValue)
  ) {
    return fail();
  }
  const header = headerValue as Record<string, unknown>;
  if (header.alg !== "RS256" || typeof header.kid !== "string") {
    return fail();
  }

  const jwk = input.certs.keys.find((key) => key.kid === header.kid);
  if (jwk === undefined) {
    return fail();
  }

  let publicKey: CryptoKey;
  try {
    publicKey = await crypto.subtle.importKey(
      "jwk",
      {
        kty: jwk.kty,
        n: jwk.n,
        e: jwk.e,
        alg: jwk.alg,
      },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
  } catch {
    return fail();
  }

  const signingInput = textEncoder.encode(`${headerSegment}.${payloadSegment}`);
  const verified = await crypto.subtle.verify(
    { name: "RSASSA-PKCS1-v1_5" },
    publicKey,
    signatureBytes,
    signingInput,
  );
  if (!verified) {
    return fail();
  }

  const payloadValue = parseJsonUtf8(payloadBytes);
  if (
    payloadValue === null ||
    typeof payloadValue !== "object" ||
    Array.isArray(payloadValue)
  ) {
    return fail();
  }
  const payload = payloadValue as Record<string, unknown>;
  if (payload.iss !== input.certs.issuer) {
    return fail();
  }
  if (!audMatches(payload.aud, input.aud)) {
    return fail();
  }
  if (typeof payload.exp !== "number" || payload.exp <= input.nowSeconds) {
    return fail();
  }
  if (typeof payload.email !== "string") {
    return fail();
  }

  return { ok: true, email: payload.email };
}
