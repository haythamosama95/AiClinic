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
  verifyReceiptSignature,
  signCompactJws,
  receiptSigningBytes,
  type AccessCertsDocument,
  type Assertion,
} from "vendor-contracts";
import { decodeDoResponse } from "../quota-do/response-decoder";
import type { DurationScale } from "../coverage/calendar";
import {
  acceptDeleteInstallation,
  executeBeginTransfer,
  executeTransferIn,
  executeTransferOut,
  dispatchDeletionCommands as dispatchDueDeletionCommands,
  dispatchTransferPreparations,
  readDeletionCommand,
  readTransferByAssertionSha256,
  isTransferRouteQuarantined,
  readTransferById,
  readTransferPreparationByAssertion,
  resumeTransferPreparation,
  resumeDeleteInstallation,
  retireHeldBindingIfEmpty,
  transferRowToDetail,
  verifyTransferOutEvidence,
} from "../coverage/transfer";
import {
  insertDoRebuildMismatchAlert,
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
import {
  buildEntrypointAuditStatement,
  writeEntrypointAudit,
} from "../control/audit";
import {
  deprecateCapabilityAction,
  retireCapabilityAction,
} from "../control/capability-lifecycle";
import {
  armKillSwitchAction,
  disarmKillSwitchAction,
} from "../control/kill-switch";
import {
  canaryRoutingPolicyAction,
  promoteRoutingPolicyAction,
  publishRoutingPolicyAction,
  rollbackRoutingPolicyAction,
} from "../control/routing-policy";
import type { ControlActionResult } from "../control/types";
import {
  activateCohortAction,
  promoteCohortAction,
} from "../control/cohort";
import {
  beginTokenContractRotationAction,
  retireTokenContractAction,
} from "../control/token-contract";
import { setInstallationSuspendedAction } from "../control/installation-lifecycle";
import {
  createManifestRetentionClassResolver,
} from "../retention";
import { supportLookup as runSupportLookup } from "../support";
import { normalizeRequestReference } from "../reference";
import { raiseAl19FromOutbox } from "../alert/index";
import {
  runRebuildClinicDo,
  runRebuildGrantLedger,
  runRefreshCoverageSnapshot,
  loadPlatformSigningKey,
  type PlatformSigningMaterial,
} from "../quota-do/coverage";

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
  feedConsumerHealth: "M",
  voidForReversal: "M",
  releaseHeld: "HP",
  recoverStrandedTerm: "HP",
  voidGrant: "HP",
  listGrantsForVoid: "M",
  beginTransfer: "HP",
  transferOut: "M",
  transferIn: "M",
  deleteInstallation: "HP",
  publishRoutingPolicy: "H",
  canaryRoutingPolicy: "H",
  promoteRoutingPolicy: "H",
  rollbackRoutingPolicy: "H",
  armKillSwitch: "H",
  disarmKillSwitch: "H",
  deprecateCapability: "H",
  retireCapability: "H",
  activateCohort: "H",
  promoteCohort: "H",
  beginTokenContractRotation: "H",
  retireTokenContract: "H",
  supportLookup: "H",
  recordOperatorAction: "H",
  rebuildClinicDo: "H",
  rebuildGrantLedger: "H",
  refreshCoverageSnapshot: "H",
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
  accepted_versions?: number[];
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
  accepted_versions?: number[];
};

const VOID_NIL_UUID = "00000000-0000-0000-0000-000000000000";
const HEX64_RE = /^[0-9a-f]{64}$/u;

