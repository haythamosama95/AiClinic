import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdTransfer,
  humanRef,
  parseRegistrationAttestation,
  sha256Hex,
  subscriptionRef,
  ulid,
  validateOperation,
  verifyAccessJwt,
  verifyAssertion,
  type AccessCertsDocument,
  type Assertion,
} from "vendor-contracts";
import { raiseAlert } from "../alert/index.js";
import {
  clinicErrorResponse,
  clinicJsonResponse,
} from "../clinic-api/version.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { insertFactLog } from "../records/append.js";
import { PAYMOB_PROVIDER_ID, providerForId } from "../provider/registry.js";
import { runReconciliation } from "../reconciliation/run.js";
import { rememberOperatorCredential } from "../watch/hourly.js";
import {
  determineReversalEffect,
  insertReverseWorkRow,
  processReverseWork,
  reversalDedupeKey,
  reversalIdFromDedupeKey,
  type ReversalEnv,
} from "../work/reversal.js";
const ASSERTION_MAX_AGE_MS = 5 * 60 * 1000;

export interface OpsEnv extends ClockEnv {
  DB: D1Database;
  R2: R2Bucket;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  OPS_HOST: string;
  ABO_GRANT_KEY: string;
  PLATFORM_PUBLIC_KEYS: string;
  PLATFORM: {
    inspectCoverage(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listGrants(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    listIssuerKeys(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listServiceKeys(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listOperatorCredentials(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    recordOperatorAction(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    voidForReversal(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    getCoverage(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    grant(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    beginTransfer(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    transferOut(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    transferIn(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    releaseHeld(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    voidGrant(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listGrantsForVoid(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    suspend(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    resume(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    deleteInstallation(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    registerOperatorCredential(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    revokeOperatorCredential(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    registerIssuerKey(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    retireIssuerKey(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    revokeIssuerKey(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    registerServiceKey(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    revokeServiceKey(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    publishPlanVersion(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    retirePlanVersion(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    setCeilingPolicy(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    publishRoutingPolicy(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    canaryRoutingPolicy(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    promoteRoutingPolicy(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    rollbackRoutingPolicy(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    armKillSwitch(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    activateCohort(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    promoteCohort(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    deprecateCapability(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    retireCapability(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    beginTokenContractRotation(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    retireTokenContract(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    supportLookup(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
  };
}

type RelayPlatformMethod =
  | "registerOperatorCredential"
  | "revokeOperatorCredential"
  | "registerIssuerKey"
  | "retireIssuerKey"
  | "revokeIssuerKey"
  | "registerServiceKey"
  | "revokeServiceKey"
  | "publishPlanVersion"
  | "retirePlanVersion"
  | "setCeilingPolicy"
  | "publishRoutingPolicy"
  | "canaryRoutingPolicy"
  | "promoteRoutingPolicy"
  | "rollbackRoutingPolicy"
  | "armKillSwitch"
  | "activateCohort"
  | "promoteCohort"
  | "deprecateCapability"
  | "retireCapability"
  | "beginTokenContractRotation"
  | "retireTokenContract"
  | "supportLookup";

type HpCredential = {
  credential_id: string;
  public_key_cose: string;
  alg: string;
};

type HpOperation = {
  op: string;
  params: Record<string, unknown>;
  actor_email: string;
  issued_at: string;
  nonce: string;
  contract_version: number;
};

type VerifiedHpContext = {
  access: VerifiedAccess;
  operation: HpOperation;
  challengeSha256: string;
  credentialId: string;
  actionId: string;
};

type VerifiedAccess = {
  email: string;
  jti: string;
  jwt: string;
};

function parseJwtPayload(jwt: string): Record<string, unknown> | null {
  const parts = jwt.split(".");
  if (parts.length !== 3) {
    return null;
  }
  try {
    const segment = parts[1]!;
    const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
    const padded =
      base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
    const json = atob(padded);
    const value = JSON.parse(json) as unknown;
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    return value as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function loadAccessCerts(env: OpsEnv): Promise<AccessCertsDocument | null> {
  const issuer = `https://${env.ACCESS_TEAM_DOMAIN}`;
  try {
    const response = await fetch(`${issuer}/cdn-cgi/access/certs`);
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

async function verifyOpsAccess(
  env: OpsEnv,
  request: Request,
): Promise<VerifiedAccess | Response> {
  const contractVersion = 1;
  const header = request.headers.get("Cf-Access-Jwt-Assertion");
  if (header === null || header.length === 0) {
    return clinicErrorResponse("unauthenticated", 401, contractVersion);
  }

  const certs = await loadAccessCerts(env);
  if (certs === null) {
    return clinicErrorResponse("unauthenticated", 401, contractVersion);
  }

  const nowSeconds = Math.floor((await clockNowMs(env)) / 1000);
  const verified = await verifyAccessJwt({
    jwt: header,
    certs,
    aud: env.ACCESS_AUD,
    nowSeconds,
  });
  if (!verified.ok) {
    return clinicErrorResponse("unauthenticated", 401, contractVersion);
  }

  const payload = parseJwtPayload(header);
  const jti = payload?.jti;
  if (typeof jti !== "string" || jti.length === 0) {
    return clinicErrorResponse("unauthenticated", 401, contractVersion);
  }

  return { email: verified.email, jti, jwt: header };
}

async function distinctOrgIds(env: OpsEnv): Promise<string[]> {
  const ids = new Set<string>();
  for (const sql of [
    `SELECT DISTINCT org_id FROM billing_contact`,
    `SELECT DISTINCT org_id FROM checkout`,
    `SELECT DISTINCT org_id FROM coverage_view`,
  ]) {
    const rows = await env.DB.prepare(sql).all<{ org_id: string }>();
    for (const row of rows.results ?? []) {
      if (row.org_id.length > 0) {
        ids.add(row.org_id);
      }
    }
  }
  return [...ids];
}

async function lookupOrgId(env: OpsEnv, query: string): Promise<string | null> {
  const q = query.trim();
  if (q.length === 0) {
    return null;
  }

  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu.test(q)) {
    const row = await env.DB.prepare(
      `SELECT org_id FROM checkout WHERE org_id = ? LIMIT 1`,
    )
      .bind(q)
      .first<{ org_id: string }>();
    if (row !== null) {
      return q;
    }
    const contact = await env.DB.prepare(
      `SELECT org_id FROM billing_contact WHERE org_id = ? LIMIT 1`,
    )
      .bind(q)
      .first<{ org_id: string }>();
    if (contact !== null) {
      return q;
    }
    const view = await env.DB.prepare(
      `SELECT org_id FROM coverage_view WHERE org_id = ? LIMIT 1`,
    )
      .bind(q)
      .first<{ org_id: string }>();
    return view?.org_id ?? null;
  }

  if (q.startsWith("CK-")) {
    const row = await env.DB.prepare(
      `SELECT org_id FROM checkout WHERE reference = ? LIMIT 1`,
    )
      .bind(q)
      .first<{ org_id: string }>();
    return row?.org_id ?? null;
  }

  if (q.startsWith("PAY-")) {
    const row = await env.DB.prepare(
      `SELECT org_id FROM payment WHERE reference = ? LIMIT 1`,
    )
      .bind(q)
      .first<{ org_id: string }>();
    return row?.org_id ?? null;
  }

  if (q.startsWith("GR-")) {
    const suffix = q.slice(3);
    const rows = await env.DB.prepare(
      `SELECT grant_id, org_id FROM grant_request`,
    ).all<{ grant_id: string; org_id: string }>();
    for (const row of rows.results ?? []) {
      if (humanRef("GR", row.grant_id) === q || row.grant_id.endsWith(suffix)) {
        return row.org_id;
      }
    }
    return null;
  }

  if (q.startsWith("AIC-")) {
    for (const orgId of await distinctOrgIds(env)) {
      const ref = await subscriptionRef(orgId);
      if (ref === q) {
        return orgId;
      }
    }
    return null;
  }

  const emailRow = await env.DB.prepare(
    `SELECT org_id FROM billing_contact b1
     WHERE email = ?
       AND version = (
         SELECT MAX(version) FROM billing_contact b2 WHERE b2.org_id = b1.org_id
       )
     LIMIT 1`,
  )
    .bind(q)
    .first<{ org_id: string }>();
  return emailRow?.org_id ?? null;
}

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

function decodeAssertion(value: unknown): Assertion | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  const alg = record.alg;
  if (alg !== "ES256" && alg !== "EdDSA") {
    return null;
  }
  if (
    typeof record.authenticator_data !== "string" ||
    typeof record.client_data_json !== "string" ||
    typeof record.signature !== "string"
  ) {
    return null;
  }
  const authenticatorData = base64UrlDecode(record.authenticator_data);
  const clientDataJSON = base64UrlDecode(record.client_data_json);
  const signature = base64UrlDecode(record.signature);
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

async function listActiveHpCredentials(env: OpsEnv): Promise<HpCredential[]> {
  const envelope = await env.PLATFORM.listOperatorCredentials({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
  });
  const parsed = await parsePlatformList(envelope);
  const credentials: HpCredential[] = [];
  for (const row of parsed) {
    if (
      typeof row.credential_id === "string" &&
      typeof row.public_key_cose === "string" &&
      typeof row.alg === "string"
    ) {
      credentials.push({
        credential_id: row.credential_id,
        public_key_cose: row.public_key_cose,
        alg: row.alg,
      });
    }
  }
  return credentials;
}

async function verifyMatchingCredential(
  env: OpsEnv,
  operation: HpOperation,
  assertionRaw: unknown,
  credentials: HpCredential[],
): Promise<{ ok: true; credentialId: string } | { ok: false }> {
  const assertion = decodeAssertion(assertionRaw);
  if (assertion === null) {
    return { ok: false };
  }
  const rpId = env.OPS_HOST;
  const origin = `https://${env.OPS_HOST}`;
  for (const credential of credentials) {
    if (credential.alg !== assertion.alg) {
      continue;
    }
    if (credential.alg !== "ES256" && credential.alg !== "EdDSA") {
      continue;
    }
    const publicKeyBytes = base64UrlDecode(credential.public_key_cose);
    if (publicKeyBytes === null) {
      continue;
    }
    const parsed = await parseRegistrationAttestation({
      alg: credential.alg,
      publicKey: publicKeyBytes,
    });
    if (!parsed.ok) {
      continue;
    }
    const verified = await verifyAssertion({
      assertion,
      operation,
      rpId,
      origin,
      publicKey: parsed.publicKey,
    });
    if (verified.ok) {
      return { ok: true, credentialId: credential.credential_id };
    }
  }
  return { ok: false };
}

async function assertionChallengeUsed(
  env: OpsEnv,
  challengeSha256: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT challenge_sha256 FROM assertion_used WHERE challenge_sha256 = ?`,
  )
    .bind(challengeSha256)
    .first<{ challenge_sha256: string }>();
  return row !== null;
}

async function insertAssertionUsed(
  env: OpsEnv,
  challengeSha256: string,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO assertion_used (challenge_sha256) VALUES (?)`,
  )
    .bind(challengeSha256)
    .run();
}

async function insertOperatorAction(
  env: OpsEnv,
  row: {
    action_id: string;
    actor_email: string;
    access_jti: string;
    action: string;
    subject: string;
    params_sha256: string;
    assertion_sha256: string | null;
    result: string;
  },
  createdAt: string,
): Promise<void> {
  const canonicalRow = {
    action_id: row.action_id,
    actor_email: row.actor_email,
    access_jti: row.access_jti,
    action: row.action,
    subject: row.subject,
    params_sha256: row.params_sha256,
    assertion_sha256: row.assertion_sha256,
    result: row.result,
  };
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO operator_action (
         action_id, actor_email, access_jti, action, subject,
         params_sha256, assertion_sha256, result
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      row.action_id,
      row.actor_email,
      row.access_jti,
      row.action,
      row.subject,
      row.params_sha256,
      row.assertion_sha256,
      row.result,
    ),
    await insertFactLog(env, "operator_action", row.action_id, canonicalRow, createdAt),
  ]);
}

async function recordPlatformOperatorAction(
  env: OpsEnv,
  accessJwt: string,
  action: string,
  subject: string,
  actionId: string,
): Promise<void> {
  await env.PLATFORM.recordOperatorAction({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: accessJwt,
    action,
    subject,
    action_id: actionId,
  });
}

async function refuseHpAction(
  env: OpsEnv,
  access: VerifiedAccess,
  action: string,
  subject: string,
  params: Record<string, unknown>,
  result: string,
  contractVersion: number,
): Promise<Response> {
  const actionId = crypto.randomUUID();
  const createdAt = await clockNowIso(env);
  const paramsSha256 = await sha256Hex(canonicalize(params));
  await insertOperatorAction(
    env,
    {
      action_id: actionId,
      actor_email: access.email,
      access_jti: access.jti,
      action,
      subject,
      params_sha256: paramsSha256,
      assertion_sha256: null,
      result,
    },
    createdAt,
  );
  return clinicErrorResponse(result, 400, contractVersion);
}

async function verifyHpRequest(
  env: OpsEnv,
  access: VerifiedAccess,
  expectedOp: string,
  subject: string,
  body: Record<string, unknown>,
  contractVersion: number,
): Promise<VerifiedHpContext | Response> {
  if (body.assertion === undefined) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      isRecord(body.operation) ? (body.operation as HpOperation).params : {},
      "assertion_required",
      contractVersion,
    );
  }

  const operationRaw = body.operation;
  if (validateOperation(operationRaw).ok !== true || !isRecord(operationRaw)) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      {},
      "assertion_invalid",
      contractVersion,
    );
  }
  const operation = operationRaw as HpOperation;
  if (operation.op !== expectedOp) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      operation.params,
      "assertion_invalid",
      contractVersion,
    );
  }
  if (operation.contract_version !== contractVersion) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      operation.params,
      "assertion_invalid",
      contractVersion,
    );
  }
  if (operation.actor_email !== access.email) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      operation.params,
      "actor_email_mismatch",
      contractVersion,
    );
  }

  const issuedAtMs = Date.parse(operation.issued_at);
  const nowMs = await clockNowMs(env);
  if (
    Number.isNaN(issuedAtMs) ||
    nowMs - issuedAtMs > ASSERTION_MAX_AGE_MS ||
    issuedAtMs > nowMs + ASSERTION_MAX_AGE_MS
  ) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      operation.params,
      "assertion_expired",
      contractVersion,
    );
  }

  const challengeSha256 = await sha256Hex(canonicalize(operation));
  if (await assertionChallengeUsed(env, challengeSha256)) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      operation.params,
      "assertion_used",
      contractVersion,
    );
  }

  const credentials = await listActiveHpCredentials(env);
  const matched = await verifyMatchingCredential(
    env,
    operation,
    body.assertion,
    credentials,
  );
  if (!matched.ok) {
    return refuseHpAction(
      env,
      access,
      expectedOp,
      subject,
      operation.params,
      "credential_not_active",
      contractVersion,
    );
  }

  return {
    access,
    operation,
    challengeSha256,
    credentialId: matched.credentialId,
    actionId: crypto.randomUUID(),
  };
}

async function commitAcceptedHp(
  env: OpsEnv,
  hp: VerifiedHpContext,
  subject: string,
): Promise<void> {
  const createdAt = await clockNowIso(env);
  const paramsSha256 = await sha256Hex(canonicalize(hp.operation.params));
  await insertAssertionUsed(env, hp.challengeSha256);
  await insertOperatorAction(
    env,
    {
      action_id: hp.actionId,
      actor_email: hp.access.email,
      access_jti: hp.access.jti,
      action: hp.operation.op,
      subject,
      params_sha256: paramsSha256,
      assertion_sha256: hp.challengeSha256,
      result: "accepted",
    },
    createdAt,
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function parseHpRequestBody(
  request: Request,
): Promise<Record<string, unknown> | null> {
  try {
    const body = (await request.json()) as unknown;
    return isRecord(body) ? body : null;
  } catch {
    return null;
  }
}

async function latestPublishedOfferVersion(
  env: OpsEnv,
  offerId: string,
): Promise<number | null> {
  const row = await env.DB.prepare(
    `SELECT MAX(version) AS version
     FROM offer_event
     WHERE offer_id = ? AND kind = 'published'`,
  )
    .bind(offerId)
    .first<{ version: number | null }>();
  return row?.version ?? null;
}

async function nextOfferVersionNumber(
  env: OpsEnv,
  offerId: string,
): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT MAX(version) AS version FROM offer_version WHERE offer_id = ?`,
  )
    .bind(offerId)
    .first<{ version: number | null }>();
  return (row?.version ?? 0) + 1;
}

async function nextTermsVersionNumber(env: OpsEnv): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT MAX(terms_version) AS terms_version FROM terms_version`,
  ).first<{ terms_version: number | null }>();
  return (row?.terms_version ?? 0) + 1;
}

async function appendOfferEvent(
  env: OpsEnv,
  row: {
    offer_id: string;
    kind: string;
    version: number;
    actor: string;
    at: string;
    contract_version: number;
  },
): Promise<void> {
  const canonicalRow = {
    offer_id: row.offer_id,
    kind: row.kind,
    version: row.version,
    actor: row.actor,
    at: row.at,
    contract_version: row.contract_version,
  };
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO offer_event (
         offer_id, kind, version, actor, at, contract_version
       ) VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(
      row.offer_id,
      row.kind,
      row.version,
      row.actor,
      row.at,
      row.contract_version,
    ),
    await insertFactLog(
      env,
      "offer_event",
      `${row.offer_id}:${row.kind}:${row.version}:${row.at}`,
      canonicalRow,
      row.at,
    ),
  ]);
}

async function paymentFullyReversed(
  env: OpsEnv,
  paymentId: string,
  amountMinor: number,
): Promise<boolean> {
  const rows = await env.DB.prepare(
    `SELECT is_full, cumulative_reversed_minor
     FROM reversal WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .all<{ is_full: number; cumulative_reversed_minor: number }>();
  for (const row of rows.results ?? []) {
    if (row.is_full === 1 || row.cumulative_reversed_minor >= amountMinor) {
      return true;
    }
  }
  return false;
}

async function handleHpCatalogueAction(
  env: OpsEnv,
  offerId: string,
  hp: VerifiedHpContext,
  contractVersion: number,
): Promise<Response> {
  const nowIso = await clockNowIso(env);
  const op = hp.operation.op;

  if (op === "publish_offer") {
    const priceMinor = hp.operation.params.price_minor;
    const termsText = hp.operation.params.terms_text;
    const copy = hp.operation.params.copy;
    if (
      typeof priceMinor !== "number" ||
      typeof termsText !== "string" ||
      !isRecord(copy)
    ) {
      return refuseHpAction(
        env,
        hp.access,
        op,
        offerId,
        hp.operation.params,
        "assertion_invalid",
        contractVersion,
      );
    }

    const template = await env.DB.prepare(
      `SELECT plan_id, plan_version, term_unit, term_count, currency,
              allowance_credits, grace_days, grace_cap_rule, contract_version
       FROM offer_version
       WHERE offer_id = ?
       ORDER BY version DESC
       LIMIT 1`,
    )
      .bind(offerId)
      .first<Record<string, unknown>>();
    if (template === null) {
      return refuseHpAction(
        env,
        hp.access,
        op,
        offerId,
        hp.operation.params,
        "not_found",
        contractVersion,
      );
    }

    await commitAcceptedHp(env, hp, offerId);
    const version = await nextOfferVersionNumber(env, offerId);
    const termsVersion = await nextTermsVersionNumber(env);
    const textSha256 = await sha256Hex(new TextEncoder().encode(termsText));
    const textR2Key = `terms/en/${termsVersion}.txt`;
    await env.R2.put(textR2Key, termsText);

    const termsCanonical = {
      terms_version: termsVersion,
      locale: "en",
      text_r2_key: textR2Key,
      text_sha256: textSha256,
      published_by: hp.access.email,
      contract_version: contractVersion,
    };
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO terms_version (
           terms_version, locale, text_r2_key, text_sha256, published_by, contract_version
         ) VALUES (?, 'en', ?, ?, ?, ?)`,
      ).bind(
        termsVersion,
        textR2Key,
        textSha256,
        hp.access.email,
        contractVersion,
      ),
      await insertFactLog(
        env,
        "terms_version",
        `${termsVersion}:en`,
        termsCanonical,
        nowIso,
      ),
    ]);

    const copyJson = JSON.stringify(copy);
    const offerCanonical = {
      offer_id: offerId,
      version,
      plan_id: template.plan_id,
      plan_version: template.plan_version,
      term_unit: template.term_unit,
      term_count: template.term_count,
      price_minor: priceMinor,
      currency: template.currency,
      allowance_credits: template.allowance_credits,
      grace_days: template.grace_days,
      grace_cap_rule: template.grace_cap_rule,
      copy: copyJson,
      terms_version: termsVersion,
      published_by: hp.access.email,
      assertion_sha256: hp.challengeSha256,
      contract_version: contractVersion,
    };
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO offer_version (
           offer_id, version, plan_id, plan_version, term_unit, term_count, price_minor,
           currency, allowance_credits, grace_days, grace_cap_rule, copy, terms_version,
           published_by, assertion_sha256, contract_version
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        offerId,
        version,
        template.plan_id,
        template.plan_version,
        template.term_unit,
        template.term_count,
        priceMinor,
        template.currency,
        template.allowance_credits,
        template.grace_days,
        template.grace_cap_rule,
        copyJson,
        termsVersion,
        hp.access.email,
        hp.challengeSha256,
        contractVersion,
      ),
      await insertFactLog(
        env,
        "offer_version",
        `${offerId}:${version}`,
        offerCanonical,
        nowIso,
      ),
    ]);
    await appendOfferEvent(env, {
      offer_id: offerId,
      kind: "published",
      version,
      actor: hp.access.email,
      at: nowIso,
      contract_version: contractVersion,
    });
  } else if (op === "retire_offer" || op === "reinstate_offer") {
    const version = await latestPublishedOfferVersion(env, offerId);
    if (version === null) {
      return refuseHpAction(
        env,
        hp.access,
        op,
        offerId,
        hp.operation.params,
        "not_found",
        contractVersion,
      );
    }
    await commitAcceptedHp(env, hp, offerId);
    await appendOfferEvent(env, {
      offer_id: offerId,
      kind: op === "retire_offer" ? "retired" : "reinstated",
      version,
      actor: hp.access.email,
      at: nowIso,
      contract_version: contractVersion,
    });
  } else {
    return refuseHpAction(
      env,
      hp.access,
      op,
      offerId,
      hp.operation.params,
      "assertion_invalid",
      contractVersion,
    );
  }

  await recordPlatformOperatorAction(
    env,
    hp.access.jwt,
    hp.operation.op,
    offerId,
    hp.actionId,
  );

  return clinicJsonResponse(
    { contract_version: contractVersion, action_id: hp.actionId },
    200,
    contractVersion,
  );
}

async function handleHpReleasePayment(
  env: OpsEnv,
  paymentId: string,
  hp: VerifiedHpContext,
  contractVersion: number,
): Promise<Response> {
  const payment = await env.DB.prepare(
    `SELECT payment_id, amount_minor, disposition FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first<{ payment_id: string; amount_minor: number; disposition: string }>();
  if (payment === null || payment.disposition !== "withheld_mismatch") {
    return refuseHpAction(
      env,
      hp.access,
      hp.operation.op,
      paymentId,
      hp.operation.params,
      "payment_not_withheld",
      contractVersion,
    );
  }
  if (await paymentFullyReversed(env, paymentId, payment.amount_minor)) {
    return refuseHpAction(
      env,
      hp.access,
      hp.operation.op,
      paymentId,
      hp.operation.params,
      "payment_fully_reversed",
      contractVersion,
    );
  }

  await commitAcceptedHp(env, hp, paymentId);
  const nowIso = await clockNowIso(env);
  const grantWorkId = crypto.randomUUID();
  const paymentReleaseCanonical = {
    payment_id: paymentId,
    operator_action_id: hp.actionId,
    at: nowIso,
  };
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO payment_release (payment_id, operator_action_id, at)
       VALUES (?, ?, ?)`,
    ).bind(paymentId, hp.actionId, nowIso),
    await insertFactLog(
      env,
      "payment_release",
      paymentId,
      paymentReleaseCanonical,
      nowIso,
    ),
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) VALUES (?, 'grant', ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
    ).bind(
      grantWorkId,
      paymentId,
      `grant:${paymentId}`,
      nowIso,
      nowIso,
    ),
  ]);

  await recordPlatformOperatorAction(
    env,
    hp.access.jwt,
    hp.operation.op,
    paymentId,
    hp.actionId,
  );

  return clinicJsonResponse(
    { contract_version: contractVersion, action_id: hp.actionId },
    200,
    contractVersion,
  );
}

async function handleHpManualChargeback(
  env: OpsEnv,
  paymentId: string,
  hp: VerifiedHpContext,
  contractVersion: number,
): Promise<Response> {
  const payment = await env.DB.prepare(
    `SELECT payment_id, amount_minor FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first<{ payment_id: string; amount_minor: number }>();
  if (payment === null) {
    return refuseHpAction(
      env,
      hp.access,
      hp.operation.op,
      paymentId,
      hp.operation.params,
      "not_found",
      contractVersion,
    );
  }

  const parentTxn = await env.DB.prepare(
    `SELECT txn_id FROM paymob_txn
     WHERE payment_id = ? AND parent_txn_id IS NULL
     ORDER BY txn_id ASC LIMIT 1`,
  )
    .bind(paymentId)
    .first<{ txn_id: string }>();
  const parentRef = parentTxn?.txn_id ?? paymentId;
  const cumulative = payment.amount_minor;
  const dedupeKey = reversalDedupeKey(parentRef, cumulative);
  const existing = await env.DB.prepare(
    `SELECT 1 FROM reversal WHERE dedupe_key = ?`,
  )
    .bind(dedupeKey)
    .first();
  if (existing !== null) {
    return refuseHpAction(
      env,
      hp.access,
      hp.operation.op,
      paymentId,
      hp.operation.params,
      "reversal_exists",
      contractVersion,
    );
  }

  await commitAcceptedHp(env, hp, paymentId);
  const effect = await determineReversalEffect(
    env as ReversalEnv,
    paymentId,
    true,
  );
  const reversalId = await reversalIdFromDedupeKey(dedupeKey);
  const reference = humanRef("REV", reversalId);
  const nowIso = await clockNowIso(env);
  const reversalCanonical = {
    reversal_id: reversalId,
    payment_id: paymentId,
    reference,
    amount_minor: payment.amount_minor,
    kind: "chargeback",
    is_full: 1,
    source: "operator",
    cumulative_reversed_minor: cumulative,
    detected_via: "manual",
    recorded_by: hp.access.email,
    evidence_sha256: hp.challengeSha256,
    effect,
    dedupe_key: dedupeKey,
  };
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO reversal (
         reversal_id, payment_id, reference, amount_minor, kind, is_full,
         source, cumulative_reversed_minor, detected_via, recorded_by,
         evidence_sha256, effect, dedupe_key
       ) VALUES (?, ?, ?, ?, 'chargeback', 1, 'operator', ?, 'manual', ?, ?, ?, ?)`,
    ).bind(
      reversalId,
      paymentId,
      reference,
      payment.amount_minor,
      cumulative,
      hp.access.email,
      hp.challengeSha256,
      effect,
      dedupeKey,
    ),
    await insertFactLog(env, "reversal", reversalId, reversalCanonical, nowIso),
  ]);

  await raiseAlert(env, "AL-06", `AL-06:${reversalId}`, reversalId);
  await insertReverseWorkRow(env as ReversalEnv, reversalId);
  const reverseWork = await env.DB.prepare(
    `SELECT work_id FROM work WHERE dedupe_key = ?`,
  )
    .bind(`reverse:${reversalId}`)
    .first<{ work_id: string }>();
  if (reverseWork !== null) {
    await processReverseWork(env as ReversalEnv, reverseWork.work_id);
  }

  await recordPlatformOperatorAction(
    env,
    hp.access.jwt,
    hp.operation.op,
    paymentId,
    hp.actionId,
  );

  return clinicJsonResponse(
    { contract_version: contractVersion, action_id: hp.actionId },
    200,
    contractVersion,
  );
}

async function deleteTenantEvidenceBodies(
  env: OpsEnv,
  orgId: string,
): Promise<void> {
  const keys = new Set<string>();
  const notifications = await env.DB.prepare(
    `SELECT n.body_r2_key
     FROM notification n
     WHERE n.body_r2_key != ''
       AND (
         n.checkout_id IN (SELECT checkout_id FROM checkout WHERE org_id = ?)
         OR n.body_sha256 IN (
           SELECT evidence_sha256 FROM payment
           WHERE org_id = ? AND evidence_sha256 != ''
         )
       )`,
  )
    .bind(orgId, orgId)
    .all<{ body_r2_key: string }>();
  for (const row of notifications.results ?? []) {
    keys.add(row.body_r2_key);
  }
  const inquiryRows = await env.DB.prepare(
    `SELECT ir.raw_r2_key
     FROM inquiry_result ir
     WHERE ir.raw_r2_key != ''
       AND ir.subject IN (
         SELECT 'checkout:' || checkout_id FROM checkout WHERE org_id = ?
       )`,
  )
    .bind(orgId)
    .all<{ raw_r2_key: string }>();
  for (const row of inquiryRows.results ?? []) {
    keys.add(row.raw_r2_key);
  }
  for (const key of keys) {
    await env.R2.delete(key);
  }
}

async function handleHpEraseContact(
  env: OpsEnv,
  orgId: string,
  hp: VerifiedHpContext,
  contractVersion: number,
): Promise<Response> {
  const contact = await env.DB.prepare(
    `SELECT 1 AS present FROM billing_contact WHERE org_id = ? LIMIT 1`,
  )
    .bind(orgId)
    .first<{ present: number }>();
  if (contact?.present !== 1) {
    return refuseHpAction(
      env,
      hp.access,
      hp.operation.op,
      orgId,
      hp.operation.params,
      "not_found",
      contractVersion,
    );
  }

  await commitAcceptedHp(env, hp, orgId);
  const nowIso = await clockNowIso(env);
  await env.DB.prepare(
    `UPDATE billing_contact
     SET name = '', email = '', phone = '', erased_at = ?, erased_by = ?
     WHERE org_id = ?`,
  )
    .bind(nowIso, hp.access.email, orgId)
    .run();
  await deleteTenantEvidenceBodies(env, orgId);

  await recordPlatformOperatorAction(
    env,
    hp.access.jwt,
    hp.operation.op,
    orgId,
    hp.actionId,
  );

  return clinicJsonResponse(
    { contract_version: contractVersion, action_id: hp.actionId },
    200,
    contractVersion,
  );
}

async function handleHpPost(
  env: OpsEnv,
  access: VerifiedAccess,
  expectedOp: string,
  subject: string,
  request: Request,
  contractVersion: number,
  execute: (
    env: OpsEnv,
    subject: string,
    hp: VerifiedHpContext,
    contractVersion: number,
  ) => Promise<Response>,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }
  const verified = await verifyHpRequest(
    env,
    access,
    expectedOp,
    subject,
    body,
    contractVersion,
  );
  if (verified instanceof Response) {
    return verified;
  }
  return execute(env, subject, verified, contractVersion);
}

async function handleGetLookup(
  env: OpsEnv,
  query: string,
  contractVersion: number,
): Promise<Response> {
  const orgId = await lookupOrgId(env, query);
  if (orgId === null) {
    return clinicErrorResponse("not_found", 404, contractVersion);
  }
  return clinicJsonResponse(
    { contract_version: contractVersion, org_id: orgId },
    200,
    contractVersion,
  );
}

async function loadCheckoutEvents(
  env: OpsEnv,
  checkoutId: string,
): Promise<Array<Record<string, unknown>>> {
  const rows = await env.DB.prepare(
    `SELECT checkout_id, kind, source, ref, actor, at, contract_version
     FROM checkout_event WHERE checkout_id = ? ORDER BY at ASC`,
  )
    .bind(checkoutId)
    .all<Record<string, unknown>>();
  return rows.results ?? [];
}

async function handleGetClinic(
  env: OpsEnv,
  orgId: string,
  access: VerifiedAccess,
  contractVersion: number,
): Promise<Response> {
  const coverage = await env.PLATFORM.getCoverage({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    org_id: orgId,
  });
  if (coverage.result !== "ok" || typeof coverage.detail !== "string") {
    return clinicErrorResponse(
      typeof coverage.code === "string" ? coverage.code : "coverage_unknown",
      404,
      contractVersion,
    );
  }

  const coverageParsed = JSON.parse(coverage.detail) as {
    snapshot?: Record<string, unknown>;
  };
  const snapshot = coverageParsed.snapshot ?? {};
  const bindingEpoch = snapshot.binding_epoch;

  const inspectCoverage = await env.PLATFORM.inspectCoverage({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    org_id: orgId,
  });
  if (inspectCoverage.result !== "ok" || typeof inspectCoverage.detail !== "string") {
    return clinicErrorResponse(
      typeof inspectCoverage.code === "string"
        ? inspectCoverage.code
        : "coverage_unknown",
      404,
      contractVersion,
    );
  }

  const coverageDetail = JSON.parse(inspectCoverage.detail) as Record<
    string,
    unknown
  >;

  const checkoutRows = await env.DB.prepare(
    `SELECT c.*, cs.state, cs.last_event_at
     FROM checkout c
     LEFT JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
     WHERE c.org_id = ?
     ORDER BY c.checkout_id ASC`,
  )
    .bind(orgId)
    .all<Record<string, unknown>>();

  const checkouts: Array<Record<string, unknown>> = [];
  for (const row of checkoutRows.results ?? []) {
    const checkoutId = String(row.checkout_id);
    checkouts.push({
      ...row,
      events: await loadCheckoutEvents(env, checkoutId),
    });
  }

  const paymentRows = await env.DB.prepare(
    `SELECT payment_id, reference, checkout_id, amount_minor, currency,
            classification, disposition, paid_at
     FROM payment WHERE org_id = ? ORDER BY paid_at ASC`,
  )
    .bind(orgId)
    .all<Record<string, unknown>>();
  const payments = paymentRows.results ?? [];

  const reversalRows = await env.DB.prepare(
    `SELECT r.*
     FROM reversal r
     INNER JOIN payment p ON p.payment_id = r.payment_id
     WHERE p.org_id = ?
     ORDER BY r.reference ASC`,
  )
    .bind(orgId)
    .all<Record<string, unknown>>();
  const reversals = reversalRows.results ?? [];

  const grantRows = await env.DB.prepare(
    `SELECT gr.grant_id, gr.org_id, gr.source_kind, gr.source_ref,
            go.result AS outcome_result, go.receipt, go.at AS outcome_at
     FROM grant_request gr
     LEFT JOIN grant_outcome go ON go.grant_id = gr.grant_id
     WHERE gr.org_id = ?
     ORDER BY gr.grant_id ASC`,
  )
    .bind(orgId)
    .all<Record<string, unknown>>();

  const grant_requests = (grantRows.results ?? []).map((row) => ({
    grant_id: row.grant_id,
    org_id: row.org_id,
    source_kind: row.source_kind,
    source_ref: row.source_ref,
    grant_outcome: row.outcome_result
      ? { result: row.outcome_result, at: row.outcome_at }
      : null,
    receipt:
      typeof row.receipt === "string" ? JSON.parse(row.receipt) : row.receipt,
  }));

  const operatorRows = await env.DB.prepare(
    `SELECT oa.*
     FROM operator_action oa
     WHERE oa.subject = ?
        OR oa.subject IN (SELECT checkout_id FROM checkout WHERE org_id = ?)
        OR oa.subject IN (
          SELECT w.work_id
          FROM work w
          INNER JOIN payment p ON p.payment_id = w.subject_id
          WHERE p.org_id = ?
        )
     ORDER BY oa.action_id ASC`,
  )
    .bind(orgId, orgId, orgId)
    .all<Record<string, unknown>>();
  const operator_actions = operatorRows.results ?? [];

  const findingRows = await env.DB.prepare(
    `SELECT f.*
     FROM finding f
     WHERE f.subject IN (SELECT checkout_id FROM checkout WHERE org_id = ?)
        OR f.subject IN (
          SELECT r.reversal_id
          FROM reversal r
          INNER JOIN payment p ON p.payment_id = r.payment_id
          WHERE p.org_id = ?
        )
        OR f.detail LIKE ?
     ORDER BY f.detected_at ASC`,
  )
    .bind(orgId, orgId, `%${orgId}%`)
    .all<Record<string, unknown>>();
  const findings = findingRows.results ?? [];

  const alertRows = await env.DB.prepare(
    `SELECT a.*
     FROM alert a
     WHERE a.active = 1
       AND (
         a.alert_key LIKE '%' || ? || '%'
         OR EXISTS (
           SELECT 1 FROM checkout c
           WHERE c.org_id = ? AND a.alert_key LIKE '%' || c.checkout_id || '%'
         )
         OR EXISTS (
           SELECT 1 FROM payment p
           WHERE p.org_id = ? AND a.alert_key LIKE '%' || p.payment_id || '%'
         )
       )
     ORDER BY a.alert_key ASC`,
  )
    .bind(orgId, orgId, orgId)
    .all<Record<string, unknown>>();
  const alerts = alertRows.results ?? [];

  return clinicJsonResponse(
    {
      contract_version: contractVersion,
      binding_epoch: bindingEpoch,
      terms: coverageDetail.terms,
      grants: coverageDetail.grants,
      reservations: coverageDetail.reservations,
      checkouts,
      payments,
      reversals,
      grant_requests,
      operator_actions,
      findings,
      alerts,
    },
    200,
    contractVersion,
  );
}

async function handleGetParked(
  env: OpsEnv,
  contractVersion: number,
): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT work_id, kind, subject_id, state, attempts, next_attempt_at,
            lease_until, last_error, opened_at
     FROM work WHERE state = 'parked'
     ORDER BY opened_at ASC`,
  ).all<Record<string, unknown>>();
  return clinicJsonResponse(
    { contract_version: contractVersion, parked: rows.results ?? [] },
    200,
    contractVersion,
  );
}

async function handleGetFindings(
  env: OpsEnv,
  contractVersion: number,
): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT finding_id, kind, subject, detail, detected_at
     FROM finding ORDER BY detected_at ASC`,
  ).all<Record<string, unknown>>();
  return clinicJsonResponse(
    { contract_version: contractVersion, findings: rows.results ?? [] },
    200,
    contractVersion,
  );
}

function groupGrants(
  grants: Array<Record<string, unknown>>,
): {
  by_source_kind: Record<string, Array<Record<string, unknown>>>;
  by_operator_credential_id: Record<string, Array<Record<string, unknown>>>;
} {
  const by_source_kind: Record<string, Array<Record<string, unknown>>> = {};
  const by_operator_credential_id: Record<
    string,
    Array<Record<string, unknown>>
  > = {};
  for (const grant of grants) {
    const sourceKind = String(grant.source_kind ?? "unknown");
    const credentialId = String(grant.operator_credential_id ?? "unknown");
    (by_source_kind[sourceKind] ??= []).push(grant);
    (by_operator_credential_id[credentialId] ??= []).push(grant);
  }
  return { by_source_kind, by_operator_credential_id };
}

async function handleGetGrants(
  env: OpsEnv,
  contractVersion: number,
): Promise<Response> {
  const envelope = await env.PLATFORM.listGrants({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
  });
  const grants =
    envelope.result === "ok" && typeof envelope.detail === "string"
      ? (JSON.parse(envelope.detail) as Array<Record<string, unknown>>)
      : [];
  const grouped = groupGrants(grants);
  return clinicJsonResponse(
    {
      contract_version: contractVersion,
      ...grouped,
    },
    200,
    contractVersion,
  );
}

async function handleGetPayoutImports(
  contractVersion: number,
): Promise<Response> {
  return clinicJsonResponse(
    { contract_version: contractVersion, payout_imports: [] },
    200,
    contractVersion,
  );
}

async function newOpsId(env: OpsEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

function periodFromSettledAt(settledAt: string): string {
  const parsed = Date.parse(settledAt);
  const date = Number.isNaN(parsed) ? new Date(settledAt) : new Date(parsed);
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

async function handlePostPayoutImport(
  env: OpsEnv,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const bytes = new Uint8Array(await request.arrayBuffer());
  const fileSha256 = await sha256Hex(bytes);
  const r2Key = `payouts/${fileSha256}`;
  await env.R2.put(r2Key, bytes);

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return clinicErrorResponse("internal_error", 500, contractVersion);
  }
  const lines = await provider.payoutLines(bytes);
  const period =
    lines.length > 0
      ? periodFromSettledAt(lines[0]!.settled_at)
      : (await clockNowIso(env)).slice(0, 7);

  const importId = await newOpsId(env);
  const actionId = crypto.randomUUID();
  const createdAt = await clockNowIso(env);
  const importCanonical = {
    import_id: importId,
    provider_id: PAYMOB_PROVIDER_ID,
    file_sha256: fileSha256,
    r2_key: r2Key,
    imported_by: access.email,
    period,
  };
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `INSERT INTO payout_import (
         import_id, provider_id, file_sha256, r2_key, imported_by, period
       ) VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(
      importId,
      PAYMOB_PROVIDER_ID,
      fileSha256,
      r2Key,
      access.email,
      period,
    ),
    await insertFactLog(env, "payout_import", importId, importCanonical, createdAt),
  ];

  for (let lineNo = 0; lineNo < lines.length; lineNo += 1) {
    const line = lines[lineNo]!;
    const lineCanonical = {
      import_id: importId,
      line_no: lineNo + 1,
      kind: line.kind,
      gross_minor: line.gross_minor,
      fee_minor: line.fee_minor,
      net_minor: line.net_minor,
      settled_at: line.settled_at,
      payment_id: line.payment_id,
    };
    statements.push(
      env.DB.prepare(
        `INSERT INTO payout_line (
           import_id, line_no, kind, gross_minor, fee_minor, net_minor,
           settled_at, payment_id
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        importId,
        lineNo + 1,
        line.kind,
        line.gross_minor,
        line.fee_minor,
        line.net_minor,
        line.settled_at,
        line.payment_id,
      ),
      await insertFactLog(
        env,
        "payout_line",
        `${importId}:${lineNo + 1}`,
        lineCanonical,
        createdAt,
      ),
    );
  }
  await env.DB.batch(statements);

  const action = "Import a payout CSV";
  const paramsSha256 = await sha256Hex(
    canonicalize({ action, subject: importId }),
  );
  await insertOperatorAction(
    env,
    {
      action_id: actionId,
      actor_email: access.email,
      access_jti: access.jti,
      action,
      subject: importId,
      params_sha256: paramsSha256,
      assertion_sha256: null,
      result: "accepted",
    },
    createdAt,
  );
  await recordPlatformOperatorAction(
    env,
    access.jwt,
    action,
    importId,
    actionId,
  );

  await runReconciliation(env);

  return clinicJsonResponse(
    {
      contract_version: contractVersion,
      import_id: importId,
      action_id: actionId,
    },
    200,
    contractVersion,
  );
}

async function handlePostResolveFinding(
  env: OpsEnv,
  findingId: string,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const finding = await env.DB.prepare(
    `SELECT finding_id FROM finding WHERE finding_id = ?`,
  )
    .bind(findingId)
    .first<{ finding_id: string }>();
  if (finding === null) {
    return clinicErrorResponse("not_found", 404, contractVersion);
  }

  let body: Record<string, unknown> | null = null;
  try {
    const parsed = (await request.json()) as unknown;
    body = isRecord(parsed) ? parsed : null;
  } catch {
    body = null;
  }
  const note = body?.note;
  if (typeof note !== "string") {
    return clinicErrorResponse("invalid_request", 400, contractVersion);
  }

  const existing = await env.DB.prepare(
    `SELECT finding_id FROM finding_resolution WHERE finding_id = ?`,
  )
    .bind(findingId)
    .first();
  const createdAt = await clockNowIso(env);
  if (existing === null) {
    const resolutionCanonical = {
      finding_id: findingId,
      resolved_by: access.email,
      note,
      at: createdAt,
    };
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO finding_resolution (finding_id, resolved_by, note, at)
         VALUES (?, ?, ?, ?)`,
      ).bind(findingId, access.email, note, createdAt),
      await insertFactLog(
        env,
        "finding_resolution",
        findingId,
        resolutionCanonical,
        createdAt,
      ),
    ]);
  }

  const action = "Resolve a finding";
  const actionId = crypto.randomUUID();
  const paramsSha256 = await sha256Hex(
    canonicalize({ action, subject: findingId, note }),
  );
  await insertOperatorAction(
    env,
    {
      action_id: actionId,
      actor_email: access.email,
      access_jti: access.jti,
      action,
      subject: findingId,
      params_sha256: paramsSha256,
      assertion_sha256: null,
      result: "accepted",
    },
    createdAt,
  );
  await recordPlatformOperatorAction(
    env,
    access.jwt,
    action,
    findingId,
    actionId,
  );

  return clinicJsonResponse(
    { contract_version: contractVersion, action_id: actionId },
    200,
    contractVersion,
  );
}

async function parsePlatformList(
  envelope: Record<string, unknown>,
): Promise<Array<Record<string, unknown>>> {
  if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
    return [];
  }
  const parsed = JSON.parse(envelope.detail) as unknown;
  return Array.isArray(parsed)
    ? (parsed as Array<Record<string, unknown>>)
    : [];
}

async function handleGetRegistries(
  env: OpsEnv,
  contractVersion: number,
): Promise<Response> {
  const contractArgs = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
  };
  const [issuerKeys, serviceKeys, operatorCredentials] = await Promise.all([
    env.PLATFORM.listIssuerKeys(contractArgs),
    env.PLATFORM.listServiceKeys(contractArgs),
    env.PLATFORM.listOperatorCredentials(contractArgs),
  ]);
  return clinicJsonResponse(
    {
      contract_version: contractVersion,
      issuer_keys: await parsePlatformList(issuerKeys),
      service_keys: await parsePlatformList(serviceKeys),
      operator_credentials: await parsePlatformList(operatorCredentials),
    },
    200,
    contractVersion,
  );
}

async function handlePostRetry(
  env: OpsEnv,
  workId: string,
  access: VerifiedAccess,
  contractVersion: number,
): Promise<Response> {
  const work = await env.DB.prepare(
    `SELECT work_id, kind, state FROM work WHERE work_id = ?`,
  )
    .bind(workId)
    .first<{ work_id: string; kind: string; state: string }>();
  if (work === null || work.kind !== "grant" || work.state !== "parked") {
    return clinicErrorResponse("not_found", 404, contractVersion);
  }

  await env.DB.prepare(
    `UPDATE work
     SET state = 'open', lease_until = NULL, last_error = NULL, next_attempt_at = NULL
     WHERE work_id = ?`,
  )
    .bind(workId)
    .run();

  const action = "Retry parked work";
  const actionId = crypto.randomUUID();
  const paramsSha256 = await sha256Hex(canonicalize({ action, subject: workId }));
  const createdAt = await clockNowIso(env);

  await insertOperatorAction(
    env,
    {
      action_id: actionId,
      actor_email: access.email,
      access_jti: access.jti,
      action,
      subject: workId,
      params_sha256: paramsSha256,
      assertion_sha256: null,
      result: "open",
    },
    createdAt,
  );

  await recordPlatformOperatorAction(
    env,
    access.jwt,
    action,
    workId,
    actionId,
  );

  return clinicJsonResponse(
    { contract_version: contractVersion, action_id: actionId },
    200,
    contractVersion,
  );
}

async function handlePostCancel(
  env: OpsEnv,
  checkoutId: string,
  access: VerifiedAccess,
  contractVersion: number,
): Promise<Response> {
  const status = await env.DB.prepare(
    `SELECT state FROM checkout_status WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ state: string }>();
  if (status === null || status.state !== "open") {
    return clinicErrorResponse("not_found", 404, contractVersion);
  }

  const actionId = crypto.randomUUID();
  const nowIso = await clockNowIso(env);

  await env.DB.prepare(
    `UPDATE checkout_status SET state = 'cancelled', last_event_at = ? WHERE checkout_id = ?`,
  )
    .bind(nowIso, checkoutId)
    .run();

  await env.DB.prepare(
    `INSERT INTO checkout_event (
       checkout_id, kind, source, ref, actor, at, contract_version
     ) VALUES (?, 'cancelled', 'operator', ?, ?, ?, ?)`,
  )
    .bind(
      checkoutId,
      actionId,
      access.email,
      nowIso,
      CHANNEL_VERSIONS.vendorEntrypoint,
    )
    .run();

  const action = "Cancel an open checkout";
  const paramsSha256 = await sha256Hex(
    canonicalize({ action, subject: checkoutId }),
  );

  await insertOperatorAction(
    env,
    {
      action_id: actionId,
      actor_email: access.email,
      access_jti: access.jti,
      action,
      subject: checkoutId,
      params_sha256: paramsSha256,
      assertion_sha256: null,
      result: "cancelled",
    },
    nowIso,
  );

  await recordPlatformOperatorAction(
    env,
    access.jwt,
    action,
    checkoutId,
    actionId,
  );

  return clinicJsonResponse(
    { contract_version: contractVersion, action_id: actionId },
    200,
    contractVersion,
  );
}

const TRANSFER_LEASE_MS = 60_000;
const TRANSFER_BATCH_LIMIT = 50;

type TransferWorkRow = {
  work_id: string;
  kind: string;
  subject_id: string;
  state: string;
  attempts: number;
  next_attempt_at: string | null;
  lease_until: string | null;
  last_error: string | null;
};

async function operatorActionExists(
  env: OpsEnv,
  actionId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM operator_action WHERE action_id = ?`,
  )
    .bind(actionId)
    .first();
  return row !== null;
}

async function grantRequestExists(
  env: OpsEnv,
  grantId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM grant_request WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first();
  return row !== null;
}

async function relayFactLogStatement(
  env: OpsEnv,
  table: string,
  key: string,
  canonicalRow: Record<string, unknown>,
  createdAt: string,
): Promise<D1PreparedStatement> {
  return insertFactLog(env, table, key, canonicalRow, createdAt);
}

function complimentaryGrantRequestCanonical(input: {
  grantId: string;
  orgId: string;
  actionId: string;
  envelopeText: string;
  envelopeSha256: string;
  assertion: string | null;
}): Record<string, unknown> {
  return {
    grant_id: input.grantId,
    org_id: input.orgId,
    source_kind: "complimentary",
    source_ref: input.actionId,
    envelope: input.envelopeText,
    envelope_sha256: input.envelopeSha256,
    assertion: input.assertion,
  };
}

function relayGrantOutcomeCanonical(input: {
  grantId: string;
  result: string;
  receipt: Record<string, unknown> | null;
  termIds: string[] | null;
  at: string;
}): Record<string, unknown> {
  return {
    grant_id: input.grantId,
    result: input.result,
    abo_kid: null,
    abo_signature: null,
    receipt: input.receipt === null ? null : JSON.stringify(input.receipt),
    term_ids: input.termIds === null ? null : JSON.stringify(input.termIds),
    at: input.at,
  };
}

function transferGrantRequestCanonical(input: {
  grantId: string;
  orgId: string;
  transferId: string;
  envelopeText: string;
  envelopeSha256: string;
}): Record<string, unknown> {
  return {
    grant_id: input.grantId,
    org_id: input.orgId,
    source_kind: "transfer",
    source_ref: input.transferId,
    envelope: input.envelopeText,
    envelope_sha256: input.envelopeSha256,
    assertion: null,
  };
}

async function insertRelayOperatorAction(
  env: OpsEnv,
  row: {
    action_id: string;
    actor_email: string;
    access_jti: string;
    action: string;
    subject: string;
    params_sha256: string;
    assertion_sha256: string | null;
    result: string;
  },
): Promise<void> {
  if (await operatorActionExists(env, row.action_id)) {
    return;
  }
  const createdAt = await clockNowIso(env);
  await insertOperatorAction(env, row, createdAt);
}

async function recordComplimentaryGrantRows(
  env: OpsEnv,
  input: {
    grantId: string;
    orgId: string;
    actionId: string;
    envelope: Record<string, unknown>;
    assertion: unknown;
    platformResult: Record<string, unknown>;
  },
): Promise<void> {
  const result = String(input.platformResult.result ?? "");
  if (
    result !== "applied" &&
    result !== "already_applied" &&
    result !== "rejected" &&
    result !== "conflict"
  ) {
    return;
  }

  const envelopeBytes = canonicalize(input.envelope);
  const envelopeText = new TextDecoder().decode(envelopeBytes);
  const envelopeSha256 = await sha256Hex(envelopeBytes);
  const assertionText =
    input.assertion === undefined || input.assertion === null
      ? null
      : JSON.stringify(input.assertion);

  const nowIso = await clockNowIso(env);
  const requestCanonical = complimentaryGrantRequestCanonical({
    grantId: input.grantId,
    orgId: input.orgId,
    actionId: input.actionId,
    envelopeText,
    envelopeSha256,
    assertion: assertionText,
  });
  const receipt =
    typeof input.platformResult.receipt === "object" &&
    input.platformResult.receipt !== null &&
    !Array.isArray(input.platformResult.receipt)
      ? (input.platformResult.receipt as Record<string, unknown>)
      : null;
  const termIds =
    receipt !== null && Array.isArray(receipt.term_ids)
      ? receipt.term_ids.filter(
          (value): value is string => typeof value === "string",
        )
      : null;
  const outcomeCanonical = relayGrantOutcomeCanonical({
    grantId: input.grantId,
    result,
    receipt,
    termIds,
    at: nowIso,
  });
  const statements: D1PreparedStatement[] = [];
  if (!(await grantRequestExists(env, input.grantId))) {
    statements.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO grant_request (
           grant_id, org_id, source_kind, source_ref, envelope, envelope_sha256, assertion
         ) VALUES (?, ?, 'complimentary', ?, ?, ?, ?)`,
      ).bind(
        input.grantId,
        input.orgId,
        input.actionId,
        envelopeText,
        envelopeSha256,
        assertionText,
      ),
    );
  }
  statements.push(
    env.DB.prepare(
      `INSERT OR IGNORE INTO grant_outcome (
         grant_id, result, abo_kid, abo_signature, receipt, term_ids, at
       ) VALUES (?, ?, NULL, NULL, ?, ?, ?)`,
    ).bind(
      input.grantId,
      result,
      receipt === null ? null : JSON.stringify(receipt),
      termIds === null ? null : JSON.stringify(termIds),
      nowIso,
    ),
    await relayFactLogStatement(
      env,
      "grant_request",
      input.grantId,
      requestCanonical,
      nowIso,
    ),
    await relayFactLogStatement(
      env,
      "grant_outcome",
      input.grantId,
      outcomeCanonical,
      nowIso,
    ),
  );
  await env.DB.batch(statements);
}

async function forwardPlatformRelay(
  env: OpsEnv,
  access: VerifiedAccess,
  contractVersion: number,
  input: {
    method: RelayPlatformMethod;
    subject: string;
    actionId: string;
    platformArgs: Record<string, unknown>;
    params: Record<string, unknown>;
  },
): Promise<Response> {
  const platformResult = await env.PLATFORM[input.method](input.platformArgs);
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(canonicalize(input.params));
  const operation = input.platformArgs.operation;
  const assertionSha256 =
    input.platformArgs.assertion !== undefined && isRecord(operation)
      ? await sha256Hex(canonicalize(operation))
      : null;

  await insertRelayOperatorAction(env, {
    action_id: input.actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: input.method,
    subject: input.subject,
    params_sha256: paramsSha256,
    assertion_sha256: assertionSha256,
    result,
  });

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostRegisterOperatorCredential(
  env: OpsEnv,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  const credentialId = body.credential_id;
  if (typeof actionId !== "string" || typeof credentialId !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformArgs: Record<string, unknown> = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    credential_id: credentialId,
    attestation: body.attestation,
  };
  if (body.operation !== undefined) {
    platformArgs.operation = body.operation;
  }
  if (body.assertion !== undefined) {
    platformArgs.assertion = body.assertion;
  }
  if (body.signer_credential_id !== undefined) {
    platformArgs.signer_credential_id = body.signer_credential_id;
  }

  const params: Record<string, unknown> = { credential_id: credentialId };
  if (body.attestation !== undefined) {
    params.attestation = body.attestation;
  }

  const platformResult = await env.PLATFORM.registerOperatorCredential(
    platformArgs,
  );
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(canonicalize(params));
  const operation = platformArgs.operation;
  const assertionSha256 =
    platformArgs.assertion !== undefined && isRecord(operation)
      ? await sha256Hex(canonicalize(operation))
      : null;

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: "registerOperatorCredential",
    subject: credentialId,
    params_sha256: paramsSha256,
    assertion_sha256: assertionSha256,
    result,
  });

  if (result === "ok" && platformResult.detail !== undefined) {
    let detail: unknown = platformResult.detail;
    if (typeof detail === "string") {
      try {
        detail = JSON.parse(detail) as unknown;
      } catch {
        detail = null;
      }
    }
    if (
      isRecord(detail) &&
      typeof detail.credential_id === "string" &&
      typeof detail.public_key_cose === "string" &&
      typeof detail.alg === "string"
    ) {
      await rememberOperatorCredential(env.DB, {
        credential_id: detail.credential_id,
        public_key_cose: detail.public_key_cose,
        alg: detail.alg,
      });
    }
  }

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostRevokeOperatorCredential(
  env: OpsEnv,
  access: VerifiedAccess,
  credentialId: string,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  if (typeof actionId !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformArgs: Record<string, unknown> = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    credential_id: credentialId,
    operation: body.operation,
    assertion: body.assertion,
    signer_credential_id: body.signer_credential_id,
  };

  return forwardPlatformRelay(env, access, contractVersion, {
    method: "revokeOperatorCredential",
    subject: credentialId,
    actionId,
    platformArgs,
    params: { credential_id: credentialId },
  });
}

function pickBodyFields(
  body: Record<string, unknown>,
  fields: string[],
): Record<string, unknown> {
  const picked: Record<string, unknown> = {};
  for (const field of fields) {
    if (body[field] !== undefined) {
      picked[field] = body[field];
    }
  }
  return picked;
}

function planVersionSubject(body: Record<string, unknown>): string {
  const planId = typeof body.plan_id === "string" ? body.plan_id : "";
  const version =
    typeof body.version === "number" ? String(body.version) : "";
  return `${planId}:${version}`;
}

function routingPolicySubject(body: Record<string, unknown>): string {
  const policyId = typeof body.policy_id === "string" ? body.policy_id : "";
  const version = typeof body.version === "string" ? body.version : "";
  return `${policyId}:${version}`;
}

function publishedRoutingPolicySubject(body: Record<string, unknown>): string {
  const document = body.document;
  if (!isRecord(document)) {
    return "";
  }
  const policyId =
    typeof document.policy_id === "string" ? document.policy_id : "";
  const version =
    typeof document.policy_version === "number"
      ? String(document.policy_version)
      : "";
  return `${policyId}:${version}`;
}

function killSwitchSubject(body: Record<string, unknown>): string {
  const scope = typeof body.scope === "string" ? body.scope : "";
  const target = typeof body.target === "string" ? body.target : "";
  return `${scope}:${target}`;
}

async function handlePostConfigurationHpRelay(
  env: OpsEnv,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
  method: RelayPlatformMethod,
  subject:
    | string
    | ((body: Record<string, unknown>) => string),
  bodyFields: string[],
  extraFields?: Record<string, unknown>,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  if (typeof actionId !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const forwarded = {
    ...pickBodyFields(body, bodyFields),
    ...extraFields,
  };
  const platformArgs: Record<string, unknown> = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    operation: body.operation,
    assertion: body.assertion,
    signer_credential_id: body.signer_credential_id,
    ...forwarded,
  };

  const resolvedSubject =
    typeof subject === "function" ? subject(body) : subject;

  return forwardPlatformRelay(env, access, contractVersion, {
    method,
    subject: resolvedSubject,
    actionId,
    platformArgs,
    params: forwarded,
  });
}

async function handlePostConfigurationClassHRelay(
  env: OpsEnv,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
  method: RelayPlatformMethod,
  subject:
    | string
    | ((body: Record<string, unknown>) => string),
  bodyFields: string[],
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  if (typeof actionId !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const forwarded = pickBodyFields(body, bodyFields);
  const platformArgs: Record<string, unknown> = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    ...forwarded,
  };

  const resolvedSubject =
    typeof subject === "function" ? subject(body) : subject;

  return forwardPlatformRelay(env, access, contractVersion, {
    method,
    subject: resolvedSubject,
    actionId,
    platformArgs,
    params: forwarded,
  });
}

async function handleGetSupportLookup(
  env: OpsEnv,
  access: VerifiedAccess,
  reference: string,
  contractVersion: number,
): Promise<Response> {
  const platformArgs: Record<string, unknown> = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    reference,
  };

  return forwardPlatformRelay(env, access, contractVersion, {
    method: "supportLookup",
    subject: reference,
    actionId: crypto.randomUUID(),
    platformArgs,
    params: { reference },
  });
}

function platformResponseJson(
  platformResult: Record<string, unknown>,
  contractVersion: number,
): Response {
  const body: Record<string, unknown> = {
    contract_version: contractVersion,
    result: platformResult.result,
  };
  if (typeof platformResult.code === "string" && platformResult.code.length > 0) {
    body.code = platformResult.code;
  }
  if (platformResult.detail !== undefined) {
    body.detail = platformResult.detail;
  }
  if (platformResult.receipt !== undefined) {
    body.receipt = platformResult.receipt;
  }
  return clinicJsonResponse(body, 200, contractVersion);
}

async function handlePostComplimentaryGrant(
  env: OpsEnv,
  orgId: string,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  if (typeof actionId !== "string" || actionId.length === 0) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const envelope = body.envelope;
  if (!isRecord(envelope)) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformArgs: Record<string, unknown> = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    envelope,
    operation: body.operation,
    signer_credential_id: body.signer_credential_id,
  };
  if (body.assertion !== undefined) {
    platformArgs.assertion = body.assertion;
  }
  if (body.ceiling_override_operation !== undefined) {
    platformArgs.ceiling_override_operation = body.ceiling_override_operation;
  }

  const platformResult = await env.PLATFORM.grant(platformArgs);
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(
    canonicalize({ org_id: orgId, action_id: actionId }),
  );
  const operation = body.operation;
  const assertionSha256 =
    isRecord(operation)
      ? await sha256Hex(canonicalize(operation))
      : null;

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: "grant",
    subject: orgId,
    params_sha256: paramsSha256,
    assertion_sha256: assertionSha256,
    result,
  });

  const grantId = await grantIdComp(actionId);
  await recordComplimentaryGrantRows(env, {
    grantId,
    orgId,
    actionId,
    envelope,
    assertion: body.assertion,
    platformResult,
  });

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostSuspend(
  env: OpsEnv,
  orgId: string,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  const reason = body.reason;
  if (typeof actionId !== "string" || typeof reason !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformResult = await env.PLATFORM.suspend({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    org_id: orgId,
    reason,
  });
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(
    canonicalize({ org_id: orgId, reason }),
  );

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: "suspend",
    subject: orgId,
    params_sha256: paramsSha256,
    assertion_sha256: null,
    result,
  });

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostResume(
  env: OpsEnv,
  orgId: string,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  const reason = body.reason;
  if (typeof actionId !== "string" || typeof reason !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformResult = await env.PLATFORM.resume({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    org_id: orgId,
    reason,
  });
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(
    canonicalize({ org_id: orgId, reason }),
  );

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: "resume",
    subject: orgId,
    params_sha256: paramsSha256,
    assertion_sha256: null,
    result,
  });

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostListGrantsForVoid(
  env: OpsEnv,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  const credentialId = body.credential_id;
  const window = body.window;
  if (
    typeof actionId !== "string" ||
    typeof credentialId !== "string" ||
    !isRecord(window)
  ) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformResult = await env.PLATFORM.listGrantsForVoid({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    credential_id: credentialId,
    window,
  });
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(
    canonicalize({ credential_id: credentialId, window }),
  );

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: "listGrantsForVoid",
    subject: credentialId,
    params_sha256: paramsSha256,
    assertion_sha256: null,
    result,
  });

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostGrantHpRelay(
  env: OpsEnv,
  grantId: string,
  platformMethod: "voidGrant" | "releaseHeld",
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  const reason = body.reason;
  if (typeof actionId !== "string" || typeof reason !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformArgs: Record<string, unknown> = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    grant_id: grantId,
    reason,
    operation: body.operation,
    assertion: body.assertion,
    signer_credential_id: body.signer_credential_id,
  };

  const platformResult =
    platformMethod === "voidGrant"
      ? await env.PLATFORM.voidGrant(platformArgs)
      : await env.PLATFORM.releaseHeld(platformArgs);
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(
    canonicalize({ grant_id: grantId, reason }),
  );
  const operation = body.operation;
  const assertionSha256 =
    isRecord(operation)
      ? await sha256Hex(canonicalize(operation))
      : null;

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: platformMethod,
    subject: grantId,
    params_sha256: paramsSha256,
    assertion_sha256: assertionSha256,
    result,
  });

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostDeleteInstallation(
  env: OpsEnv,
  orgId: string,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  const reason = body.reason;
  if (typeof actionId !== "string" || typeof reason !== "string") {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformResult = await env.PLATFORM.deleteInstallation({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    org_id: orgId,
    reason,
    operation: body.operation,
    assertion: body.assertion,
    signer_credential_id: body.signer_credential_id,
  });
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(
    canonicalize({ org_id: orgId, reason }),
  );
  const operation = body.operation;
  const assertionSha256 =
    isRecord(operation)
      ? await sha256Hex(canonicalize(operation))
      : null;

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: "deleteInstallation",
    subject: orgId,
    params_sha256: paramsSha256,
    assertion_sha256: assertionSha256,
    result,
  });

  return platformResponseJson(platformResult, contractVersion);
}

async function handlePostBeginTransfer(
  env: OpsEnv,
  orgId: string,
  access: VerifiedAccess,
  request: Request,
  contractVersion: number,
): Promise<Response> {
  const body = await parseHpRequestBody(request);
  if (body === null) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const actionId = body.action_id;
  const fromInstallationId = body.from_installation_id;
  const reason = body.reason;
  if (
    typeof actionId !== "string" ||
    typeof fromInstallationId !== "string" ||
    typeof reason !== "string"
  ) {
    return clinicErrorResponse("assertion_invalid", 400, contractVersion);
  }

  const platformResult = await env.PLATFORM.beginTransfer({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    org_id: orgId,
    from_installation_id: fromInstallationId,
    reason,
    operation: body.operation,
    assertion: body.assertion,
    signer_credential_id: body.signer_credential_id,
  });
  const result = String(platformResult.result ?? "");
  const paramsSha256 = await sha256Hex(
    canonicalize({
      org_id: orgId,
      from_installation_id: fromInstallationId,
      reason,
    }),
  );
  const operation = body.operation;
  const assertionSha256 =
    isRecord(operation)
      ? await sha256Hex(canonicalize(operation))
      : null;

  await insertRelayOperatorAction(env, {
    action_id: actionId,
    actor_email: access.email,
    access_jti: access.jti,
    action: "beginTransfer",
    subject: orgId,
    params_sha256: paramsSha256,
    assertion_sha256: assertionSha256,
    result,
  });

  if (result === "ok" && typeof platformResult.detail === "string") {
    const detail = JSON.parse(platformResult.detail) as Record<string, unknown>;
    const transferId = detail.transfer_id;
    if (typeof transferId === "string" && transferId.length > 0) {
      const dedupeKey = `transfer_step:${transferId}`;
      const existing = await env.DB.prepare(
        `SELECT 1 FROM work WHERE dedupe_key = ?`,
      )
        .bind(dedupeKey)
        .first();
      if (existing === null) {
        const nowIso = await clockNowIso(env);
        const workId = crypto.randomUUID();
        await env.DB.prepare(
          `INSERT INTO work (
             work_id, kind, subject_id, dedupe_key, state, attempts,
             next_attempt_at, lease_until, last_error, opened_at
           ) VALUES (?, 'transfer_step', ?, ?, 'open', 0, NULL, NULL, NULL, ?)`,
        )
          .bind(workId, transferId, dedupeKey, nowIso)
          .run();
      }
    }
  }

  return platformResponseJson(platformResult, contractVersion);
}

async function takeTransferWork(
  env: OpsEnv,
  workId: string,
): Promise<TransferWorkRow | null> {
  const nowMs = await clockNowMs(env);
  const nowIso = new Date(nowMs).toISOString();
  const leaseUntil = new Date(nowMs + TRANSFER_LEASE_MS).toISOString();

  const leased = await env.DB.prepare(
    `UPDATE work
     SET lease_until = ?
     WHERE work_id = ?
       AND kind = 'transfer_step'
       AND state = 'open'
       AND (lease_until IS NULL OR lease_until <= ?)
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)`,
  )
    .bind(leaseUntil, workId, nowIso, nowIso)
    .run();
  if ((leased.meta.changes ?? 0) === 0) {
    return null;
  }

  return env.DB.prepare(
    `SELECT work_id, kind, subject_id, state, attempts, next_attempt_at,
            lease_until, last_error
     FROM work WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .first<TransferWorkRow>();
}

async function clearTransferLease(
  env: OpsEnv,
  workId: string,
  leaseUntil: string,
): Promise<void> {
  await env.DB.prepare(
    `UPDATE work SET lease_until = NULL WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .run();
}

async function writeTransferGrantRequests(
  env: OpsEnv,
  transferId: string,
  orgId: string,
  packageDetail: unknown,
): Promise<void> {
  if (!Array.isArray(packageDetail)) {
    return;
  }

  const nowIso = await clockNowIso(env);
  for (let n = 0; n < packageDetail.length; n += 1) {
    const element = packageDetail[n];
    if (!isRecord(element)) {
      continue;
    }
    const grantId = await grantIdTransfer(transferId, n);
    if (await grantRequestExists(env, grantId)) {
      continue;
    }
    const envelopeBytes = canonicalize(element);
    const envelopeText = new TextDecoder().decode(envelopeBytes);
    const envelopeSha256 = await sha256Hex(envelopeBytes);
    const requestCanonical = transferGrantRequestCanonical({
      grantId,
      orgId,
      transferId,
      envelopeText,
      envelopeSha256,
    });
    await env.DB.batch([
      env.DB.prepare(
        `INSERT OR IGNORE INTO grant_request (
           grant_id, org_id, source_kind, source_ref, envelope, envelope_sha256, assertion
         ) VALUES (?, ?, 'transfer', ?, ?, ?, NULL)`,
      ).bind(
        grantId,
        orgId,
        transferId,
        envelopeText,
        envelopeSha256,
      ),
      await relayFactLogStatement(
        env,
        "grant_request",
        grantId,
        requestCanonical,
        nowIso,
      ),
    ]);
  }
}

async function finishTransferStep(
  env: OpsEnv,
  work: TransferWorkRow,
  leaseUntil: string,
): Promise<void> {
  await env.DB.prepare(
    `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
     WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(work.work_id, leaseUntil)
    .run();
}

async function reopenTransferStep(
  env: OpsEnv,
  work: TransferWorkRow,
  leaseUntil: string,
  lastError: string,
): Promise<void> {
  await env.DB.prepare(
    `UPDATE work SET lease_until = NULL, last_error = ?
     WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(lastError, work.work_id, leaseUntil)
    .run();
}

function transferOutPackageDetail(detail: unknown): unknown {
  if (typeof detail === "string") {
    try {
      return JSON.parse(detail) as unknown;
    } catch {
      return null;
    }
  }
  return detail;
}

function transferOrgIdFromReceipt(receipt: unknown): string | null {
  if (!isRecord(receipt)) {
    return null;
  }
  const orgId = receipt.org_id;
  return typeof orgId === "string" && orgId.length > 0 ? orgId : null;
}

async function processTransferStepWork(
  env: OpsEnv,
  work: TransferWorkRow,
): Promise<void> {
  const leaseUntil = work.lease_until;
  if (leaseUntil === null) {
    return;
  }

  const transferId = work.subject_id;
  const contractArgs = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    transfer_id: transferId,
  };

  if (work.last_error === null) {
    const inResult = await env.PLATFORM.transferIn(contractArgs);
    const inOutcome = String(inResult.result ?? "");
    if (
      inOutcome === "transient" &&
      inResult.detail === "awaiting_transfer_out"
    ) {
      await reopenTransferStep(env, work, leaseUntil, "awaiting_transfer_out");
      return;
    }
    if (inOutcome === "applied" || inOutcome === "already_applied") {
      await finishTransferStep(env, work, leaseUntil);
      return;
    }
    await reopenTransferStep(
      env,
      work,
      leaseUntil,
      inOutcome.length > 0 ? inOutcome : "transient",
    );
    return;
  }

  const outResult = await env.PLATFORM.transferOut(contractArgs);
  const outOutcome = String(outResult.result ?? "");
  if (outOutcome !== "applied" && outOutcome !== "already_applied") {
    await reopenTransferStep(
      env,
      work,
      leaseUntil,
      outOutcome.length > 0 ? outOutcome : "transient",
    );
    return;
  }

  const orgId = transferOrgIdFromReceipt(outResult.receipt);
  if (orgId !== null) {
    const packageDetail = transferOutPackageDetail(outResult.detail);
    await writeTransferGrantRequests(env, transferId, orgId, packageDetail);
  }

  const inResult = await env.PLATFORM.transferIn(contractArgs);
  const inOutcome = String(inResult.result ?? "");
  if (inOutcome === "applied" || inOutcome === "already_applied") {
    await finishTransferStep(env, work, leaseUntil);
    return;
  }
  await reopenTransferStep(
    env,
    work,
    leaseUntil,
    inOutcome === "transient"
      ? "awaiting_transfer_in"
      : inOutcome.length > 0
        ? inOutcome
        : "awaiting_transfer_in",
  );
}

export async function runDueTransferSteps(
  env: OpsEnv,
  limit = TRANSFER_BATCH_LIMIT,
): Promise<number> {
  const nowIso = await clockNowIso(env);
  const due = await env.DB.prepare(
    `SELECT work_id FROM work
     WHERE kind = 'transfer_step'
       AND state = 'open'
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
     ORDER BY opened_at ASC
     LIMIT ?`,
  )
    .bind(nowIso, limit)
    .all<{ work_id: string }>();

  let processed = 0;
  for (const row of due.results ?? []) {
    const work = await takeTransferWork(env, row.work_id);
    if (work === null) {
      continue;
    }
    try {
      await processTransferStepWork(env, work);
      processed += 1;
    } catch {
      const leaseUntil = work.lease_until;
      if (leaseUntil !== null) {
        await clearTransferLease(env, work.work_id, leaseUntil);
      }
    }
  }
  return processed;
}

export async function handleOps(
  request: Request,
  env: OpsEnv,
  path: string,
  contractVersion: number,
): Promise<Response> {
  const access = await verifyOpsAccess(env, request);
  if (access instanceof Response) {
    return access;
  }

  const url = new URL(request.url);

  if (request.method === "GET" && path === "/ops/lookup") {
    const q = url.searchParams.get("q") ?? "";
    return handleGetLookup(env, q, contractVersion);
  }

  const clinicMatch = /^\/ops\/clinics\/([^/]+)$/u.exec(path);
  if (request.method === "GET" && clinicMatch !== null) {
    return handleGetClinic(env, clinicMatch[1]!, access, contractVersion);
  }

  if (request.method === "GET" && path === "/ops/parked") {
    return handleGetParked(env, contractVersion);
  }

  if (request.method === "GET" && path === "/ops/findings") {
    return handleGetFindings(env, contractVersion);
  }

  if (request.method === "GET" && path === "/ops/grants") {
    return handleGetGrants(env, contractVersion);
  }

  if (request.method === "GET" && path === "/ops/payout-imports") {
    return handleGetPayoutImports(contractVersion);
  }

  if (request.method === "POST" && path === "/ops/payout-imports") {
    return handlePostPayoutImport(env, access, request, contractVersion);
  }

  const resolveFindingMatch =
    /^\/ops\/findings\/([^/]+)\/resolve$/u.exec(path);
  if (request.method === "POST" && resolveFindingMatch !== null) {
    return handlePostResolveFinding(
      env,
      resolveFindingMatch[1]!,
      access,
      request,
      contractVersion,
    );
  }

  if (request.method === "GET" && path === "/ops/registries") {
    return handleGetRegistries(env, contractVersion);
  }

  const retryMatch = /^\/ops\/parked\/([^/]+)\/retry$/u.exec(path);
  if (request.method === "POST" && retryMatch !== null) {
    return handlePostRetry(env, retryMatch[1]!, access, contractVersion);
  }

  const cancelMatch = /^\/ops\/checkouts\/([^/]+)\/cancel$/u.exec(path);
  if (request.method === "POST" && cancelMatch !== null) {
    return handlePostCancel(env, cancelMatch[1]!, access, contractVersion);
  }

  const publishMatch = /^\/ops\/offers\/([^/]+)\/publish$/u.exec(path);
  if (request.method === "POST" && publishMatch !== null) {
    return handleHpPost(
      env,
      access,
      "publish_offer",
      publishMatch[1]!,
      request,
      contractVersion,
      handleHpCatalogueAction,
    );
  }

  const retireMatch = /^\/ops\/offers\/([^/]+)\/retire$/u.exec(path);
  if (request.method === "POST" && retireMatch !== null) {
    return handleHpPost(
      env,
      access,
      "retire_offer",
      retireMatch[1]!,
      request,
      contractVersion,
      handleHpCatalogueAction,
    );
  }

  const reinstateMatch = /^\/ops\/offers\/([^/]+)\/reinstate$/u.exec(path);
  if (request.method === "POST" && reinstateMatch !== null) {
    return handleHpPost(
      env,
      access,
      "reinstate_offer",
      reinstateMatch[1]!,
      request,
      contractVersion,
      handleHpCatalogueAction,
    );
  }

  const releaseMatch = /^\/ops\/payments\/([^/]+)\/release$/u.exec(path);
  if (request.method === "POST" && releaseMatch !== null) {
    return handleHpPost(
      env,
      access,
      "release_payment",
      releaseMatch[1]!,
      request,
      contractVersion,
      handleHpReleasePayment,
    );
  }

  const chargebackMatch = /^\/ops\/payments\/([^/]+)\/chargeback$/u.exec(path);
  if (request.method === "POST" && chargebackMatch !== null) {
    return handleHpPost(
      env,
      access,
      "manual_chargeback",
      chargebackMatch[1]!,
      request,
      contractVersion,
      handleHpManualChargeback,
    );
  }

  const eraseMatch = /^\/ops\/orgs\/([^/]+)\/erase-contact$/u.exec(path);
  if (request.method === "POST" && eraseMatch !== null) {
    return handleHpPost(
      env,
      access,
      "erase_contact",
      eraseMatch[1]!,
      request,
      contractVersion,
      handleHpEraseContact,
    );
  }

  const complimentaryGrantMatch =
    /^\/ops\/orgs\/([^/]+)\/complimentary-grant$/u.exec(path);
  if (request.method === "POST" && complimentaryGrantMatch !== null) {
    return handlePostComplimentaryGrant(
      env,
      complimentaryGrantMatch[1]!,
      access,
      request,
      contractVersion,
    );
  }

  const suspendMatch = /^\/ops\/orgs\/([^/]+)\/suspend$/u.exec(path);
  if (request.method === "POST" && suspendMatch !== null) {
    return handlePostSuspend(
      env,
      suspendMatch[1]!,
      access,
      request,
      contractVersion,
    );
  }

  const resumeMatch = /^\/ops\/orgs\/([^/]+)\/resume$/u.exec(path);
  if (request.method === "POST" && resumeMatch !== null) {
    return handlePostResume(
      env,
      resumeMatch[1]!,
      access,
      request,
      contractVersion,
    );
  }

  const deleteInstallationMatch =
    /^\/ops\/orgs\/([^/]+)\/delete-installation$/u.exec(path);
  if (request.method === "POST" && deleteInstallationMatch !== null) {
    return handlePostDeleteInstallation(
      env,
      deleteInstallationMatch[1]!,
      access,
      request,
      contractVersion,
    );
  }

  const beginTransferMatch = /^\/ops\/orgs\/([^/]+)\/begin-transfer$/u.exec(path);
  if (request.method === "POST" && beginTransferMatch !== null) {
    return handlePostBeginTransfer(
      env,
      beginTransferMatch[1]!,
      access,
      request,
      contractVersion,
    );
  }

  if (request.method === "POST" && path === "/ops/grants/list-for-void") {
    return handlePostListGrantsForVoid(env, access, request, contractVersion);
  }

  const voidGrantMatch = /^\/ops\/grants\/([^/]+)\/void$/u.exec(path);
  if (request.method === "POST" && voidGrantMatch !== null) {
    return handlePostGrantHpRelay(
      env,
      voidGrantMatch[1]!,
      "voidGrant",
      access,
      request,
      contractVersion,
    );
  }

  const releaseHeldMatch = /^\/ops\/grants\/([^/]+)\/release-held$/u.exec(path);
  if (request.method === "POST" && releaseHeldMatch !== null) {
    return handlePostGrantHpRelay(
      env,
      releaseHeldMatch[1]!,
      "releaseHeld",
      access,
      request,
      contractVersion,
    );
  }

  if (request.method === "POST" && path === "/ops/operator-credentials") {
    return handlePostRegisterOperatorCredential(
      env,
      access,
      request,
      contractVersion,
    );
  }

  const revokeCredentialMatch =
    /^\/ops\/operator-credentials\/([^/]+)\/revoke$/u.exec(path);
  if (request.method === "POST" && revokeCredentialMatch !== null) {
    return handlePostRevokeOperatorCredential(
      env,
      access,
      revokeCredentialMatch[1]!,
      request,
      contractVersion,
    );
  }

  if (request.method === "POST" && path === "/ops/plan-versions") {
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "publishPlanVersion",
      planVersionSubject,
      [
        "plan_id",
        "version",
        "display_name",
        "capabilities",
        "max_cost_class",
        "concurrency_limit",
        "max_allowance_per_month",
      ],
    );
  }

  if (request.method === "POST" && path === "/ops/ceiling-policy") {
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "setCeilingPolicy",
      "ceiling_policy",
      [
        "per_grant_max_days",
        "per_grant_max_allowance_months",
        "window_days",
        "window_max_days",
        "window_max_allowance_months",
        "max_paid_grace_days",
        "paid_cap_rule",
      ],
    );
  }

