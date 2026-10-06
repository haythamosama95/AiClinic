import { WorkerEntrypoint, env as workerBindings } from "cloudflare:workers";
import {
  CHANNEL_VERSIONS,
  canonicalize,
  grantEnvelopeHash,
  negotiate,
  operationChallenge,
  parseRegistrationAttestation,
  sha256Hex,
  validateGrantEnvelope,
  validateOperation,
  verifyAccessJwt,
  verifyAssertion,
  verifyGrantSignature,
  signCompactJws,
  receiptSigningBytes,
  type AccessCertsDocument,
  type Assertion,
} from "vendor-contracts";
import type { DurationScale } from "../coverage/calendar";
import {
  executeBeginTransfer,
  executeDeleteInstallation,
  executeTransferIn,
  executeTransferOut,
  readTransferByAssertionSha256,
  retireHeldBindingIfEmpty,
  transferRowToDetail,
} from "../coverage/transfer";
import {
  raiseAl13,
  raiseAl13Bootstrap,
  raiseAl13IssuerKey,
  raiseAl13ServiceKey,
} from "../alert/index";
import {
  clockNowIso,
  clockNowMs,
  clockNowSeconds,
  type ClockEnv,
} from "../clock";
import { writeEntrypointAudit } from "../control/audit";

const VENDOR_CHANNEL = CHANNEL_VERSIONS.vendorEntrypoint;
const ACTIVATION_MS = 24 * 60 * 60 * 1000;
const ASSERTION_FRESHNESS_MS = 5 * 60 * 1000;

const METHOD_CLASS = {
  registerOperatorCredential: "HP",
  revokeOperatorCredential: "HP",
  registerIssuerKey: "HP",
  retireIssuerKey: "HP",
  revokeIssuerKey: "HP",
  registerServiceKey: "HP",
  revokeServiceKey: "HP",
  publishPlanVersion: "HP",
  retirePlanVersion: "HP",
  setCeilingPolicy: "HP",
  listOperatorCredentials: "M",
  listIssuerKeys: "M",
  listServiceKeys: "M",
  grant: "M",
  getCoverage: "M",
  listGrants: "M",
  readCoverageEvents: "M",
  voidForReversal: "M",
  releaseHeld: "HP",
  voidGrant: "HP",
  listGrantsForVoid: "M",
  beginTransfer: "HP",
  transferOut: "M",
  transferIn: "M",
  deleteInstallation: "HP",
} as const;

type VendorMethod = keyof typeof METHOD_CLASS;

type HpVendorMethod = {
  [K in VendorMethod]: (typeof METHOD_CLASS)[K] extends "HP" ? K : never;
}[VendorMethod];

type HpAssertionMethod = HpVendorMethod | "grant";

type CeilingPolicyRow = {
  version: number;
  per_grant_max_days: number;
  per_grant_max_allowance_months: number;
  window_days: number;
  window_max_days: number;
  window_max_allowance_months: number;
  max_paid_grace_days: number;
  paid_cap_rule: string;
  set_by: string;
  assertion_sha256: string;
};

type VendorResultEnvelope = {
  contract_version: number;
  result: "ok" | "rejected" | "conflict";
  code: string;
  detail: string;
};

type GrantResultEnvelope = {
  contract_version: number;
  result:
    | "ok"
    | "rejected"
    | "conflict"
    | "applied"
    | "already_applied"
    | "transient";
  code: string;
  detail: string;
  receipt?: Record<string, unknown>;
};

const VOID_NIL_UUID = "00000000-0000-0000-0000-000000000000";
const HEX64_RE = /^[0-9a-f]{64}$/u;

type VendorEnv = ClockEnv & {
  DB: D1Database;
  R2: R2Bucket;
  DO: DurableObjectNamespace;
  ISSUER_ID: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  WEBAUTHN_RP_ID: string;
  WEBAUTHN_ORIGIN: string;
  ALERT_EMAIL_TO: string;
  PLATFORM_SIGNING_KEY: string;
  DURATION_SCALE?: string;
  SEND_EMAIL: {
    send(message: {
      from: string;
      to: string;
      subject: string;
      text: string;
    }): Promise<void>;
  };
};

type OperatorCredentialRow = {
  credential_id: string;
  operator_email: string;
  public_key_cose: string;
  alg: string;
  status: string;
  activates_at: string;
  approved_by: string | null;
  revoked_by: string | null;
};

type IssuerKeyRow = {
  kid: string;
  issuer: string;
  public_key: string;
  status: string;
  not_before: string;
  not_after: string;
  registered_by: string;
  assertion_sha256: string;
};

type ServiceKeyRow = {
  kid: string;
  service: string;
  public_key: string;
  status: string;
  not_before: string;
  not_after: string;
  registered_by: string;
  assertion_sha256: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseRequestedVersion(
  args: Record<string, unknown>,
): number | null {
  const raw = args.contract_version;
  if (raw === undefined || raw === null) {
    return null;
  }
  if (!Number.isInteger(raw)) {
    return null;
  }
  return raw as number;
}

function rejected(
  contractVersion: number,
  code: string,
  detail = "",
): VendorResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "rejected",
    code,
    detail,
  };
}

function ok(contractVersion: number, detail: string): VendorResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "ok",
    code: "",
    detail,
  };
}

function conflict(contractVersion: number, code: string): VendorResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "conflict",
    code,
    detail: "",
  };
}

function rowToDetail(row: OperatorCredentialRow): string {
  const ordered = {
    credential_id: row.credential_id,
    operator_email: row.operator_email,
    public_key_cose: row.public_key_cose,
    alg: row.alg,
    status: row.status,
    activates_at: row.activates_at,
    approved_by: row.approved_by,
    revoked_by: row.revoked_by,
  };
  return JSON.stringify(ordered);
}

function issuerKeyRowToDetail(row: IssuerKeyRow): string {
  const ordered = {
    kid: row.kid,
    issuer: row.issuer,
    public_key: row.public_key,
    status: row.status,
    not_before: row.not_before,
    not_after: row.not_after,
    registered_by: row.registered_by,
    assertion_sha256: row.assertion_sha256,
  };
  return JSON.stringify(ordered);
}

function isValidEd25519PublicKeyEncoding(publicKey: string): boolean {
  const decoded = base64UrlDecode(publicKey);
  return decoded !== null && decoded.length === 32;
}

async function readIssuerKey(
  db: D1Database,
  kid: string,
): Promise<IssuerKeyRow | null> {
  return db
    .prepare(
      `SELECT kid, issuer, public_key, status, not_before, not_after,
              registered_by, assertion_sha256
       FROM issuer_key WHERE kid = ?`,
    )
    .bind(kid)
    .first<IssuerKeyRow>();
}

function serviceKeyRowToDetail(row: ServiceKeyRow): string {
  const ordered = {
    kid: row.kid,
    service: row.service,
    public_key: row.public_key,
    status: row.status,
    not_before: row.not_before,
    not_after: row.not_after,
    registered_by: row.registered_by,
    assertion_sha256: row.assertion_sha256,
  };
  return JSON.stringify(ordered);
}

async function readServiceKey(
  db: D1Database,
  kid: string,
): Promise<ServiceKeyRow | null> {
  return db
    .prepare(
      `SELECT kid, service, public_key, status, not_before, not_after,
              registered_by, assertion_sha256
       FROM service_key WHERE kid = ?`,
    )
    .bind(kid)
    .first<ServiceKeyRow>();
}

type PlanVersionRow = {
  plan_id: string;
  version: number;
  display_name: string;
  capabilities: string;
  max_cost_class: string;
  concurrency_limit: number;
  max_allowance_per_month: number;
  status: string;
  published_by: string;
  assertion_sha256: string;
};

function planVersionRowToDetail(row: PlanVersionRow): string {
  const capabilities = JSON.parse(row.capabilities) as unknown;
  const ordered = {
    plan_id: row.plan_id,
    version: row.version,
    display_name: row.display_name,
    capabilities,
    max_cost_class: row.max_cost_class,
    concurrency_limit: row.concurrency_limit,
    max_allowance_per_month: row.max_allowance_per_month,
    status: row.status,
    published_by: row.published_by,
    assertion_sha256: row.assertion_sha256,
  };
  return JSON.stringify(ordered);
}

function planVersionContentMatches(
  row: PlanVersionRow,
  content: {
    display_name: string;
    capabilities: unknown;
    max_cost_class: string;
    concurrency_limit: number;
    max_allowance_per_month: number;
  },
): boolean {
  if (row.display_name !== content.display_name) {
    return false;
  }
  if (row.max_cost_class !== content.max_cost_class) {
    return false;
  }
  if (row.concurrency_limit !== content.concurrency_limit) {
    return false;
  }
  if (row.max_allowance_per_month !== content.max_allowance_per_month) {
    return false;
  }
  const storedCapabilities = JSON.parse(row.capabilities) as unknown;
  return stableJson(storedCapabilities) === stableJson(content.capabilities);
}

function grantRejected(
  contractVersion: number,
  code: string,
  detail = "",
): GrantResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "rejected",
    code,
    detail,
  };
}

function grantTransient(
  contractVersion: number,
  detail: string,
): GrantResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "transient",
    code: "",
    detail,
  };
}

function jwsPayloadBytes(jws: string): Uint8Array | null {
  const parts = jws.split(".");
  if (parts.length !== 3 || !parts[1]) {
    return null;
  }
  return base64UrlDecode(parts[1]);
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) {
    return false;
  }
  for (let index = 0; index < a.byteLength; index += 1) {
    if (a[index] !== b[index]) {
      return false;
    }
  }
  return true;
}

async function importEd25519VerifyKey(
  publicKeyB64: string,
): Promise<CryptoKey | null> {
  const raw = base64UrlDecode(publicKeyB64);
  if (raw === null || raw.length !== 32) {
    return null;
  }
  return crypto.subtle.importKey(
    "raw",
    raw,
    { name: "Ed25519" },
    false,
    ["verify"],
  );
}

async function readPlanVersion(
  db: D1Database,
  planId: string,
  version: number,
): Promise<PlanVersionRow | null> {
  return db
    .prepare(
      `SELECT plan_id, version, display_name, capabilities, max_cost_class,
              concurrency_limit, max_allowance_per_month, status, published_by,
              assertion_sha256
       FROM plan_version WHERE plan_id = ? AND version = ?`,
    )
    .bind(planId, version)
    .first<PlanVersionRow>();
}

async function readActiveTenantBinding(
  db: D1Database,
  orgId: string,
): Promise<{ installation_id: string; epoch: number } | null> {
  return db
    .prepare(
      `SELECT installation_id, epoch FROM tenant_binding
       WHERE org_id = ? AND status = 'active'
       ORDER BY epoch DESC
       LIMIT 1`,
    )
    .bind(orgId)
    .first<{ installation_id: string; epoch: number }>();
}

async function readLiveTenantBinding(
  db: D1Database,
  orgId: string,
): Promise<{ installation_id: string; epoch: number; status: string } | null> {
  return db
    .prepare(
      `SELECT installation_id, epoch, status FROM tenant_binding
       WHERE org_id = ? AND status IN ('active', 'held_for_transfer')
       ORDER BY epoch DESC
       LIMIT 1`,
    )
    .bind(orgId)
    .first<{ installation_id: string; epoch: number; status: string }>();
}

async function readTenantBindingForInstallation(
  db: D1Database,
  orgId: string,
  installationId: string,
): Promise<{ installation_id: string; epoch: number; status: string } | null> {
  return db
    .prepare(
      `SELECT installation_id, epoch, status FROM tenant_binding
       WHERE org_id = ? AND installation_id = ?`,
    )
    .bind(orgId, installationId)
    .first<{ installation_id: string; epoch: number; status: string }>();
}

async function readMaxTenantBindingEpoch(
  db: D1Database,
  orgId: string,
): Promise<number> {
  const row = await db
    .prepare(`SELECT MAX(epoch) AS max_epoch FROM tenant_binding WHERE org_id = ?`)
    .bind(orgId)
    .first<{ max_epoch: number | null }>();
  return row?.max_epoch ?? 0;
}