type VendorEnv = ClockEnv & {
  DB: D1Database;
  R2: R2Bucket;
  DO: DurableObjectNamespace;
  ISSUER_ID: string;
  ENVIRONMENT: string;
  TEST_CLOCK?: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  /** Local full-stack tests provide the generated Access certificates here. */
  ACCESS_CERTS_JSON?: string;
  WEBAUTHN_RP_ID: string;
  WEBAUTHN_ORIGIN: string;
  ALERT_EMAIL_TO: string;
  PLATFORM_SIGNING_KEY?: string;
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
    ...(code === "contract_version_unsupported"
      ? { accepted_versions: [VENDOR_CHANNEL - 1, VENDOR_CHANNEL] }
      : {}),
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

function envelopeFromControlResult(
  version: number,
  result: ControlActionResult,
): VendorResultEnvelope {
  if (result.ok) {
    return ok(version, JSON.stringify(result.body));
  }
  if (result.status === 409) {
    return conflict(version, result.error);
  }
  if (result.status === 404) {
    return rejected(version, result.error);
  }
  return rejected(version, result.error);
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

/**
 * R1-C3: validity bounds must be canonical UTC ISO-8601 timestamps
 * (`YYYY-MM-DDTHH:MM:SS[.sss]Z`) that parse to a finite instant, so a typo
 * like `2030-13-01` can never silently remove a time restriction.
 */
const CANONICAL_UTC_ISO_RE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/u;

function parseCanonicalUtcTimestampMs(value: string): number | null {
  if (!CANONICAL_UTC_ISO_RE.test(value)) {
    return null;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function validKeyWindowBounds(
  notBefore: unknown,
  notAfter: unknown,
): boolean {
  if (typeof notBefore !== "string" || typeof notAfter !== "string") {
    return false;
  }
  const notBeforeMs = parseCanonicalUtcTimestampMs(notBefore);
  const notAfterMs = parseCanonicalUtcTimestampMs(notAfter);
  return (
    notBeforeMs !== null && notAfterMs !== null && notBeforeMs < notAfterMs
  );
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
    ...(code === "contract_version_unsupported"
      ? { accepted_versions: [VENDOR_CHANNEL - 1, VENDOR_CHANNEL] }
      : {}),
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

async function verifyJwsAgainstWirePayload(input: {
  jws: string;
  publicKey: CryptoKey;
  kid: string;
  payloadBytes: Uint8Array;
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
  if (
    headerBytes === null ||
    payloadBytes === null ||
    signatureBytes === null
  ) {
    return false;
  }
  const headerValue = JSON.parse(new TextDecoder().decode(headerBytes)) as {
    alg?: string;
    kid?: string;
  };
  if (headerValue.alg !== "EdDSA" || headerValue.kid !== input.kid) {
    return false;
  }
  if (!bytesEqual(payloadBytes, input.payloadBytes)) {
    return false;
  }
  const signingInput = new TextEncoder().encode(
    `${headerSegment}.${payloadSegment}`,
  );
  return crypto.subtle.verify(
    { name: "Ed25519" },
    input.publicKey,
    signatureBytes,
    signingInput,
  );
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

type GrantClaimRow = {
  grant_id: string;
  org_id: string;
  source_kind: string;
  envelope: string;
  envelope_sha256: string;
  installation_id: string;
  binding_epoch: number;
  route_generation: number;
  state: "pending" | "completed" | "disputed";
  receipt: string | null;
  accepted_command: string | null;
  accepted_actor: string | null;
  signer_credential_id: string | null;
  assertion_sha256: string | null;
  override_assertion_sha256: string | null;
  accepted_contract_version: number | null;
  accepted_ceiling_policy_version: number | null;
  plan_snapshot: string | null;
  accepted_at: string | null;
  due_at: string | null;
  lease_token: string | null;
  lease_until: string | null;
  dispatch_attempts: number;
  command_state: "none" | "accepted" | "completed" | "rejected";
  terminal_code: string | null;
  terminal_detail: string | null;
};

type LiveValueRouteRow = {
  grant_id: string;
  org_id: string;
  installation_id: string;
  binding_epoch: number;
  generation: number;
  state: "stable" | "moving" | "voiding" | "retired";
  transfer_id: string | null;
  reversal_id: string | null;
};

type ReversalCommandRow = {
  reversal_id: string;
  grant_id: string;
  request_sha256: string;
  request_body: string;
  route_installation_id: string | null;
  route_epoch: number | null;
  route_generation: number | null;
  state: "due" | "terminal";
  receipt: string | null;
  export_payload: string | null;
  export_state: "none" | "due" | "shipped";
  created_at: string;
  updated_at: string;
};

function canonicalJsonText(value: unknown): string {
  return new TextDecoder().decode(canonicalize(value));
}

async function readGrantClaim(
  db: D1Database,
  grantId: string,
): Promise<GrantClaimRow | GrantResultEnvelope | null> {
  return db
    .prepare(
      `SELECT grant_id, org_id, source_kind, envelope, envelope_sha256,
              installation_id, binding_epoch, route_generation, state, receipt,
              accepted_command, accepted_actor, signer_credential_id,
              assertion_sha256, override_assertion_sha256,
              accepted_contract_version, accepted_ceiling_policy_version,
              plan_snapshot, accepted_at, due_at,
              lease_token, lease_until, dispatch_attempts, command_state,
              terminal_code, terminal_detail
       FROM grant_claim WHERE grant_id = ?`,
    )
    .bind(grantId)
    .first<GrantClaimRow>();
}

async function readLiveValueRoute(
  db: D1Database,
  grantId: string,
): Promise<LiveValueRouteRow | null> {
  return db.prepare(
    `SELECT grant_id, org_id, installation_id, binding_epoch, generation,
            state, transfer_id, reversal_id
     FROM live_value_route WHERE grant_id = ?`,
  ).bind(grantId).first<LiveValueRouteRow>();
}

function isGrantResultEnvelope(
  value: GrantClaimRow | GrantResultEnvelope,
): value is GrantResultEnvelope {
  return "result" in value && !("grant_id" in value);
}

async function alertGrantClaimDispute(
  env: VendorEnv,
  orgId: string,
  grantId: string,
  nowIso: string,
): Promise<void> {
  const alertKey = `AL-10:grant-claim:${grantId}`;
  await env.DB.prepare(
    `INSERT INTO grant_claim_dispute (grant_id, org_id, reason, first_at, last_at, count)
     VALUES (?, ?, 'grant_identity_mismatch', ?, ?, 1)
     ON CONFLICT(grant_id) DO UPDATE SET last_at = excluded.last_at, count = count + 1`,
  )
    .bind(grantId, orgId, nowIso, nowIso)
    .run();
  await env.DB.prepare(
    `INSERT INTO platform_alert
       (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at)
     VALUES (?, 'AL-10', 'high', ?, ?, 1, 'unsent', NULL, NULL)
     ON CONFLICT(alert_key) DO UPDATE SET last_at = excluded.last_at, count = count + 1`,
  )
    .bind(alertKey, nowIso, nowIso)
    .run();
  const existing = await readGrantClaim(env.DB, grantId);
  if (existing !== null && existing.state !== "disputed") {
    await env.DB.prepare(
      `UPDATE grant_claim SET state = 'disputed' WHERE grant_id = ?`,
    )
      .bind(grantId)
      .run();
  }
}

async function parseGrantReceipt(value: unknown): Promise<Record<string, unknown> | null> {
  if (isRecord(value)) return value;
  if (typeof value !== "string") return null;
  try {
    const parsed: unknown = JSON.parse(value);
    return isRecord(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

async function readGrantLedgerR2(
  env: VendorEnv,
  grantId: string,
): Promise<Record<string, unknown> | null> {
  const object = await env.R2.get(`grant-ledger/${grantId}.ndjson`);
  if (object === null) return null;
  try {
    const line = (await object.text()).trim().split("\n")[0] ?? "";
    if (line.length === 0) return null;
    const parsed: unknown = JSON.parse(line);
    return isRecord(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/** Reconcile every retained route before the first dispatcher uses global claims. */
async function ensureGrantClaimsBackfilled(
  env: VendorEnv,
  orgId: string,
  version: number,
): Promise<boolean> {
  const done = await env.DB.prepare(
    "SELECT org_id FROM grant_claim_backfill WHERE org_id = ?",
  )
    .bind(orgId)
    .first<{ org_id: string }>();
  if (done !== null) {
    return ensureComplimentaryCeilingClaimsBackfilled(env, orgId, version);
  }

  const bindings = await env.DB.prepare(
    `SELECT installation_id, epoch FROM tenant_binding WHERE org_id = ? ORDER BY epoch ASC`,
  )
    .bind(orgId)
    .all<{ installation_id: string; epoch: number }>();
  const ledgerRows = await env.DB.prepare(
    `SELECT grant_id, installation_id, envelope_sha256, receipt, source_kind, applied_at
     FROM grant_ledger WHERE org_id = ? ORDER BY applied_at, grant_id`,
  )
    .bind(orgId)
    .all<{
      grant_id: string;
      installation_id: string;
      envelope_sha256: string;
      receipt: string;
      source_kind: string;
      applied_at: string;
    }>();
  const ledgerById = new Map((ledgerRows.results ?? []).map((row) => [row.grant_id, row]));
  const seen = new Set<string>();
  const nowIso = await clockNowIso(env);

  for (const binding of bindings.results ?? []) {
    const inspected = await callCoverageDo(env, binding.installation_id, {
      kind: "inspect_coverage",
      installationId: binding.installation_id,
      orgId,
      vendorContractVersion: version,
    });
    if (inspected === null || !Array.isArray(inspected.grants)) return false;
    for (const raw of inspected.grants) {
      if (!isRecord(raw) || typeof raw.grant_id !== "string") {
        await alertGrantClaimDispute(env, orgId, "unknown", nowIso);
        return false;
      }
      const grantId = raw.grant_id;
      const envelopeRaw = raw.envelope;
      const envelopeText = typeof envelopeRaw === "string"
        ? envelopeRaw
        : JSON.stringify(envelopeRaw) ?? "";
      let envelope: unknown;
      try { envelope = JSON.parse(envelopeText); } catch { envelope = null; }
      if (
        raw.source_kind === "transfer" && isRecord(envelope) &&
        typeof envelope.transfer_id === "string" && Number.isInteger(envelope.index)
      ) {
        const transfer = await readTransferById(env.DB, envelope.transfer_id);
        const transferPackage: unknown = transfer?.package === null || transfer?.package === undefined
          ? null
          : JSON.parse(transfer.package);
        envelope = Array.isArray(transferPackage)
          ? transferPackage[envelope.index as number] ?? null
          : null;
      }
      const receipt = await parseGrantReceipt(raw.receipt);
      if (
        !isRecord(envelope) || receipt === null ||
        typeof raw.envelope_sha256 !== "string" ||
        typeof raw.source_kind !== "string" ||
        receipt.org_id !== orgId ||
        receipt.installation_id !== binding.installation_id ||
        receipt.grant_id !== grantId ||
        receipt.envelope_sha256 !== raw.envelope_sha256 ||
        await grantEnvelopeHash(envelope) !== raw.envelope_sha256
      ) {
        await alertGrantClaimDispute(env, orgId, grantId, nowIso);
        return false;
      }
      const ledger = ledgerById.get(grantId);
      if (ledger !== undefined) {
        const ledgerReceipt = await parseGrantReceipt(ledger.receipt);
        if (
          ledger.installation_id !== binding.installation_id ||
          ledger.source_kind !== raw.source_kind ||
          ledger.envelope_sha256 !== raw.envelope_sha256 ||
          ledgerReceipt === null || canonicalJsonText(ledgerReceipt) !== canonicalJsonText(receipt)
        ) {
          await alertGrantClaimDispute(env, orgId, grantId, nowIso);
          return false;
        }
      }
      const r2Row = await readGrantLedgerR2(env, grantId);
      if (r2Row !== null) {
        const r2Receipt = await parseGrantReceipt(r2Row.receipt);
        if (
          r2Row.org_id !== orgId ||
          r2Row.grant_id !== grantId ||
          r2Row.installation_id !== binding.installation_id ||
          r2Row.source_kind !== raw.source_kind ||
          r2Row.envelope_sha256 !== raw.envelope_sha256 ||
          r2Receipt === null || canonicalJsonText(r2Receipt) !== canonicalJsonText(receipt)
        ) {
          await alertGrantClaimDispute(env, orgId, grantId, nowIso);
          return false;
        }
      }
      const claim = await readGrantClaim(env.DB, grantId);
      if (claim !== null) {
        const claimReceipt = await parseGrantReceipt(claim.receipt);
        if (
          claim.org_id !== orgId ||
          claim.source_kind !== raw.source_kind ||
          claim.envelope_sha256 !== raw.envelope_sha256 ||
          claim.installation_id !== binding.installation_id ||
          claim.envelope !== canonicalJsonText(envelope) ||
          (claim.state === "completed" && (
            claimReceipt === null || canonicalJsonText(claimReceipt) !== canonicalJsonText(receipt)
          ))
        ) {
          await alertGrantClaimDispute(env, orgId, grantId, nowIso);
          return false;
        }
      } else {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO grant_claim (
             grant_id, org_id, source_kind, envelope, envelope_sha256,
             installation_id, binding_epoch, route_generation, state, receipt,
             created_at, completed_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 'completed', ?, ?, ?)`,
        )
          .bind(
            grantId,
            orgId,
            raw.source_kind,
            canonicalJsonText(envelope),
            raw.envelope_sha256,
            binding.installation_id,
            binding.epoch,
            canonicalJsonText(receipt),
            typeof raw.applied_at === "string" ? raw.applied_at : nowIso,
            typeof raw.applied_at === "string" ? raw.applied_at : nowIso,
          )
          .run();
      }
      await env.DB.prepare(
        `INSERT OR IGNORE INTO live_value_route (
           grant_id, org_id, installation_id, binding_epoch, generation, state, updated_at
         ) SELECT grant_id, org_id, installation_id, binding_epoch, route_generation,
                  'stable', ?
           FROM grant_claim WHERE grant_id = ? AND state <> 'disputed'`,
      ).bind(nowIso, grantId).run();
      seen.add(grantId);
    }
  }

  for (const row of ledgerRows.results ?? []) {
    if (!seen.has(row.grant_id)) {
      await alertGrantClaimDispute(env, orgId, row.grant_id, nowIso);
      return false;
    }
  }
  await env.DB.prepare(
    `INSERT OR IGNORE INTO grant_claim_backfill (org_id, completed_at) VALUES (?, ?)`,
  )
    .bind(orgId, nowIso)
    .run();
  return ensureComplimentaryCeilingClaimsBackfilled(env, orgId, version);
}

function buildGrantClaimInsertStatement(
  db: D1Database,
  input: {
    grantId: string;
    orgId: string;
    sourceKind: "paid" | "complimentary" | "transfer";
    envelope: Record<string, unknown>;
    envelopeSha256: string;
    installationId: string;
    bindingEpoch: number;
    nowIso: string;
    accepted?: {
      command: Record<string, unknown>;
      actor: string;
      signerCredentialId: string;
      assertionSha256: string;
      overrideAssertionSha256: string | null;
      contractVersion: number;
      ceilingPolicyVersion: number;
      planSnapshot: Record<string, unknown>;
    };
  },
): D1PreparedStatement {
  const accepted = input.accepted;
  return db.prepare(
    `INSERT OR IGNORE INTO grant_claim (
       grant_id, org_id, source_kind, envelope, envelope_sha256,
       installation_id, binding_epoch, route_generation, state, receipt,
       created_at, completed_at, accepted_command, accepted_actor,
       signer_credential_id, assertion_sha256, override_assertion_sha256,
       accepted_contract_version, accepted_ceiling_policy_version,
       plan_snapshot, accepted_at, due_at,
       command_state
     ) SELECT ?, ?, ?, ?, ?, ?, ?, 1, 'pending', NULL, ?, NULL,
       ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
       WHERE NOT EXISTS (SELECT 1 FROM grant_tombstone WHERE grant_id = ?)`
  ).bind(
    input.grantId,
    input.orgId,
    input.sourceKind,
    canonicalJsonText(input.envelope),
    input.envelopeSha256,
    input.installationId,
    input.bindingEpoch,
    input.nowIso,
    accepted === undefined ? null : canonicalJsonText(accepted.command),
    accepted?.actor ?? null,
    accepted?.signerCredentialId ?? null,
    accepted?.assertionSha256 ?? null,
    accepted?.overrideAssertionSha256 ?? null,
    accepted?.contractVersion ?? null,
    accepted?.ceilingPolicyVersion ?? null,
    accepted === undefined ? null : canonicalJsonText(accepted.planSnapshot),
    accepted?.command === undefined ? null : input.nowIso,
    accepted?.command === undefined ? null : input.nowIso,
    accepted === undefined ? "none" : "accepted",
    input.grantId,
  );
}

async function createOrReadGrantClaim(
  env: VendorEnv,
  input: Parameters<typeof buildGrantClaimInsertStatement>[1],
): Promise<GrantClaimRow | null> {
  await env.DB.batch([
    buildGrantClaimInsertStatement(env.DB, input),
    env.DB.prepare(
      `INSERT OR IGNORE INTO live_value_route (
         grant_id, org_id, installation_id, binding_epoch, generation, state, updated_at
       ) SELECT grant_id, org_id, installation_id, binding_epoch, route_generation,
                'stable', ?
         FROM grant_claim WHERE grant_id = ? AND state <> 'disputed'
           AND NOT EXISTS (SELECT 1 FROM grant_tombstone WHERE grant_id = ?)`
    ).bind(input.nowIso, input.grantId, input.grantId),
  ]);
  const claim = await readGrantClaim(env.DB, input.grantId);
  if (
    claim === null || claim.org_id !== input.orgId ||
    claim.envelope_sha256 !== input.envelopeSha256 ||
    claim.source_kind !== input.sourceKind ||
    claim.envelope !== canonicalJsonText(input.envelope)
  ) {
    return null;
  }
  return claim;
}

async function acquireAcceptedGrantLease(
  env: VendorEnv,
  grantId: string,
  nowIso: string,
): Promise<string | null> {
  const leaseToken = crypto.randomUUID();
  const leaseUntil = new Date(Date.parse(nowIso) + 60_000).toISOString();
  await env.DB.prepare(
    `UPDATE grant_claim
     SET lease_token = ?, lease_until = ?, dispatch_attempts = dispatch_attempts + 1
     WHERE grant_id = ? AND state = 'pending' AND command_state = 'accepted'
       AND (lease_until IS NULL OR lease_until <= ?)`,
  ).bind(leaseToken, leaseUntil, grantId, nowIso).run();
  const claim = await readGrantClaim(env.DB, grantId);
  return claim?.lease_token === leaseToken ? leaseToken : null;
}

async function releaseAcceptedGrantLease(
  env: VendorEnv,
  claim: GrantClaimRow,
  leaseToken: string,
  nowIso: string,
): Promise<void> {
  const dueAt = new Date(Date.parse(nowIso) + 60_000).toISOString();
  await env.DB.prepare(
    `UPDATE grant_claim SET lease_token = NULL, lease_until = NULL, due_at = ?
     WHERE grant_id = ? AND command_state = 'accepted' AND lease_token = ?`,
  ).bind(dueAt, claim.grant_id, leaseToken).run();
}

async function rejectAcceptedGrantCommand(
  env: VendorEnv,
  claim: GrantClaimRow,
  code: string,
  detail: string,
): Promise<void> {
  await env.DB.prepare(
    `UPDATE grant_claim
     SET command_state = 'rejected', terminal_code = ?, terminal_detail = ?,
         lease_token = NULL, lease_until = NULL
     WHERE grant_id = ? AND command_state = 'accepted'`,
  ).bind(code, detail, claim.grant_id).run();
}

function claimReplayResult(
  version: number,
  claim: GrantClaimRow,
  envelopeSha256: string,
  orgId: string,
): GrantResultEnvelope | "pending" | "conflict" | "disputed" {
  if (claim.org_id !== orgId || claim.envelope_sha256 !== envelopeSha256) {
    return "conflict";
  }
  if (claim.state === "disputed") return "disputed";
  if (claim.command_state === "rejected") {
    return {
      contract_version: version,
      result: "rejected",
      code: claim.terminal_code ?? "coverage_unknown",
      detail: claim.terminal_detail ?? "",
    };
  }
  if (claim.state === "pending") return "pending";
  if (claim.receipt === null) return "disputed";
  try {
    const receipt: unknown = JSON.parse(claim.receipt);
    if (!isRecord(receipt)) return "disputed";
    return {
      contract_version: version,
      result: "already_applied",
      code: "",
      detail: "",
      receipt,
    };
  } catch {
    return "disputed";
  }
}

async function routePendingGrantClaim(
  env: VendorEnv,
  claim: GrantClaimRow,
  version: number,
): Promise<GrantClaimRow | null> {
  if (claim.state !== "pending") {
    return null;
  }
  const valueRoute = await readLiveValueRoute(env.DB, claim.grant_id);
  if (valueRoute === null || valueRoute.state !== "stable") return null;
  const oldBinding = await readTenantBindingForInstallation(
    env.DB,
    claim.org_id,
    claim.installation_id,
  );
  if (oldBinding === null || oldBinding.status !== "retired") return claim;

  let liveBinding = await readActiveTenantBinding(env.DB, claim.org_id);
  if (liveBinding === null) {
    await resolveOrInsertGrantBinding(env, claim.org_id);
    liveBinding = await readActiveTenantBinding(env.DB, claim.org_id);
  }
  if (liveBinding === null) return null;
  const sealedAt = await clockNowIso(env);
  const sealed = await callCoverageDo(env, claim.installation_id, {
    kind: "seal_grant_route",
    installationId: claim.installation_id,
    orgId: claim.org_id,
    bindingEpoch: claim.binding_epoch,
    grantId: claim.grant_id,
    envelopeSha256: claim.envelope_sha256,
    routeGeneration: claim.route_generation,
    sealedAt,
  });
  if (sealed === null) return null;
  if (sealed.result === "already_applied" && isRecord(sealed.receipt)) {
    const receipt = sealed.receipt;
    if (
      receipt.org_id !== claim.org_id ||
      receipt.installation_id !== claim.installation_id ||
      receipt.grant_id !== claim.grant_id ||
      receipt.envelope_sha256 !== claim.envelope_sha256
    ) {
      await alertGrantClaimDispute(env, claim.org_id, claim.grant_id, sealedAt);
      return null;
    }
    await env.DB.prepare(
      `UPDATE grant_claim SET state = 'completed', receipt = ?, completed_at = ?,
              command_state = CASE WHEN accepted_command IS NULL THEN command_state ELSE 'completed' END,
              lease_token = NULL, lease_until = NULL
       WHERE grant_id = ? AND state = 'pending' AND installation_id = ? AND route_generation = ?`,
    )
      .bind(canonicalJsonText(receipt), sealedAt, claim.grant_id, claim.installation_id, claim.route_generation)
      .run();
    const reread = await readGrantClaim(env.DB, claim.grant_id);
    if (reread === null) return null;
    const replay = claimReplayResult(version, reread, claim.envelope_sha256, claim.org_id);
    return typeof replay === "object" ? replay : null;
  }
  if (sealed.result !== "sealed") {
    await alertGrantClaimDispute(env, claim.org_id, claim.grant_id, sealedAt);
    return null;
  }

  await env.DB.batch([
    env.DB.prepare(
      `UPDATE grant_claim
       SET installation_id = ?, binding_epoch = ?, route_generation = route_generation + 1
       WHERE grant_id = ? AND state = 'pending' AND installation_id = ?
         AND binding_epoch = ? AND route_generation = ?
         AND EXISTS (SELECT 1 FROM live_value_route WHERE grant_id = ?
           AND state = 'stable' AND generation = ? AND installation_id = ?)`,
    ).bind(
      liveBinding.installation_id, liveBinding.epoch, claim.grant_id,
      claim.installation_id, claim.binding_epoch, claim.route_generation,
      claim.grant_id, claim.route_generation, claim.installation_id,
    ),
    env.DB.prepare(
      `UPDATE live_value_route SET installation_id = ?, binding_epoch = ?,
         generation = generation + 1, updated_at = ?
       WHERE grant_id = ? AND state = 'stable' AND generation = ? AND installation_id = ?`,
    ).bind(
      liveBinding.installation_id, liveBinding.epoch, sealedAt, claim.grant_id,
      claim.route_generation, claim.installation_id,
    ),
  ]);
  return readGrantClaim(env.DB, claim.grant_id);
}

async function persistGrantClaimReceipt(
  env: VendorEnv,
  claim: GrantClaimRow,
  receipt: Record<string, unknown>,
  nowIso: string,
): Promise<boolean> {
  if (
    receipt.org_id !== claim.org_id ||
    receipt.installation_id !== claim.installation_id ||
    receipt.grant_id !== claim.grant_id ||
    receipt.envelope_sha256 !== claim.envelope_sha256
  ) {
    await alertGrantClaimDispute(env, claim.org_id, claim.grant_id, nowIso);
    return false;
  }
  const ceilingClaim = await readComplimentaryCeilingClaim(env.DB, claim.grant_id);
  if (claim.source_kind === "complimentary") {
    if (
      ceilingClaim === null || ceilingClaim.org_id !== claim.org_id ||
      ceilingClaim.envelope_sha256 !== claim.envelope_sha256 ||
      receipt.result !== "applied" || typeof receipt.applied_at !== "string" ||
      !(await verifyPlatformReceipt(env, receipt))
    ) {
      await alertGrantClaimDispute(env, claim.org_id, claim.grant_id, nowIso);
      return false;
    }
  }
  const statements = [env.DB.prepare(
    `UPDATE grant_claim SET state = 'completed', receipt = ?, completed_at = ?,
            command_state = CASE WHEN accepted_command IS NULL THEN command_state ELSE 'completed' END,
            lease_token = NULL, lease_until = NULL
     WHERE grant_id = ? AND state = 'pending' AND installation_id = ? AND route_generation = ?`,
  )
    .bind(canonicalJsonText(receipt), nowIso, claim.grant_id, claim.installation_id, claim.route_generation)];
  if (claim.source_kind === "complimentary" && ceilingClaim !== null) {
    statements.push(env.DB.prepare(
      `UPDATE complimentary_ceiling_claim
       SET status = 'applied', receipt = ?, applied_at = ?
       WHERE grant_id = ? AND org_id = ? AND envelope_sha256 = ? AND status = 'pending'`,
    ).bind(
      canonicalJsonText(receipt),
      receipt.applied_at as string,
      claim.grant_id,
      claim.org_id,
      claim.envelope_sha256,
    ));
  }
  await env.DB.batch(statements);
  const stored = await readGrantClaim(env.DB, claim.grant_id);
  const storedCeilingClaim = claim.source_kind === "complimentary"
    ? await readComplimentaryCeilingClaim(env.DB, claim.grant_id)
    : null;
  return stored?.state === "completed" && stored.receipt !== null &&
    canonicalJsonText(JSON.parse(stored.receipt)) === canonicalJsonText(receipt) &&
    (claim.source_kind !== "complimentary" || (
      storedCeilingClaim?.status === "applied" &&
      storedCeilingClaim.applied_at === receipt.applied_at &&
      storedCeilingClaim.receipt !== null &&
      canonicalJsonText(JSON.parse(storedCeilingClaim.receipt)) === canonicalJsonText(receipt)
    ));
}

async function verifyPlatformReceipt(
  env: VendorEnv,
  receipt: Record<string, unknown>,
): Promise<boolean> {
  try {
    const signing = typeof env.PLATFORM_SIGNING_KEY === "string"
      ? JSON.parse(env.PLATFORM_SIGNING_KEY) as { public_key?: unknown }
      : null;
    if (typeof signing?.public_key !== "string") return false;
    const bytes = base64UrlDecode(signing.public_key);
    if (bytes === null) return false;
    const publicKey = await crypto.subtle.importKey(
      "raw",
      bytes,
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    return verifyReceiptSignature({ receipt, publicKey });
  } catch {
    return false;
  }
}

async function sealPendingCeilingClaimNoEffect(
  env: VendorEnv,
  grantClaim: GrantClaimRow,
  ceilingClaim: ComplimentaryCeilingClaimRow,
  version: number,
  nowIso: string,
): Promise<"sealed" | "applied" | false> {
  if (ceilingClaim.status === "applied") return "applied";
  if (ceilingClaim.status === "sealed_no_effect") return "sealed";
  const response = await callCoverageDo(env, grantClaim.installation_id, {
    kind: "seal_ceiling_claim",
    installationId: grantClaim.installation_id,
    orgId: grantClaim.org_id,
    bindingEpoch: grantClaim.binding_epoch,
    routeGeneration: grantClaim.route_generation,
    vendorContractVersion: version,
    grantId: grantClaim.grant_id,
    envelopeSha256: grantClaim.envelope_sha256,
    nowIso,
    platformSigningKeyJson: env.PLATFORM_SIGNING_KEY,
  });
  if (response === null || !isRecord(response.receipt)) return false;
  const receipt = response.receipt;
  if (response.result === "already_applied") {
    if (receipt.result !== "applied") return false;
    return await persistGrantClaimReceipt(env, grantClaim, receipt, nowIso)
      ? "applied"
      : false;
  }
  if (
    (response.result !== "sealed" && response.result !== "sealed_no_effect") ||
    receipt.result !== "sealed_no_effect" ||
    receipt.org_id !== grantClaim.org_id ||
    receipt.installation_id !== grantClaim.installation_id ||
    receipt.grant_id !== grantClaim.grant_id ||
    receipt.envelope_sha256 !== grantClaim.envelope_sha256 ||
    receipt.route_generation !== grantClaim.route_generation ||
    !(await verifyPlatformReceipt(env, receipt))
  ) return false;
  await env.DB.prepare(
    `UPDATE complimentary_ceiling_claim
     SET status = 'sealed_no_effect', receipt = ?
     WHERE grant_id = ? AND org_id = ? AND envelope_sha256 = ? AND status = 'pending'`,
  ).bind(
    canonicalJsonText(receipt),
    ceilingClaim.grant_id,
    ceilingClaim.org_id,
    ceilingClaim.envelope_sha256,
  ).run();
  const stored = await readComplimentaryCeilingClaim(env.DB, ceilingClaim.grant_id);
  return stored?.status === "sealed_no_effect" && stored.receipt !== null &&
    canonicalJsonText(JSON.parse(stored.receipt)) === canonicalJsonText(receipt)
    ? "sealed"
    : false;
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
        environment: env.ENVIRONMENT,
      }),
    });
    if (!response.ok) {
      return null;
    }
    return decodeDoResponse<Record<string, unknown>>(
      await response.json(),
      CHANNEL_VERSIONS.platformDo,
    ) ?? null;
  } catch {
    return null;
  }
}

type GrantDoCallResult =
  | { kind: "response"; response: Record<string, unknown> }
  | { kind: "unavailable" }
  | { kind: "version_refusal" };

async function callGrantCoverageDo(
  env: VendorEnv,
  installationId: string,
  body: Record<string, unknown>,
): Promise<GrantDoCallResult> {
  const stub = env.DO.get(env.DO.idFromName(installationId));
  let response: Response;
  try {
    response = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        installationId,
        ...body,
        environment: env.ENVIRONMENT,
      }),
    });
  } catch {
    return { kind: "unavailable" };
  }
  if (!response.ok) return { kind: "unavailable" };
  let raw: unknown;
  try {
    raw = await response.json();
  } catch {
    return { kind: "unavailable" };
  }
  if (
    isRecord(raw) &&
    raw.result === "rejected" &&
    raw.code === "contract_version_unsupported"
  ) {
    return { kind: "version_refusal" };
  }
  const decoded = decodeDoResponse<Record<string, unknown>>(
    raw,
    CHANNEL_VERSIONS.platformDo,
  );
  return decoded === undefined
    ? { kind: "unavailable" }
    : { kind: "response", response: decoded };
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

/** Provision the route only after the complimentary command is durably accepted. */
async function ensureAcceptedGrantBinding(
  env: VendorEnv,
  claim: GrantClaimRow,
): Promise<GrantClaimRow | null> {
  const rebindAcceptedClaim = async (
    installationId: string,
    bindingEpoch: number,
  ): Promise<GrantClaimRow | null> => {
    const updatedAt = await clockNowIso(env);
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE grant_claim
         SET installation_id = ?, binding_epoch = ?, route_generation = route_generation + 1
         WHERE grant_id = ? AND org_id = ? AND state = 'pending'
           AND command_state = 'accepted' AND installation_id = ?
           AND binding_epoch = ? AND route_generation = ?
           AND EXISTS (
             SELECT 1 FROM live_value_route
             WHERE grant_id = ? AND org_id = ? AND state = 'stable'
               AND installation_id = ? AND binding_epoch = ? AND generation = ?
           )`,
      ).bind(
        installationId, bindingEpoch, claim.grant_id, claim.org_id,
        claim.installation_id, claim.binding_epoch, claim.route_generation,
        claim.grant_id, claim.org_id, claim.installation_id,
        claim.binding_epoch, claim.route_generation,
      ),
      env.DB.prepare(
        `UPDATE live_value_route
         SET installation_id = ?, binding_epoch = ?, generation = generation + 1, updated_at = ?
         WHERE grant_id = ? AND org_id = ? AND state = 'stable'
           AND installation_id = ? AND binding_epoch = ? AND generation = ?
           AND EXISTS (
             SELECT 1 FROM grant_claim
             WHERE grant_id = ? AND org_id = ? AND state = 'pending'
               AND command_state = 'accepted' AND installation_id = ?
               AND binding_epoch = ? AND route_generation = ?
           )`,
      ).bind(
        installationId, bindingEpoch, updatedAt, claim.grant_id, claim.org_id,
        claim.installation_id, claim.binding_epoch, claim.route_generation,
        claim.grant_id, claim.org_id, installationId, bindingEpoch,
        claim.route_generation + 1,
      ),
    ]);
    const [updated, route] = await Promise.all([
      readGrantClaim(env.DB, claim.grant_id),
      readLiveValueRoute(env.DB, claim.grant_id),
    ]);
    if (
      updated === null || !("grant_id" in updated) || route === null ||
      updated.org_id !== claim.org_id || route.org_id !== claim.org_id ||
      updated.installation_id !== installationId || updated.binding_epoch !== bindingEpoch ||
      updated.route_generation !== claim.route_generation + 1 ||
      route.installation_id !== installationId || route.binding_epoch !== bindingEpoch ||
      route.generation !== updated.route_generation || route.state !== "stable"
    ) {
      return null;
    }
    return updated;
  };

  const existingRoute = await readTenantBindingForInstallation(
    env.DB,
    claim.org_id,
    claim.installation_id,
  );
  if (existingRoute !== null) return claim;

  const active = await readLiveTenantBinding(env.DB, claim.org_id);
  if (active !== null) {
    return rebindAcceptedClaim(active.installation_id, active.epoch);
  }

  const createdAt = await clockNowIso(env);
  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO installation (
           installation_id, org_id, status, display_name, region, enrolled_at
         ) VALUES (?, ?, 'active', '', '', ?)`,
      ).bind(claim.installation_id, claim.org_id, createdAt),
      env.DB.prepare(
        `INSERT INTO tenant_binding (
           org_id, installation_id, epoch, status, retired_at, reason, created_at
         ) VALUES (?, ?, ?, 'active', NULL, NULL, ?)`,
      ).bind(claim.org_id, claim.installation_id, claim.binding_epoch, createdAt),
    ]);
  } catch {
    const winner = await readLiveTenantBinding(env.DB, claim.org_id);
    if (winner === null) return null;
    if (winner.installation_id !== claim.installation_id) {
      return rebindAcceptedClaim(winner.installation_id, winner.epoch);
    }
  }
  const updated = await readGrantClaim(env.DB, claim.grant_id);
  return updated !== null && "grant_id" in updated ? updated : null;
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
  if (typeof env.ACCESS_CERTS_JSON === "string") {
    try {
      const body = JSON.parse(env.ACCESS_CERTS_JSON) as {
        keys?: AccessCertsDocument["keys"];
      };
      return Array.isArray(body.keys) ? { issuer, keys: body.keys } : null;
    } catch {
      return null;
    }
  }
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

async function buildAssertionUsedStatement(
  env: VendorEnv,
  challengeSha256: string,
  credentialId: string,
): Promise<D1PreparedStatement> {
  const usedAt = await clockNowIso(env);
  return env.DB.prepare(
    `INSERT INTO assertion_used (challenge_sha256, credential_id, used_at)
     VALUES (?, ?, ?)`,
  ).bind(challengeSha256, credentialId, usedAt);
}

async function insertAssertionUsed(
  env: VendorEnv,
  challengeSha256: string,
  credentialId: string,
): Promise<void> {
  await (
    await buildAssertionUsedStatement(env, challengeSha256, credentialId)
  ).run();
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

/** R2-C1: byte equality of the RFC 8785 canonical forms of both maps. */
function canonicalParamsEqual(
  params: unknown,
  expected: Record<string, unknown>,
): boolean {
  try {
    return bytesEqual(canonicalize(params), canonicalize(expected));
  } catch {
    // Canonicalization errors (undefined members, invalid numbers) are a
    // failed match, never a throw.
    return false;
  }
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
  } else if (method === "recoverStrandedTerm") {
    expected.action_id = rpcArgs.action_id;
    expected.org_id = rpcArgs.org_id;
    expected.installation_id = rpcArgs.installation_id;
    expected.binding_epoch = rpcArgs.binding_epoch;
    expected.target_term_id = rpcArgs.target_term_id;
    expected.source_grant_id = rpcArgs.source_grant_id;
    expected.expected_clinic_seq = rpcArgs.expected_clinic_seq;
    expected.reason = rpcArgs.reason;
    expected.evidence_sha256 = rpcArgs.evidence_sha256;
    expected.signer_credential_id = rpcArgs.signer_credential_id;
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
  return canonicalParamsEqual(params, expected);
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
  if (method === "recoverStrandedTerm") {
    return typeof rpcArgs.target_term_id === "string" ? rpcArgs.target_term_id : "";
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

type CeilingPolicyCommandRow = {
  challenge_sha256: string;
  policy_version: number;
  actor: string;
  operation_json: string;
  contract_version: number;
  result_json: string;
};

type ComplimentaryCeilingClaimRow = {
  grant_id: string;
  org_id: string;
  envelope_sha256: string;
  plan_id: string;
  plan_version: number;
  allowance_denominator: number;
  day_contribution: number;
  allowance_contribution: number;
  apply_per_grant_caps: number;
  override_authorized: number;
  status: "pending" | "applied" | "sealed_no_effect";
  receipt: string | null;
  applied_at: string | null;
  created_at: string;
};

type CeilingContribution = {
  planId: string;
  planVersion: number;
  allowanceDenominator: number;
  dayContribution: number;
  allowanceContribution: number;
  applyPerGrantCaps: boolean;
};

function complimentaryCeilingContribution(
  envelope: Record<string, unknown>,
  plan: PlanVersionRow,
): CeilingContribution | null {
  if (!Number.isInteger(plan.max_allowance_per_month) || plan.max_allowance_per_month <= 0) {
    return null;
  }
  const planInput = envelope.plan;
  if (!isRecord(planInput) || typeof planInput.plan_id !== "string" || !Number.isInteger(planInput.plan_version)) {
    return null;
  }
  if (envelope.kind === "term_adjustment") {
    const adjustment = envelope.adjustment;
    if (!isRecord(adjustment)) return null;
    const extendDays = adjustment.extend_days;
    const addAllowance = adjustment.add_allowance;
    return {
      planId: planInput.plan_id,
      planVersion: planInput.plan_version as number,
      allowanceDenominator: plan.max_allowance_per_month,
      dayContribution: Number.isInteger(extendDays) && (extendDays as number) > 0 ? extendDays as number : 0,
      allowanceContribution: Number.isInteger(addAllowance) && (addAllowance as number) > 0 ? addAllowance as number : 0,
      applyPerGrantCaps: false,
    };
  }
  const duration = envelope.duration;
  if (!isRecord(duration) || !Number.isInteger(duration.count) || (duration.count as number) < 1) {
    return null;
  }
  const dayContribution = duration.unit === "month"
    ? (duration.count as number) * 31
    : duration.unit === "day" ? duration.count as number : null;
  if (dayContribution === null || !Number.isInteger(envelope.allowance_credits)) return null;
  return {
    planId: planInput.plan_id,
    planVersion: planInput.plan_version as number,
    allowanceDenominator: plan.max_allowance_per_month,
    dayContribution,
    allowanceContribution: envelope.allowance_credits as number,
    applyPerGrantCaps: true,
  };
}

async function readComplimentaryCeilingClaim(
  db: D1Database,
  grantId: string,
): Promise<ComplimentaryCeilingClaimRow | null> {
  return db.prepare(
    `SELECT grant_id, org_id, envelope_sha256, plan_id, plan_version,
            allowance_denominator, day_contribution, allowance_contribution,
            apply_per_grant_caps, override_authorized, status, receipt,
            applied_at, created_at
     FROM complimentary_ceiling_claim WHERE grant_id = ?`,
  ).bind(grantId).first<ComplimentaryCeilingClaimRow>();
}

function buildComplimentaryCeilingClaimInsertStatement(
  db: D1Database,
  input: {
    grantId: string;
    orgId: string;
    envelopeSha256: string;
    contribution: CeilingContribution;
    overrideAuthorized: boolean;
    nowIso: string;
  },
): D1PreparedStatement {
  return db.prepare(
    `INSERT INTO complimentary_ceiling_claim (
       grant_id, org_id, envelope_sha256, plan_id, plan_version,
       allowance_denominator, day_contribution, allowance_contribution,
       apply_per_grant_caps, override_authorized, status, receipt, applied_at, created_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL, NULL, ?)`,
  ).bind(
    input.grantId,
    input.orgId,
    input.envelopeSha256,
    input.contribution.planId,
    input.contribution.planVersion,
    input.contribution.allowanceDenominator,
    input.contribution.dayContribution,
    input.contribution.allowanceContribution,
    input.contribution.applyPerGrantCaps ? 1 : 0,
    input.overrideAuthorized ? 1 : 0,
    input.nowIso,
  );
}

async function complimentaryCeilingClaimFitsCurrentPolicy(
  db: D1Database,
  claim: ComplimentaryCeilingClaimRow,
  nowIso: string,
): Promise<boolean> {
  if (claim.status !== "pending") return claim.status === "applied";
  if (claim.override_authorized === 1) return true;
  const policy = await readCurrentCeilingPolicy(db);
  if (policy === null) return false;
  const sums = await db.prepare(
    `SELECT COALESCE(SUM(day_contribution), 0) AS days,
            COALESCE(SUM(CAST(allowance_contribution AS REAL) / allowance_denominator), 0) AS allowance_months
     FROM complimentary_ceiling_claim
     WHERE org_id = ?
       AND (status = 'pending' OR (
         status = 'applied'
         AND julianday(applied_at) > julianday(?) - ?
         AND julianday(applied_at) <= julianday(?)
       ))`,
  ).bind(claim.org_id, nowIso, policy.window_days, nowIso)
    .first<{ days: number; allowance_months: number }>();
  if (sums === null || sums.days > policy.window_max_days ||
      sums.allowance_months > policy.window_max_allowance_months) return false;
  return claim.apply_per_grant_caps === 0 || (
    claim.day_contribution <= policy.per_grant_max_days &&
    claim.allowance_contribution / claim.allowance_denominator <=
      policy.per_grant_max_allowance_months
  );
}

async function ensureComplimentaryCeilingClaimsBackfilled(
  env: VendorEnv,
  orgId: string,
  version: number,
): Promise<boolean> {
  const done = await env.DB.prepare(
    "SELECT org_id FROM complimentary_ceiling_claim_backfill WHERE org_id = ?",
  ).bind(orgId).first<{ org_id: string }>();
  if (done !== null) return true;
  const bindings = await env.DB.prepare(
    `SELECT installation_id FROM tenant_binding WHERE org_id = ? ORDER BY epoch ASC`,
  ).bind(orgId).all<{ installation_id: string }>();
  const nowIso = await clockNowIso(env);
  const seen = new Set<string>();
  for (const binding of bindings.results ?? []) {
    const inspected = await callCoverageDo(env, binding.installation_id, {
      kind: "inspect_coverage",
      installationId: binding.installation_id,
      orgId,
      vendorContractVersion: version,
    });
    if (inspected === null || !Array.isArray(inspected.grants)) return false;
    for (const raw of inspected.grants) {
      if (!isRecord(raw) || raw.source_kind !== "complimentary") continue;
      if (typeof raw.grant_id !== "string" || typeof raw.envelope_sha256 !== "string") {
        await alertGrantClaimDispute(env, orgId, "unknown", nowIso);
        return false;
      }
      const grantId = raw.grant_id;
      const envelope = isRecord(raw.envelope)
        ? raw.envelope
        : typeof raw.envelope === "string" ? (() => {
          try { const parsed: unknown = JSON.parse(raw.envelope); return isRecord(parsed) ? parsed : null; }
          catch { return null; }
        })() : null;
      const receipt = await parseGrantReceipt(raw.receipt);
      const claim = await readGrantClaim(env.DB, grantId);
      if (
        envelope === null || receipt === null || claim === null || !("grant_id" in claim) ||
        claim.org_id !== orgId || claim.envelope_sha256 !== raw.envelope_sha256 ||
        claim.installation_id !== binding.installation_id ||
        claim.envelope !== canonicalJsonText(envelope) ||
        receipt.org_id !== orgId || receipt.installation_id !== binding.installation_id ||
        receipt.grant_id !== grantId || receipt.envelope_sha256 !== raw.envelope_sha256 ||
        receipt.result !== "applied" || typeof receipt.applied_at !== "string" ||
        await grantEnvelopeHash(envelope) !== raw.envelope_sha256 ||
        (typeof raw.applied_at === "string" && raw.applied_at !== receipt.applied_at) ||
        !(await verifyPlatformReceipt(env, receipt))
      ) {
        await alertGrantClaimDispute(env, orgId, grantId, nowIso);
        return false;
      }
      const planInput = envelope.plan;
      if (!isRecord(planInput) || typeof planInput.plan_id !== "string" || !Number.isInteger(planInput.plan_version)) {
        await alertGrantClaimDispute(env, orgId, grantId, nowIso);
        return false;
      }
      const plan = await readPlanVersion(env.DB, planInput.plan_id, planInput.plan_version as number);
      const contribution = plan === null ? null : complimentaryCeilingContribution(envelope, plan);
      if (contribution === null) {
        await alertGrantClaimDispute(env, orgId, grantId, nowIso);
        return false;
      }
      const ledger = await env.DB.prepare(
        `SELECT installation_id, envelope_sha256, receipt FROM grant_ledger WHERE grant_id = ?`,
      ).bind(grantId).first<{ installation_id: string; envelope_sha256: string; receipt: string }>();
      if (ledger !== null) {
        const ledgerReceipt = await parseGrantReceipt(ledger.receipt);
        if (
          ledger.installation_id !== binding.installation_id ||
          ledger.envelope_sha256 !== raw.envelope_sha256 || ledgerReceipt === null ||
          canonicalJsonText(ledgerReceipt) !== canonicalJsonText(receipt)
        ) {
          await alertGrantClaimDispute(env, orgId, grantId, nowIso);
          return false;
        }
      }
      const r2Row = await readGrantLedgerR2(env, grantId);
      if (r2Row !== null) {
        const r2Receipt = await parseGrantReceipt(r2Row.receipt);
        if (
          r2Row.org_id !== orgId || r2Row.installation_id !== binding.installation_id ||
          r2Row.envelope_sha256 !== raw.envelope_sha256 || r2Receipt === null ||
          canonicalJsonText(r2Receipt) !== canonicalJsonText(receipt)
        ) {
          await alertGrantClaimDispute(env, orgId, grantId, nowIso);
          return false;
        }
      }
      const prior = await readComplimentaryCeilingClaim(env.DB, grantId);
      if (prior === null) {
        await env.DB.prepare(
          `INSERT INTO complimentary_ceiling_claim (
             grant_id, org_id, envelope_sha256, plan_id, plan_version,
             allowance_denominator, day_contribution, allowance_contribution,
             apply_per_grant_caps, source_reconciled, override_authorized,
             status, receipt, applied_at, created_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0, 'applied', ?, ?, ?)`,
        ).bind(
          grantId, orgId, raw.envelope_sha256, contribution.planId,
          contribution.planVersion, contribution.allowanceDenominator,
          contribution.dayContribution, contribution.allowanceContribution,
          contribution.applyPerGrantCaps ? 1 : 0, canonicalJsonText(receipt),
          receipt.applied_at, typeof raw.applied_at === "string" ? raw.applied_at : receipt.applied_at,
        ).run();
      } else if (
        prior.org_id !== orgId || prior.envelope_sha256 !== raw.envelope_sha256 ||
        prior.plan_id !== contribution.planId || prior.plan_version !== contribution.planVersion ||
        prior.allowance_denominator !== contribution.allowanceDenominator ||
        prior.day_contribution !== contribution.dayContribution ||
        prior.allowance_contribution !== contribution.allowanceContribution
      ) {
        await alertGrantClaimDispute(env, orgId, grantId, nowIso);
        return false;
      } else if (prior.status === "pending") {
        await env.DB.prepare(
          `UPDATE complimentary_ceiling_claim SET status = 'applied', receipt = ?, applied_at = ?
           WHERE grant_id = ? AND status = 'pending'`,
        ).bind(canonicalJsonText(receipt), receipt.applied_at, grantId).run();
      } else if (
        prior.status !== "applied" || prior.applied_at !== receipt.applied_at ||
        prior.receipt === null || canonicalJsonText(JSON.parse(prior.receipt)) !== canonicalJsonText(receipt)
      ) {
        await alertGrantClaimDispute(env, orgId, grantId, nowIso);
        return false;
      }
      seen.add(grantId);
    }
  }

  const pending = await env.DB.prepare(
    `SELECT grant_id, envelope, envelope_sha256, accepted_at, created_at,
            override_assertion_sha256
     FROM grant_claim
     WHERE org_id = ? AND source_kind = 'complimentary' AND state = 'pending'
       AND command_state = 'accepted'`,
  ).bind(orgId).all<{
    grant_id: string;
    envelope: string;
    envelope_sha256: string;
    accepted_at: string | null;
    created_at: string;
    override_assertion_sha256: string | null;
  }>();
  for (const row of pending.results ?? []) {
    if (await readComplimentaryCeilingClaim(env.DB, row.grant_id) !== null) continue;
    let envelope: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(row.envelope);
      if (!isRecord(parsed)) throw new Error("invalid_envelope");
      envelope = parsed;
    } catch {
      await alertGrantClaimDispute(env, orgId, row.grant_id, nowIso);
      return false;
    }
    const planInput = envelope.plan;
    if (!isRecord(planInput) || typeof planInput.plan_id !== "string" || !Number.isInteger(planInput.plan_version)) {
      await alertGrantClaimDispute(env, orgId, row.grant_id, nowIso);
      return false;
    }
    const plan = await readPlanVersion(env.DB, planInput.plan_id, planInput.plan_version as number);
    const contribution = plan === null ? null : complimentaryCeilingContribution(envelope, plan);
    if (contribution === null || await grantEnvelopeHash(envelope) !== row.envelope_sha256) {
      await alertGrantClaimDispute(env, orgId, row.grant_id, nowIso);
      return false;
    }
    await env.DB.prepare(
      `INSERT INTO complimentary_ceiling_claim (
         grant_id, org_id, envelope_sha256, plan_id, plan_version,
         allowance_denominator, day_contribution, allowance_contribution,
         apply_per_grant_caps, source_reconciled, override_authorized,
         status, receipt, applied_at, created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, 'pending', NULL, NULL, ?)`,
    ).bind(
      row.grant_id, orgId, row.envelope_sha256, contribution.planId,
      contribution.planVersion, contribution.allowanceDenominator,
      contribution.dayContribution, contribution.allowanceContribution,
      contribution.applyPerGrantCaps ? 1 : 0,
      row.override_assertion_sha256 === null ? 0 : 1,
      row.accepted_at ?? row.created_at,
    ).run();
  }
  const unclaimedLedger = await env.DB.prepare(
    `SELECT grant_id FROM grant_ledger WHERE org_id = ? AND source_kind = 'complimentary'`,
  ).bind(orgId).all<{ grant_id: string }>();
  for (const row of unclaimedLedger.results ?? []) {
    if (!seen.has(row.grant_id)) {
      await alertGrantClaimDispute(env, orgId, row.grant_id, nowIso);
      return false;
    }
  }
  await env.DB.prepare(
    `INSERT OR IGNORE INTO complimentary_ceiling_claim_backfill (org_id, completed_at) VALUES (?, ?)`,
  ).bind(orgId, nowIso).run();
  return true;
}

async function readCeilingPolicyCommand(
  db: D1Database,
  challengeSha256: string,
): Promise<CeilingPolicyCommandRow | null> {
  return db.prepare(
    `SELECT challenge_sha256, policy_version, actor, operation_json,
            contract_version, result_json
     FROM ceiling_policy_command WHERE challenge_sha256 = ?`,
  ).bind(challengeSha256).first<CeilingPolicyCommandRow>();
}

function ceilingPolicyCommandResult(
  command: CeilingPolicyCommandRow,
  operation: Record<string, unknown>,
  actor: string,
  version: number,
): VendorResultEnvelope {
  if (
    command.operation_json !== canonicalJsonText(operation) ||
    command.actor !== actor || command.contract_version !== version
  ) {
    return { contract_version: version, result: "conflict", code: "", detail: "" };
  }
  try {
    const row = JSON.parse(command.result_json) as Record<string, unknown>;
    return ok(version, JSON.stringify(row));
  } catch {
    return rejected(version, "storage_error");
  }
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

  let overrideClientData: { challenge?: string };
  try {
    overrideClientData = JSON.parse(
      new TextDecoder().decode(assertion.clientDataJSON),
    ) as { challenge?: string };
  } catch {
    // R2-P2: invalid clientDataJSON is assertion_invalid, never a throw.
    return { ok: false, code: "assertion_invalid" };
  }
  const overrideChallenge =
    typeof overrideClientData.challenge === "string"
      ? overrideClientData.challenge
      : "";
  const grantChallenge = await operationChallenge(grantOperation);
  if (overrideChallenge.length > 0 && overrideChallenge === grantChallenge) {
    return { ok: false, code: "assertion_used" };
  }

  const envelopeForOverride = envelopeWithoutCeilingOverride(envelope);
  // R2-P2: an absent explicit operation derives only the exact existing
  // grant-metadata form; the timestamp-search fallback is removed.
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
  // R2-P2: the exception is bound to this call's negotiated version, its
  // Access actor, and the current envelope (minus ceiling_override); only
  // the separate ceremony's nonce and issued_at may differ.
  if (operation.contract_version !== version) {
    return { ok: false, code: "assertion_invalid" };
  }
  if (
    !canonicalParamsEqual(operation.params, {
      contract_version: version,
      access_jwt: accessJwt,
      envelope: envelopeForOverride,
    })
  ) {
    return { ok: false, code: "assertion_invalid" };
  }
  if (typeof operation.actor_email !== "string" || operation.actor_email !== accessEmail) {
    return { ok: false, code: "actor_email_mismatch" };
  }
  if (
    typeof operation.issued_at !== "string" ||
    !(await assertionIssuedAtFresh(env, operation.issued_at))
  ) {
    return { ok: false, code: "assertion_expired" };
  }
  if (signer.status !== "active") {
    return { ok: false, code: "credential_not_active" };
  }

  const grantDigest = await operationAssertionSha256(grantOperation);
  const assertionSha256 = await operationAssertionSha256(operation);
  // R2-P2: replay is verified against the actually verified digest, which
  // must differ from the first (grant) digest.
  if (assertionSha256 === grantDigest) {
    return { ok: false, code: "assertion_used" };
  }
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
    return { ok: false, code: "assertion_invalid" };
  }

  return { ok: true, assertionSha256 };
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

async function readReversalCommand(
  db: D1Database,
  reversalId: string,
): Promise<ReversalCommandRow | null> {
  return db.prepare(
    `SELECT reversal_id, grant_id, request_sha256, request_body,
            route_installation_id, route_epoch, route_generation, state,
            receipt, export_payload, export_state, created_at, updated_at
     FROM reversal_command WHERE reversal_id = ?`,
  ).bind(reversalId).first<ReversalCommandRow>();
}

async function shipReversalExport(
  env: VendorEnv,
  command: ReversalCommandRow,
): Promise<boolean> {
  if (command.state !== "terminal" || command.export_payload === null) return false;
  if (command.export_state === "shipped") return true;
  try {
    await env.R2.put(
      `grant-ledger/${command.grant_id}.void.ndjson`,
      command.export_payload,
    );
  } catch {
    return false;
  }
  await env.DB.prepare(
    `UPDATE reversal_command SET export_state = 'shipped', updated_at = ?
     WHERE reversal_id = ? AND state = 'terminal' AND export_payload = ?`,
  ).bind(await clockNowIso(env), command.reversal_id, command.export_payload).run();
  return true;
}

async function recoverExactLegacyReversal(
  env: VendorEnv,
  input: {
    grantId: string;
    reversalId: string;
    reason: string;
    evidenceSha256: string;
    requestSha256: string;
    requestBody: string;
    nowIso: string;
  },
): Promise<"recovered" | "unavailable" | "mismatch"> {
  let object: R2ObjectBody | null;
  try {
    object = await env.R2.get(`grant-ledger/${input.grantId}.void.ndjson`);
  } catch {
    return "unavailable";
  }
  if (object === null) return "unavailable";
  const exportPayload = await object.text();
  const line = exportPayload.trimEnd().split("\n")[0];
  if (line === undefined || line.length === 0) return "mismatch";
  let row: Record<string, unknown>;
  try { row = JSON.parse(line) as Record<string, unknown>; } catch { return "mismatch"; }
  if (
    row.grant_id !== input.grantId || row.reason !== input.reason ||
    row.evidence_sha256 !== input.evidenceSha256 || !isRecord(row.receipt) ||
    row.receipt.reversal_id !== input.reversalId ||
    !(await verifyPlatformReceipt(env, row.receipt))
  ) return "mismatch";
  const now = await clockNowIso(env);
  await env.DB.prepare(
    `INSERT OR IGNORE INTO reversal_command (
       reversal_id, grant_id, request_sha256, request_body,
       state, receipt, export_payload, export_state, created_at, updated_at
     ) VALUES (?, ?, ?, ?, 'terminal', ?, ?, 'shipped', ?, ?)`,
  ).bind(
    input.reversalId, input.grantId, input.requestSha256, input.requestBody,
    canonicalJsonText(row.receipt), exportPayload, now, now,
  ).run();
  const stored = await readReversalCommand(env.DB, input.reversalId);
  return stored !== null && stored.grant_id === input.grantId &&
      stored.request_sha256 === input.requestSha256 && stored.state === "terminal"
    ? "recovered"
    : "mismatch";
}

function reversalConflict(version: number): GrantResultEnvelope {
  return { contract_version: version, result: "conflict", code: "", detail: "" };
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

  // R2-P3: the conditional INSERT makes the emptiness test and the insertion
  // one atomic D1 statement, so concurrent bootstrap attempts admit exactly
  // one row (any existing row, including pending or revoked, closes
  // bootstrap). The early count above stays only as a fast refusal.
  const insertResult = await env.DB.prepare(
    `INSERT INTO operator_credential
       (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
     SELECT ?, ?, ?, ?, 'pending', ?, NULL, NULL
     WHERE NOT EXISTS (SELECT 1 FROM operator_credential)`,
  )
    .bind(credentialId, accessEmail, publicKeyCose, parsed.alg, activatesAt)
    .run();

  const insertedRows = insertResult.meta.changes ?? 0;
  if (insertedRows === 0) {
    // Lost the bootstrap race: another credential already exists, so a new
    // credential requires HP approval. No bootstrap success alert.
    await writeEntrypointAudit(
      env.DB,
      accessEmail,
      "registerOperatorCredential",
      credentialId,
      null,
    );
    return rejected(negotiatedVersion, "assertion_required");
  }

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
  async drainDurableObjectsForHarness(
    args: Record<string, unknown>,
  ): Promise<{ result: "drained"; count: number }> {
    if (this.env.ENVIRONMENT !== "development" || this.env.TEST_CLOCK !== "1") {
      throw new Error("harness_drain_unavailable");
    }
    const installationIds = args.installation_ids;
    if (
      !Array.isArray(installationIds) ||
      installationIds.some((installationId) =>
        typeof installationId !== "string" || installationId.length === 0
      )
    ) {
      throw new Error("harness_drain_invalid_installations");
    }

    for (const installationId of [...new Set(installationIds as string[])].sort()) {
      const stub = this.env.DO.get(this.env.DO.idFromName(installationId)) as unknown as {
        drainForHarness(): Promise<{ result: "drained" }>;
      };
      const result = await stub.drainForHarness();
      if (result.result !== "drained") {
        throw new Error(`harness_drain_not_confirmed:${installationId}`);
      }
    }
    return { result: "drained", count: new Set(installationIds as string[]).size };
  }

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

    // R1-C3: malformed or reversed validity windows are rejected before the
    // assertion is consumed or any row is written.
    if (!validKeyWindowBounds(notBefore, notAfter)) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
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

    // R8-KEY1: the transition is guarded on the row still being `active`, and
    // the shared audit-statement helper keeps its audit in the same D1 batch.
    // A losing active→retiring race has no transition audit; an already-
    // retiring idempotent request still records the accepted operator action.
    await this.env.DB.batch([
      await buildAssertionUsedStatement(
        this.env,
        check.assertionSha256,
        check.signer.credential_id,
      ),
      this.env.DB.prepare(
        `UPDATE issuer_key SET status = 'retiring' WHERE kid = ? AND status = 'active'`,
      ).bind(kid),
      buildEntrypointAuditStatement(
        this.env.DB,
        access.email,
        "retireIssuerKey",
        check.auditTarget,
        check.assertionSha256,
        existing.status,
        existing.status === "active" ? "retiring" : existing.status,
        existing.status === "active",
      ),
    ]);

    const row = await readIssuerKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "kid_not_found");
    }
    if (row.status === "revoked") {
      return rejected(version, "kid_revoked");
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

    // R1-C3: malformed or reversed validity windows are rejected before the
    // assertion is consumed or any row is written.
    if (!validKeyWindowBounds(notBefore, notAfter)) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerServiceKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
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
    const existingCommand = await readCeilingPolicyCommand(this.env.DB, assertionSha256);
    if (existingCommand !== null) {
      return ceilingPolicyCommandResult(
        existingCommand,
        operation,
        access.email,
        version,
      );
    }
    // Pre-RM18 policy rows did not retain accepted bytes or actor. They cannot
    // be treated as exact retries without evidence, so leave them read-only.
    if (await readCeilingPolicyByAssertionSha256(this.env.DB, assertionSha256) !== null) {
      return { contract_version: version, result: "conflict", code: "", detail: "" };
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

    const nowIso = await clockNowIso(this.env);
    const operationJson = canonicalJsonText(operation);
    try {
      await this.env.DB.batch([
        this.env.DB.prepare(
          `INSERT INTO ceiling_policy (
             version, per_grant_max_days, per_grant_max_allowance_months,
             window_days, window_max_days, window_max_allowance_months,
             max_paid_grace_days, paid_cap_rule, set_by, assertion_sha256
           ) SELECT COALESCE(MAX(version), 0) + 1, ?, ?, ?, ?, ?, ?, ?, ?, ?
             FROM ceiling_policy`,
        ).bind(
          perGrantMaxDays,
          perGrantMaxAllowanceMonths,
          windowDays,
          windowMaxDays,
          windowMaxAllowanceMonths,
          maxPaidGraceDays,
          paidCapRule,
          access.email,
          check.assertionSha256,
        ),
        this.env.DB.prepare(
          `INSERT INTO ceiling_policy_command (
             challenge_sha256, policy_version, actor, operation_json,
             contract_version, result_json, created_at
           ) SELECT ?, version, ?, ?, ?, json_object(
             'version', version,
             'per_grant_max_days', per_grant_max_days,
             'per_grant_max_allowance_months', per_grant_max_allowance_months,
             'window_days', window_days,
             'window_max_days', window_max_days,
             'window_max_allowance_months', window_max_allowance_months,
             'max_paid_grace_days', max_paid_grace_days,
             'paid_cap_rule', paid_cap_rule,
             'set_by', set_by,
             'assertion_sha256', assertion_sha256
           ), ?
           FROM ceiling_policy WHERE assertion_sha256 = ? ORDER BY version DESC LIMIT 1`,
        ).bind(
          assertionSha256,
          access.email,
          operationJson,
          version,
          nowIso,
          assertionSha256,
        ),
        await buildAssertionUsedStatement(
          this.env,
          check.assertionSha256,
          check.signer.credential_id,
        ),
        buildEntrypointAuditStatement(
          this.env.DB,
          access.email,
          "setCeilingPolicy",
          check.auditTarget,
          check.assertionSha256,
        ),
      ]);
    } catch {
      const raced = await readCeilingPolicyCommand(this.env.DB, assertionSha256);
      if (raced !== null) {
        return ceilingPolicyCommandResult(raced, operation, access.email, version);
      }
      return rejected(version, "assertion_used");
    }
    const command = await readCeilingPolicyCommand(this.env.DB, assertionSha256);
    return command === null
      ? rejected(version, "storage_error")
      : ceilingPolicyCommandResult(command, operation, access.email, version);
  }

  async grant(args: Record<string, unknown>): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return grantRejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    if (typeof args.grant_rpc_json === "string") {
      try {
        const grantRpc = JSON.parse(args.grant_rpc_json) as Record<
          string,
          unknown
        >;
        if (typeof grantRpc.envelope_b64 === "string") {
          args.envelope_b64 = grantRpc.envelope_b64;
        }
        if (typeof grantRpc.abo_kid === "string") {
          args.abo_kid = grantRpc.abo_kid;
        }
        if (typeof grantRpc.abo_signature === "string") {
          args.abo_signature = grantRpc.abo_signature;
        }
        if (grantRpc.envelope !== undefined) {
          args.envelope = grantRpc.envelope;
        }
      } catch {
        return grantRejected(version, "bad_signature");
      }
    }

    let envelope: unknown = args.envelope;
    if (typeof args.envelope_b64 === "string") {
      try {
        const bytes = Uint8Array.from(atob(args.envelope_b64), (char) =>
          char.charCodeAt(0),
        );
        envelope = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
      } catch {
        return grantRejected(version, "bad_signature");
      }
    } else if (envelope === undefined && typeof args.envelope_json === "string") {
      try {
        const envelopeJson = JSON.parse(args.envelope_json) as Record<
          string,
          unknown
        >;
        if (
          typeof envelopeJson.envelope_b64 === "string" &&
          typeof envelopeJson.abo_signature === "string"
        ) {
          args.envelope_b64 = envelopeJson.envelope_b64;
          if (typeof envelopeJson.abo_kid === "string") {
            args.abo_kid = envelopeJson.abo_kid;
          }
          args.abo_signature = envelopeJson.abo_signature;
        } else {
          envelope = envelopeJson;
        }
      } catch {
        return grantRejected(version, "bad_signature");
      }
    } else if (typeof envelope === "string") {
      const envelopeText = envelope;
      try {
        envelope = JSON.parse(envelopeText) as unknown;
      } catch {
        try {
          const bytes = Uint8Array.from(atob(envelopeText), (char) =>
            char.charCodeAt(0),
          );
          envelope = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
        } catch {
          return grantRejected(version, "bad_signature");
        }
      }
    }
    if (!isRecord(envelope)) {
      return grantRejected(version, "bad_signature");
    }

    if (
      typeof envelope.envelope_b64 === "string" &&
      typeof envelope.abo_signature === "string"
    ) {
      args.envelope_b64 = envelope.envelope_b64;
      if (typeof envelope.abo_kid === "string") {
        args.abo_kid = envelope.abo_kid;
      }
      args.abo_signature = envelope.abo_signature;
      try {
        const bytes = Uint8Array.from(atob(args.envelope_b64 as string), (char) =>
          char.charCodeAt(0),
        );
        envelope = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
      } catch {
        return grantRejected(version, "bad_signature");
      }
      if (!isRecord(envelope)) {
        return grantRejected(version, "bad_signature");
      }
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

      let access: { ok: true; email: string } | { ok: false };
      if (args.accepted_command_dispatch === true) {
        const requestedGrantId = args.accepted_command_grant_id;
        const acceptedClaim = typeof requestedGrantId === "string"
          ? await readGrantClaim(this.env.DB, requestedGrantId)
          : null;
        if (
          acceptedClaim === null ||
          acceptedClaim.command_state !== "accepted" ||
          acceptedClaim.state !== "pending" ||
          acceptedClaim.envelope !== canonicalJsonText(envelope)
        ) {
          return grantRejected(version, "unauthenticated");
        }
        access = { ok: true, email: acceptedClaim.accepted_actor ?? "" };
      } else {
        access = await verifyHpAccess(this.env, args.access_jwt);
      }
      if (!access.ok || access.email.length === 0) {
        return grantRejected(version, "unauthenticated");
      }

      const grantEnvelopeValidation = validateGrantEnvelope(envelope);
      if (!grantEnvelopeValidation.ok) {
        if (
          "code" in grantEnvelopeValidation &&
          grantEnvelopeValidation.code === "placement_not_supported"
        ) {
          return grantRejected(version, "placement_not_supported");
        }
        return grantRejected(version, "unit_not_allowed");
      }
      const claimOrgId = envelope.org_id;
      const claimGrantId = envelope.grant_id;
      if (typeof claimOrgId !== "string" || typeof claimGrantId !== "string") {
        return grantRejected(version, "bad_signature");
      }
      const claimEnvelopeSha256 = await grantEnvelopeHash(envelope);
      if (!(await ensureGrantClaimsBackfilled(this.env, claimOrgId, version))) {
        return grantRejected(version, "coverage_unknown");
      }
      let existingGrantClaim = await readGrantClaim(this.env.DB, claimGrantId);
      if (existingGrantClaim !== null) {
        const replay = claimReplayResult(
          version,
          existingGrantClaim,
          claimEnvelopeSha256,
          claimOrgId,
        );
        if (replay === "conflict") {
          return { contract_version: version, result: "conflict", code: "", detail: "" };
        }
        if (replay === "disputed") return grantRejected(version, "coverage_unknown");
        if (replay !== "pending") return replay;
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
      if (
        planRow === null ||
        (planRow.status !== "published" && existingGrantClaim?.command_state !== "completed")
      ) {
        if (existingGrantClaim?.command_state === "accepted") {
          await rejectAcceptedGrantCommand(this.env, existingGrantClaim, "plan_not_published", "");
        }
        return grantRejected(version, "plan_not_published");
      }
      const ceilingContribution = complimentaryCeilingContribution(envelope, planRow);
      if (ceilingContribution === null) {
        return grantRejected(version, "coverage_unknown");
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

      const orgId = claimOrgId;

      const ceilingPolicy = await readCurrentCeilingPolicy(this.env.DB);
      if (ceilingPolicy === null && existingGrantClaim === null) {
        return grantRejected(version, "coverage_unknown");
      }
      if (ceilingPolicy === null && existingGrantClaim?.command_state === "accepted") {
        await rejectAcceptedGrantCommand(this.env, existingGrantClaim, "coverage_unknown", "");
        return grantRejected(version, "coverage_unknown");
      }

      const accessJwt =
        typeof args.access_jwt === "string" ? args.access_jwt : "";

      let assertionCheck: Awaited<ReturnType<typeof runHpAssertionChecks>> | null = null;
      if (existingGrantClaim === null) {
        assertionCheck = await runHpAssertionChecks(
          this.env,
          "grant",
          args,
          access.email,
          version,
        );
        if (!assertionCheck.ok) {
          const rejectedEnvelope = await rejectHpAssertion(
            this.env,
            access.email,
            "grant",
            assertionCheck,
          );
          return {
            contract_version: rejectedEnvelope.contract_version,
            result: "rejected",
            code: rejectedEnvelope.code,
            detail: rejectedEnvelope.detail,
          };
        }
        const approvals =
          isRecord(envelope.evidence) && Array.isArray(envelope.evidence.approvals)
            ? envelope.evidence.approvals
            : [];
        const evidenceCredentialId = isRecord(approvals[0]) &&
            typeof approvals[0].credential_id === "string"
          ? approvals[0].credential_id
          : null;
        if (evidenceCredentialId !== assertionCheck.signer.credential_id) {
          await writeEntrypointAudit(
            this.env.DB,
            access.email,
            "grant",
            assertionCheck.auditTarget,
            assertionCheck.assertionSha256,
          );
          return grantRejected(version, "bad_assertion");
        }
      }

      let skipCeilingCheck = existingGrantClaim !== null &&
        existingGrantClaim.override_assertion_sha256 !== null &&
        ceilingPolicy?.version === existingGrantClaim.accepted_ceiling_policy_version;
      let overrideAssertionSha256: string | null = null;
      if (existingGrantClaim === null && envelope.ceiling_override !== undefined) {
        const overrideCheck = await verifyCeilingOverrideAssertion(
          this.env,
          args,
          access.email,
          accessJwt,
          version,
          envelope,
          assertionCheck!.signer,
        );
        if (!overrideCheck.ok) {
          return grantRejected(version, overrideCheck.code);
        }
        skipCeilingCheck = true;
        overrideAssertionSha256 = overrideCheck.assertionSha256;
      }

      const liveBinding = existingGrantClaim === null
        ? await readLiveTenantBinding(this.env.DB, orgId)
        : null;
      const installationId = existingGrantClaim?.installation_id ??
        liveBinding?.installation_id ?? crypto.randomUUID();
      const bindingEpoch = existingGrantClaim?.binding_epoch ?? liveBinding?.epoch ??
        (await readMaxTenantBindingEpoch(this.env.DB, orgId)) + 1;

      if (existingGrantClaim === null) {
        const acceptedAt = await clockNowIso(this.env);
        const planSnapshot = {
          plan_id: planId,
          version: planVersion,
          display_name: planRow.display_name,
          capabilities: JSON.parse(planRow.capabilities) as unknown,
          max_cost_class: planRow.max_cost_class,
          concurrency_limit: planRow.concurrency_limit,
        };
        const accepted = {
          command: {
            contract_version: version,
            operation: assertionCheck!.operation,
            override_operation: isRecord(args.ceiling_override_operation)
              ? args.ceiling_override_operation
              : null,
            envelope,
          },
          actor: access.email,
          signerCredentialId: assertionCheck!.signer.credential_id,
          assertionSha256: assertionCheck!.assertionSha256,
          overrideAssertionSha256,
          contractVersion: version,
          ceilingPolicyVersion: ceilingPolicy!.version,
          planSnapshot,
        };
        const statements = [
          buildGrantClaimInsertStatement(this.env.DB, {
            grantId: claimGrantId,
            orgId,
            sourceKind: "complimentary",
            envelope,
            envelopeSha256: claimEnvelopeSha256,
            installationId,
            bindingEpoch,
            nowIso: acceptedAt,
            accepted,
          }),
          this.env.DB.prepare(
            `INSERT OR IGNORE INTO live_value_route (
               grant_id, org_id, installation_id, binding_epoch, generation, state, updated_at
             ) SELECT grant_id, org_id, installation_id, binding_epoch, route_generation,
                      'stable', ?
               FROM grant_claim WHERE grant_id = ? AND state <> 'disputed'
                 AND NOT EXISTS (SELECT 1 FROM grant_tombstone WHERE grant_id = ?)`
          ).bind(acceptedAt, claimGrantId, claimGrantId),
          buildComplimentaryCeilingClaimInsertStatement(this.env.DB, {
            grantId: claimGrantId,
            orgId,
            envelopeSha256: claimEnvelopeSha256,
            contribution: ceilingContribution,
            overrideAuthorized: overrideAssertionSha256 !== null,
            nowIso: acceptedAt,
          }),
          await buildAssertionUsedStatement(
            this.env,
            assertionCheck!.assertionSha256,
            assertionCheck!.signer.credential_id,
          ),
        ];
        if (overrideAssertionSha256 !== null) {
          statements.push(await buildAssertionUsedStatement(
            this.env,
            overrideAssertionSha256,
            assertionCheck!.signer.credential_id,
          ));
        }
        statements.push(buildEntrypointAuditStatement(
          this.env.DB,
          access.email,
          "grant",
          assertionCheck!.auditTarget,
          assertionCheck!.assertionSha256,
        ));
        try {
          await this.env.DB.batch(statements);
        } catch (error) {
          if (String(error).includes("complimentary_ceiling_exceeded")) {
            return grantRejected(version, "exceeds_ceiling");
          }
          const raced = await readGrantClaim(this.env.DB, claimGrantId);
          if (
            raced === null || !("grant_id" in raced) || raced.org_id !== orgId ||
            raced.envelope_sha256 !== claimEnvelopeSha256 ||
            raced.accepted_actor !== access.email ||
            raced.accepted_command !== canonicalJsonText(accepted.command)
          ) {
            await writeEntrypointAudit(
              this.env.DB,
              access.email,
              "grant",
              assertionCheck!.auditTarget,
              assertionCheck!.assertionSha256,
            );
            return grantRejected(version, "assertion_used");
          }
          existingGrantClaim = raced;
        }
        if (existingGrantClaim === null) {
          existingGrantClaim = await readGrantClaim(this.env.DB, claimGrantId);
        }
      }
      if (existingGrantClaim === null) return grantRejected(version, "coverage_unknown");
      const ceilingClaim = await readComplimentaryCeilingClaim(this.env.DB, claimGrantId);
      if (
        ceilingClaim === null || ceilingClaim.org_id !== orgId ||
        ceilingClaim.envelope_sha256 !== claimEnvelopeSha256 ||
        ceilingClaim.plan_id !== ceilingContribution.planId ||
        ceilingClaim.plan_version !== ceilingContribution.planVersion ||
        ceilingClaim.allowance_denominator !== ceilingContribution.allowanceDenominator ||
        ceilingClaim.day_contribution !== ceilingContribution.dayContribution ||
        ceilingClaim.allowance_contribution !== ceilingContribution.allowanceContribution
      ) {
        return grantRejected(version, "coverage_unknown");
      }
      if (ceilingClaim.status === "sealed_no_effect") {
        if (existingGrantClaim.command_state === "accepted") {
          await rejectAcceptedGrantCommand(this.env, existingGrantClaim, "exceeds_ceiling", "");
        }
        return grantRejected(version, "exceeds_ceiling");
      }
      if (existingGrantClaim.command_state === "accepted") {
        try {
          existingGrantClaim = await ensureAcceptedGrantBinding(this.env, existingGrantClaim);
        } catch {
          return grantTransient(version, "unavailable");
        }
        if (existingGrantClaim === null) return grantTransient(version, "unavailable");
      }
      const routedClaim = await routePendingGrantClaim(this.env, existingGrantClaim, version);
      if (routedClaim === null || !("grant_id" in routedClaim)) {
        return routedClaim === null ? grantRejected(version, "coverage_unknown") : routedClaim;
      }
      existingGrantClaim = routedClaim;
      const dispatchInstallationId = existingGrantClaim.installation_id;
      const dispatchBinding = await readTenantBindingForInstallation(this.env.DB, orgId, dispatchInstallationId);
      if (dispatchBinding === null) return grantRejected(version, "coverage_unknown");

      const complimentaryGrantId = envelope.grant_id;
      if (typeof complimentaryGrantId === "string" && complimentaryGrantId.length > 0) {
        const voided = await rejectIfGrantVoided(
          this.env,
          version,
          complimentaryGrantId,
        );
        if (voided !== null) {
          if (existingGrantClaim.command_state === "accepted") {
            await rejectAcceptedGrantCommand(
              this.env,
              existingGrantClaim,
              voided.code || "voided",
              voided.detail,
            );
          }
          return voided;
        }
      }

      const nowIso = await clockNowIso(this.env);
      if (!(await complimentaryCeilingClaimFitsCurrentPolicy(this.env.DB, ceilingClaim, nowIso))) {
        const resolution = await sealPendingCeilingClaimNoEffect(
          this.env,
          existingGrantClaim,
          ceilingClaim,
          version,
          nowIso,
        );
        if (resolution === "applied") {
          const completed = await readGrantClaim(this.env.DB, claimGrantId);
          return completed !== null && "grant_id" in completed
            ? claimReplayResult(version, completed, claimEnvelopeSha256, orgId) as GrantResultEnvelope
            : grantRejected(version, "coverage_unknown");
        }
        if (resolution === "sealed") {
          await rejectAcceptedGrantCommand(this.env, existingGrantClaim, "exceeds_ceiling", "");
          return grantRejected(version, "exceeds_ceiling");
        }
        return grantTransient(version, "unavailable");
      }
      const planSnapshot = existingGrantClaim.plan_snapshot === null
        ? {
        plan_id: planId,
        version: planVersion,
        display_name: planRow.display_name,
        capabilities: JSON.parse(planRow.capabilities) as unknown,
        max_cost_class: planRow.max_cost_class,
        concurrency_limit: planRow.concurrency_limit,
        }
        : JSON.parse(existingGrantClaim.plan_snapshot) as Record<string, unknown>;

      const grace = envelope.grace;
      const graceDays =
        isRecord(grace) && Number.isInteger(grace.days)
          ? (grace.days as number)
          : 0;

      const adjustment =
        envelopeKind === "term_adjustment" && isRecord(envelope.adjustment)
          ? (envelope.adjustment as Record<string, unknown>)
          : undefined;

      const dispatchLeaseToken = existingGrantClaim.command_state === "accepted"
        ? await acquireAcceptedGrantLease(this.env, existingGrantClaim.grant_id, nowIso)
        : null;
      if (existingGrantClaim.command_state === "accepted" && dispatchLeaseToken === null) {
        return grantTransient(version, "unavailable");
      }

      const doCall = await callGrantCoverageDo(this.env, dispatchInstallationId, {
        kind: "apply_grant",
        bindingEpoch: dispatchBinding.epoch,
        routeGeneration: existingGrantClaim.route_generation,
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
        operatorCredentialId: existingGrantClaim.signer_credential_id ?? "",
        operatorEmail: existingGrantClaim.accepted_actor ?? access.email,
        platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
        durationScale: durationScaleFromEnv(this.env),
        nowIso,
        sourceKind: "complimentary",
        envelopeKind: envelopeKind ?? "term",
        planMaxAllowancePerMonth: planRow.max_allowance_per_month,
        ceilingPolicy: ceilingPolicy === null ? undefined : {
          per_grant_max_days: ceilingPolicy.per_grant_max_days,
          per_grant_max_allowance_months:
            ceilingPolicy.per_grant_max_allowance_months,
          window_days: ceilingPolicy.window_days,
          window_max_days: ceilingPolicy.window_max_days,
          window_max_allowance_months:
            ceilingPolicy.window_max_allowance_months,
        },
        skipCeilingCheck,
        ceilingClaim: {
          grantId: ceilingClaim.grant_id,
          orgId: ceilingClaim.org_id,
          envelopeSha256: ceilingClaim.envelope_sha256,
          planId: ceilingClaim.plan_id,
          planVersion: ceilingClaim.plan_version,
          allowanceDenominator: ceilingClaim.allowance_denominator,
          dayContribution: ceilingClaim.day_contribution,
          allowanceContribution: ceilingClaim.allowance_contribution,
        },
        adjustment,
      });

      if (doCall.kind === "unavailable") {
        if (dispatchLeaseToken !== null) {
          await releaseAcceptedGrantLease(this.env, existingGrantClaim, dispatchLeaseToken, nowIso);
        }
        return grantTransient(version, "unavailable");
      }
      if (doCall.kind === "version_refusal") {
        if (dispatchLeaseToken !== null) {
          await rejectAcceptedGrantCommand(this.env, existingGrantClaim, "contract_version_unsupported", "");
        }
        return grantRejected(version, "contract_version_unsupported");
      }
      const doResponse = doCall.response;
      const mapped = mapApplyGrantDoResponse(version, doResponse);
      if ((mapped.result === "applied" || mapped.result === "already_applied") && mapped.receipt !== undefined) {
        if (!(await persistGrantClaimReceipt(this.env, existingGrantClaim, mapped.receipt, await clockNowIso(this.env)))) {
          return grantRejected(version, "coverage_unknown");
        }
      } else if (mapped.result === "rejected" && dispatchLeaseToken !== null) {
        await rejectAcceptedGrantCommand(
          this.env,
          existingGrantClaim,
          mapped.code,
          mapped.detail,
        );
      } else if (dispatchLeaseToken !== null) {
        await releaseAcceptedGrantLease(this.env, existingGrantClaim, dispatchLeaseToken, await clockNowIso(this.env));
      }
      return mapped;
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
    const envelopeBytes =
      typeof args.envelope_b64 === "string"
        ? Uint8Array.from(atob(args.envelope_b64), (char) => char.charCodeAt(0))
        : canonicalize(envelope);
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
    const usedEnvelopeWire =
      typeof args.envelope_b64 === "string" &&
      payloadBytes !== null &&
      bytesEqual(payloadBytes, envelopeBytes);
    const signatureValid = usedEnvelopeWire
      ? await verifyJwsAgainstWirePayload({
          jws: aboSignature,
          publicKey: verifyKey,
          kid: aboKid,
          payloadBytes: envelopeBytes,
        })
      : await verifyGrantSignature({
          envelope,
          jws: aboSignature,
          publicKey: verifyKey,
          kid: aboKid,
        });
    if (!signatureValid) {
      return grantRejected(version, "bad_signature");
    }

    const envelopeValidation = validateGrantEnvelope(envelope);
    if (!envelopeValidation.ok) {
      if (
        "code" in envelopeValidation &&
        envelopeValidation.code === "placement_not_supported"
      ) {
        return grantRejected(version, "placement_not_supported");
      }
      const rejectedGrace = envelope.grace;
      const rejectedSource = envelope.source;
      const rejectedDuration = envelope.duration;
      if (
        isRecord(rejectedSource) && rejectedSource.kind === "paid" &&
        isRecord(rejectedDuration) && rejectedDuration.unit === "month" &&
        Number.isInteger(rejectedDuration.count) &&
        [1, 3, 12].includes(rejectedDuration.count as number) &&
        isRecord(rejectedGrace) && Number.isInteger(rejectedGrace.days) &&
        (rejectedGrace.days as number) > 7 &&
        rejectedGrace.cap_rule === "proportional"
      ) {
        return grantRejected(version, "exceeds_plan_bound");
      }
      return grantRejected(version, "unit_not_allowed");
    }
    const claimOrgId = envelope.org_id;
    const claimGrantId = envelope.grant_id;
    if (typeof claimOrgId !== "string" || typeof claimGrantId !== "string") {
      return grantRejected(version, "bad_signature");
    }
    const claimEnvelopeSha256 = await grantEnvelopeHash(envelope);
    if (!(await ensureGrantClaimsBackfilled(this.env, claimOrgId, version))) {
      return grantRejected(version, "coverage_unknown");
    }
    let existingGrantClaim = await readGrantClaim(this.env.DB, claimGrantId);
    if (existingGrantClaim !== null) {
      const replay = claimReplayResult(
        version,
        existingGrantClaim,
        claimEnvelopeSha256,
        claimOrgId,
      );
      if (replay === "conflict") {
        return { contract_version: version, result: "conflict", code: "", detail: "" };
      }
      if (replay === "disputed") return grantRejected(version, "coverage_unknown");
      if (replay !== "pending") return replay;
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
    if (planRow === null || (planRow.status !== "published" && existingGrantClaim === null)) {
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
    if (ceilingPolicy === null && existingGrantClaim === null) {
      return grantRejected(version, "coverage_unknown");
    }

    const grace = envelope.grace;
    if (!isRecord(grace) || (existingGrantClaim === null && (
      !Number.isInteger(grace.days) || ceilingPolicy === null ||
      (grace.days as number) > ceilingPolicy.max_paid_grace_days ||
      grace.cap_rule !== ceilingPolicy.paid_cap_rule
    ))) {
      return grantRejected(version, "exceeds_plan_bound");
    }

    if (envelope.placement === "immediate" || envelope.placement === "replace") {
      return grantRejected(version, "placement_not_supported");
    }

    const orgId = claimOrgId;

    const heldBinding = await readLiveTenantBinding(this.env.DB, orgId);
    if (existingGrantClaim === null && heldBinding?.status === "held_for_transfer") {
      return grantTransient(version, "transfer_pending");
    }

    let binding = existingGrantClaim === null
      ? await readActiveTenantBinding(this.env.DB, orgId)
      : { installation_id: existingGrantClaim.installation_id, epoch: existingGrantClaim.binding_epoch };
    let installationId = binding?.installation_id ?? (await resolveOrInsertGrantBinding(this.env, orgId));
    if (binding === null) binding = await readActiveTenantBinding(this.env.DB, orgId);
    if (binding === null) return grantRejected(version, "coverage_unknown");

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

    if (existingGrantClaim === null) {
      existingGrantClaim = await createOrReadGrantClaim(this.env, {
        grantId: claimGrantId,
        orgId,
        sourceKind: "paid",
        envelope,
        envelopeSha256: claimEnvelopeSha256,
        installationId,
        bindingEpoch: binding.epoch,
        nowIso,
      });
    }
    if (existingGrantClaim === null) {
      const tombstone = await this.env.DB.prepare(
        "SELECT grant_id FROM grant_tombstone WHERE grant_id = ?",
      ).bind(claimGrantId).first<{ grant_id: string }>();
      return tombstone !== null
        ? grantRejected(version, "grant_voided")
        : grantRejected(version, "coverage_unknown");
    }
    const routedClaim = await routePendingGrantClaim(this.env, existingGrantClaim, version);
    if (routedClaim === null || !("grant_id" in routedClaim)) {
      return routedClaim === null ? grantRejected(version, "coverage_unknown") : routedClaim;
    }
    existingGrantClaim = routedClaim;
    installationId = existingGrantClaim.installation_id;
    const dispatchBinding = await readTenantBindingForInstallation(this.env.DB, orgId, installationId);
    if (dispatchBinding === null) return grantRejected(version, "coverage_unknown");

    const doCall = await callGrantCoverageDo(this.env, installationId, {
      kind: "apply_grant",
      bindingEpoch: dispatchBinding.epoch,
      routeGeneration: existingGrantClaim.route_generation,
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

    if (doCall.kind === "unavailable") {
      return grantTransient(version, "unavailable");
    }
    if (doCall.kind === "version_refusal") {
      return grantRejected(version, "contract_version_unsupported");
    }
    const doResponse = doCall.response;

    const doResult = doResponse.result;
    if (doResult === "conflict") {
      return {
        contract_version: version,
        result: "conflict",
        code: "",
        detail: "",
      };
    }
    const mapped = mapApplyGrantDoResponse(version, doResponse);
    if ((mapped.result === "applied" || mapped.result === "already_applied") && mapped.receipt !== undefined) {
      if (!(await persistGrantClaimReceipt(this.env, existingGrantClaim, mapped.receipt, await clockNowIso(this.env)))) {
        return grantRejected(version, "coverage_unknown");
      }
    }
    return mapped;
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
    const existingByAssertion = await readTransferPreparationByAssertion(
      this.env.DB,
      assertionSha256,
    );
    if (existingByAssertion !== null) {
      if (
        existingByAssertion.org_id !== orgId ||
        existingByAssertion.from_installation_id !== fromInstallationId ||
        existingByAssertion.reason !== reason ||
        existingByAssertion.accepted_actor !== access.email ||
        existingByAssertion.accepted_signer_credential_id !== args.signer_credential_id
      ) return grantRejected(version, "assertion_invalid");
      let accepted: Record<string, unknown>;
      try {
        accepted = JSON.parse(existingByAssertion.accepted_command) as Record<string, unknown>;
      } catch {
        return grantRejected(version, "coverage_unknown");
      }
      if (accepted.contract_version !== version) return grantRejected(version, "assertion_invalid");
      const resumed = await resumeTransferPreparation(this.env, existingByAssertion.transfer_id);
      if (resumed === "transient") {
        return { contract_version: version, result: "transient", code: "", detail: "transfer_preparation_pending" };
      }
      if (resumed === "bad_request") return grantRejected(version, "bad_request");
      return {
        contract_version: version,
        result: "ok",
        code: "",
        detail: transferRowToDetail(resumed),
      };
    }

    const legacyTransfer = await readTransferByAssertionSha256(this.env.DB, assertionSha256);
    if (legacyTransfer !== null) {
      const [audits, usedAssertions] = await Promise.all([
        this.env.DB.prepare(
          `SELECT actor, operator_id FROM control_audit
           WHERE action = 'beginTransfer' AND target = ? AND assertion_sha256 = ?`,
        ).bind(`${orgId}:${fromInstallationId}`, assertionSha256)
          .all<{ actor: string; operator_id: string }>(),
        this.env.DB.prepare(
          `SELECT credential_id FROM assertion_used WHERE challenge_sha256 = ?`,
        ).bind(assertionSha256).all<{ credential_id: string }>(),
      ]);
      const audit = audits.results?.length === 1 ? audits.results[0] : undefined;
      const used = usedAssertions.results?.length === 1 ? usedAssertions.results[0] : undefined;
      if (
        legacyTransfer.org_id !== orgId ||
        legacyTransfer.from_installation_id !== fromInstallationId ||
        legacyTransfer.reason !== reason ||
        audit === undefined || used === undefined ||
        audit.actor !== access.email || audit.operator_id !== access.email ||
        used.credential_id !== args.signer_credential_id
      ) {
        await this.env.DB.prepare(
          `INSERT OR IGNORE INTO transfer_route_quarantine
             (transfer_id, grant_id, reason, created_at)
           VALUES (?, '', 'legacy_transfer_authorization_ambiguous', ?)`
        ).bind(legacyTransfer.transfer_id, await clockNowIso(this.env)).run();
        return grantRejected(version, "coverage_unknown");
      }
      const adopted = await executeBeginTransfer(this.env, {
        orgId,
        fromInstallationId,
        reason,
        assertionSha256,
        acceptedActor: audit.actor,
        signerCredentialId: used.credential_id,
        contractVersion: version,
      });
      if (adopted === "bad_request") return grantRejected(version, "coverage_unknown");
      if (adopted === "transient") {
        return { contract_version: version, result: "transient", code: "", detail: "transfer_preparation_pending" };
      }
      return {
        contract_version: version,
        result: "ok",
        code: "",
        detail: transferRowToDetail(adopted),
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
      acceptedActor: access.email,
      signerCredentialId: check.signer.credential_id,
      contractVersion: version,
    });
    if (created === "transient") {
      return { contract_version: version, result: "transient", code: "", detail: "transfer_preparation_pending" };
    }
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

    const transfer = await readTransferById(this.env.DB, transferId);
    if (transfer === null) {
      return grantRejected(version, "bad_request");
    }
    if (await isTransferRouteQuarantined(this.env.DB, transferId)) {
      return grantRejected(version, "transfer_route_quarantined");
    }
    if (transfer.package !== null && !(await verifyTransferOutEvidence(this.env, transfer))) {
      return grantRejected(version, "transfer_route_quarantined");
    }
    if (transfer.package === null) {
      const step = await executeTransferIn(this.env, version, transferId);
      if (step.result === "transient") {
        return grantTransient(version, step.detail);
      }
      if (step.result === "rejected") {
        return grantRejected(version, step.code);
      }
      return grantRejected(version, "bad_request");
    }
    if (!(await ensureGrantClaimsBackfilled(this.env, transfer.org_id, version))) {
      return grantRejected(version, "coverage_unknown");
    }
    const packageValue: unknown = JSON.parse(transfer.package);
    if (!Array.isArray(packageValue)) return grantRejected(version, "bad_request");
    const targetBinding = await readTenantBindingForInstallation(
      this.env.DB,
      transfer.org_id,
      transfer.to_installation_id,
    );
    if (targetBinding === null) return grantRejected(version, "coverage_unknown");
    const claimCreatedAt = await clockNowIso(this.env);
    const transferClaims: GrantClaimRow[] = [];
    for (let index = 0; index < packageValue.length; index += 1) {
      const packageTerm = packageValue[index];
      if (!isRecord(packageTerm)) return grantRejected(version, "bad_request");
      const grantId = await sha256Hex(
        new TextEncoder().encode(`grant:transfer:${transferId}:${index}`),
      );
      const envelopeSha256 = await grantEnvelopeHash(packageTerm);
      const claim = await createOrReadGrantClaim(this.env, {
        grantId,
        orgId: transfer.org_id,
        sourceKind: "transfer",
        envelope: packageTerm,
        envelopeSha256,
        installationId: transfer.to_installation_id,
        bindingEpoch: targetBinding.epoch,
        nowIso: claimCreatedAt,
      });
      if (claim === null || claim.state === "disputed") {
        await alertGrantClaimDispute(this.env, transfer.org_id, grantId, claimCreatedAt);
        return grantRejected(version, "coverage_unknown");
      }
      if (claim.state === "completed") {
        continue;
      }
      transferClaims.push(claim);
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
    const inspected = await callCoverageDo(this.env, transfer.to_installation_id, {
      kind: "inspect_coverage",
      installationId: transfer.to_installation_id,
      orgId: transfer.org_id,
      vendorContractVersion: version,
    });
    if (inspected === null || !Array.isArray(inspected.grants)) {
      return grantTransient(version, "unavailable");
    }
    for (const claim of transferClaims) {
      const stored = inspected.grants.find((row) => isRecord(row) && row.grant_id === claim.grant_id);
      if (!isRecord(stored) || typeof stored.receipt !== "string") {
        return grantTransient(version, "unavailable");
      }
      const receipt: unknown = JSON.parse(stored.receipt);
      if (!isRecord(receipt) || !(await persistGrantClaimReceipt(this.env, claim, receipt, await clockNowIso(this.env)))) {
        await alertGrantClaimDispute(this.env, transfer.org_id, claim.grant_id, await clockNowIso(this.env));
        return grantRejected(version, "coverage_unknown");
      }
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

    const operation = args.operation;
    if (validateOperation(operation).ok && isRecord(operation)) {
      const assertionSha256 = await operationAssertionSha256(operation);
      const prior = await readDeletionCommand(this.env.DB, assertionSha256);
      if (prior !== null) {
        let accepted: unknown;
        try { accepted = JSON.parse(prior.accepted_command); } catch { accepted = null; }
        if (
          isRecord(accepted) && prior.org_id === orgId && prior.reason === reason &&
          prior.accepted_actor === access.email &&
          prior.signer_credential_id === args.signer_credential_id &&
          accepted.contract_version === version && accepted.org_id === orgId &&
          accepted.reason === reason && accepted.actor === access.email &&
          operationParamsMatch("deleteInstallation", operation, args,
            typeof args.access_jwt === "string" ? args.access_jwt : "", version)
        ) {
          const resumed = await resumeDeleteInstallation(this.env, assertionSha256);
          return resumed.result === "ok"
            ? { contract_version: version, result: "ok", code: "", detail: resumed.detail }
            : { contract_version: version, result: "transient", code: "", detail: "deletion_pending" };
        }
      }
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

    const nowIso = await clockNowIso(this.env);
    const binding = await this.env.DB.prepare(
      `SELECT installation_id, epoch FROM tenant_binding
       WHERE org_id = ? AND status IN ('active', 'held_for_transfer')
       ORDER BY epoch DESC LIMIT 1`,
    ).bind(orgId).first<{ installation_id: string; epoch: number }>();
    if (binding === null) {
      await writeEntrypointAudit(this.env.DB, access.email, "deleteInstallation",
        check.auditTarget, check.assertionSha256);
      return grantRejected(version, "bad_request");
    }
    const acceptedCommand = JSON.stringify({
      contract_version: version,
      snapshot_version: CHANNEL_VERSIONS.platformDo,
      org_id: orgId,
      installation_id: binding.installation_id,
      binding_epoch: binding.epoch,
      reason,
      actor: access.email,
      signer_credential_id: check.signer.credential_id,
      accepted_at: nowIso,
      duration_scale: this.env.DURATION_SCALE === "staging" ? "staging" : null,
    });
    const accepted = await acceptDeleteInstallation(this.env, {
      orgId,
      reason,
      operatorId: access.email,
      assertionSha256: check.assertionSha256,
      signerCredentialId: check.signer.credential_id,
      acceptedCommand,
    });
    if (accepted.result !== "accepted") {
      await writeEntrypointAudit(this.env.DB, access.email, "deleteInstallation",
        check.auditTarget, check.assertionSha256);
      return grantRejected(version, "bad_request");
    }
    const resumed = await resumeDeleteInstallation(this.env, accepted.assertionSha256);
    return resumed.result === "ok"
      ? { contract_version: version, result: "ok", code: "", detail: resumed.detail }
      : { contract_version: version, result: "transient", code: "", detail: "deletion_pending" };
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
    const requestBody = canonicalJsonText(signedBody);
    let command = await readReversalCommand(this.env.DB, reversalId);
    if (command !== null && (
      command.grant_id !== grantId || command.request_sha256 !== envelopeSha256 ||
      command.request_body !== requestBody
    )) return reversalConflict(version);
    if (command?.state === "terminal") {
      await shipReversalExport(this.env, command);
      return {
        contract_version: version,
        result: "already_applied",
        code: "",
        detail: "",
        receipt: JSON.parse(command.receipt!) as Record<string, unknown>,
      };
    }
    const priorGrantVoid = await this.env.DB.prepare(
      "SELECT grant_id FROM grant_void WHERE grant_id = ?",
    ).bind(grantId).first<{ grant_id: string }>();
    if (priorGrantVoid !== null) {
      const recovered = await recoverExactLegacyReversal(this.env, {
        grantId, reversalId, reason, evidenceSha256,
        requestSha256: envelopeSha256, requestBody, nowIso,
      });
      if (recovered === "unavailable") return grantTransient(version, "reversal_receipt_unavailable");
      if (recovered === "mismatch") return reversalConflict(version);
      const legacyCommand = await readReversalCommand(this.env.DB, reversalId);
      if (legacyCommand === null || legacyCommand.receipt === null) return grantRejected(version, "coverage_unknown");
      return {
        contract_version: version,
        result: "already_applied",
        code: "",
        detail: "",
        receipt: JSON.parse(legacyCommand.receipt) as Record<string, unknown>,
      };
    }
    if (partial) return grantRejected(version, "partial_void", "");

    let route = await readLiveValueRoute(this.env.DB, grantId);
    let claim = await readGrantClaim(this.env.DB, grantId);
    if (route === null && claim !== null && !isGrantResultEnvelope(claim)) {
      await this.env.DB.prepare(
        `INSERT OR IGNORE INTO live_value_route (
           grant_id, org_id, installation_id, binding_epoch, generation, state, updated_at
         ) VALUES (?, ?, ?, ?, ?, 'stable', ?)`,
      ).bind(grantId, claim.org_id, claim.installation_id, claim.binding_epoch,
        claim.route_generation, nowIso).run();
      route = await readLiveValueRoute(this.env.DB, grantId);
    }

    if (route === null) {
      if (claim !== null) return grantRejected(version, "coverage_unknown");
      const priorVoid = await this.env.DB.prepare(
        "SELECT grant_id FROM grant_void WHERE grant_id = ?",
      ).bind(grantId).first<{ grant_id: string }>();
      if (priorVoid !== null) return reversalConflict(version);
      const signingKey = await loadPlatformSigningKey(
        this.env.PLATFORM_SIGNING_KEY, this.env.ENVIRONMENT,
      );
      if (signingKey === null) return grantRejected(version, "coverage_unknown");
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
      const exportPayload = `${JSON.stringify({
        grant_id: grantId, reason, source: "reversal", evidence_sha256: evidenceSha256,
        at: nowIso, receipt,
      })}\n`;
      await this.env.DB.batch([
        this.env.DB.prepare(
          `INSERT OR IGNORE INTO grant_tombstone (
             grant_id, reversal_id, request_sha256, receipt, export_payload, created_at
           ) SELECT ?, ?, ?, ?, ?, ?
             WHERE NOT EXISTS (SELECT 1 FROM grant_claim WHERE grant_id = ?)
               AND NOT EXISTS (SELECT 1 FROM grant_void WHERE grant_id = ?)`,
        ).bind(grantId, reversalId, envelopeSha256, canonicalJsonText(receipt),
          exportPayload, nowIso, grantId, grantId),
        this.env.DB.prepare(
          `INSERT OR IGNORE INTO grant_void (grant_id, reason, source, evidence_sha256, at)
           SELECT grant_id, ?, 'reversal', ?, ? FROM grant_tombstone
           WHERE grant_id = ? AND reversal_id = ? AND request_sha256 = ?`,
        ).bind(reason, evidenceSha256, nowIso, grantId, reversalId, envelopeSha256),
        this.env.DB.prepare(
          `INSERT OR IGNORE INTO reversal_command (
             reversal_id, grant_id, request_sha256, request_body,
             state, receipt, export_payload, export_state, created_at, updated_at
           ) SELECT ?, ?, ?, ?, 'terminal', ?, ?, 'due', ?, ?
             FROM grant_tombstone WHERE grant_id = ? AND reversal_id = ?
               AND request_sha256 = ?`,
        ).bind(reversalId, grantId, envelopeSha256, requestBody,
          canonicalJsonText(receipt), exportPayload, nowIso, nowIso,
          grantId, reversalId, envelopeSha256),
      ]);
      command = await readReversalCommand(this.env.DB, reversalId);
      if (command === null) {
        const racedRoute = await readLiveValueRoute(this.env.DB, grantId);
        return racedRoute === null
          ? reversalConflict(version)
          : grantTransient(version, "grant_route_claim_race");
      }
      if (command.request_sha256 !== envelopeSha256 || command.grant_id !== grantId) {
        return reversalConflict(version);
      }
      await shipReversalExport(this.env, command);
      return { contract_version: version, result: "applied", code: "", detail: "", receipt };
    }

    if (route.org_id !== (claim !== null && !isGrantResultEnvelope(claim) ? claim.org_id : route.org_id)) {
      return grantRejected(version, "coverage_unknown");
    }
    if (route.state === "moving") {
      if (command === null) {
        await this.env.DB.prepare(
          `INSERT OR IGNORE INTO reversal_command (
             reversal_id, grant_id, request_sha256, request_body,
             route_installation_id, route_epoch, route_generation,
             state, receipt, export_payload, export_state, created_at, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, 'due', NULL, NULL, 'none', ?, ?)`,
        ).bind(reversalId, grantId, envelopeSha256, requestBody, route.installation_id,
          route.binding_epoch, route.generation, nowIso, nowIso).run();
        command = await readReversalCommand(this.env.DB, reversalId);
      }
      if (command === null || command.grant_id !== grantId ||
          command.request_sha256 !== envelopeSha256 || command.request_body !== requestBody) {
        return reversalConflict(version);
      }
      return grantTransient(version, "transfer_pending");
    }
    if (route.state === "retired") return reversalConflict(version);
    if (route.state === "voiding" && route.reversal_id !== reversalId) return reversalConflict(version);
    if (route.state === "stable") {
      const currentBinding = await readTenantBindingForInstallation(
        this.env.DB, route.org_id, route.installation_id,
      );
      if (currentBinding === null || currentBinding.epoch !== route.binding_epoch ||
          (currentBinding.status !== "active" && currentBinding.status !== "held_for_transfer")) {
        await this.env.DB.prepare(
          `INSERT OR IGNORE INTO reversal_command (
             reversal_id, grant_id, request_sha256, request_body,
             route_installation_id, route_epoch, route_generation,
             state, receipt, export_payload, export_state, created_at, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, 'due', NULL, NULL, 'none', ?, ?)`,
        ).bind(reversalId, grantId, envelopeSha256, requestBody, route.installation_id,
          route.binding_epoch, route.generation, nowIso, nowIso).run();
        return grantTransient(version, "binding_route_pending");
      }
      await this.env.DB.batch([
        this.env.DB.prepare(
          `UPDATE live_value_route SET state = 'voiding', reversal_id = ?, updated_at = ?
           WHERE grant_id = ? AND state = 'stable' AND generation = ?`,
        ).bind(reversalId, nowIso, grantId, route.generation),
        this.env.DB.prepare(
          `INSERT OR IGNORE INTO reversal_command (
             reversal_id, grant_id, request_sha256, request_body,
             route_installation_id, route_epoch, route_generation,
             state, receipt, export_payload, export_state, created_at, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, 'due', NULL, NULL, 'none', ?, ?)`,
        ).bind(reversalId, grantId, envelopeSha256, requestBody, route.installation_id,
          route.binding_epoch, route.generation, nowIso, nowIso),
      ]);
      route = await readLiveValueRoute(this.env.DB, grantId);
      command = await readReversalCommand(this.env.DB, reversalId);
    }
    if (
      route === null || command === null || command.grant_id !== grantId ||
      command.request_sha256 !== envelopeSha256 || command.request_body !== requestBody
    ) return reversalConflict(version);
    if (route.state !== "voiding" || route.reversal_id !== reversalId) {
      return grantTransient(version, "transfer_pending");
    }
    if (command.route_installation_id !== route.installation_id ||
        command.route_epoch !== route.binding_epoch || command.route_generation !== route.generation) {
      return reversalConflict(version);
    }
    if (claim === null || isGrantResultEnvelope(claim) || claim.state === "disputed" ||
        claim.org_id !== route.org_id) {
      return grantRejected(version, "coverage_unknown");
    }
    const doResponse = await callCoverageDo(this.env, route.installation_id, {
      kind: "void_for_reversal",
      installationId: route.installation_id,
      orgId: route.org_id,
      vendorContractVersion: version,
      bindingEpoch: route.binding_epoch,
      routeGeneration: route.generation,
      grantEnvelopeSha256: claim.envelope_sha256,
      grantId,
      reversalId,
      reason,
      evidenceSha256,
      envelopeSha256,
      nowIso,
      platformSigningKeyJson: this.env.PLATFORM_SIGNING_KEY,
      durationScale: durationScaleFromEnv(this.env),
    });
    if (doResponse === null || doResponse.result === "transient") {
      return grantTransient(version, "reversal_due");
    }
    if (doResponse.result === "conflict") return reversalConflict(version);
    if (doResponse.result !== "applied" && doResponse.result !== "already_applied") {
      return grantRejected(version, "coverage_unknown");
    }
    if (!isRecord(doResponse.receipt)) return grantRejected(version, "coverage_unknown");
    const receipt = doResponse.receipt;
    if (
      receipt.reversal_id !== reversalId || receipt.installation_id !== route.installation_id ||
      receipt.org_id !== route.org_id || receipt.envelope_sha256 !== envelopeSha256 ||
      (receipt.result !== "applied" && receipt.result !== "already_applied") ||
      !(await verifyPlatformReceipt(this.env, receipt))
    ) return grantRejected(version, "coverage_unknown");
    const exportPayload = `${JSON.stringify({
      grant_id: grantId, reason, source: "reversal", evidence_sha256: evidenceSha256,
      at: typeof receipt.applied_at === "string" ? receipt.applied_at : nowIso, receipt,
    })}\n`;
    const completedAt = await clockNowIso(this.env);
    await this.env.DB.batch([
      this.env.DB.prepare(
        `UPDATE live_value_route SET state = 'retired', transfer_id = NULL,
           updated_at = ? WHERE grant_id = ? AND state = 'voiding' AND reversal_id = ?
           AND generation = ?`,
      ).bind(completedAt, grantId, reversalId, route.generation),
      this.env.DB.prepare(
        `INSERT OR IGNORE INTO grant_void (grant_id, reason, source, evidence_sha256, at)
         SELECT ?, ?, 'reversal', ?, ? WHERE EXISTS (
           SELECT 1 FROM live_value_route WHERE grant_id = ? AND state = 'retired'
             AND reversal_id = ? AND generation = ?
         )`,
      ).bind(grantId, reason, evidenceSha256,
        typeof receipt.applied_at === "string" ? receipt.applied_at : completedAt,
        grantId, reversalId, route.generation),
      this.env.DB.prepare(
        `UPDATE reversal_command SET state = 'terminal', receipt = ?, export_payload = ?,
           export_state = 'due', updated_at = ? WHERE reversal_id = ? AND grant_id = ?
           AND request_sha256 = ? AND state = 'due' AND EXISTS (
             SELECT 1 FROM live_value_route WHERE grant_id = ? AND state = 'retired'
               AND reversal_id = ? AND generation = ?
           )`,
      ).bind(canonicalJsonText(receipt), exportPayload, completedAt, reversalId,
        grantId, envelopeSha256, grantId, reversalId, route.generation),
    ]);
    command = await readReversalCommand(this.env.DB, reversalId);
    if (command === null || command.state !== "terminal" || command.receipt === null) {
      return grantTransient(version, "reversal_commit_pending");
    }
    await shipReversalExport(this.env, command);
    return {
      contract_version: version,
      result: doResponse.result,
      code: "",
      detail: "",
      receipt: JSON.parse(command.receipt) as Record<string, unknown>,
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

  async recoverStrandedTerm(args: Record<string, unknown>): Promise<GrantResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) return grantRejected(VENDOR_CHANNEL, negotiated.code);
    const version = negotiated.version;
    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) return grantRejected(version, "unauthenticated");
    const actionId = args.action_id;
    const orgId = args.org_id;
    const installationId = args.installation_id;
    const targetTermId = args.target_term_id;
    const sourceGrantId = args.source_grant_id;
    const expectedClinicSeq = args.expected_clinic_seq;
    const expectedBindingEpoch = args.binding_epoch;
    const reason = args.reason;
    const evidenceSha256 = args.evidence_sha256;
    const credentialId = args.signer_credential_id;
    if (typeof actionId !== "string" || actionId.length === 0 ||
      typeof orgId !== "string" || orgId.length === 0 ||
      typeof installationId !== "string" || installationId.length === 0 ||
      typeof targetTermId !== "string" || targetTermId.length === 0 ||
      typeof sourceGrantId !== "string" || sourceGrantId.length === 0 ||
      typeof reason !== "string" || reason.length === 0 ||
      typeof evidenceSha256 !== "string" || !HEX64_RE.test(evidenceSha256) ||
      typeof credentialId !== "string" || credentialId.length === 0 ||
      typeof expectedClinicSeq !== "number" || !Number.isInteger(expectedClinicSeq) || expectedClinicSeq < 0 ||
      typeof expectedBindingEpoch !== "number" || !Number.isInteger(expectedBindingEpoch) || expectedBindingEpoch < 0) {
      return grantRejected(version, "bad_request");
    }
    const originalGrant = await this.env.DB.prepare(
      "SELECT org_id, installation_id, kind, source_kind FROM grant_ledger WHERE grant_id = ?",
    ).bind(sourceGrantId).first<{ org_id: string; installation_id: string; kind: string; source_kind: string }>();
    if (originalGrant === null || originalGrant.org_id !== orgId ||
        originalGrant.kind !== "term" || originalGrant.source_kind !== "complimentary" ||
        originalGrant.installation_id !== installationId) {
      return grantRejected(version, "coverage_unknown");
    }
    const operationRaw = args.operation;
    if (!validateOperation(operationRaw).ok) return grantRejected(version, "assertion_invalid");
    const assertionSha256 = await operationAssertionSha256(operationRaw as Record<string, unknown>);
    const nowIso = await clockNowIso(this.env);
    const doRequest = {
      kind: "recover_stranded_term",
      actionId,
      orgId,
      installationId,
      bindingEpoch: expectedBindingEpoch,
      targetTermId,
      sourceGrantId,
      expectedClinicSeq,
      reason,
      evidenceSha256,
      actorEmail: access.email,
      credentialId,
      assertionSha256,
      nowIso,
      vendorContractVersion: version,
      durationScale: durationScaleFromEnv(this.env),
      replayOnly: true,
    };
    const requestSha256 = await sha256Hex(canonicalize({
      action_id: actionId,
      org_id: orgId,
      installation_id: installationId,
      binding_epoch: expectedBindingEpoch,
      target_term_id: targetTermId,
      source_grant_id: sourceGrantId,
      expected_clinic_seq: expectedClinicSeq,
      reason,
      evidence_sha256: evidenceSha256,
      actor_email: access.email,
      credential_id: credentialId,
      assertion_sha256: assertionSha256,
      vendor_contract_version: version,
    }));
    const persistRecoveryFact = async (detail: Record<string, unknown>): Promise<void> => {
      await this.env.DB.prepare(
        `INSERT OR IGNORE INTO stranded_term_recovery (
          action_id, org_id, installation_id, binding_epoch, target_term_id,
          source_grant_id, expected_clinic_seq, reason, request_sha256, evidence_sha256,
          actor_email, credential_id, assertion_sha256, recovered_at, result_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        actionId, orgId, installationId, expectedBindingEpoch, targetTermId,
        sourceGrantId, expectedClinicSeq, reason, requestSha256, evidenceSha256,
        access.email, credentialId, assertionSha256, detail.recovered_at,
        canonicalJsonText({ kind: "recover_stranded_term", result: "ok", detail }),
      ).run();
    };
    const durableReplay = await this.env.DB.prepare(
      "SELECT request_sha256, result_json FROM stranded_term_recovery WHERE action_id = ?",
    ).bind(actionId).first<{ request_sha256: string; result_json: string }>();
    if (durableReplay !== null) {
      if (durableReplay.request_sha256 !== requestSha256) {
        return { contract_version: version, result: "conflict", code: "recovery_conflict", detail: "" };
      }
      const stored = JSON.parse(durableReplay.result_json) as Record<string, unknown>;
      const detail = stored.detail;
      if (!isRecord(detail)) return grantTransient(version, "recovery_audit_invalid");
      return { contract_version: version, result: "ok", code: "", detail: canonicalJsonText(detail) };
    }
    // Completed action identity is permanent in the pinned DO. Read it before
    // one-use assertion validation so a lost HTTP reply can replay exactly.
    const replay = await callCoverageDo(this.env, installationId, doRequest);
    if (replay?.result === "ok" && isRecord(replay.detail)) {
      await persistRecoveryFact(replay.detail);
      return { contract_version: version, result: "ok", code: "", detail: canonicalJsonText(replay.detail) };
    }
    if (replay?.result === "conflict") return { contract_version: version, result: "conflict", code: "recovery_conflict", detail: "" };
    const authoritativeVoid = await this.env.DB.prepare(
      "SELECT COUNT(*) AS count FROM grant_void WHERE grant_id = ?",
    ).bind(sourceGrantId).first<{ count: number }>();
    if ((authoritativeVoid?.count ?? 0) > 0) {
      return { contract_version: version, result: "conflict", code: "recovery_history_conflict", detail: "" };
    }
    const binding = await readActiveTenantBinding(this.env.DB, orgId);
    if (binding === null || binding.installation_id !== installationId || binding.epoch !== expectedBindingEpoch) {
      return grantRejected(version, "coverage_unknown");
    }
    const historyRows = await this.env.DB.prepare(
      "SELECT clinic_seq, kind, snapshot FROM coverage_event WHERE installation_id = ? AND instr(snapshot, ?) > 0 ORDER BY clinic_seq ASC",
    ).bind(installationId, targetTermId).all<{
      clinic_seq: number;
      kind: string;
      snapshot: string;
    }>();
    const history: Array<{
      clinicSeq: number;
      kind: string;
      snapshot: Record<string, unknown>;
      terms: Record<string, unknown>[];
    }> = [];
    let wasActivated = false;
    let historyInvalid = false;
    for (const row of historyRows.results ?? []) {
      try {
        const snapshot = JSON.parse(row.snapshot) as Record<string, unknown>;
        const terms = Array.isArray(snapshot.terms)
          ? snapshot.terms.filter(isRecord)
          : [];
        const target = terms.find((term) => term.term_id === targetTermId);
        if (target?.state === "active") wasActivated = true;
        history.push({ clinicSeq: row.clinic_seq, kind: row.kind, snapshot, terms });
      } catch {
        historyInvalid = true;
      }
    }
    const placementProofs = history.flatMap((event) => {
      if (event.kind !== "grant_applied") return [];
      const target = event.terms.find((term) =>
        term.term_id === targetTermId && term.grant_id === sourceGrantId &&
        term.state === "queued" && term.held !== true &&
        typeof term.position === "number",
      );
      if (target === undefined) return [];
      const predecessors = event.terms.filter((term) =>
        typeof term.position === "number" &&
        term.position < (target.position as number) &&
        (term.state === "active" || term.state === "grace"),
      );
      if (predecessors.length === 0) return [];
      const snapshotTerm = isRecord(event.snapshot.term) ? event.snapshot.term : null;
      return [{
        clinicSeq: event.clinicSeq,
        predecessorIds: predecessors.map((term) => term.term_id).filter(
          (termId): termId is string => typeof termId === "string",
        ),
        gracePredecessor: event.snapshot.state === "grace" &&
          snapshotTerm !== null &&
          predecessors.some((term) => term.state === "grace" &&
            snapshotTerm.ref === term.term_id),
      }];
    });
    const orphanBoundaryProven = placementProofs.some((placement) =>
      history.some((event) => {
        if (event.clinicSeq <= placement.clinicSeq || event.kind !== "term_ended" ||
            event.snapshot.state === "active" || event.snapshot.state === "grace") {
          return false;
        }
        const target = event.terms.find((term) =>
          term.term_id === targetTermId && term.state === "queued" && term.held !== true,
        );
        return target !== undefined && placement.predecessorIds.every((predecessorId) =>
          event.terms.some((term) => term.term_id === predecessorId &&
            (term.state === "ended" || term.state === "exhausted")),
        );
      }),
    );
    const gracePlacementProven = placementProofs.some((placement) => placement.gracePredecessor);
    const priorUsage = await this.env.DB.prepare(
      "SELECT COUNT(*) AS count FROM usage_event WHERE installation_id = ? AND term_id = ?",
    ).bind(installationId, targetTermId).first<{ count: number }>();
    if (historyInvalid || wasActivated ||
        (!orphanBoundaryProven && !gracePlacementProven) ||
        (priorUsage?.count ?? 0) > 0) {
      return { contract_version: version, result: "conflict", code: "recovery_history_conflict", detail: "" };
    }

    const check = await runHpAssertionChecks(
      this.env, "recoverStrandedTerm", args, access.email, version,
    );
    if (!check.ok) {
      const rejectedEnvelope = await rejectHpAssertion(
        this.env, access.email, "recoverStrandedTerm", check,
      );
      return { contract_version: version, result: "rejected", code: rejectedEnvelope.code, detail: rejectedEnvelope.detail };
    }
    const doResponse = await callCoverageDo(this.env, installationId, {
      ...doRequest,
      assertionSha256: check.assertionSha256,
      actorEmail: access.email,
      credentialId: check.signer.credential_id,
      replayOnly: false,
    });
    if (doResponse === null) return grantTransient(version, "coverage_unknown");
    if (doResponse.result === "conflict") return { contract_version: version, result: "conflict", code: "recovery_conflict", detail: "" };
    if (doResponse.result !== "ok" || !isRecord(doResponse.detail)) return grantRejected(version, "coverage_unknown");
    await persistRecoveryFact(doResponse.detail);
    await finishHpAssertion(this.env, access.email, "recoverStrandedTerm", check);
    return { contract_version: version, result: "ok", code: "", detail: canonicalJsonText(doResponse.detail) };
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

    const lifecycle = await setInstallationSuspendedAction(
      { DB: this.env.DB },
      access.email,
      binding.installation_id,
      kind === "suspend",
    );
    if (!lifecycle.ok) {
      return rejected(version, lifecycle.error);
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

  private async invokeClassH(
    args: Record<string, unknown>,
    run: (version: number, accessEmail: string) => Promise<VendorResultEnvelope>,
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

    return run(version, access.email);
  }

  async publishRoutingPolicy(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const document = args.document;
      if (!isRecord(document)) {
        return rejected(version, "missing_document");
      }
      const result = await publishRoutingPolicyAction(
        { DB: this.env.DB, R2: this.env.R2 },
        email,
        document,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async canaryRoutingPolicy(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const policyId = args.policy_id;
      const policyVersion = args.version;
      const installationIds = args.installation_ids;
      if (typeof policyId !== "string" || typeof policyVersion !== "string") {
        return rejected(version, "bad_request");
      }
      if (!Array.isArray(installationIds)) {
        return rejected(version, "missing_installation_ids");
      }
      const cohortName =
        typeof args.cohort_name === "string" ? args.cohort_name : undefined;
      const result = await canaryRoutingPolicyAction(
        { DB: this.env.DB },
        email,
        policyId,
        policyVersion,
        installationIds as string[],
        cohortName,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async promoteRoutingPolicy(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const policyId = args.policy_id;
      const policyVersion = args.version;
      if (typeof policyId !== "string" || typeof policyVersion !== "string") {
        return rejected(version, "bad_request");
      }
      const result = await promoteRoutingPolicyAction(
        { DB: this.env.DB },
        email,
        policyId,
        policyVersion,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async rollbackRoutingPolicy(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const policyId = args.policy_id;
      const policyVersion = args.version;
      if (typeof policyId !== "string" || typeof policyVersion !== "string") {
        return rejected(version, "bad_request");
      }
      const result = await rollbackRoutingPolicyAction(
        { DB: this.env.DB },
        email,
        policyId,
        policyVersion,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async armKillSwitch(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await armKillSwitchAction({ DB: this.env.DB }, email, args);
      if (!result.ok) {
        return envelopeFromControlResult(version, result);
      }
      const scope = String(args.scope);
      const target = String(args.target);
      await raiseAl19FromOutbox(this.env, `AL-19:kill_switch:${scope}:${target}`, {
        code: "AL-19",
        scope,
        target,
      });
      return envelopeFromControlResult(version, result);
    });
  }

  async disarmKillSwitch(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await disarmKillSwitchAction({ DB: this.env.DB }, email, args);
      if (!result.ok) {
        return envelopeFromControlResult(version, result);
      }
      const scope = String(args.scope);
      const target = String(args.target);
      await raiseAl19FromOutbox(this.env, `AL-19:kill_switch:${scope}:${target}`, {
        code: "AL-19",
        scope,
        target,
      });
      return envelopeFromControlResult(version, result);
    });
  }

  async deprecateCapability(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await deprecateCapabilityAction(
        { DB: this.env.DB },
        email,
        args,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async retireCapability(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await retireCapabilityAction(
        { DB: this.env.DB },
        email,
        args,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async beginTokenContractRotation(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await beginTokenContractRotationAction(
        { DB: this.env.DB },
        email,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async retireTokenContract(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await retireTokenContractAction(
        { DB: this.env.DB },
        email,
        args,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async activateCohort(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await activateCohortAction(
        { DB: this.env.DB },
        email,
        args,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async promoteCohort(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const result = await promoteCohortAction(
        { DB: this.env.DB },
        email,
        args,
      );
      return envelopeFromControlResult(version, result);
    });
  }

  async rebuildClinicDo(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version) => {
      const installationId = args.installation_id;
      if (typeof installationId !== "string" || installationId.length === 0) {
        return rejected(version, "missing_installation_id");
      }
      const nowIso = await clockNowIso(this.env);
      const outcome = await runRebuildClinicDo(this.env, installationId, {
        onMismatch: async (mismatchInstallationId) => {
          await insertDoRebuildMismatchAlert(
            this.env.DB,
            mismatchInstallationId,
            nowIso,
          );
        },
      });
      if (outcome.status === "not_found") {
        return rejected(version, "not_found");
      }
      if (outcome.compare === "clean") {
        return ok(
          version,
          JSON.stringify({
            compare: "clean",
            installation_id: installationId,
          }),
        );
      }
      return ok(version, JSON.stringify({}));
    });
  }

  async rebuildGrantLedger(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version) => {
      try {
        const counts = await runRebuildGrantLedger(this.env);
        return ok(version, JSON.stringify(counts));
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.startsWith("grant_ledger_recovery_capsule_required:")) {
          return rejected(version, "recovery_evidence_required", message);
        }
        throw error;
      }
    });
  }

  async refreshCoverageSnapshot(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version) => {
      const installationId = args.installation_id;
      if (typeof installationId !== "string" || installationId.length === 0) {
        return rejected(version, "missing_installation_id");
      }
      const row = await this.env.DB.prepare(
        `SELECT event_id FROM coverage_event WHERE installation_id = ? LIMIT 1`,
      )
        .bind(installationId)
        .first();
      if (row === null) {
        return rejected(version, "not_found");
      }
      const nowIso = await clockNowIso(this.env);
      const refreshed = await runRefreshCoverageSnapshot(
        this.env,
        installationId,
        nowIso,
      );
      if (refreshed === "not_found") {
        return rejected(version, "not_found");
      }
      return ok(
        version,
        JSON.stringify({
          event_id: refreshed.event_id,
          installation_id: installationId,
        }),
      );
    });
  }

  async recordOperatorAction(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const action = args.action;
      const subject = args.subject;
      const actionId = args.action_id;
      if (
        typeof action !== "string" ||
        action.length === 0 ||
        typeof subject !== "string" ||
        subject.length === 0 ||
        typeof actionId !== "string" ||
        actionId.length === 0
      ) {
        return rejected(version, "bad_request");
      }

      const existing = await this.env.DB.prepare(
        `SELECT audit_id FROM control_audit WHERE target = ?`,
      )
        .bind(actionId)
        .first<{ audit_id: string }>();
      if (existing !== null) {
        return ok(version, "");
      }

      await writeEntrypointAudit(this.env.DB, email, action, actionId, null);
      return ok(version, "");
    });
  }

  async supportLookup(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    return this.invokeClassH(args, async (version, email) => {
      const reference =
        typeof args.reference === "string" ? args.reference : undefined;
      const subscriptionRefArg =
        typeof args.subscription_ref === "string"
          ? args.subscription_ref
          : undefined;
      const orgId = typeof args.org_id === "string" ? args.org_id : undefined;
      const limit = typeof args.limit === "number" ? args.limit : undefined;
      const cursor = typeof args.cursor === "string" ? args.cursor : undefined;

      if (!reference && !subscriptionRefArg && !orgId) {
        return rejected(version, "missing_lookup_key");
      }
      if (
        (args.limit !== undefined &&
          (typeof args.limit !== "number" ||
            !Number.isInteger(args.limit) ||
            args.limit < 1 ||
            args.limit > 100)) ||
        (args.cursor !== undefined && typeof args.cursor !== "string")
      ) {
        return rejected(version, "bad_request");
      }

      const normalizedReference = reference === undefined
        ? undefined
        : normalizeRequestReference(reference.trim());
      const normalizedSubscriptionRef = subscriptionRefArg?.trim();
      const normalizedOrgId = orgId?.trim().toLowerCase();
      const selector = normalizedReference !== undefined
        ? { reference: normalizedReference }
        : normalizedSubscriptionRef !== undefined
          ? { subscription_ref: normalizedSubscriptionRef }
          : { org_id: normalizedOrgId! };

      // Diagnostic-retention gate reads the harness clock so TEST_CLOCK
      // runs age rows deterministically; production falls back to
      // Date.now() (single snapshot per lookup).
      const lookupNowMs = await clockNowMs(this.env);
      const result = await runSupportLookup(
        {
          reference: normalizedReference,
          subscription_ref: normalizedSubscriptionRef,
          org_id: normalizedOrgId,
          limit,
          cursor,
        },
        {
          db: this.env.DB,
          r2: this.env.R2,
          resolveRetentionClass: createManifestRetentionClassResolver(),
          now: () => new Date(lookupNowMs),
        },
      );

      if (!result.found) {
        return rejected(version, "not_found");
      }

      try {
        await writeEntrypointAudit(
          this.env.DB,
          email,
          "support_lookup",
          JSON.stringify(selector),
          null,
        );
      } catch {
        return rejected(version, "storage_error");
      }

      if ("requests" in result) {
        const body = {
          requests: result.requests.map((entry) => ({
            request: entry.request,
            attempts: entry.attempts,
            envelope: entry.envelope,
          })),
          next_after: result.next_after,
          has_more: result.has_more,
        };
        return ok(version, JSON.stringify(body));
      }

      const body = {
        request: result.request,
        attempts: result.attempts,
        envelope: result.envelope,
      };
      return ok(version, JSON.stringify(body));
    });
  }

  async feedConsumerHealth(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const row = await this.env.DB.prepare(
      `SELECT last_pull_at, last_cursor FROM feed_consumer WHERE consumer = 'backend-feed'`,
    ).first<{ last_pull_at: string | null; last_cursor: number | null }>();

    const detail = JSON.stringify({
      last_pull_at: row?.last_pull_at ?? null,
      last_cursor: row?.last_cursor ?? null,
    });
    return ok(version, detail);
  }

  async dispatchAcceptedGrantCommands(): Promise<number> {
    const nowIso = await clockNowIso(this.env);
    const rows = await this.env.DB.prepare(
      `SELECT grant_id, accepted_command
       FROM grant_claim
       WHERE command_state = 'accepted' AND state = 'pending'
         AND due_at <= ? AND (lease_until IS NULL OR lease_until <= ?)
         AND NOT EXISTS (
           SELECT 1 FROM transfer_preparation p
           WHERE p.org_id = grant_claim.org_id
             AND p.from_installation_id = grant_claim.installation_id
             AND p.phase <> 'completed'
         )
         AND NOT EXISTS (
           SELECT 1 FROM deletion_command d
           WHERE d.org_id = grant_claim.org_id
             AND d.installation_id = grant_claim.installation_id
             AND d.phase <> 'completed'
         )
       ORDER BY due_at, grant_id LIMIT 25`,
    ).bind(nowIso, nowIso).all<{ grant_id: string; accepted_command: string | null }>();
    let attempted = 0;
    for (const row of rows.results ?? []) {
      if (row.accepted_command === null) continue;
      let accepted: unknown;
      try {
        accepted = JSON.parse(row.accepted_command);
      } catch {
        await this.env.DB.prepare(
          `UPDATE grant_claim SET command_state = 'rejected',
             terminal_code = 'coverage_unknown', terminal_detail = 'invalid accepted command'
           WHERE grant_id = ? AND command_state = 'accepted'`,
        ).bind(row.grant_id).run();
        continue;
      }
      if (!isRecord(accepted) || !isRecord(accepted.envelope)) continue;
      attempted += 1;
      await this.grant({
        contract_version: accepted.contract_version,
        envelope: accepted.envelope,
        accepted_command_dispatch: true,
        accepted_command_grant_id: row.grant_id,
      });
    }
    return attempted;
  }

  async dispatchAcceptedTransferPreparations(): Promise<number> {
    return dispatchTransferPreparations(this.env, 25);
  }

  async dispatchDeletionCommands(): Promise<number> {
    return dispatchDueDeletionCommands(this.env, 25);
  }

  async shipDueReversalExports(): Promise<number> {
    const rows = await this.env.DB.prepare(
      `SELECT reversal_id, grant_id, request_sha256, request_body,
              route_installation_id, route_epoch, route_generation, state,
              receipt, export_payload, export_state, created_at, updated_at
       FROM reversal_command
       WHERE state = 'terminal' AND export_state = 'due'
       ORDER BY updated_at, reversal_id LIMIT 25`,
    ).all<ReversalCommandRow>();
    let shipped = 0;
    for (const command of rows.results ?? []) {
      if (await shipReversalExport(this.env, command)) shipped += 1;
    }
    return shipped;
  }
}
