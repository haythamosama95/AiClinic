import {
  canonicalize,
  CHANNEL_VERSIONS,
  humanRef,
  sha256Hex,
  subscriptionRef,
  verifyAccessJwt,
  type AccessCertsDocument,
} from "vendor-contracts";
import {
  clinicErrorResponse,
  clinicJsonResponse,
} from "../clinic-api/version.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";

export interface OpsEnv extends ClockEnv {
  DB: D1Database;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
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
  };
}

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

async function insertOperatorAction(
  env: OpsEnv,
  row: {
    action_id: string;
    actor_email: string;
    access_jti: string;
    action: string;
    subject: string;
    params_sha256: string;
    assertion_sha256: null;
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
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
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
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind("operator_action", row.action_id, rowSha256, createdAt),
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
  const coverage = await env.PLATFORM.inspectCoverage({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    access_jwt: access.jwt,
    org_id: orgId,
  });
  if (coverage.result !== "ok" || typeof coverage.detail !== "string") {
    return clinicErrorResponse(
      typeof coverage.code === "string" ? coverage.code : "coverage_unknown",
      404,
      contractVersion,
    );
  }

  const coverageDetail = JSON.parse(coverage.detail) as Record<string, unknown>;

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
        OR f.detail LIKE ?
     ORDER BY f.detected_at ASC`,
  )
    .bind(orgId, `%${orgId}%`)
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

  return new Response(null, { status: 404 });
}