async function callCoverageDo(
  env: VendorEnv,
  installationId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown> | null> {
  const id = env.DO.idFromName(installationId);
  const stub = env.DO.get(id);
  try {
    const response = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        installationId,
        ...body,
      }),
    });
    if (!response.ok) {
      return null;
    }
    return (await response.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function durationScaleFromEnv(env: VendorEnv): DurationScale | undefined {
  const bindings = workerBindings as { DURATION_SCALE?: string };
  const raw = bindings.DURATION_SCALE ?? env.DURATION_SCALE;
  return raw === "staging" ? "staging" : undefined;
}

async function resolveOrInsertGrantBinding(
  env: VendorEnv,
  orgId: string,
): Promise<string> {
  const existing = await readLiveTenantBinding(env.DB, orgId);
  if (existing !== null) {
    return existing.installation_id;
  }

  const installationId = crypto.randomUUID();
  const createdAt = await clockNowIso(env);
  const nextEpoch = (await readMaxTenantBindingEpoch(env.DB, orgId)) + 1;

  try {
    await env.DB.batch([
      env.DB
        .prepare(
          `INSERT INTO installation (
            installation_id, org_id, status, display_name, region, enrolled_at
          ) VALUES (?, ?, 'active', '', '', ?)`,
        )
        .bind(installationId, orgId, createdAt),
      env.DB
        .prepare(
          `INSERT INTO tenant_binding (
            org_id, installation_id, epoch, status, retired_at, reason, created_at
          ) VALUES (?, ?, ?, 'active', NULL, NULL, ?)`,
        )
        .bind(orgId, installationId, nextEpoch, createdAt),
    ]);
  } catch {
    const rebound = await readLiveTenantBinding(env.DB, orgId);
    if (rebound === null) {
      throw new Error("tenant_binding insert conflict without live row");
    }
    return rebound.installation_id;
  }

  return installationId;
}

function serviceKeyActiveAt(row: ServiceKeyRow, nowIso: string): boolean {
  if (row.status !== "active") {
    return false;
  }
  const nowMs = Date.parse(nowIso);
  const notBeforeMs = Date.parse(row.not_before);
  const notAfterMs = Date.parse(row.not_after);
  if (Number.isNaN(nowMs) || Number.isNaN(notBeforeMs) || Number.isNaN(notAfterMs)) {
    return false;
  }
  return nowMs >= notBeforeMs && nowMs <= notAfterMs;
}

function isStringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((entry) => typeof entry === "string")
  );
}

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  } catch {
    return null;
  }
}

function decodeAssertion(
  value: unknown,
): Assertion | null {
  if (!isRecord(value)) {
    return null;
  }
  const alg = value.alg;
  if (alg !== "ES256" && alg !== "EdDSA") {
    return null;
  }
  if (
    typeof value.authenticator_data !== "string" ||
    typeof value.client_data_json !== "string" ||
    typeof value.signature !== "string"
  ) {
    return null;
  }
  const authenticatorData = base64UrlDecode(value.authenticator_data);
  const clientDataJSON = base64UrlDecode(value.client_data_json);
  const signature = base64UrlDecode(value.signature);
  if (
    authenticatorData === null ||
    clientDataJSON === null ||
    signature === null
  ) {
    return null;
  }
  return {
    alg,
    authenticatorData,
    clientDataJSON,
    signature,
  };
}

function decodeAttestation(value: unknown): { alg: "ES256" | "EdDSA"; publicKey: Uint8Array } | null {
  if (!isRecord(value)) {
    return null;
  }
  if (value.alg !== "ES256" && value.alg !== "EdDSA") {
    return null;
  }
  if (typeof value.public_key !== "string") {
    return null;
  }
  const publicKey = base64UrlDecode(value.public_key);
  if (publicKey === null) {
    return null;
  }
  return { alg: value.alg, publicKey };
}

async function loadAccessCerts(env: VendorEnv): Promise<AccessCertsDocument | null> {
  const issuer = `https://${env.ACCESS_TEAM_DOMAIN}`;
  const url = `${issuer}/cdn-cgi/access/certs`;
  try {
    const response = await fetch(url);
    if (!response.ok) {
      return null;
    }
    const body = (await response.json()) as { keys?: AccessCertsDocument["keys"] };
    if (!Array.isArray(body.keys)) {
      return null;
    }
    return { issuer, keys: body.keys };
  } catch {
    return null;
  }
}

async function verifyHpAccess(
  env: VendorEnv,
  accessJwt: unknown,
): Promise<{ ok: true; email: string } | { ok: false }> {
  if (typeof accessJwt !== "string" || accessJwt.length === 0) {
    return { ok: false };
  }
  const certs = await loadAccessCerts(env);
  if (certs === null) {
    return { ok: false };
  }
  const nowSeconds = await clockNowSeconds(env);
  return verifyAccessJwt({
    jwt: accessJwt,
    certs,
    aud: env.ACCESS_AUD,
    nowSeconds,
  });
}

async function operatorCredentialCount(db: D1Database): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) AS count FROM operator_credential")
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function readOperatorCredential(
  db: D1Database,
  credentialId: string,
): Promise<OperatorCredentialRow | null> {
  return db
    .prepare(
      `SELECT credential_id, operator_email, public_key_cose, alg, status,
              activates_at, approved_by, revoked_by
       FROM operator_credential WHERE credential_id = ?`,
    )
    .bind(credentialId)
    .first<OperatorCredentialRow>();
}

async function promoteCredentialIfDue(
  env: VendorEnv,
  row: OperatorCredentialRow,
): Promise<OperatorCredentialRow> {
  if (row.status !== "pending") {
    return row;
  }
  const nowIso = await clockNowIso(env);
  if (row.activates_at > nowIso) {
    return row;
  }
  await env.DB.prepare(
    `UPDATE operator_credential SET status = 'active'
     WHERE credential_id = ? AND status = 'pending'`,
  )
    .bind(row.credential_id)
    .run();
  const updated = await readOperatorCredential(env.DB, row.credential_id);
  return updated ?? { ...row, status: "active" };
}

async function promoteAllDueCredentials(env: VendorEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  await env.DB.prepare(
    `UPDATE operator_credential SET status = 'active'
     WHERE status = 'pending' AND activates_at <= ?`,
  )
    .bind(nowIso)
    .run();
}

async function operationAssertionSha256(
  operation: Record<string, unknown>,
): Promise<string> {
  return sha256Hex(canonicalize(operation));
}

async function assertionChallengeUsed(
  db: D1Database,
  challengeSha256: string,
): Promise<boolean> {
  const row = await db
    .prepare("SELECT challenge_sha256 FROM assertion_used WHERE challenge_sha256 = ?")
    .bind(challengeSha256)
    .first<{ challenge_sha256: string }>();
  return row !== null;
}

async function insertAssertionUsed(
  env: VendorEnv,
  challengeSha256: string,
  credentialId: string,
): Promise<void> {
  const usedAt = await clockNowIso(env);
  await env.DB.prepare(
    `INSERT INTO assertion_used (challenge_sha256, credential_id, used_at)
     VALUES (?, ?, ?)`,
  )
    .bind(challengeSha256, credentialId, usedAt)
    .run();
}

async function importSignerPublicKey(
  row: OperatorCredentialRow,
): Promise<CryptoKey | null> {
  const publicKeyBytes = base64UrlDecode(row.public_key_cose);
  if (publicKeyBytes === null) {
    return null;
  }
  const alg = row.alg === "ES256" || row.alg === "EdDSA" ? row.alg : null;
  if (alg === null) {
    return null;
  }
  const parsed = await parseRegistrationAttestation({
    alg,
    publicKey: publicKeyBytes,
  });
  return parsed.ok ? parsed.publicKey : null;
}

function stableJson(value: unknown): string {
  return JSON.stringify(value);
}

function operationParamsMatch(
  method: HpAssertionMethod,
  operation: Record<string, unknown>,
  rpcArgs: Record<string, unknown>,
  accessJwt: string,
  negotiatedVersion: number,
): boolean {
  if (operation.op !== method) {
    return false;
  }
  if (operation.contract_version !== negotiatedVersion) {
    return false;
  }
  if (!isRecord(operation.params)) {
    return false;
  }
  const params = operation.params;
  const expected: Record<string, unknown> = {
    contract_version: negotiatedVersion,
    access_jwt: accessJwt,
  };
  if (method === "registerOperatorCredential") {
    expected.credential_id = rpcArgs.credential_id;
    expected.attestation = rpcArgs.attestation;
    if (rpcArgs.signer_credential_id !== undefined) {
      expected.signer_credential_id = rpcArgs.signer_credential_id;
    }
  } else if (method === "revokeOperatorCredential") {
    expected.credential_id = rpcArgs.credential_id;
    expected.signer_credential_id = rpcArgs.signer_credential_id;
  } else if (method === "registerIssuerKey") {
    expected.kid = rpcArgs.kid;
    expected.public_key = rpcArgs.public_key;
    expected.not_before = rpcArgs.not_before;
    expected.not_after = rpcArgs.not_after;
  } else if (method === "registerServiceKey") {
    expected.kid = rpcArgs.kid;
    expected.public_key = rpcArgs.public_key;
    expected.not_before = rpcArgs.not_before;
    expected.not_after = rpcArgs.not_after;
  } else if (
    method === "retireIssuerKey" ||
    method === "revokeIssuerKey" ||
    method === "revokeServiceKey"
  ) {
    expected.kid = rpcArgs.kid;
  } else if (method === "publishPlanVersion") {
    expected.plan_id = rpcArgs.plan_id;
    expected.version = rpcArgs.version;
    expected.display_name = rpcArgs.display_name;
    expected.capabilities = rpcArgs.capabilities;
    expected.max_cost_class = rpcArgs.max_cost_class;
    expected.concurrency_limit = rpcArgs.concurrency_limit;
    expected.max_allowance_per_month = rpcArgs.max_allowance_per_month;
  } else if (method === "retirePlanVersion") {
    expected.plan_id = rpcArgs.plan_id;
    expected.version = rpcArgs.version;
  } else if (method === "grant") {
    expected.envelope = rpcArgs.envelope;
  } else if (method === "setCeilingPolicy") {
    expected.per_grant_max_days = rpcArgs.per_grant_max_days;
    expected.per_grant_max_allowance_months =
      rpcArgs.per_grant_max_allowance_months;
    expected.window_days = rpcArgs.window_days;
    expected.window_max_days = rpcArgs.window_max_days;
    expected.window_max_allowance_months = rpcArgs.window_max_allowance_months;
    expected.max_paid_grace_days = rpcArgs.max_paid_grace_days;
    expected.paid_cap_rule = rpcArgs.paid_cap_rule;
  } else if (method === "releaseHeld" || method === "voidGrant") {
    expected.grant_id = rpcArgs.grant_id;
    expected.reason = rpcArgs.reason;
  } else if (method === "beginTransfer") {
    expected.org_id = rpcArgs.org_id;
    expected.from_installation_id = rpcArgs.from_installation_id;
    expected.reason = rpcArgs.reason;
  } else if (method === "deleteInstallation") {
    expected.org_id = rpcArgs.org_id;
    expected.reason = rpcArgs.reason;
  } else {
    return false;
  }
  return stableJson(params) === stableJson(expected);
}

function hpAuditTarget(
  method: HpAssertionMethod,
  rpcArgs: Record<string, unknown>,
): string {
  if (
    method === "registerIssuerKey" ||
    method === "retireIssuerKey" ||
    method === "revokeIssuerKey" ||
    method === "registerServiceKey" ||
    method === "revokeServiceKey"
  ) {
    return typeof rpcArgs.kid === "string" ? rpcArgs.kid : "";
  }
  if (method === "publishPlanVersion" || method === "retirePlanVersion") {
    const planId = typeof rpcArgs.plan_id === "string" ? rpcArgs.plan_id : "";
    const version =
      typeof rpcArgs.version === "number" ? String(rpcArgs.version) : "";
    return `${planId}:${version}`;
  }
  if (method === "grant") {
    const envelope = rpcArgs.envelope;
    if (isRecord(envelope) && typeof envelope.grant_id === "string") {
      return envelope.grant_id;
    }
    return "";
  }
  if (method === "setCeilingPolicy") {
    return "ceiling_policy";
  }
  if (method === "releaseHeld" || method === "voidGrant") {
    return typeof rpcArgs.grant_id === "string" ? rpcArgs.grant_id : "";
  }
  if (method === "beginTransfer") {
    const fromId =
      typeof rpcArgs.from_installation_id === "string"
        ? rpcArgs.from_installation_id
        : "";
    const orgId = typeof rpcArgs.org_id === "string" ? rpcArgs.org_id : "";
    return `${orgId}:${fromId}`;
  }
  if (method === "deleteInstallation") {
    return typeof rpcArgs.org_id === "string" ? rpcArgs.org_id : "";
  }
  return typeof rpcArgs.credential_id === "string" ? rpcArgs.credential_id : "";
}

function ceilingPolicyRowToDetail(row: CeilingPolicyRow): string {
  const ordered = {
    version: row.version,
    per_grant_max_days: row.per_grant_max_days,
    per_grant_max_allowance_months: row.per_grant_max_allowance_months,
    window_days: row.window_days,
    window_max_days: row.window_max_days,
    window_max_allowance_months: row.window_max_allowance_months,
    max_paid_grace_days: row.max_paid_grace_days,
    paid_cap_rule: row.paid_cap_rule,
    set_by: row.set_by,
    assertion_sha256: row.assertion_sha256,
  };
  return JSON.stringify(ordered);
}