  if (request.method === "POST" && path === "/ops/plan-versions/retire") {
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "retirePlanVersion",
      planVersionSubject,
      ["plan_id", "version"],
    );
  }

  if (request.method === "POST" && path === "/ops/issuer-keys") {
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "registerIssuerKey",
      (body) => (typeof body.kid === "string" ? body.kid : ""),
      ["kid", "public_key", "not_before", "not_after"],
    );
  }

  const revokeIssuerMatch = /^\/ops\/issuer-keys\/([^/]+)\/revoke$/u.exec(path);
  if (request.method === "POST" && revokeIssuerMatch !== null) {
    const kid = revokeIssuerMatch[1]!;
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "revokeIssuerKey",
      kid,
      [],
      { kid },
    );
  }

  const retireIssuerMatch = /^\/ops\/issuer-keys\/([^/]+)\/retire$/u.exec(path);
  if (request.method === "POST" && retireIssuerMatch !== null) {
    const kid = retireIssuerMatch[1]!;
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "retireIssuerKey",
      kid,
      [],
      { kid },
    );
  }

  if (request.method === "POST" && path === "/ops/service-keys") {
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "registerServiceKey",
      (body) => (typeof body.kid === "string" ? body.kid : ""),
      ["kid", "public_key", "not_before", "not_after"],
    );
  }

  const revokeServiceKeyMatch =
    /^\/ops\/service-keys\/([^/]+)\/revoke$/u.exec(path);
  if (request.method === "POST" && revokeServiceKeyMatch !== null) {
    const kid = revokeServiceKeyMatch[1]!;
    return handlePostConfigurationHpRelay(
      env,
      access,
      request,
      contractVersion,
      "revokeServiceKey",
      kid,
      [],
      { kid },
    );
  }

  if (request.method === "POST" && path === "/ops/routing-policy") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "publishRoutingPolicy",
      publishedRoutingPolicySubject,
      ["document"],
    );
  }

  if (request.method === "POST" && path === "/ops/routing-policy/canary") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "canaryRoutingPolicy",
      routingPolicySubject,
      ["policy_id", "version", "installation_ids", "cohort_name"],
    );
  }

  if (request.method === "POST" && path === "/ops/routing-policy/promote") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "promoteRoutingPolicy",
      routingPolicySubject,
      ["policy_id", "version"],
    );
  }

  if (request.method === "POST" && path === "/ops/routing-policy/rollback") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "rollbackRoutingPolicy",
      routingPolicySubject,
      ["policy_id", "version"],
    );
  }

  if (request.method === "POST" && path === "/ops/kill-switches") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "armKillSwitch",
      killSwitchSubject,
      ["scope", "target"],
    );
  }

  if (request.method === "POST" && path === "/ops/cohorts/activate") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "activateCohort",
      (body) =>
        typeof body.capability_id === "string" ? body.capability_id : "",
      [
        "capability_id",
        "capability_version",
        "installation_ids",
        "cohort_name",
      ],
    );
  }

  if (request.method === "POST" && path === "/ops/cohorts/promote") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "promoteCohort",
      (body) =>
        typeof body.capability_id === "string" ? body.capability_id : "",
      ["capability_id", "capability_version", "cohort_name"],
    );
  }

  if (request.method === "POST" && path === "/ops/capabilities/deprecate") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "deprecateCapability",
      (body) =>
        typeof body.capability_id === "string" ? body.capability_id : "",
      ["capability_id", "capability_version", "successor_id"],
    );
  }

  if (request.method === "POST" && path === "/ops/capabilities/retire") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "retireCapability",
      (body) =>
        typeof body.capability_id === "string" ? body.capability_id : "",
      ["capability_id", "capability_version"],
    );
  }

  if (request.method === "POST" && path === "/ops/token-contracts/begin-rotation") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "beginTokenContractRotation",
      "token_contract",
      [],
    );
  }

  if (request.method === "POST" && path === "/ops/token-contracts/retire") {
    return handlePostConfigurationClassHRelay(
      env,
      access,
      request,
      contractVersion,
      "retireTokenContract",
      (body) => (typeof body.ver === "string" ? body.ver : ""),
      ["ver"],
    );
  }

  if (request.method === "GET" && path === "/ops/support-lookup") {
    const reference = url.searchParams.get("reference") ?? "";
    return handleGetSupportLookup(env, access, reference, contractVersion);
  }

  return new Response(null, { status: 404 });
}
