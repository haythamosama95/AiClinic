/**
 * Identity stage — TokenVerifier port and enrolled-key verification (B3 §4.3.2).
 */

import {
  type ConfigCache,
  ConfigCacheMissError,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import { recordGuardRejection } from "../rate-limit";

export interface Principal {
  readonly installationId: string;
  readonly organizationId: string;
  readonly branchId: string;
  readonly actorId: string;
  readonly role: string;
  readonly scopes: readonly string[];
  readonly jti: string;
  readonly iat: number;
  readonly exp: number;
  readonly ver: string;
}

export interface VerifyContext {
  audience: string;
  clockSkewSeconds: number;
  now: number;
  cache: ConfigCache;
  reader: D1Reader;
}

export type VerifyResult =
  | { ok: true; principal: Principal }
  | { ok: false; code: "unauthenticated" | "installation_suspended" };

export interface TokenVerifier {
  verify(token: string, ctx: VerifyContext): Promise<VerifyResult>;
}

/** Guard-metric bucket for failures before signature verification (§4.7). */
const UNVERIFIED_INSTALLATION_BUCKET = "unverified";

type AatPayload = {
  iss: string;
  aud: string;
  sub: string;
  org: string;
  branch: string;
  role: string;
  scopes: string[];
  jti: string;
  iat: number;
  exp: number;
  ver: string;
};

function rejectUnauthenticated(installationId?: string): VerifyResult {
  recordGuardRejection({
    error_code: "unauthenticated",
    installation_id: installationId ?? UNVERIFIED_INSTALLATION_BUCKET,
  });
  return { ok: false, code: "unauthenticated" };
}

function rejectSuspended(installationId: string): VerifyResult {
  recordGuardRejection({
    error_code: "installation_suspended",
    installation_id: installationId,
  });
  return { ok: false, code: "installation_suspended" };
}

function base64urlDecode(segment: string): Uint8Array | null {
  try {
    const padded = segment + "=".repeat((4 - (segment.length % 4)) % 4);
    const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
}

function parseJson<T>(bytes: Uint8Array): T | null {
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as T;
  } catch {
    return null;
  }
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function parsePayloadClaims(raw: Record<string, unknown>): AatPayload | null {
  const requiredStringFields = [
    "iss",
    "aud",
    "sub",
    "org",
    "branch",
    "role",
    "jti",
    "ver",
  ] as const;

  for (const field of requiredStringFields) {
    if (!isString(raw[field])) {
      return null;
    }
  }

  if (!Array.isArray(raw.scopes) || !raw.scopes.every((scope) => typeof scope === "string")) {
    return null;
  }

  if (typeof raw.iat !== "number" || typeof raw.exp !== "number") {
    return null;
  }

  return {
    iss: raw.iss,
    aud: raw.aud,
    sub: raw.sub,
    org: raw.org,
    branch: raw.branch,
    role: raw.role,
    scopes: [...raw.scopes],
    jti: raw.jti,
    iat: raw.iat,
    exp: raw.exp,
    ver: raw.ver,
  };
}

function buildPrincipal(payload: AatPayload): Principal {
  const principal: Principal = {
    installationId: payload.iss,
    organizationId: payload.org,
    branchId: payload.branch,
    actorId: payload.sub,
    role: payload.role,
    scopes: Object.freeze([...payload.scopes]),
    jti: payload.jti,
    iat: payload.iat,
    exp: payload.exp,
    ver: payload.ver,
  };
  return Object.freeze(principal);
}

async function importEd25519PublicKey(
  keyRow: Record<string, unknown>,
): Promise<CryptoKey | null> {
  const jwk = keyRow.jwk;
  if (
    jwk &&
    typeof jwk === "object" &&
    (jwk as { kty?: string }).kty === "OKP" &&
    (jwk as { crv?: string }).crv === "Ed25519" &&
    isString((jwk as { x?: string }).x)
  ) {
    try {
      return await crypto.subtle.importKey(
        "jwk",
        {
          kty: "OKP",
          crv: "Ed25519",
          x: (jwk as { x: string }).x,
        },
        { name: "Ed25519" },
        false,
        ["verify"],
      );
    } catch {
      return null;
    }
  }

  if (!isString(keyRow.public_key)) {
    return null;
  }

  const rawBytes = base64urlDecode(keyRow.public_key);
  if (!rawBytes) {
    return null;
  }

  try {
    return await crypto.subtle.importKey(
      "raw",
      rawBytes,
      { name: "Ed25519" },
      false,
      ["verify"],
    );
  } catch {
    return null;
  }
}

/** Enforce `valid_from <= now < COALESCE(valid_until, +inf)` (§4.5). */
function isKeyWithinValidityWindow(
  keyRow: Record<string, unknown>,
  nowSeconds: number,
): boolean {
  const nowMs = nowSeconds * 1000;

  if (isString(keyRow.valid_from)) {
    const validFromMs = Date.parse(keyRow.valid_from);
    if (!Number.isNaN(validFromMs) && nowMs < validFromMs) {
      return false;
    }
  }

  if (isString(keyRow.valid_until)) {
    const validUntilMs = Date.parse(keyRow.valid_until);
    if (!Number.isNaN(validUntilMs) && nowMs >= validUntilMs) {
      return false;
    }
  }

  return true;
}

export class EnrolledKeyVerifier implements TokenVerifier {
  async verify(token: string, ctx: VerifyContext): Promise<VerifyResult> {
    const segments = token.split(".");
    if (segments.length !== 3) {
      return rejectUnauthenticated();
    }

    const [headerB64, payloadB64, signatureB64] = segments;
    if (!headerB64 || !payloadB64 || !signatureB64) {
      return rejectUnauthenticated();
    }

    const headerBytes = base64urlDecode(headerB64);
    if (!headerBytes) {
      return rejectUnauthenticated();
    }

    const header = parseJson<{ alg?: string; kid?: string }>(headerBytes);
    if (!header) {
      return rejectUnauthenticated();
    }

    if (header.alg !== "EdDSA") {
      return rejectUnauthenticated();
    }

    if (!isString(header.kid) || header.kid.length === 0) {
      return rejectUnauthenticated();
    }

    const payloadBytes = base64urlDecode(payloadB64);
    if (!payloadBytes) {
      return rejectUnauthenticated();
    }

    const rawPayload = parseJson<Record<string, unknown>>(payloadBytes);
    if (!rawPayload) {
      return rejectUnauthenticated();
    }

    const payload = parsePayloadClaims(rawPayload);
    if (!payload) {
      return rejectUnauthenticated();
    }

    // Cheap claim checks before any config-cache / D1 load (§4.3.2).
    // Pre-verification: never attribute forged payload.iss (§4.7).
    if (payload.aud !== ctx.audience) {
      return rejectUnauthenticated();
    }

    if (
      payload.iat - ctx.clockSkewSeconds > ctx.now ||
      ctx.now > payload.exp + ctx.clockSkewSeconds
    ) {
      return rejectUnauthenticated();
    }

    let installation: Record<string, unknown>;
    try {
      installation = await loadConfig(ctx.cache, ctx.reader, "installations", payload.iss);
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        return rejectUnauthenticated();
      }
      throw error;
    }

    let keyRow: Record<string, unknown>;
    try {
      keyRow = await loadConfig(ctx.cache, ctx.reader, "keys", header.kid);
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        return rejectUnauthenticated();
      }
      throw error;
    }

    if (keyRow.revoked_at != null) {
      return rejectUnauthenticated();
    }

    if (!isKeyWithinValidityWindow(keyRow, ctx.now)) {
      return rejectUnauthenticated();
    }

    // Key selected by iss AND kid (§4.3.2) — bind ownership before verify.
    if (keyRow.installation_id !== payload.iss) {
      return rejectUnauthenticated();
    }

    const signatureBytes = base64urlDecode(signatureB64);
    if (!signatureBytes) {
      return rejectUnauthenticated();
    }

    const publicKey = await importEd25519PublicKey(keyRow);
    if (!publicKey) {
      return rejectUnauthenticated();
    }

    const signingInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const valid = await crypto.subtle.verify(
      { name: "Ed25519" },
      publicKey,
      signatureBytes,
      signingInput,
    );

    if (!valid) {
      return rejectUnauthenticated();
    }

    // Signature verified — installation_id attribution is safe from here (§4.7).
    const installationId = payload.iss;

    // Fail closed on lifecycle: only `active` authenticates (§4.3.2 / B2 delete).
    if (installation.status === "suspended") {
      return rejectSuspended(installationId);
    }
    if (installation.status !== "active") {
      return rejectUnauthenticated(installationId);
    }

    let contractRow: Record<string, unknown>;
    try {
      contractRow = await loadConfig(ctx.cache, ctx.reader, "token_contracts", payload.ver);
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        return rejectUnauthenticated(installationId);
      }
      throw error;
    }

    if (contractRow.retired_at != null) {
      return rejectUnauthenticated(installationId);
    }

    return { ok: true, principal: buildPrincipal(payload) };
  }
}