async function readCurrentCeilingPolicy(
  db: D1Database,
): Promise<CeilingPolicyRow | null> {
  return db
    .prepare(
      `SELECT version, per_grant_max_days, per_grant_max_allowance_months,
              window_days, window_max_days, window_max_allowance_months,
              max_paid_grace_days, paid_cap_rule, set_by, assertion_sha256
       FROM ceiling_policy ORDER BY version DESC LIMIT 1`,
    )
    .first<CeilingPolicyRow>();
}

async function readCeilingPolicyByAssertionSha256(
  db: D1Database,
  assertionSha256: string,
): Promise<CeilingPolicyRow | null> {
  if (assertionSha256.length === 0) {
    return null;
  }
  return db
    .prepare(
      `SELECT version, per_grant_max_days, per_grant_max_allowance_months,
              window_days, window_max_days, window_max_allowance_months,
              max_paid_grace_days, paid_cap_rule, set_by, assertion_sha256
       FROM ceiling_policy WHERE assertion_sha256 = ?`,
    )
    .bind(assertionSha256)
    .first<CeilingPolicyRow>();
}

async function assertionIssuedAtFresh(
  env: VendorEnv,
  issuedAt: string,
): Promise<boolean> {
  const issuedMs = Date.parse(issuedAt);
  if (Number.isNaN(issuedMs)) {
    return false;
  }
  const nowMs = await clockNowMs(env);
  return Math.abs(nowMs - issuedMs) <= ASSERTION_FRESHNESS_MS;
}

type HpAssertionReject = {
  ok: false;
  envelope: VendorResultEnvelope;
  auditAssertionSha256: string | null;
  auditTarget: string;
};

type HpAssertionOk = {
  ok: true;
  signer: OperatorCredentialRow;
  operation: Record<string, unknown>;
  assertionSha256: string;
  auditTarget: string;
};

type HpAssertionResult = HpAssertionReject | HpAssertionOk;

async function runHpAssertionChecks(
  env: VendorEnv,
  method: HpAssertionMethod,
  rpcArgs: Record<string, unknown>,
  accessEmail: string,
  negotiatedVersion: number,
): Promise<HpAssertionResult> {
  const auditTarget = hpAuditTarget(method, rpcArgs);
  const assertionRaw = rpcArgs.assertion;
  const operationRaw = rpcArgs.operation;
  const signerCredentialId = rpcArgs.signer_credential_id;

  if (assertionRaw === undefined || assertionRaw === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_required"),
      auditAssertionSha256: null,
      auditTarget,
    };
  }
  if (typeof signerCredentialId !== "string" || signerCredentialId.length === 0) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: null,
      auditTarget,
    };
  }
  if (!validateOperation(operationRaw).ok) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: null,
      auditTarget,
    };
  }
  const operation = operationRaw as Record<string, unknown>;
  const assertionSha256 = await operationAssertionSha256(operation);
  const accessJwt =
    typeof rpcArgs.access_jwt === "string" ? rpcArgs.access_jwt : "";
  if (!operationParamsMatch(method, operation, rpcArgs, accessJwt, negotiatedVersion)) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  const assertion = decodeAssertion(assertionRaw);
  if (assertion === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  let signer = await readOperatorCredential(env.DB, signerCredentialId);
  if (signer === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "credential_not_found"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  const publicKey = await importSignerPublicKey(signer);
  if (publicKey === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  const verified = await verifyAssertion({
    assertion,
    operation: operationRaw,
    rpId: env.WEBAUTHN_RP_ID,
    origin: env.WEBAUTHN_ORIGIN,
    publicKey,
  });
  if (!verified.ok) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (typeof operation.actor_email !== "string") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }
  if (typeof operation.issued_at !== "string") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (!(await assertionIssuedAtFresh(env, operation.issued_at))) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_expired"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }
  if (operation.actor_email !== accessEmail) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "actor_email_mismatch"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (await assertionChallengeUsed(env.DB, assertionSha256)) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_used"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (signer.status === "revoked") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "credential_revoked"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  signer = await promoteCredentialIfDue(env, signer);
  if (signer.status !== "active") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "credential_not_active"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  return {
    ok: true,
    signer,
    operation,
    assertionSha256,
    auditTarget,
  };
}

async function finishHpAssertion(
  env: VendorEnv,
  accessEmail: string,
  method: HpAssertionMethod,
  check: HpAssertionOk,
): Promise<void> {
  await insertAssertionUsed(env, check.assertionSha256, check.signer.credential_id);
  await writeEntrypointAudit(
    env.DB,
    accessEmail,
    method,
    check.auditTarget,
    check.assertionSha256,
  );
}

function envelopeWithoutCeilingOverride(
  envelope: Record<string, unknown>,
): Record<string, unknown> {
  const copy = { ...envelope };
  delete copy.ceiling_override;
  return copy;
}

function buildCeilingOverrideOperation(
  grantOperation: Record<string, unknown>,
  version: number,
  accessJwt: string,
  envelope: Record<string, unknown>,
): Record<string, unknown> {
  return {
    op: "ceiling_override",
    params: {
      contract_version: version,
      access_jwt: accessJwt,
      envelope,
    },
    actor_email: grantOperation.actor_email,
    issued_at: grantOperation.issued_at,
    nonce: grantOperation.nonce,
    contract_version: grantOperation.contract_version,
  };
}

async function verifyCeilingOverrideAssertion(
  env: VendorEnv,
  args: Record<string, unknown>,
  accessEmail: string,
  accessJwt: string,
  version: number,
  envelope: Record<string, unknown>,
  signer: OperatorCredentialRow,
): Promise<
  { ok: true; assertionSha256: string } | { ok: false; code: string }
> {
  const overrideRaw = envelope.ceiling_override;
  const overrideOperationRaw = args.ceiling_override_operation;
  const assertion = decodeAssertion(overrideRaw);
  if (assertion === null) {
    return { ok: false, code: "assertion_invalid" };
  }

  const grantOperation = args.operation;
  if (!isRecord(grantOperation)) {
    return { ok: false, code: "assertion_invalid" };
  }

  const overrideClientData = JSON.parse(
    new TextDecoder().decode(assertion.clientDataJSON),
  ) as { challenge?: string };
  const overrideChallenge =
    typeof overrideClientData.challenge === "string"
      ? overrideClientData.challenge
      : "";
  const grantChallenge = await operationChallenge(grantOperation);
  if (overrideChallenge.length > 0 && overrideChallenge === grantChallenge) {
    return { ok: false, code: "assertion_used" };
  }

  const envelopeForOverride = envelopeWithoutCeilingOverride(envelope);
  const operation = isRecord(overrideOperationRaw)
    ? overrideOperationRaw
    : buildCeilingOverrideOperation(
        grantOperation,
        version,
        accessJwt,
        envelopeForOverride,
      );

  if (!validateOperation(operation).ok || operation.op !== "ceiling_override") {
    return { ok: false, code: "assertion_invalid" };
  }

  const assertionSha256 = await operationAssertionSha256(operation);
  if (await assertionChallengeUsed(env.DB, assertionSha256)) {
    return { ok: false, code: "assertion_used" };
  }

  const publicKey = await importSignerPublicKey(signer);
  if (publicKey === null) {
    return { ok: false, code: "assertion_invalid" };
  }

  const verified = await verifyAssertion({
    assertion,
    operation,
    rpId: env.WEBAUTHN_RP_ID,
    origin: env.WEBAUTHN_ORIGIN,
    publicKey,
  });
  if (!verified.ok) {
    const clientData = JSON.parse(
      new TextDecoder().decode(assertion.clientDataJSON),
    ) as { challenge?: string };
    const challenge =
      typeof clientData.challenge === "string" ? clientData.challenge : "";
    const nowMs = await clockNowMs(env);
    const grantOp = grantOperation;
    for (
      let offsetMs = 0;
      offsetMs <= ASSERTION_FRESHNESS_MS;
      offsetMs += 1000
    ) {
      const issuedAt = new Date(nowMs - offsetMs).toISOString();
      const candidate = {
        op: "ceiling_override",
        params: {
          contract_version: version,
          access_jwt: accessJwt,
          envelope: envelopeForOverride,
        },
        actor_email: grantOp.actor_email,
        issued_at: issuedAt,
        nonce: grantOp.nonce,
        contract_version: grantOp.contract_version,
      };
      const expectedChallenge = await operationChallenge(candidate);
      if (expectedChallenge !== challenge) {
        continue;
      }
      const retry = await verifyAssertion({
        assertion,
        operation: candidate,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        publicKey,
      });
      if (retry.ok) {
        const verifiedSha = await operationAssertionSha256(candidate);
        return { ok: true, assertionSha256: verifiedSha };
      }
    }
    return { ok: false, code: "assertion_invalid" };
  }

  if (typeof operation.actor_email !== "string" || operation.actor_email !== accessEmail) {
    return { ok: false, code: "actor_email_mismatch" };
  }

  return { ok: true, assertionSha256 };
}

async function tryComplimentaryGrantIdempotency(
  env: VendorEnv,
  version: number,
  orgId: string,
  envelope: Record<string, unknown>,
): Promise<GrantResultEnvelope | null> {
  const grantId = envelope.grant_id;
  if (typeof grantId !== "string" || grantId.length === 0) {
    return null;
  }

  const installationId = await resolveOrInsertGrantBinding(env, orgId);
  const envelopeSha256 = await grantEnvelopeHash(envelope);
  const inspect = await callCoverageDo(env, installationId, {
    kind: "inspect_coverage",
    orgId,
    vendorContractVersion: version,
  });
  if (inspect === null || !Array.isArray(inspect.grants)) {
    return null;
  }

  for (const row of inspect.grants) {
    if (!isRecord(row)) {
      continue;
    }
    if (row.grant_id !== grantId) {
      continue;
    }
    const storedHash = row.envelope_sha256;
    if (typeof storedHash !== "string") {
      return null;
    }
    if (storedHash !== envelopeSha256) {
      return {
        contract_version: version,
        result: "conflict",
        code: "",
        detail: "",
      };
    }
    const receiptRaw = row.receipt;
    let receipt: Record<string, unknown> | null = null;
    if (typeof receiptRaw === "string") {
      try {
        receipt = JSON.parse(receiptRaw) as Record<string, unknown>;
      } catch {
        receipt = null;
      }
    } else if (isRecord(receiptRaw)) {
      receipt = receiptRaw;
    }
    if (receipt === null) {
      return null;
    }
    return {
      contract_version: version,
      result: "already_applied",
      code: "",
      detail: "",
      receipt,
    };
  }

  return null;
}

function mapVoidForReversalDoResponse(
  version: number,
  doResponse: Record<string, unknown>,
): GrantResultEnvelope {
  const doResult = doResponse.result;
  if (doResult === "conflict") {
    return {
      contract_version: version,
      result: "conflict",
      code: "",
      detail: "",
    };
  }
  if (doResult === "already_applied" || doResult === "applied") {
    const receipt = doResponse.receipt;
    if (!isRecord(receipt)) {
      return grantRejected(version, "coverage_unknown");
    }
    return {
      contract_version: version,
      result: doResult,
      code: "",
      detail: "",
      receipt,
    };
  }
  return grantRejected(version, "coverage_unknown");
}

function mapHpVoidDoResponse(
  version: number,
  doResponse: Record<string, unknown>,
): GrantResultEnvelope {
  const doResult = doResponse.result;
  if (doResult === "already_applied" || doResult === "applied") {
    const receipt = doResponse.receipt;
    if (!isRecord(receipt)) {
      return grantRejected(version, "coverage_unknown");
    }
    return {
      contract_version: version,
      result: doResult,
      code: "",
      detail: "",
      receipt,
    };
  }
  return grantRejected(version, "coverage_unknown");
}

function parseListGrantsForVoidWindow(
  windowRaw: unknown,
): { applied_from: string; applied_to: string } | null {
  if (!isRecord(windowRaw)) {
    return null;
  }
  const appliedFrom = windowRaw.applied_from;
  const appliedTo = windowRaw.applied_to;
  if (typeof appliedFrom !== "string" || typeof appliedTo !== "string") {
    return null;
  }
  if (!appliedFrom.endsWith("Z") || !appliedTo.endsWith("Z")) {
    return null;
  }
  const fromMs = Date.parse(appliedFrom);
  const toMs = Date.parse(appliedTo);
  if (Number.isNaN(fromMs) || Number.isNaN(toMs)) {
    return null;
  }
  if (fromMs > toMs) {
    return null;
  }
  return { applied_from: appliedFrom, applied_to: appliedTo };
}

function mapApplyGrantDoResponse(
  version: number,
  doResponse: Record<string, unknown>,
): GrantResultEnvelope {
  const doResult = doResponse.result;
  if (doResult === "exceeds_ceiling") {
    return grantRejected(version, "exceeds_ceiling");
  }
  if (doResult === "bad_request") {
    return grantRejected(version, "bad_request");
  }
  if (doResult === "conflict") {
    return {
      contract_version: version,
      result: "conflict",
      code: "",
      detail: "",
    };
  }
  if (doResult === "already_applied" || doResult === "applied") {
    const receipt = doResponse.receipt;
    if (!isRecord(receipt)) {
      return grantRejected(version, "coverage_unknown");
    }
    return {
      contract_version: version,
      result: doResult,
      code: "",
      detail: "",
      receipt,
    };
  }
  if (doResult === "rejected") {
    const code =
      typeof doResponse.code === "string" ? doResponse.code : "bad_request";
    return grantRejected(version, code);
  }
  if (doResult === "transient") {
    const detail =
      typeof doResponse.detail === "string" ? doResponse.detail : "";
    return grantTransient(version, detail);
  }
  return grantRejected(version, "coverage_unknown");
}

function isHex64(value: unknown): value is string {
  return typeof value === "string" && HEX64_RE.test(value);
}

type PlatformSigningMaterial = {
  kid: string;
  privateKey: CryptoKey;
};

async function loadPlatformSigningKey(
  json: string,
): Promise<PlatformSigningMaterial | null> {
  try {
    const parsed = JSON.parse(json) as {
      kid?: string;
      pkcs8?: string;
    };
    if (typeof parsed.kid !== "string" || typeof parsed.pkcs8 !== "string") {
      return null;
    }
    const pkcs8 = base64UrlDecode(parsed.pkcs8);
    if (pkcs8 === null) {
      return null;
    }
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      pkcs8,
      { name: "Ed25519" },
      false,
      ["sign"],
    );
    return { kid: parsed.kid, privateKey };
  } catch {
    return null;
  }
}

