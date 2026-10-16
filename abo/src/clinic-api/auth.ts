import { validateTokenClaims } from "vendor-contracts";
import { clinicErrorResponse } from "./version.js";

const textEncoder = new TextEncoder();

export type BillingAuthEnv = {
  DB: D1Database;
  ISSUER_ID: string;
  ISSUER_KEYS: string;
  TEST_CLOCK?: string;
};

export type BillingClaims = {
  sub: string;
  org: string;
  role: string;
  branch: string;
  jti: string;
  iat: number;
  exp: number;
};

export type AuthSuccess = {
  ok: true;
  claims: BillingClaims;
};

export type AuthFailure = {
  ok: false;
  response: Response;
};

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function importEd25519PublicKey(publicKeyB64: string): Promise<CryptoKey | null> {
  const bytes = base64UrlDecode(publicKeyB64);
  if (bytes === null || bytes.byteLength !== 32) {
    return null;
  }
  try {
    return crypto.subtle.importKey("raw", bytes, "Ed25519", true, ["verify"]);
  } catch {
    return null;
  }
}

export async function loadIssuerPins(
  env: BillingAuthEnv,
): Promise<Map<string, string>> {
  const pins = new Map<string, string>();
  if (env.TEST_CLOCK === "1") {
    try {
      const result = await env.DB.prepare(
        `SELECT kid, public_key FROM harness_issuer_pin`,
      ).all<{ kid: string; public_key: string }>();
      if (result.results.length > 0) {
        for (const row of result.results) {
          pins.set(row.kid, row.public_key);
        }
        return pins;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!/no such table/i.test(message)) {
        throw error;
      }
    }
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(env.ISSUER_KEYS || "[]");
  } catch {
    return pins;
  }
  if (!Array.isArray(parsed)) {
    return pins;
  }
  for (const entry of parsed) {
    if (
      typeof entry === "object" &&
      entry !== null &&
      typeof (entry as { kid?: unknown }).kid === "string" &&
      typeof (entry as { public_key?: unknown }).public_key === "string"
    ) {
      const row = entry as { kid: string; public_key: string };
      pins.set(row.kid, row.public_key);
    }
  }
  return pins;
}

function extractBearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  if (header === null) {
    return null;
  }
  const match = /^Bearer\s+(.+)$/iu.exec(header);
  if (!match) {
    return null;
  }
  const token = match[1]?.trim();
  return token && token.length > 0 ? token : null;
}

function readJwtKid(jwt: string): string | null {
  const parts = jwt.split(".");
  if (parts.length !== 3) {
    return null;
  }
  const headerBytes = base64UrlDecode(parts[0]!);
  if (headerBytes === null) {
    return null;
  }
  const headerValue = parseJsonUtf8(headerBytes);
  if (!isRecord(headerValue) || typeof headerValue.kid !== "string") {
    return null;
  }
  return headerValue.kid;
}

async function verifyJwtSignature(
  jwt: string,
  publicKey: CryptoKey,
): Promise<Record<string, unknown> | null> {
  const parts = jwt.split(".");
  if (parts.length !== 3) {
    return null;
  }
  const [headerSegment, payloadSegment, signatureSegment] = parts;
  if (!headerSegment || !payloadSegment || !signatureSegment) {
    return null;
  }
  const signatureBytes = base64UrlDecode(signatureSegment);
  if (signatureBytes === null) {
    return null;
  }
  const signingInput = textEncoder.encode(`${headerSegment}.${payloadSegment}`);
  const valid = await crypto.subtle.verify(
    { name: "Ed25519" },
    publicKey,
    signatureBytes,
    signingInput,
  );
  if (!valid) {
    return null;
  }
  const payloadBytes = base64UrlDecode(payloadSegment);
  if (payloadBytes === null) {
    return null;
  }
  const payloadValue = parseJsonUtf8(payloadBytes);
  if (!isRecord(payloadValue)) {
    return null;
  }
  return payloadValue;
}

function claimsFromPayload(payload: Record<string, unknown>): BillingClaims | null {
  if (
    typeof payload.sub !== "string" ||
    typeof payload.org !== "string" ||
    typeof payload.role !== "string" ||
    typeof payload.branch !== "string" ||
    typeof payload.jti !== "string" ||
    typeof payload.iat !== "number" ||
    typeof payload.exp !== "number"
  ) {
    return null;
  }
  return {
    sub: payload.sub,
    org: payload.org,
    role: payload.role,
    branch: payload.branch,
    jti: payload.jti,
    iat: payload.iat,
    exp: payload.exp,
  };
}

function lifetimeValid(payload: Record<string, unknown>): boolean {
  if (
    typeof payload.iat !== "number" ||
    typeof payload.exp !== "number" ||
    !Number.isFinite(payload.iat) ||
    !Number.isFinite(payload.exp)
  ) {
    return false;
  }
  const lifetime = payload.exp - payload.iat;
  return lifetime >= 0 && lifetime <= 300;
}

export async function authenticateBilling(
  request: Request,
  env: BillingAuthEnv,
  contractVersion: number,
): Promise<AuthSuccess | AuthFailure> {
  const jwt = extractBearerToken(request);
  if (jwt === null) {
    return {
      ok: false,
      response: clinicErrorResponse("unauthenticated", 401, contractVersion),
    };
  }

  const kid = readJwtKid(jwt);
  if (kid === null) {
    return {
      ok: false,
      response: clinicErrorResponse("unauthenticated", 401, contractVersion),
    };
  }

  const pins = await loadIssuerPins(env);
  const publicKeyB64 = pins.get(kid);
  if (publicKeyB64 === undefined) {
    return {
      ok: false,
      response: clinicErrorResponse("unauthenticated", 401, contractVersion),
    };
  }

  const publicKey = await importEd25519PublicKey(publicKeyB64);
  if (publicKey === null) {
    return {
      ok: false,
      response: clinicErrorResponse("unauthenticated", 401, contractVersion),
    };
  }

  const validated = await validateTokenClaims({
    jwt,
    audience: "abo",
    issuerId: env.ISSUER_ID,
    publicKey,
    kid,
  });
  if (validated.ok) {
    const payload = await verifyJwtSignature(jwt, publicKey);
    const claims = payload ? claimsFromPayload(payload) : null;
    if (claims === null) {
      return {
        ok: false,
        response: clinicErrorResponse("unauthenticated", 401, contractVersion),
      };
    }
    return { ok: true, claims };
  }

  const payload = await verifyJwtSignature(jwt, publicKey);
  if (payload === null) {
    return {
      ok: false,
      response: clinicErrorResponse("unauthenticated", 401, contractVersion),
    };
  }

  if (
    payload.aud !== "abo" ||
    payload.ver !== "2" ||
    !lifetimeValid(payload)
  ) {
    return {
      ok: false,
      response: clinicErrorResponse("unauthenticated", 401, contractVersion),
    };
  }

  if (payload.role !== "administrator") {
    return {
      ok: false,
      response: clinicErrorResponse("forbidden_role", 403, contractVersion),
    };
  }

  return {
    ok: false,
    response: clinicErrorResponse("unauthenticated", 401, contractVersion),
  };
}
