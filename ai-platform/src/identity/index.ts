/**
 * Identity stage — TokenVerifier port and issuer-token verification (P3.2).
 */

import type { AlertEnv } from "../alert";
import { raiseAl20 } from "../alert";
import {
  type ConfigCache,
  ConfigCacheMissError,
  type ConfigEntityKind,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import { noopLogger } from "../logger";
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
  /** Wall clock for config-cache consult/remember; defaults to `now * 1000`. */
  nowMs?: number;
  cache: ConfigCache;
  reader: D1Reader;
  issuerId: string;
  db?: D1Database;
  alertEnv?: AlertEnv;
}

export type VerifyResult =
  | { ok: true; principal: Principal }
  | { ok: false; code: "unauthenticated" | "suspended" };

export interface TokenVerifier {
  verify(token: string, ctx: VerifyContext): Promise<VerifyResult>;
}

/** Maximum AAT lifetime (`exp − iat`) in seconds. §5.6 "short lifetime, minutes". */
export const MAX_AAT_LIFETIME_SECONDS = 600;

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

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
    error_code: "suspended",
    installation_id: installationId,
  });
  return { ok: false, code: "suspended" };
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

function buildPrincipal(payload: AatPayload, installationId: string): Principal {
  const principal: Principal = {
    installationId,
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

function isIssuerKeyWithinValidityWindow(
  keyRow: Record<string, unknown>,
  nowSeconds: number,
): boolean {
  if (isString(keyRow.not_before)) {
    const notBeforeMs = Date.parse(keyRow.not_before);
    if (
      !Number.isNaN(notBeforeMs) &&
      nowSeconds < Math.floor(notBeforeMs / 1000)
    ) {
      return false;
    }
  }

  if (isString(keyRow.not_after)) {
    const notAfterMs = Date.parse(keyRow.not_after);
    if (
      !Number.isNaN(notAfterMs) &&
      nowSeconds >= Math.floor(notAfterMs / 1000)
    ) {
      return false;
    }
  }

  return true;
}

function isIssuerKeyUsable(
  keyRow: Record<string, unknown>,
  nowSeconds: number,
): boolean {
  const status = keyRow.status;
  if (status === "revoked") {
    return false;
  }
  if (status !== "active" && status !== "retiring") {
    return false;
  }
  return isIssuerKeyWithinValidityWindow(keyRow, nowSeconds);
}

async function loadConfigAt(
  ctx: VerifyContext,
  kind: ConfigEntityKind,
  key: string,
): Promise<Record<string, unknown>> {
  return loadConfig(
    ctx.cache,
    ctx.reader,
    kind,
    key,
    noopLogger,
    ctx.nowMs ?? ctx.now * 1000,
  );
}

async function countEpochOneBindingsLast24Hours(
  db: D1Database,
  nowSeconds: number,
): Promise<number> {
  const nowIso = new Date(nowSeconds * 1000).toISOString();
  const windowStart = new Date(Date.parse(nowIso) - ONE_DAY_MS).toISOString();
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS count
       FROM tenant_binding
       WHERE epoch = 1 AND created_at > ?`,
    )
    .bind(windowStart)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function readActiveBindingFromD1(
  db: D1Database,
  orgId: string,
): Promise<Record<string, unknown> | null> {
  return db
    .prepare(
      `SELECT * FROM tenant_binding
       WHERE org_id = ? AND status = 'active'
       ORDER BY epoch DESC
       LIMIT 1`,
    )
    .bind(orgId)
    .first<Record<string, unknown>>();
}

async function resolveInstallationId(
  ctx: VerifyContext,
  orgId: string,
): Promise<string | VerifyResult> {
  try {
    const binding = await loadConfigAt(ctx, "tenant_bindings", orgId);
    if (!isString(binding.installation_id)) {
      return rejectUnauthenticated();
    }
    return binding.installation_id;
  } catch (error) {
    if (!(error instanceof ConfigCacheMissError)) {
      throw error;
    }
  }

  if (ctx.db === undefined) {
    return rejectUnauthenticated();
  }

  const recentCreations = await countEpochOneBindingsLast24Hours(ctx.db, ctx.now);
  if (recentCreations >= 50) {
    if (ctx.alertEnv !== undefined) {
      await raiseAl20(ctx.alertEnv);
    }
    return rejectUnauthenticated();
  }

  const installationId = crypto.randomUUID();
  const createdAt = new Date(ctx.now * 1000).toISOString();

  try {
    await ctx.db.batch([
      ctx.db
        .prepare(
          `INSERT INTO installation (
            installation_id, org_id, status, display_name, region, enrolled_at
          ) VALUES (?, ?, 'active', '', '', ?)`,
        )
        .bind(installationId, orgId, createdAt),
      ctx.db
        .prepare(
          `INSERT INTO tenant_binding (
            org_id, installation_id, epoch, status, retired_at, reason, created_at
          ) VALUES (?, ?, 1, 'active', NULL, NULL, ?)`,
        )
        .bind(orgId, installationId, createdAt),
    ]);
  } catch {
    const existing = await readActiveBindingFromD1(ctx.db, orgId);
    if (existing === null || !isString(existing.installation_id)) {
      return rejectUnauthenticated();
    }
    ctx.cache.remember(
      "tenant_bindings",
      orgId,
      existing,
      ctx.now * 1000,
    );
    return existing.installation_id;
  }

  const bindingRow: Record<string, unknown> = {
    org_id: orgId,
    installation_id: installationId,
    epoch: 1,
    status: "active",
    retired_at: null,
    reason: null,
    created_at: createdAt,
  };
  ctx.cache.remember("tenant_bindings", orgId, bindingRow, ctx.now * 1000);
  ctx.cache.remember(
    "installations",
    installationId,
    {
      installation_id: installationId,
      org_id: orgId,
      status: "active",
      display_name: "",
      region: "",
      enrolled_at: createdAt,
    },
    ctx.now * 1000,
  );

  return installationId;
}

export class IssuerTokenVerifier implements TokenVerifier {
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

    if (payload.aud !== ctx.audience) {
      return rejectUnauthenticated();
    }

    if (
      payload.iat - ctx.clockSkewSeconds > ctx.now ||
      ctx.now > payload.exp + ctx.clockSkewSeconds
    ) {
      return rejectUnauthenticated();
    }

    if (payload.exp - payload.iat > MAX_AAT_LIFETIME_SECONDS) {
      return rejectUnauthenticated();
    }

    let contractRow: Record<string, unknown>;
    try {
      contractRow = await loadConfigAt(ctx, "token_contracts", payload.ver);
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        return rejectUnauthenticated();
      }
      throw error;
    }

    if (contractRow.retired_at != null) {
      return rejectUnauthenticated();
    }

    const kid = header.kid;

    let keyRow: Record<string, unknown>;
    try {
      keyRow = await loadConfigAt(ctx, "issuer_keys", kid);
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        return rejectUnauthenticated();
      }
      throw error;
    }

    if (!isIssuerKeyUsable(keyRow, ctx.now)) {
      return rejectUnauthenticated();
    }

    if (payload.iss !== ctx.issuerId) {
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

    const installationIdOrReject = await resolveInstallationId(ctx, payload.org);
    if (typeof installationIdOrReject !== "string") {
      return installationIdOrReject;
    }
    const installationId = installationIdOrReject;

    let installation: Record<string, unknown>;
    try {
      installation = await loadConfigAt(ctx, "installations", installationId);
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        return rejectUnauthenticated(installationId);
      }
      throw error;
    }

    if (installation.status === "suspended") {
      return rejectSuspended(installationId);
    }
    if (installation.status !== "active") {
      return rejectUnauthenticated(installationId);
    }

    return {
      ok: true,
      principal: buildPrincipal(payload, installationId),
    };
  }
}