async function readVoidReceiptFromR2(
  env: VendorEnv,
  grantId: string,
): Promise<Record<string, unknown> | null> {
  const key = `grant-ledger/${grantId}.void.ndjson`;
  const object = await env.R2.get(key);
  if (object === null) {
    return null;
  }
  const text = await object.text();
  const line = text.trimEnd().split("\n")[0];
  if (!line) {
    return null;
  }
  try {
    const parsed = JSON.parse(line) as Record<string, unknown>;
    if (!isRecord(parsed.receipt)) {
      return null;
    }
    return parsed.receipt;
  } catch {
    return null;
  }
}

type StoredReversalVoid = {
  grant_id: string;
  reason: string;
  evidence_sha256: string;
  receipt: Record<string, unknown>;
};

async function findStoredReversalVoid(
  env: VendorEnv,
  version: number,
  reversalId: string,
  ledgerRow: { org_id: string; installation_id: string } | null,
  grantId: string,
  reason: string,
  evidenceSha256: string,
  envelopeSha256: string,
  nowIso: string,
): Promise<StoredReversalVoid | "conflict" | null> {
  if (ledgerRow !== null) {
    const binding = await readActiveTenantBinding(env.DB, ledgerRow.org_id);
    if (binding !== null) {
      const doResponse = await callCoverageDo(env, ledgerRow.installation_id, {
        kind: "void_for_reversal",
        installationId: ledgerRow.installation_id,
        orgId: ledgerRow.org_id,
        vendorContractVersion: version,
        bindingEpoch: binding.epoch,
        grantId,
        reversalId,
        reason,
        evidenceSha256,
        envelopeSha256,
        nowIso,
        platformSigningKeyJson: env.PLATFORM_SIGNING_KEY,
        durationScale: durationScaleFromEnv(env),
        replayOnly: true,
      });
      if (doResponse !== null) {
        if (doResponse.result === "conflict") {
          return "conflict";
        }
        if (
          doResponse.result === "already_applied" &&
          isRecord(doResponse.receipt)
        ) {
          return {
            grant_id: grantId,
            reason,
            evidence_sha256: evidenceSha256,
            receipt: doResponse.receipt,
          };
        }
      }
    }
  }

  const rows = await env.DB.prepare(
    "SELECT grant_id, reason, evidence_sha256 FROM grant_void",
  ).all<{ grant_id: string; reason: string; evidence_sha256: string }>();

  for (const row of rows.results ?? []) {
    const receipt = await readVoidReceiptFromR2(env, row.grant_id);
    if (receipt === null) {
      continue;
    }
    const storedReversalId = receipt.reversal_id;
    if (typeof storedReversalId !== "string" || storedReversalId !== reversalId) {
      continue;
    }
    return {
      grant_id: row.grant_id,
      reason: row.reason,
      evidence_sha256: row.evidence_sha256,
      receipt,
    };
  }

  return null;
}

function mapStoredReversalVoidReplay(
  version: number,
  stored: StoredReversalVoid,
  grantId: string,
  reason: string,
  evidenceSha256: string,
  partial: boolean,
): GrantResultEnvelope {
  if (
    stored.grant_id === grantId &&
    stored.reason === reason &&
    stored.evidence_sha256 === evidenceSha256 &&
    partial === false
  ) {
    return {
      contract_version: version,
      result: "already_applied",
      code: "",
      detail: "",
      receipt: stored.receipt,
    };
  }
  return {
    contract_version: version,
    result: "conflict",
    code: "",
    detail: "",
  };
}

async function signReversalVoidReceipt(input: {
  signingKey: PlatformSigningMaterial;
  vendorContractVersion: number;
  reversalId: string;
  installationId: string;
  orgId: string;
  termIds: string[];
  appliedAt: string;
  ledgerSeq: number;
  envelopeSha256: string;
}): Promise<Record<string, unknown>> {
  const unsigned = {
    contract_version: input.vendorContractVersion,
    reversal_id: input.reversalId,
    installation_id: input.installationId,
    org_id: input.orgId,
    result: "applied",
    term_ids: input.termIds,
    applied_at: input.appliedAt,
    ledger_seq: input.ledgerSeq,
    envelope_sha256: input.envelopeSha256,
    kid: input.signingKey.kid,
  };
  const signature = await signCompactJws({
    payload: receiptSigningBytes(unsigned),
    privateKey: input.signingKey.privateKey,
    kid: input.signingKey.kid,
  });
  return { ...unsigned, signature };
}

async function rejectIfGrantVoided(
  env: VendorEnv,
  version: number,
  grantId: string,
): Promise<GrantResultEnvelope | null> {
  const row = await env.DB.prepare(
    "SELECT grant_id FROM grant_void WHERE grant_id = ?",
  )
    .bind(grantId)
    .first<{ grant_id: string }>();
  if (row !== null) {
    return grantRejected(version, "voided", "");
  }
  return null;
}

async function rejectHpAssertion(
  env: VendorEnv,
  accessEmail: string,
  method: HpAssertionMethod,
  check: HpAssertionReject,
): Promise<VendorResultEnvelope> {
  await writeEntrypointAudit(
    env.DB,
    accessEmail,
    method,
    check.auditTarget,
    check.auditAssertionSha256,
  );
  return check.envelope;
}

async function bootstrapRegister(
  env: VendorEnv,
  rpcArgs: Record<string, unknown>,
  accessEmail: string,
  negotiatedVersion: number,
): Promise<VendorResultEnvelope> {
  const credentialId = rpcArgs.credential_id;
  const attestationRaw = rpcArgs.attestation;
  if (typeof credentialId !== "string" || credentialId.length === 0) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }
  const attestation = decodeAttestation(attestationRaw);
  if (attestation === null) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }
  const parsed = await parseRegistrationAttestation(attestation);
  if (!parsed.ok) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }

  const nowMs = await clockNowMs(env);
  const activatesAt = new Date(nowMs + ACTIVATION_MS).toISOString();
  const publicKeyCose = attestationRaw && isRecord(attestationRaw)
    ? String(attestationRaw.public_key)
    : "";

  await env.DB.prepare(
    `INSERT INTO operator_credential
       (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
     VALUES (?, ?, ?, ?, 'pending', ?, NULL, NULL)`,
  )
    .bind(credentialId, accessEmail, publicKeyCose, parsed.alg, activatesAt)
    .run();

  const row = await readOperatorCredential(env.DB, credentialId);
  if (row === null) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }

  await writeEntrypointAudit(
    env.DB,
    accessEmail,
    "registerOperatorCredential",
    credentialId,
    null,
  );

  await raiseAl13Bootstrap(env, {
    credentialId,
    operatorEmail: accessEmail,
  });

  return ok(negotiatedVersion, rowToDetail(row));
}

export class VendorEntrypoint extends WorkerEntrypoint<VendorEnv> {
  async registerOperatorCredential(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const hasAssertion =
      args.assertion !== undefined && args.assertion !== null;
    const registrySize = await operatorCredentialCount(this.env.DB);

    if (!hasAssertion) {
      if (registrySize > 0) {
        const target =
          typeof args.credential_id === "string" ? args.credential_id : "";
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "registerOperatorCredential",
          target,
          null,
        );
        return rejected(version, "assertion_required");
      }
      return bootstrapRegister(this.env, args, access.email, version);
    }

