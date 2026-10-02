import { canonicalize } from "./canonical.js";

const textEncoder = new TextEncoder();

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;

const LIFETIME_MAX: Record<TokenAudience, number> = {
  "ai-platform": 600,
  abo: 300,
  "ai-platform-feed": 120,
};

export type TokenAudience = "ai-platform" | "abo" | "ai-platform-feed";

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

function parseJwtHeader(
  headerBytes: Uint8Array,
  expectedKid: string,
): boolean {
  const headerValue = parseJsonUtf8(headerBytes);
  if (
    headerValue === null ||
    typeof headerValue !== "object" ||
    Array.isArray(headerValue)
  ) {
    return false;
  }
  const header = headerValue as Record<string, unknown>;
  if (
    header.alg !== "EdDSA" ||
    header.kid !== expectedKid ||
    header.typ !== "JWT"
  ) {
    return false;
  }
  return bytesEqual(
    headerBytes,
    canonicalize({ alg: "EdDSA", kid: expectedKid, typ: "JWT" }),
  );
}

function validateCommonClaims(
  payload: Record<string, unknown>,
  audience: TokenAudience,
  issuerId: string,
): boolean {
  if (payload.iss !== issuerId || payload.ver !== "2" || payload.aud !== audience) {
    return false;
  }
  if (typeof payload.jti !== "string" || !UUID_RE.test(payload.jti)) {
    return false;
  }
  if (
    typeof payload.iat !== "number" ||
    typeof payload.exp !== "number" ||
    !Number.isFinite(payload.iat) ||
    !Number.isFinite(payload.exp)
  ) {
    return false;
  }
  const lifetime = payload.exp - payload.iat;
  if (lifetime < 0 || lifetime > LIFETIME_MAX[audience]) {
    return false;
  }
  return true;
}

function validateAiClaims(payload: Record<string, unknown>): boolean {
  const keys = ["iss", "ver", "aud", "jti", "iat", "exp", "sub", "org", "role", "branch", "scopes"];
  if (!hasOnlyKeys(payload, keys)) {
    return false;
  }
  if (
    typeof payload.sub !== "string" ||
    typeof payload.org !== "string" ||
    typeof payload.role !== "string" ||
    typeof payload.branch !== "string"
  ) {
    return false;
  }
  if (!Array.isArray(payload.scopes)) {
    return false;
  }
  return payload.scopes.every(
    (scope) => typeof scope === "string" && scope.startsWith("ai."),
  );
}

function validateBillingClaims(payload: Record<string, unknown>): boolean {
  const keys = ["iss", "ver", "aud", "jti", "iat", "exp", "sub", "org", "role", "branch"];
  if (!hasOnlyKeys(payload, keys)) {
    return false;
  }
  return (
    typeof payload.sub === "string" &&
    typeof payload.org === "string" &&
    payload.role === "administrator" &&
    typeof payload.branch === "string"
  );
}

function validateFeedClaims(payload: Record<string, unknown>): boolean {
  if ("org" in payload) {
    return false;
  }
  const keys = ["iss", "ver", "aud", "jti", "iat", "exp", "sub"];
  if (!hasOnlyKeys(payload, keys)) {
    return false;
  }
  return payload.sub === "backend-feed";
}

function validateAudienceClaims(
  payload: Record<string, unknown>,
  audience: TokenAudience,
): boolean {
  switch (audience) {
    case "ai-platform":
      return validateAiClaims(payload);
    case "abo":
      return validateBillingClaims(payload);
    case "ai-platform-feed":
      return validateFeedClaims(payload);
    default:
      return false;
  }
}

export async function validateTokenClaims(input: {
  jwt: string;
  audience: TokenAudience;
  issuerId: string;
  publicKey: CryptoKey;
  kid: string;
}): Promise<{ ok: true } | { ok: false }> {
  const parts = input.jwt.split(".");
  if (parts.length !== 3) {
    return fail();
  }
  const [headerSegment, payloadSegment, signatureSegment] = parts;
  if (!headerSegment || !payloadSegment || !signatureSegment) {
    return fail();
  }

  const headerBytes = base64UrlDecode(headerSegment);
  const payloadBytes = base64UrlDecode(payloadSegment);
  const signatureBytes = base64UrlDecode(signatureSegment);
  if (headerBytes === null || payloadBytes === null || signatureBytes === null) {
    return fail();
  }

  if (!parseJwtHeader(headerBytes, input.kid)) {
    return fail();
  }

  const signingInput = textEncoder.encode(`${headerSegment}.${payloadSegment}`);
  const signatureValid = await crypto.subtle.verify(
    { name: "Ed25519" },
    input.publicKey,
    signatureBytes,
    signingInput,
  );
  if (!signatureValid) {
    return fail();
  }

  const payloadValue = parseJsonUtf8(payloadBytes);
  if (!isRecord(payloadValue)) {
    return fail();
  }
  if (!bytesEqual(payloadBytes, canonicalize(payloadValue))) {
    return fail();
  }

  if (
    !validateCommonClaims(payloadValue, input.audience, input.issuerId) ||
    !validateAudienceClaims(payloadValue, input.audience)
  ) {
    return fail();
  }

  return { ok: true };
}