    const check = await runHpAssertionChecks(
      this.env,
      "registerOperatorCredential",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "registerOperatorCredential",
        check,
      );
    }

    const credentialId = args.credential_id;
    const attestationRaw = args.attestation;
    if (typeof credentialId !== "string" || credentialId.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }
    const attestation = decodeAttestation(attestationRaw);
    if (attestation === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }
    const parsed = await parseRegistrationAttestation(attestation);
    if (!parsed.ok) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }
    const publicKeyCose =
      attestationRaw && isRecord(attestationRaw)
        ? String(attestationRaw.public_key)
        : "";

    const existing = await readOperatorCredential(this.env.DB, credentialId);
    if (existing !== null) {
      if (existing.public_key_cose !== publicKeyCose) {
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "registerOperatorCredential",
          check.auditTarget,
          check.assertionSha256,
        );
        return conflict(version, "public_key_cose_mismatch");
      }
      await finishHpAssertion(
        this.env,
        access.email,
        "registerOperatorCredential",
        check,
      );
      return ok(version, rowToDetail(existing));
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "registerOperatorCredential",
      check,
    );

    const nowMs = await clockNowMs(this.env);
    const activatesAt = new Date(nowMs + ACTIVATION_MS).toISOString();
    await this.env.DB.prepare(
      `INSERT INTO operator_credential
         (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
       VALUES (?, ?, ?, ?, 'pending', ?, ?, NULL)`,
    )
      .bind(
        credentialId,
        access.email,
        publicKeyCose,
        parsed.alg,
        activatesAt,
        access.email,
      )
      .run();

    const row = await readOperatorCredential(this.env.DB, credentialId);
    if (row === null) {
      return rejected(version, "assertion_invalid");
    }

    await raiseAl13(this.env, {
      credentialId,
      operatorEmail: access.email,
      kind: "register",
      operation: check.operation,
    });

    return ok(version, rowToDetail(row));
  }

  async revokeOperatorCredential(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "revokeOperatorCredential",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "revokeOperatorCredential",
        check,
      );
    }

    const targetId = args.credential_id;
    if (typeof targetId !== "string" || targetId.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "credential_not_found");
    }
    const target = await readOperatorCredential(this.env.DB, targetId);
    if (target === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeOperatorCredential",
        targetId,
        check.assertionSha256,
      );
      return rejected(version, "credential_not_found");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "revokeOperatorCredential",
      check,
    );

    if (target.status !== "revoked") {
      await this.env.DB.prepare(
        `UPDATE operator_credential SET status = 'revoked', revoked_by = ?
         WHERE credential_id = ?`,
      )
        .bind(access.email, targetId)
        .run();
    }

    const row = await readOperatorCredential(this.env.DB, targetId);
    if (row === null) {
      return rejected(version, "credential_not_found");
    }

    await raiseAl13(this.env, {
      credentialId: targetId,
      operatorEmail: row.operator_email,
      kind: "revoke",
      operation: check.operation,
    });

    return ok(version, rowToDetail(row));
  }

  async listOperatorCredentials(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    await promoteAllDueCredentials(this.env);

    const { results } = await this.env.DB.prepare(
      `SELECT credential_id, public_key_cose, alg
       FROM operator_credential
       WHERE status = 'active'
       ORDER BY credential_id ASC`,
    ).all<{ credential_id: string; public_key_cose: string; alg: string }>();

    const keys = (results ?? []).map((row) => ({
      credential_id: row.credential_id,
      public_key_cose: row.public_key_cose,
      alg: row.alg,
    }));

    return ok(version, JSON.stringify(keys));
  }

  async registerIssuerKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "registerIssuerKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "registerIssuerKey",
        check,
      );
    }

    const kid = args.kid;
    const publicKey = args.public_key;
    const notBefore = args.not_before;
    const notAfter = args.not_after;
    if (
      typeof kid !== "string" ||
      kid.length === 0 ||
      typeof publicKey !== "string" ||
      typeof notBefore !== "string" ||
      notBefore.length === 0 ||
      typeof notAfter !== "string" ||
      notAfter.length === 0
    ) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }

    if (!isValidEd25519PublicKeyEncoding(publicKey)) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "public_key_invalid");
    }

    const existing = await readIssuerKey(this.env.DB, kid);
    if (existing !== null) {
      if (existing.public_key !== publicKey) {
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "registerIssuerKey",
          check.auditTarget,
          check.assertionSha256,
        );
        return conflict(version, "public_key_mismatch");
      }
      await finishHpAssertion(
        this.env,
        access.email,
        "registerIssuerKey",
        check,
      );
      return ok(version, issuerKeyRowToDetail(existing));
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "registerIssuerKey",
      check,
    );

    await this.env.DB.prepare(
      `INSERT INTO issuer_key
         (kid, issuer, public_key, status, not_before, not_after, registered_by, assertion_sha256)
       VALUES (?, ?, ?, 'active', ?, ?, ?, ?)`,
    )
      .bind(
        kid,
        this.env.ISSUER_ID,
        publicKey,
        notBefore,
        notAfter,
        access.email,
        check.assertionSha256,
      )
      .run();

    const row = await readIssuerKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "assertion_invalid");
    }

    await raiseAl13IssuerKey(this.env, {
      kid,
      kind: "register",
      operation: check.operation,
    });

    return ok(version, issuerKeyRowToDetail(row));
  }

  async listIssuerKeys(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const { results } = await this.env.DB.prepare(
      `SELECT kid, public_key, status, not_before, not_after
       FROM issuer_key
       WHERE status IN ('active', 'retiring')
       ORDER BY kid ASC`,
    ).all<{
      kid: string;
      public_key: string;
      status: string;
      not_before: string;
      not_after: string;
    }>();

    const keys = (results ?? []).map((row) => ({
      kid: row.kid,
      public_key: row.public_key,
      status: row.status,
      not_before: row.not_before,
      not_after: row.not_after,
    }));

    return ok(version, JSON.stringify(keys));
  }

  async retireIssuerKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "retireIssuerKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "retireIssuerKey",
        check,
      );
    }

    const kid = args.kid;
    if (typeof kid !== "string" || kid.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retireIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    const existing = await readIssuerKey(this.env.DB, kid);
    if (existing === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retireIssuerKey",
        kid,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    if (existing.status === "revoked") {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retireIssuerKey",
        kid,
        check.assertionSha256,
      );
      return rejected(version, "kid_revoked");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "retireIssuerKey",
      check,
    );

    if (existing.status === "active") {
      await this.env.DB.prepare(
        `UPDATE issuer_key SET status = 'retiring' WHERE kid = ?`,
      )
        .bind(kid)
        .run();
    }

    const row = await readIssuerKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "kid_not_found");
    }

    await raiseAl13IssuerKey(this.env, {
      kid,
      kind: "retire",
      operation: check.operation,
    });

    return ok(version, issuerKeyRowToDetail(row));
  }

  async revokeIssuerKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "revokeIssuerKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "revokeIssuerKey",
        check,
      );
    }

    const kid = args.kid;
    if (typeof kid !== "string" || kid.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    const existing = await readIssuerKey(this.env.DB, kid);
    if (existing === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeIssuerKey",
        kid,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "revokeIssuerKey",
      check,
    );

    if (existing.status !== "revoked") {
      await this.env.DB.prepare(
        `UPDATE issuer_key SET status = 'revoked' WHERE kid = ?`,
      )
        .bind(kid)
        .run();
    }

    const row = await readIssuerKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "kid_not_found");
    }

    await raiseAl13IssuerKey(this.env, {
      kid,
      kind: "revoke",
      operation: check.operation,
    });

    return ok(version, issuerKeyRowToDetail(row));
  }

  async registerServiceKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "registerServiceKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "registerServiceKey",
        check,
      );
    }

    const kid = args.kid;
    const publicKey = args.public_key;
    const notBefore = args.not_before;
    const notAfter = args.not_after;
    if (
      typeof kid !== "string" ||
      kid.length === 0 ||
      typeof publicKey !== "string" ||
      typeof notBefore !== "string" ||
      notBefore.length === 0 ||
      typeof notAfter !== "string" ||
      notAfter.length === 0
    ) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerServiceKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }

    if (!isValidEd25519PublicKeyEncoding(publicKey)) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerServiceKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "public_key_invalid");
    }

    const existing = await readServiceKey(this.env.DB, kid);
    if (existing !== null) {
      if (existing.public_key !== publicKey) {
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "registerServiceKey",
          check.auditTarget,
          check.assertionSha256,
        );
        return conflict(version, "public_key_mismatch");
      }
      await finishHpAssertion(
        this.env,
        access.email,
        "registerServiceKey",
        check,
      );
      return ok(version, serviceKeyRowToDetail(existing));
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "registerServiceKey",
      check,
    );

    await this.env.DB.prepare(
      `INSERT INTO service_key
         (kid, service, public_key, status, not_before, not_after, registered_by, assertion_sha256)
       VALUES (?, 'abo', ?, 'active', ?, ?, ?, ?)`,
    )
      .bind(
        kid,
        publicKey,
        notBefore,
        notAfter,
        access.email,
        check.assertionSha256,
      )
      .run();

    const row = await readServiceKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "assertion_invalid");
    }

    await raiseAl13ServiceKey(this.env, {
      kid,
      kind: "register",
      operation: check.operation,
    });

    return ok(version, serviceKeyRowToDetail(row));
  }

  async revokeServiceKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "revokeServiceKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "revokeServiceKey",
        check,
      );
    }

    const kid = args.kid;
    if (typeof kid !== "string" || kid.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeServiceKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    const existing = await readServiceKey(this.env.DB, kid);
    if (existing === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeServiceKey",
        kid,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "revokeServiceKey",
      check,
    );

    if (existing.status !== "revoked") {
      await this.env.DB.prepare(
        `UPDATE service_key SET status = 'revoked' WHERE kid = ?`,
      )
        .bind(kid)
        .run();
    }

    const row = await readServiceKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "kid_not_found");
    }

    await raiseAl13ServiceKey(this.env, {
      kid,
      kind: "revoke",
      operation: check.operation,
    });

    return ok(version, serviceKeyRowToDetail(row));
  }

  async listServiceKeys(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const { results } = await this.env.DB.prepare(
      `SELECT kid, status, not_before, not_after
       FROM service_key
       ORDER BY kid ASC`,
    ).all<{
      kid: string;
      status: string;
      not_before: string;
      not_after: string;
    }>();

    const keys = (results ?? []).map((row) => ({
      kid: row.kid,
      status: row.status,
      not_before: row.not_before,
      not_after: row.not_after,
    }));

    return ok(version, JSON.stringify(keys));
  }

  async publishPlanVersion(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "publishPlanVersion",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "publishPlanVersion",
        check,
      );
    }

    const planId = args.plan_id;
    const planVersion = args.version;
    const displayName = args.display_name;
    const capabilities = args.capabilities;
    const maxCostClassRaw = args.max_cost_class;
    const concurrencyLimit = args.concurrency_limit;
    const maxAllowancePerMonth = args.max_allowance_per_month;
    let maxCostClass: string;
    if (typeof maxCostClassRaw === "string") {
      maxCostClass = maxCostClassRaw;
    } else if (
      typeof maxCostClassRaw === "number" &&
      Number.isInteger(maxCostClassRaw)
    ) {
      maxCostClass = String(maxCostClassRaw);
    } else {
      maxCostClass = "";
    }
    if (
      typeof planId !== "string" ||
      planId.length === 0 ||
      !Number.isInteger(planVersion) ||
      typeof displayName !== "string" ||
      !isStringArray(capabilities) ||
      maxCostClass.length === 0 ||
      !Number.isInteger(concurrencyLimit) ||
      !Number.isInteger(maxAllowancePerMonth)
    ) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "publishPlanVersion",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }

    const content = {
      display_name: displayName,
      capabilities,
      max_cost_class: maxCostClass,
      concurrency_limit: concurrencyLimit,
      max_allowance_per_month: maxAllowancePerMonth,
    };

    const existing = await readPlanVersion(
      this.env.DB,
      planId,
      planVersion as number,
    );
    if (existing !== null) {
      if (!planVersionContentMatches(existing, content)) {
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "publishPlanVersion",
          check.auditTarget,
          check.assertionSha256,
        );
        return conflict(version, "plan_version_mismatch");
      }
      await finishHpAssertion(
        this.env,
        access.email,
        "publishPlanVersion",
        check,
      );
      return ok(version, planVersionRowToDetail(existing));
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "publishPlanVersion",
      check,
    );

    await this.env.DB.prepare(
      `INSERT INTO plan_version (
         plan_id, version, display_name, capabilities, max_cost_class,
         concurrency_limit, max_allowance_per_month, status, published_by,
         assertion_sha256
       ) VALUES (?, ?, ?, ?, ?, ?, ?, 'published', ?, ?)`,
    )
      .bind(
        planId,
        planVersion,
        displayName,
        JSON.stringify(capabilities),
        maxCostClass,
        concurrencyLimit,
        maxAllowancePerMonth,
        access.email,
        check.assertionSha256,
      )
      .run();

    const row = await readPlanVersion(
      this.env.DB,
      planId,
      planVersion as number,
    );
    if (row === null) {
      return rejected(version, "assertion_invalid");
    }

    return ok(version, planVersionRowToDetail(row));
  }

  async retirePlanVersion(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "retirePlanVersion",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "retirePlanVersion",
        check,
      );
    }

    const planId = args.plan_id;
    const planVersion = args.version;
    if (
      typeof planId !== "string" ||
      planId.length === 0 ||
      !Number.isInteger(planVersion)
    ) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retirePlanVersion",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "plan_version_not_found");
    }

    const existing = await readPlanVersion(
      this.env.DB,
      planId,
      planVersion as number,
    );
    if (existing === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retirePlanVersion",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "plan_version_not_found");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "retirePlanVersion",
      check,
    );

    if (existing.status !== "retired") {
      await this.env.DB.prepare(
        `UPDATE plan_version SET status = 'retired'
         WHERE plan_id = ? AND version = ?`,
      )
        .bind(planId, planVersion)
        .run();
    }

    const row = await readPlanVersion(
      this.env.DB,
      planId,
      planVersion as number,
    );
    if (row === null) {
      return rejected(version, "plan_version_not_found");
    }

    return ok(version, planVersionRowToDetail(row));
  }

  async setCeilingPolicy(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const operationRaw = args.operation;
    if (!validateOperation(operationRaw).ok) {
      return rejected(version, "assertion_invalid");
    }
    const operation = operationRaw as Record<string, unknown>;
    const assertionSha256 = await operationAssertionSha256(operation);
    const existingByAssertion = await readCeilingPolicyByAssertionSha256(
      this.env.DB,
      assertionSha256,
    );
    if (existingByAssertion !== null) {
      return ok(version, ceilingPolicyRowToDetail(existingByAssertion));
    }

    const check = await runHpAssertionChecks(
      this.env,
      "setCeilingPolicy",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "setCeilingPolicy",
        check,
      );
    }

    const perGrantMaxDays = args.per_grant_max_days;
    const perGrantMaxAllowanceMonths = args.per_grant_max_allowance_months;
    const windowDays = args.window_days;
    const windowMaxDays = args.window_max_days;
    const windowMaxAllowanceMonths = args.window_max_allowance_months;
    const maxPaidGraceDays = args.max_paid_grace_days;
    const paidCapRule = args.paid_cap_rule;
    if (
      !Number.isInteger(perGrantMaxDays) ||
      !Number.isInteger(perGrantMaxAllowanceMonths) ||
      !Number.isInteger(windowDays) ||
      !Number.isInteger(windowMaxDays) ||
      !Number.isInteger(windowMaxAllowanceMonths) ||
      !Number.isInteger(maxPaidGraceDays) ||
      typeof paidCapRule !== "string" ||
      paidCapRule.length === 0
    ) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "setCeilingPolicy",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "bad_request");
    }

    const current = await readCurrentCeilingPolicy(this.env.DB);
    const nextVersion = (current?.version ?? 0) + 1;

    await finishHpAssertion(
      this.env,
      access.email,
      "setCeilingPolicy",
      check,
    );

    await this.env.DB.prepare(
      `INSERT INTO ceiling_policy (
         version, per_grant_max_days, per_grant_max_allowance_months,
         window_days, window_max_days, window_max_allowance_months,
         max_paid_grace_days, paid_cap_rule, set_by, assertion_sha256
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        nextVersion,
        perGrantMaxDays,
        perGrantMaxAllowanceMonths,
        windowDays,
        windowMaxDays,
        windowMaxAllowanceMonths,
        maxPaidGraceDays,
        paidCapRule,
        access.email,
        check.assertionSha256,
      )
      .run();

    const row = await readCeilingPolicyByAssertionSha256(
      this.env.DB,
      check.assertionSha256,
    );
    if (row === null) {
      return rejected(version, "bad_request");
    }

    return ok(version, ceilingPolicyRowToDetail(row));
  }

  async grant(args: Record<string, unknown>): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const envelope = args.envelope;
    if (!isRecord(envelope)) {
      return grantRejected(version, "bad_signature");
    }

    const source = envelope.source;
    const sourceKind =
      isRecord(source) && typeof source.kind === "string" ? source.kind : null;
    const envelopeKind =
      typeof envelope.kind === "string" ? envelope.kind : null;

    if (sourceKind === "complimentary" || envelopeKind === "term_adjustment") {
      if (envelopeKind === "term_adjustment" && sourceKind === "paid") {
        return grantRejected(version, "bad_request");
      }

      if (sourceKind === "complimentary") {
        const operatorEmail =
          isRecord(source) && typeof source.operator_email === "string"
            ? source.operator_email
            : "";
        const reason =
          isRecord(source) && typeof source.reason === "string"
            ? source.reason
            : "";
        if (operatorEmail.length === 0 || reason.length === 0) {
          return grantRejected(version, "bad_request");
        }
      }

      if (envelope.placement === "immediate") {
        return grantRejected(version, "placement_not_supported");
      }

      const access = await verifyHpAccess(this.env, args.access_jwt);
      if (!access.ok) {
        return grantRejected(version, "unauthenticated");
      }

      const envelopeValidation = validateGrantEnvelope(envelope);
      if (!envelopeValidation.ok) {
        if (
          "code" in envelopeValidation &&
          envelopeValidation.code === "placement_not_supported"
        ) {
          return grantRejected(version, "placement_not_supported");
        }
        return grantRejected(version, "unit_not_allowed");
      }

      const plan = envelope.plan;
      if (!isRecord(plan)) {
        return grantRejected(version, "plan_not_published");
      }
      const planId = plan.plan_id;
      const planVersionRaw = plan.plan_version;
      if (typeof planId !== "string" || !Number.isInteger(planVersionRaw)) {
        return grantRejected(version, "plan_not_published");
      }
      const planVersion = planVersionRaw as number;
      const planRow = await readPlanVersion(this.env.DB, planId, planVersion);
      if (planRow === null || planRow.status !== "published") {
        return grantRejected(version, "plan_not_published");
      }

      const duration = envelope.duration;
      if (!isRecord(duration)) {
        return grantRejected(version, "unit_not_allowed");
      }
      const durationUnit = duration.unit;
      const durationCount = duration.count;
      if (
        envelopeKind !== "term_adjustment" &&
        durationUnit !== "day" &&
        durationUnit !== "month"
      ) {
        return grantRejected(version, "unit_not_allowed");
      }
      if (
        envelopeKind !== "term_adjustment" &&
        (!Number.isInteger(durationCount) || (durationCount as number) < 1)
      ) {
        return grantRejected(version, "unit_not_allowed");
      }

      const allowanceCredits = envelope.allowance_credits;
      if (!Number.isInteger(allowanceCredits) || (allowanceCredits as number) < 1) {
        return grantRejected(version, "exceeds_plan_bound");
      }

      const orgId = envelope.org_id;
      if (typeof orgId !== "string") {
        return grantRejected(version, "bad_signature");
      }

      const ceilingPolicy = await readCurrentCeilingPolicy(this.env.DB);
      if (ceilingPolicy === null) {
        return grantRejected(version, "coverage_unknown");
      }

      const accessJwt =
        typeof args.access_jwt === "string" ? args.access_jwt : "";

      const idempotent = await tryComplimentaryGrantIdempotency(
        this.env,
        version,
        orgId,
        envelope,
      );
      if (idempotent !== null) {
        return idempotent;
      }

      const check = await runHpAssertionChecks(
        this.env,
        "grant",
        args,
        access.email,
        version,
      );
      if (!check.ok) {
        const rejectedEnvelope = await rejectHpAssertion(
          this.env,
          access.email,
          "grant",
          check,
        );
        return {
          contract_version: rejectedEnvelope.contract_version,
          result: "rejected",
          code: rejectedEnvelope.code,
          detail: rejectedEnvelope.detail,
        };
      }

      let skipCeilingCheck = false;
      let overrideAssertionSha256: string | null = null;
      if (envelope.ceiling_override !== undefined) {
        const overrideCheck = await verifyCeilingOverrideAssertion(
          this.env,
          args,
          access.email,
          accessJwt,
          version,
          envelope,
          check.signer,
        );
        if (!overrideCheck.ok) {
          return grantRejected(version, overrideCheck.code);
        }
        skipCeilingCheck = true;
        overrideAssertionSha256 = overrideCheck.assertionSha256;
      }

      await finishHpAssertion(this.env, access.email, "grant", check);
      if (overrideAssertionSha256 !== null) {
        await insertAssertionUsed(
          this.env,
          overrideAssertionSha256,
          check.signer.credential_id,
        );
      }

      const liveBinding = await readLiveTenantBinding(this.env.DB, orgId);
      const installationId =
        liveBinding?.installation_id ??
        (await resolveOrInsertGrantBinding(this.env, orgId));
      const binding =
        liveBinding ??
        (await readLiveTenantBinding(this.env.DB, orgId));
      if (binding === null) {
        return grantRejected(version, "coverage_unknown");
      }

      const complimentaryGrantId = envelope.grant_id;
      if (typeof complimentaryGrantId === "string" && complimentaryGrantId.length > 0) {
        const voided = await rejectIfGrantVoided(
          this.env,
          version,
          complimentaryGrantId,
        );
        if (voided !== null) {
          return voided;
        }
      }

      const nowIso = await clockNowIso(this.env);
      const approvals =
        isRecord(envelope.evidence) && Array.isArray(envelope.evidence.approvals)
          ? envelope.evidence.approvals
          : [];
      const approvalsCredentialId =
        isRecord(approvals[0]) && typeof approvals[0].credential_id === "string"
          ? approvals[0].credential_id
          : "";

      const planSnapshot = {
        plan_id: planId,
        version: planVersion,
        display_name: planRow.display_name,
        capabilities: JSON.parse(planRow.capabilities) as unknown,
        max_cost_class: planRow.max_cost_class,
        concurrency_limit: planRow.concurrency_limit,
      };

      const grace = envelope.grace;
      const graceDays =
        isRecord(grace) && Number.isInteger(grace.days)
          ? (grace.days as number)
          : 0;

      const adjustment =
        envelopeKind === "term_adjustment" && isRecord(envelope.adjustment)
          ? (envelope.adjustment as Record<string, unknown>)
          : undefined;

      const doResponse = await callCoverageDo(this.env, installationId, {
        kind: "apply_grant",
        bindingEpoch: binding.epoch,
        vendorContractVersion: version,
        orgId,
        envelope,
        planSnapshot,
        durationUnit:
          envelopeKind === "term_adjustment"
            ? undefined
            : (durationUnit as "day" | "month"),
        durationCount:
          envelopeKind === "term_adjustment"
            ? undefined
            : (durationCount as number),
        allowanceCredits: allowanceCredits as number,
        graceDays,
        operatorCredentialId: approvalsCredentialId,
        platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
        durationScale: durationScaleFromEnv(this.env),
        nowIso,
        sourceKind: "complimentary",
        envelopeKind: envelopeKind ?? "term",
        planMaxAllowancePerMonth: planRow.max_allowance_per_month,
        ceilingPolicy: {
          per_grant_max_days: ceilingPolicy.per_grant_max_days,
          per_grant_max_allowance_months:
            ceilingPolicy.per_grant_max_allowance_months,
          window_days: ceilingPolicy.window_days,
          window_max_days: ceilingPolicy.window_max_days,
          window_max_allowance_months:
            ceilingPolicy.window_max_allowance_months,
        },
        skipCeilingCheck,
        adjustment,
      });

      if (doResponse === null) {
        return grantRejected(version, "coverage_unknown");
      }

      return mapApplyGrantDoResponse(version, doResponse);
    }

    const aboKid = args.abo_kid;
    const aboSignature = args.abo_signature;
    if (
      typeof aboKid !== "string" ||
      aboKid.length === 0 ||
      typeof aboSignature !== "string" ||
      aboSignature.length === 0
    ) {
      return grantRejected(version, "bad_signature");
    }

    if (sourceKind !== "paid") {
      return grantRejected(version, "unit_not_allowed");
    }

    const payloadBytes = jwsPayloadBytes(aboSignature);
    const envelopeBytes = canonicalize(envelope);
    if (payloadBytes === null || !bytesEqual(payloadBytes, envelopeBytes)) {
      return grantRejected(version, "bad_signature");
    }

    const evidence = envelope.evidence;
    const approvals =
      isRecord(evidence) && Array.isArray(evidence.approvals)
        ? evidence.approvals
        : null;
    if (approvals === null || approvals.length < 1) {
      return grantRejected(version, "approvals_required");
    }

    const serviceKey = await readServiceKey(this.env.DB, aboKid);
    if (serviceKey === null) {
      return grantTransient(version, "unknown_kid");
    }

    const nowIso = await clockNowIso(this.env);
    if (
      serviceKey.status === "revoked" ||
      !serviceKeyActiveAt(serviceKey, nowIso)
    ) {
      return grantRejected(version, "bad_signature");
    }

    const verifyKey = await importEd25519VerifyKey(serviceKey.public_key);
    if (verifyKey === null) {
      return grantRejected(version, "bad_signature");
    }
    const signatureValid = await verifyGrantSignature({
      envelope,
      jws: aboSignature,
      publicKey: verifyKey,
      kid: aboKid,
    });
    if (!signatureValid) {
      return grantRejected(version, "bad_signature");
    }

    const plan = envelope.plan;
    if (!isRecord(plan)) {
      return grantRejected(version, "plan_not_published");
    }
    const planId = plan.plan_id;
    const planVersionRaw = plan.plan_version;
    if (typeof planId !== "string" || !Number.isInteger(planVersionRaw)) {
      return grantRejected(version, "plan_not_published");
    }
    const planVersion = planVersionRaw as number;

    const planRow = await readPlanVersion(this.env.DB, planId, planVersion);
    if (planRow === null || planRow.status !== "published") {
      return grantRejected(version, "plan_not_published");
    }

    if (envelope.kind !== "term") {
      return grantRejected(version, "unit_not_allowed");
    }

    const duration = envelope.duration;
    if (!isRecord(duration)) {
      return grantRejected(version, "unit_not_allowed");
    }
    const durationUnit = duration.unit;
    const durationCount = duration.count;
    if (
      durationUnit !== "month" ||
      !Number.isInteger(durationCount) ||
      (durationCount !== 1 && durationCount !== 3 && durationCount !== 12)
    ) {
      return grantRejected(version, "unit_not_allowed");
    }

    const allowanceCredits = envelope.allowance_credits;
    if (
      !Number.isInteger(allowanceCredits) ||
      allowanceCredits < 1 ||
      allowanceCredits >
        planRow.max_allowance_per_month * (durationCount as number)
    ) {
      return grantRejected(version, "exceeds_plan_bound");
    }

    const ceilingPolicy = await readCurrentCeilingPolicy(this.env.DB);
    if (ceilingPolicy === null) {
      return grantRejected(version, "coverage_unknown");
    }

    const grace = envelope.grace;
    if (
      !isRecord(grace) ||
      !Number.isInteger(grace.days) ||
      (grace.days as number) > ceilingPolicy.max_paid_grace_days ||
      grace.cap_rule !== ceilingPolicy.paid_cap_rule
    ) {
      return grantRejected(version, "exceeds_plan_bound");
    }

    if (envelope.placement === "immediate" || envelope.placement === "replace") {
      return grantRejected(version, "placement_not_supported");
    }

    const envelopeValidation = validateGrantEnvelope(envelope);
    if (!envelopeValidation.ok) {
      if (
        "code" in envelopeValidation &&
        envelopeValidation.code === "placement_not_supported"
      ) {
        return grantRejected(version, "placement_not_supported");
      }
      return grantRejected(version, "unit_not_allowed");
    }

    const orgId = envelope.org_id;
    if (typeof orgId !== "string") {
      return grantRejected(version, "bad_signature");
    }

    const heldBinding = await readLiveTenantBinding(this.env.DB, orgId);
    if (heldBinding?.status === "held_for_transfer") {
      return grantTransient(version, "transfer_pending");
    }

    const installationOverride =
      typeof args.installation_id === "string" ? args.installation_id : null;
    const installationId =
      installationOverride ??
      (await resolveOrInsertGrantBinding(this.env, orgId));
    let bindingEpoch = 1;
    if (installationOverride !== null) {
      const bindingRow = await this.env.DB.prepare(
        `SELECT epoch FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
      )
        .bind(orgId, installationOverride)
        .first<{ epoch: number }>();
      if (bindingRow === null) {
        return grantRejected(version, "coverage_unknown");
      }
      bindingEpoch = bindingRow.epoch;
    } else {
      const binding = await readActiveTenantBinding(this.env.DB, orgId);
      if (binding === null) {
        return grantRejected(version, "coverage_unknown");
      }
      bindingEpoch = binding.epoch;
    }

    const paidGrantId = envelope.grant_id;
    if (typeof paidGrantId === "string" && paidGrantId.length > 0) {
      const voided = await rejectIfGrantVoided(this.env, version, paidGrantId);
      if (voided !== null) {
        return voided;
      }
    }

    const approvalsCredentialId =
      isRecord(approvals[0]) && typeof approvals[0].credential_id === "string"
        ? approvals[0].credential_id
        : "";
    const planSnapshot = {
      plan_id: planId,
      version: planVersion,
      display_name: planRow.display_name,
      capabilities: JSON.parse(planRow.capabilities) as unknown,
      max_cost_class: planRow.max_cost_class,
      concurrency_limit: planRow.concurrency_limit,
    };

    const doResponse = await callCoverageDo(this.env, installationId, {
      kind: "apply_grant",
      bindingEpoch,
      vendorContractVersion: version,
      orgId,
      envelope,
      aboKid,
      planSnapshot,
      durationUnit: "month",
      durationCount: durationCount as number,
      allowanceCredits: allowanceCredits as number,
      graceDays: grace.days as number,
      operatorCredentialId: approvalsCredentialId,
      platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
      durationScale: durationScaleFromEnv(this.env),
      nowIso,
    });

    if (doResponse === null) {
      return grantRejected(version, "coverage_unknown");
    }

    const doResult = doResponse.result;
    if (doResult === "conflict") {
      return {
        contract_version: version,
        result: "conflict",
        code: "",
        detail: "",
      };
    }
    return mapApplyGrantDoResponse(version, doResponse);
  }

  async beginTransfer(
    args: Record<string, unknown>,
  ): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return grantRejected(version, "unauthenticated");
    }

    const orgId = args.org_id;
    const fromInstallationId = args.from_installation_id;
    const reason = args.reason;
    if (
      typeof orgId !== "string" ||
      typeof fromInstallationId !== "string" ||
      typeof reason !== "string"
    ) {
      return grantRejected(version, "bad_request");
    }

    const operationRaw = args.operation;
    if (!validateOperation(operationRaw).ok) {
      return grantRejected(version, "assertion_invalid");
    }
    const operation = operationRaw as Record<string, unknown>;
    const assertionSha256 = await operationAssertionSha256(operation);
    const existingByAssertion = await readTransferByAssertionSha256(
      this.env.DB,
      assertionSha256,
    );
    if (existingByAssertion !== null) {
      return {
        contract_version: version,
        result: "ok",
        code: "",
        detail: transferRowToDetail(existingByAssertion),
      };
    }

    const check = await runHpAssertionChecks(
      this.env,
      "beginTransfer",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      const rejectedEnvelope = await rejectHpAssertion(
        this.env,
        access.email,
        "beginTransfer",
        check,
      );
      return {
        contract_version: rejectedEnvelope.contract_version,
        result: "rejected",
        code: rejectedEnvelope.code,
        detail: rejectedEnvelope.detail,
      };
    }

    const created = await executeBeginTransfer(this.env, {
      orgId,
      fromInstallationId,
      reason,
      assertionSha256: check.assertionSha256,
    });
    if (created === "bad_request") {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "beginTransfer",
        check.auditTarget,
        check.assertionSha256,
      );
      return grantRejected(version, "bad_request");
    }

    await finishHpAssertion(this.env, access.email, "beginTransfer", check);

    return {
      contract_version: version,
      result: "ok",
      code: "",
      detail: transferRowToDetail(created),
    };
  }

  async transferOut(args: Record<string, unknown>): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const transferId = args.transfer_id;
    if (typeof transferId !== "string" || transferId.length === 0) {
      return grantRejected(version, "bad_request");
    }

    const step = await executeTransferOut(this.env, version, transferId);
    if (step.result === "bad_request") {
      return grantRejected(version, "bad_request");
    }
    if (step.result === "transient") {
      return grantTransient(version, step.detail);
    }
    if (step.result === "rejected") {
      return grantRejected(version, step.code);
    }
    return {
      contract_version: version,
      result: step.result,
      code: "",
      detail: step.detail,
      receipt: step.receipt,
    };
  }

  async transferIn(args: Record<string, unknown>): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const transferId = args.transfer_id;
    if (typeof transferId !== "string" || transferId.length === 0) {
      return grantRejected(version, "bad_request");
    }

    const step = await executeTransferIn(this.env, version, transferId);
    if (step.result === "bad_request") {
      return grantRejected(version, "bad_request");
    }
    if (step.result === "transient") {
      return grantTransient(version, step.detail);
    }
    if (step.result === "rejected") {
      return grantRejected(version, step.code);
    }
    return {
      contract_version: version,
      result: step.result,
      code: "",
      detail: step.detail,
      receipt: step.receipt,
    };
  }

  async deleteInstallation(
    args: Record<string, unknown>,
  ): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return grantRejected(version, "unauthenticated");
    }

    const orgId = args.org_id;
    const reason = args.reason;
    if (typeof orgId !== "string" || typeof reason !== "string") {
      return grantRejected(version, "bad_request");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "deleteInstallation",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      const rejectedEnvelope = await rejectHpAssertion(
        this.env,
        access.email,
        "deleteInstallation",
        check,
      );
      return {
        contract_version: rejectedEnvelope.contract_version,
        result: "rejected",
        code: rejectedEnvelope.code,
        detail: rejectedEnvelope.detail,
      };
    }

    const deleted = await executeDeleteInstallation(this.env, {
      orgId,
      reason,
      operatorId: access.email,
    });
    if (deleted.result === "bad_request") {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "deleteInstallation",
        check.auditTarget,
        check.assertionSha256,
      );
      return grantRejected(version, "bad_request");
    }

    await finishHpAssertion(this.env, access.email, "deleteInstallation", check);

    return {
      contract_version: version,
      result: "ok",
      code: "",
      detail: deleted.detail,
    };
  }

  async voidForReversal(
    args: Record<string, unknown>,
  ): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    if (!("partial" in args) || typeof args.partial !== "boolean") {
      return grantRejected(version, "partial_invalid", "");
    }
    const partial = args.partial;

    const grantId = args.grant_id;
    const reversalId = args.reversal_id;
    const reason = args.reason;
    const evidenceSha256 = args.evidence_sha256;
    const aboKid = args.abo_kid;
    const aboSignature = args.abo_signature;
    if (
      typeof grantId !== "string" ||
      !isHex64(grantId) ||
      typeof reversalId !== "string" ||
      !isHex64(reversalId) ||
      typeof reason !== "string" ||
      reason.length === 0 ||
      typeof evidenceSha256 !== "string" ||
      !isHex64(evidenceSha256) ||
      typeof aboKid !== "string" ||
      aboKid.length === 0 ||
      typeof aboSignature !== "string" ||
      aboSignature.length === 0
    ) {
      return grantRejected(version, "bad_signature");
    }

    const signedBody = {
      contract_version: version,
      grant_id: grantId,
      reversal_id: reversalId,
      reason,
      evidence_sha256: evidenceSha256,
      partial,
    };

    const serviceKey = await readServiceKey(this.env.DB, aboKid);
    if (serviceKey === null) {
      return grantTransient(version, "unknown_kid");
    }

    const nowIso = await clockNowIso(this.env);
    if (
      serviceKey.status === "revoked" ||
      !serviceKeyActiveAt(serviceKey, nowIso)
    ) {
      return grantRejected(version, "bad_signature");
    }

    const verifyKey = await importEd25519VerifyKey(serviceKey.public_key);
    if (verifyKey === null) {
      return grantRejected(version, "bad_signature");
    }
    const signatureValid = await verifyGrantSignature({
      envelope: signedBody,
      jws: aboSignature,
      publicKey: verifyKey,
      kid: aboKid,
    });
    if (!signatureValid) {
      return grantRejected(version, "bad_signature");
    }

    const envelopeSha256 = await sha256Hex(canonicalize(signedBody));

    const ledgerRow = await this.env.DB.prepare(
      "SELECT grant_id, org_id, installation_id FROM grant_ledger WHERE grant_id = ?",
    )
      .bind(grantId)
      .first<{ grant_id: string; org_id: string; installation_id: string }>();

    const storedVoid = await findStoredReversalVoid(
      this.env,
      version,
      reversalId,
      ledgerRow,
      grantId,
      reason,
      evidenceSha256,
      envelopeSha256,
      nowIso,
    );
    if (storedVoid === "conflict") {
      return {
        contract_version: version,
        result: "conflict",
        code: "",
        detail: "",
      };
    }
    if (storedVoid !== null) {
      return mapStoredReversalVoidReplay(
        version,
        storedVoid,
        grantId,
        reason,
        evidenceSha256,
        partial,
      );
    }

    const voidForGrant = await this.env.DB.prepare(
      "SELECT grant_id FROM grant_void WHERE grant_id = ?",
    )
      .bind(grantId)
      .first<{ grant_id: string }>();
    if (voidForGrant !== null) {
      const receiptForGrant = await readVoidReceiptFromR2(this.env, grantId);
      if (receiptForGrant === null) {
        return grantRejected(version, "coverage_unknown");
      }
      const storedReversalIdForGrant = receiptForGrant.reversal_id;
      if (
        typeof storedReversalIdForGrant !== "string" ||
        storedReversalIdForGrant !== reversalId
      ) {
        return {
          contract_version: version,
          result: "conflict",
          code: "",
          detail: "",
        };
      }
    }

    if (partial) {
      return grantRejected(version, "partial_void", "");
    }

    if (ledgerRow !== null) {
      const binding = await readActiveTenantBinding(this.env.DB, ledgerRow.org_id);
      if (binding === null) {
        return grantRejected(version, "coverage_unknown");
      }
      const doResponse = await callCoverageDo(this.env, ledgerRow.installation_id, {
        kind: "void_for_reversal",
        installationId: ledgerRow.installation_id,
        orgId: ledgerRow.org_id,
        vendorContractVersion: version,
        bindingEpoch: binding.epoch,
        grantId,
        reversalId,
        reason,
        evidenceSha256,
        envelopeSha256,
        nowIso,
        platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
        durationScale: durationScaleFromEnv(this.env),
      });
      if (doResponse === null) {
        return grantRejected(version, "coverage_unknown");
      }
      return mapVoidForReversalDoResponse(version, doResponse);
    }
    const signingKey = await loadPlatformSigningKey(this.env.PLATFORM_SIGNING_KEY);
    if (signingKey === null) {
      return grantRejected(version, "coverage_unknown");
    }

    const receipt = await signReversalVoidReceipt({
      signingKey,
      vendorContractVersion: version,
      reversalId,
      installationId: VOID_NIL_UUID,
      orgId: VOID_NIL_UUID,
      termIds: [],
      appliedAt: nowIso,
      ledgerSeq: 0,
      envelopeSha256,
    });

    await this.env.DB.prepare(
      `INSERT INTO grant_void (grant_id, reason, source, evidence_sha256, at)
       VALUES (?, ?, 'reversal', ?, ?)`,
    )
      .bind(grantId, reason, evidenceSha256, nowIso)
      .run();

    const voidKey = `grant-ledger/${grantId}.void.ndjson`;
    const voidLine = JSON.stringify({
      grant_id: grantId,
      reason,
      source: "reversal",
      evidence_sha256: evidenceSha256,
      at: nowIso,
      receipt,
    });
    await this.env.R2.put(voidKey, `${voidLine}\n`);

    return {
      contract_version: version,
      result: "applied",
      code: "",
      detail: "",
      receipt,
    };
  }

  async releaseHeld(args: Record<string, unknown>): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return grantRejected(version, "unauthenticated");
    }

    const grantId = args.grant_id;
    const reason = args.reason;
    if (typeof grantId !== "string" || typeof reason !== "string") {
      return grantRejected(version, "bad_request");
    }

    const ledgerRow = await this.env.DB.prepare(
      "SELECT org_id, installation_id FROM grant_ledger WHERE grant_id = ?",
    )
      .bind(grantId)
      .first<{ org_id: string; installation_id: string }>();
    if (ledgerRow === null) {
      return grantRejected(version, "coverage_unknown");
    }
    const binding = await readActiveTenantBinding(this.env.DB, ledgerRow.org_id);
    if (binding === null) {
      return grantRejected(version, "coverage_unknown");
    }

    const operationRaw = args.operation;
    if (!validateOperation(operationRaw).ok) {
      return grantRejected(version, "assertion_invalid");
    }
    const operation = operationRaw as Record<string, unknown>;
    const assertionSha256 = await operationAssertionSha256(operation);
    const nowIso = await clockNowIso(this.env);

    const replayPeek = await callCoverageDo(this.env, ledgerRow.installation_id, {
      kind: "release_held",
      installationId: ledgerRow.installation_id,
      orgId: ledgerRow.org_id,
      vendorContractVersion: version,
      bindingEpoch: binding.epoch,
      grantId,
      reason,
      assertionSha256,
      nowIso,
      platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
      durationScale: durationScaleFromEnv(this.env),
      replayOnly: true,
    });
    if (
      replayPeek !== null &&
      replayPeek.result === "already_applied" &&
      isRecord(replayPeek.receipt)
    ) {
      return {
        contract_version: version,
        result: "already_applied",
        code: "",
        detail: "",
        receipt: replayPeek.receipt,
      };
    }

    const check = await runHpAssertionChecks(
      this.env,
      "releaseHeld",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      const rejectedEnvelope = await rejectHpAssertion(
        this.env,
        access.email,
        "releaseHeld",
        check,
      );
      return {
        contract_version: rejectedEnvelope.contract_version,
        result: "rejected",
        code: rejectedEnvelope.code,
        detail: rejectedEnvelope.detail,
      };
    }

    const doResponse = await callCoverageDo(this.env, ledgerRow.installation_id, {
      kind: "release_held",
      installationId: ledgerRow.installation_id,
      orgId: ledgerRow.org_id,
      vendorContractVersion: version,
      bindingEpoch: binding.epoch,
      grantId,
      reason,
      assertionSha256: check.assertionSha256,
      nowIso,
      platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
      durationScale: durationScaleFromEnv(this.env),
    });
    if (doResponse === null) {
      return grantRejected(version, "coverage_unknown");
    }

    await finishHpAssertion(this.env, access.email, "releaseHeld", check);
    return mapHpVoidDoResponse(version, doResponse);
  }

  async voidGrant(args: Record<string, unknown>): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return grantRejected(version, "unauthenticated");
    }

    const grantId = args.grant_id;
    const reason = args.reason;
    if (typeof grantId !== "string" || typeof reason !== "string") {
      return grantRejected(version, "bad_request");
    }

    const ledgerRow = await this.env.DB.prepare(
      "SELECT org_id, installation_id FROM grant_ledger WHERE grant_id = ?",
    )
      .bind(grantId)
      .first<{ org_id: string; installation_id: string }>();
    if (ledgerRow === null) {
      return grantRejected(version, "coverage_unknown");
    }
    const binding = await readTenantBindingForInstallation(
      this.env.DB,
      ledgerRow.org_id,
      ledgerRow.installation_id,
    );
    if (binding === null) {
      return grantRejected(version, "coverage_unknown");
    }

    const operationRaw = args.operation;
    if (!validateOperation(operationRaw).ok) {
      return grantRejected(version, "assertion_invalid");
    }
    const operation = operationRaw as Record<string, unknown>;
    const challenge = await operationChallenge(operation);
    const nowIso = await clockNowIso(this.env);

    const replayPeek = await callCoverageDo(this.env, ledgerRow.installation_id, {
      kind: "void_grant",
      installationId: ledgerRow.installation_id,
      orgId: ledgerRow.org_id,
      vendorContractVersion: version,
      bindingEpoch: binding.epoch,
      grantId,
      reason,
      assertionSha256: challenge,
      evidenceSha256: challenge,
      nowIso,
      platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
      durationScale: durationScaleFromEnv(this.env),
      replayOnly: true,
    });
    if (
      replayPeek !== null &&
      replayPeek.result === "already_applied" &&
      isRecord(replayPeek.receipt)
    ) {
      return {
        contract_version: version,
        result: "already_applied",
        code: "",
        detail: "",
        receipt: replayPeek.receipt,
      };
    }

    const check = await runHpAssertionChecks(
      this.env,
      "voidGrant",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      const rejectedEnvelope = await rejectHpAssertion(
        this.env,
        access.email,
        "voidGrant",
        check,
      );
      return {
        contract_version: rejectedEnvelope.contract_version,
        result: "rejected",
        code: rejectedEnvelope.code,
        detail: rejectedEnvelope.detail,
      };
    }

    const doResponse = await callCoverageDo(this.env, ledgerRow.installation_id, {
      kind: "void_grant",
      installationId: ledgerRow.installation_id,
      orgId: ledgerRow.org_id,
      vendorContractVersion: version,
      bindingEpoch: binding.epoch,
      grantId,
      reason,
      assertionSha256: challenge,
      evidenceSha256: challenge,
      nowIso,
      platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
      durationScale: durationScaleFromEnv(this.env),
    });
    if (doResponse === null) {
      return grantRejected(version, "coverage_unknown");
    }

    await finishHpAssertion(this.env, access.email, "voidGrant", check);
    const mapped = mapHpVoidDoResponse(version, doResponse);
    if (mapped.result === "applied") {
      await retireHeldBindingIfEmpty(
        this.env,
        ledgerRow.org_id,
        ledgerRow.installation_id,
        reason,
      );
    }
    return mapped;
  }

  async listGrantsForVoid(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const credentialId = args.credential_id;
    if (typeof credentialId !== "string" || credentialId.length === 0) {
      return rejected(version, "window_invalid", "");
    }

    const window = parseListGrantsForVoidWindow(args.window);
    if (window === null) {
      return rejected(version, "window_invalid", "");
    }

    const rows = await this.env.DB.prepare(
      `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
              operator_credential_id, envelope_sha256, receipt, applied_at
       FROM grant_ledger
       WHERE operator_credential_id = ?
         AND applied_at >= ?
         AND applied_at <= ?
       ORDER BY applied_at ASC, grant_id ASC`,
    )
      .bind(credentialId, window.applied_from, window.applied_to)
      .all<{
        grant_id: string;
        origin_grant_id: string;
        org_id: string;
        installation_id: string;
        kind: string;
        source_kind: string;
        operator_credential_id: string;
        envelope_sha256: string;
        receipt: string;
        applied_at: string;
      }>();

    const mapped = (rows.results ?? []).map((row) => ({
      grant_id: row.grant_id,
      origin_grant_id: row.origin_grant_id,
      org_id: row.org_id,
      installation_id: row.installation_id,
      kind: row.kind,
      source_kind: row.source_kind,
      operator_credential_id: row.operator_credential_id,
      envelope_sha256: row.envelope_sha256,
      receipt: JSON.parse(row.receipt) as Record<string, unknown>,
      applied_at: row.applied_at,
    }));

    return ok(version, JSON.stringify(mapped));
  }

  async suspend(args: Record<string, unknown>): Promise<VendorResultEnvelope> {
    return this.suspendOrResume("suspend", args);
  }

  async resume(args: Record<string, unknown>): Promise<VendorResultEnvelope> {
    return this.suspendOrResume("resume", args);
  }

  private async suspendOrResume(
    kind: "suspend" | "resume",
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const orgId = args.org_id;
    const reason = args.reason;
    if (typeof orgId !== "string" || typeof reason !== "string") {
      return rejected(version, "bad_request");
    }

    const binding = await readActiveTenantBinding(this.env.DB, orgId);
    if (binding === null) {
      return rejected(version, "coverage_unknown");
    }

    const nowIso = await clockNowIso(this.env);
    const doResponse = await callCoverageDo(this.env, binding.installation_id, {
      kind,
      orgId,
      reason,
      vendorContractVersion: version,
      bindingEpoch: binding.epoch,
      nowIso,
    });
    if (doResponse === null || !isRecord(doResponse.snapshot)) {
      return rejected(version, "coverage_unknown");
    }

    return ok(version, JSON.stringify(doResponse.snapshot));
  }

  async inspectCoverage(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const orgId = args.org_id;
    if (typeof orgId !== "string" || orgId.length === 0) {
      return rejected(version, "bad_request");
    }

    const binding = await readActiveTenantBinding(this.env.DB, orgId);
    if (binding === null) {
      return rejected(version, "coverage_unknown");
    }

    const doResponse = await callCoverageDo(this.env, binding.installation_id, {
      kind: "inspect_coverage",
      orgId,
      vendorContractVersion: version,
    });
    if (doResponse === null) {
      return rejected(version, "coverage_unknown");
    }

    const detail = JSON.stringify({
      terms: doResponse.terms,
      grants: doResponse.grants,
      reservations: doResponse.reservations,
    });
    return ok(version, detail);
  }

  async getCoverage(args: Record<string, unknown>): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;
    const orgId = args.org_id;
    if (typeof orgId !== "string" || orgId.length === 0) {
      return rejected(version, "bad_request");
    }

    const installationOverride =
      typeof args.installation_id === "string" ? args.installation_id : null;
    const installationId =
      installationOverride ??
      (await readActiveTenantBinding(this.env.DB, orgId))?.installation_id ??
      null;
    if (installationId === null) {
      return rejected(version, "coverage_unknown");
    }

    const doResponse = await callCoverageDo(this.env, installationId, {
      kind: "read_coverage",
      orgId,
      vendorContractVersion: version,
    });
    if (doResponse === null) {
      return rejected(version, "coverage_unknown");
    }

    const detail = JSON.stringify({
      snapshot: doResponse.snapshot,
      queued_terms: doResponse.queued_terms,
      recent_terms: doResponse.recent_terms,
    });
    return ok(version, detail);
  }

  async listGrants(args: Record<string, unknown>): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const conditions: string[] = [];
    const binds: unknown[] = [];
    if (typeof args.org_id === "string") {
      conditions.push("org_id = ?");
      binds.push(args.org_id);
    }
    if (typeof args.source_kind === "string") {
      conditions.push("source_kind = ?");
      binds.push(args.source_kind);
    }
    if (typeof args.credential_id === "string") {
      conditions.push("operator_credential_id = ?");
      binds.push(args.credential_id);
    }
    if (typeof args.applied_from === "string") {
      conditions.push("applied_at >= ?");
      binds.push(args.applied_from);
    }
    if (typeof args.applied_to === "string") {
      conditions.push("applied_at <= ?");
      binds.push(args.applied_to);
    }

    const whereClause =
      conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    const rows = await this.env.DB.prepare(
      `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
              operator_credential_id, envelope_sha256, receipt, applied_at
       FROM grant_ledger
       ${whereClause}
       ORDER BY applied_at ASC, grant_id ASC`,
    )
      .bind(...binds)
      .all<{
        grant_id: string;
        origin_grant_id: string;
        org_id: string;
        installation_id: string;
        kind: string;
        source_kind: string;
        operator_credential_id: string;
        envelope_sha256: string;
        receipt: string;
        applied_at: string;
      }>();

    const mapped = (rows.results ?? []).map((row) => ({
      grant_id: row.grant_id,
      origin_grant_id: row.origin_grant_id,
      org_id: row.org_id,
      installation_id: row.installation_id,
      kind: row.kind,
      source_kind: row.source_kind,
      operator_credential_id: row.operator_credential_id,
      envelope_sha256: row.envelope_sha256,
      receipt: JSON.parse(row.receipt) as Record<string, unknown>,
      applied_at: row.applied_at,
    }));

    return ok(version, JSON.stringify(mapped));
  }

  async readCoverageEvents(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const limitRaw = args.limit;
    if (
      limitRaw === undefined ||
      !Number.isInteger(limitRaw) ||
      (limitRaw as number) < 1 ||
      (limitRaw as number) > 200
    ) {
      return rejected(version, "limit_invalid");
    }
    const limit = limitRaw as number;
    const afterRaw = args.after;
    const after =
      afterRaw === undefined
        ? 0
        : Number.isInteger(afterRaw)
          ? (afterRaw as number)
          : 0;

    const pageRows = await this.env.DB.prepare(
      `SELECT event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq,
              kind, at, snapshot
       FROM coverage_event
       WHERE feed_seq > ?
       ORDER BY feed_seq ASC
       LIMIT ?`,
    )
      .bind(after, limit)
      .all<{
        event_id: string;
        feed_seq: number;
        org_id: string;
        installation_id: string;
        binding_epoch: number;
        clinic_seq: number;
        kind: string;
        at: string;
        snapshot: string;
      }>();

    const events = (pageRows.results ?? []).map((row) => ({
      event_id: row.event_id,
      feed_seq: row.feed_seq,
      org_id: row.org_id,
      installation_id: row.installation_id,
      binding_epoch: row.binding_epoch,
      clinic_seq: row.clinic_seq,
      kind: row.kind,
      at: row.at,
      snapshot: JSON.parse(row.snapshot) as Record<string, unknown>,
    }));

    const nextAfter =
      events.length > 0 ? events[events.length - 1]!.feed_seq : after;

    const moreRow = await this.env.DB.prepare(
      `SELECT feed_seq FROM coverage_event WHERE feed_seq > ? LIMIT 1`,
    )
      .bind(nextAfter)
      .first<{ feed_seq: number }>();

    const detail = JSON.stringify({
      after,
      events,
      next_after: nextAfter,
      has_more: moreRow !== null,
    });
    return ok(version, detail);
  }
}
