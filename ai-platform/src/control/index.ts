export type OperatorPrincipal = {
  operatorId: string;
};

/** Port seam resolving an operator principal or rejecting (Clarification Q2). */
export type OperatorAuth = {
  resolve(request: Request): OperatorPrincipal | null;
};

/** Default bearer-token operator auth for the Worker route (real scheme is out of scope). */
export const defaultOperatorAuth: OperatorAuth = {
  resolve(request: Request) {
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return null;
    }
    const token = authorization.slice("Bearer ".length).trim();
    if (!token) {
      return null;
    }
    return { operatorId: token };
  },
};

import { purgeByInstallationId } from "../retention";
import { supportLookup } from "../support";
import { OVERLAP_WINDOW_MS } from "../capability";

type ControlBindings = {
  DB: D1Database;
  R2?: R2Bucket;
};

type EnrollPayload = {
  org_id: string;
  display_name: string;
  region: string;
  plan: string;
  public_key: string;
  algorithm: string;
  kid: string;
};

type RotatePayload = {
  kid: string;
  public_key: string;
  algorithm: string;
};

type DeprecatePayload = {
  successor_id: string;
};

type CapabilityRoute = {
  capabilityId: string;
  version: string;
  action: "deprecate" | "retire";
};

const INSTALLATION_ACTIVE_STATUS = "active";
const INSTALLATION_SUSPENDED_STATUS = "suspended";
const INSTALLATION_DELETED_STATUS = "deleted";

function unauthorized(): Response {
  return new Response(JSON.stringify({ error: "unauthorized" }), {
    status: 401,
    headers: { "content-type": "application/json" },
  });
}

function reject(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function ok(body: Record<string, unknown> = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

function nowIso(): string {
  return new Date().toISOString();
}

function newId(): string {
  return crypto.randomUUID();
}

function parseInstallationId(request: Request): string | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/(?:enroll|rotate|suspend|resume|delete)$/,
  );
  return match?.[1] ?? null;
}

function requireOperator(
  request: Request,
  operatorAuth: OperatorAuth,
): OperatorPrincipal | Response {
  const principal = operatorAuth.resolve(request);
  if (!principal) {
    return unauthorized();
  }
  return principal;
}

async function writeAudit(
  db: D1Database,
  operatorId: string,
  action: string,
  target: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, ?, ?, NULL, NULL, ?)`,
    )
    .bind(newId(), operatorId, action, target, nowIso())
    .run();
}

async function parseJsonBody<T>(request: Request): Promise<T | Response> {
  try {
    return (await request.json()) as T;
  } catch {
    return reject(400, "invalid_json");
  }
}

export async function handleEnroll(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<EnrollPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const existing = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ? OR org_id = ?",
  )
    .bind(installationId, body.org_id)
    .first<{ installation_id: string }>();

  if (existing) {
    return reject(409, "already_enrolled");
  }

  const enrolledAt = nowIso();
  const entitlementId = newId();
  const auditId = newId();
  const platformBaseUrl = new URL(request.url).origin;

  await DB.batch([
    DB.prepare(
      `INSERT INTO installation
         (installation_id, org_id, display_name, status, region, enrolled_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(
      installationId,
      body.org_id,
      body.display_name,
      INSTALLATION_ACTIVE_STATUS,
      body.region,
      enrolledAt,
    ),
    DB.prepare(
      `INSERT INTO installation_key
         (key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at)
       VALUES (?, ?, ?, ?, ?, NULL, NULL)`,
    ).bind(
      body.kid,
      installationId,
      body.public_key,
      body.algorithm,
      enrolledAt,
    ),
    DB.prepare(
      `INSERT INTO entitlement
         (entitlement_id, installation_id, plan, period_start, period_end,
          request_quota, token_budget, cost_budget, allowed_capabilities,
          soft_threshold, status)
       VALUES (?, ?, ?, ?, ?, 0, 0, 0, '[]', 0, 'pending')`,
    ).bind(entitlementId, installationId, body.plan, enrolledAt, enrolledAt),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'enroll', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, enrolledAt),
  ]);

  return ok({ platform_base_url: platformBaseUrl });
}

export async function handleRotate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<RotatePayload>(request);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const validFrom = nowIso();
  const auditId = newId();

  await DB.batch([
    DB.prepare(
      `INSERT INTO installation_key
         (key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at)
       VALUES (?, ?, ?, ?, ?, NULL, NULL)`,
    ).bind(
      body.kid,
      installationId,
      body.public_key,
      body.algorithm,
      validFrom,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'rotate', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, validFrom),
  ]);

  return ok();
}

export async function handleSuspend(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const recordedAt = nowIso();
  const auditId = newId();

  await DB.batch([
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(INSTALLATION_SUSPENDED_STATUS, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'suspend', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);

  return ok();
}

export async function handleResume(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id, status FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string; status: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const recordedAt = nowIso();
  const auditId = newId();
  const restoredStatus =
    installation.status === INSTALLATION_SUSPENDED_STATUS
      ? INSTALLATION_ACTIVE_STATUS
      : installation.status;

  await DB.batch([
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(restoredStatus, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'resume', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);

  return ok();
}

function parseCapabilityRoute(request: Request): CapabilityRoute | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/(deprecate|retire)$/,
  );
  if (!match) {
    return null;
  }
  return {
    capabilityId: match[1],
    version: match[2],
    action: match[3] as "deprecate" | "retire",
  };
}

async function loadGlobalOverlay(
  db: D1Database,
  capabilityId: string,
  version: string,
): Promise<Record<string, unknown> | null> {
  const row = await db
    .prepare(
      `SELECT lifecycle_state, successor_id, deprecated_at, retire_after
       FROM capability_grant
       WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
       ORDER BY changed_at DESC LIMIT 1`,
    )
    .bind(capabilityId, version)
    .first<Record<string, unknown>>();
  return row ?? null;
}

export async function handleDeprecate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCapabilityRoute(request);
  if (!route || route.action !== "deprecate") {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<DeprecatePayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!body.successor_id) {
    return reject(400, "missing_successor_id");
  }

  const { DB } = bindings;
  const deprecatedAt = nowIso();
  const retireAfter = new Date(
    new Date(deprecatedAt).getTime() + OVERLAP_WINDOW_MS,
  ).toISOString();
  const grantId = newId();
  const target = `${route.capabilityId}@${route.version}`;

  await DB.batch([
    DB.prepare(
      `INSERT INTO capability_grant (
         grant_id, scope, capability_id, capability_version,
         granted_at, revoked_at, changed_at, changed_by,
         lifecycle_state, successor_id, deprecated_at, retire_after
       ) VALUES (?, 'global', ?, ?, ?, NULL, ?, ?, 'deprecated', ?, ?, ?)`,
    ).bind(
      grantId,
      route.capabilityId,
      route.version,
      deprecatedAt,
      deprecatedAt,
      auth.operatorId,
      body.successor_id,
      deprecatedAt,
      retireAfter,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'deprecate', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, deprecatedAt),
  ]);

  return ok();
}

export async function handleRetire(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCapabilityRoute(request);
  if (!route || route.action !== "retire") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const overlay = await loadGlobalOverlay(DB, route.capabilityId, route.version);

  if (
    !overlay ||
    overlay.lifecycle_state !== "deprecated" ||
    typeof overlay.successor_id !== "string" ||
    !overlay.successor_id
  ) {
    return reject(400, "not_deprecated");
  }

  const retireAfter =
    typeof overlay.retire_after === "string" ? overlay.retire_after : null;
  if (!retireAfter || nowIso() < retireAfter) {
    return reject(400, "overlap_window_active");
  }

  const recordedAt = nowIso();
  const grantId = newId();
  const target = `${route.capabilityId}@${route.version}`;

  await DB.batch([
    DB.prepare(
      `INSERT INTO capability_grant (
         grant_id, scope, capability_id, capability_version,
         granted_at, revoked_at, changed_at, changed_by,
         lifecycle_state, successor_id, deprecated_at, retire_after
       ) VALUES (?, 'global', ?, ?, ?, NULL, ?, ?, 'retired', ?, ?, ?)`,
    ).bind(
      grantId,
      route.capabilityId,
      route.version,
      recordedAt,
      recordedAt,
      auth.operatorId,
      overlay.successor_id,
      overlay.deprecated_at,
      overlay.retire_after,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'retire', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  ]);

  return ok();
}

type CohortPayload = {
  installation_ids: string[];
  cohort_name?: string;
};

type PublishPayload = {
  document: Record<string, unknown>;
};

type CohortCapabilityRoute = {
  capabilityId: string;
  version: string;
  action: "activate" | "promote";
};

type RoutingPolicyRoute = {
  policyId: string;
  version: string;
  action: "publish" | "canary" | "rollback";
};

function parseCohortCapabilityRoute(request: Request): CohortCapabilityRoute | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/(activate|promote)$/,
  );
  if (!match) {
    return null;
  }
  return {
    capabilityId: match[1],
    version: match[2],
    action: match[3] as "activate" | "promote",
  };
}

function parseRoutingPolicyRoute(request: Request): RoutingPolicyRoute | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/(publish|canary|rollback)$/,
  );
  if (!match) {
    return null;
  }
  return {
    policyId: match[1],
    version: match[2],
    action: match[3] as "publish" | "canary" | "rollback",
  };
}

export async function handleCohortActivate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCohortCapabilityRoute(request);
  if (!route || route.action !== "activate") {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<CohortPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!Array.isArray(body.installation_ids) || body.installation_ids.length === 0) {
    return reject(400, "missing_installation_ids");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = body.cohort_name
    ? `${route.capabilityId}@${route.version}:${body.cohort_name}`
    : `${route.capabilityId}@${route.version}`;

  const statements: D1PreparedStatement[] = [];
  for (const installationId of body.installation_ids) {
    const existing = await DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL`,
    )
      .bind(`installation:${installationId}`, route.capabilityId)
      .first<{ grant_id: string }>();

    if (existing) {
      statements.push(
        DB.prepare(
          `UPDATE capability_grant
           SET capability_version = ?, changed_at = ?, changed_by = ?
           WHERE grant_id = ?`,
        ).bind(route.version, recordedAt, auth.operatorId, existing.grant_id),
      );
    } else {
      statements.push(
        DB.prepare(
          `INSERT INTO capability_grant (
             grant_id, scope, capability_id, capability_version,
             granted_at, revoked_at, changed_at, changed_by
           ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
        ).bind(
          newId(),
          `installation:${installationId}`,
          route.capabilityId,
          route.version,
          recordedAt,
          recordedAt,
          auth.operatorId,
        ),
      );
    }
  }

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'cohort_activate', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  );

  await DB.batch(statements);
  return ok();
}

export async function handleCohortPromote(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCohortCapabilityRoute(request);
  if (!route || route.action !== "promote") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.capabilityId}@${route.version}`;

  const grants = await DB.prepare(
    `SELECT grant_id FROM capability_grant
     WHERE capability_id = ? AND scope LIKE 'installation:%' AND revoked_at IS NULL`,
  )
    .bind(route.capabilityId)
    .all<{ grant_id: string }>();

  const statements: D1PreparedStatement[] = (grants.results ?? []).map((grant) =>
    DB.prepare(
      `UPDATE capability_grant
       SET capability_version = ?, changed_at = ?, changed_by = ?
       WHERE grant_id = ?`,
    ).bind(route.version, recordedAt, auth.operatorId, grant.grant_id),
  );

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'cohort_promote', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  );

  if (statements.length > 0) {
    await DB.batch(statements);
  }

  return ok();
}

export async function handleRoutingPolicyPublish(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "publish") {
    return reject(400, "invalid_route");
  }

  if (!bindings.R2) {
    return reject(500, "missing_r2_binding");
  }

  const body = await parseJsonBody<PublishPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!body.document || typeof body.document !== "object") {
    return reject(400, "missing_document");
  }

  const { DB, R2 } = bindings;
  const recordedAt = nowIso();
  const contentPointer = `control/routing-policy/${route.policyId}/${route.version}.json`;
  const target = `${route.policyId}@${route.version}`;

  await R2.put(contentPointer, JSON.stringify(body.document), {
    httpMetadata: { contentType: "application/json" },
  });

  await DB.batch([
    DB.prepare(
      `INSERT INTO routing_policy (
         policy_id, version, content_pointer, active_from, activated_by, canary_installation_ids
       ) VALUES (?, ?, ?, ?, ?, NULL)`,
    ).bind(
      route.policyId,
      route.version,
      contentPointer,
      recordedAt,
      auth.operatorId,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_publish', ?, NULL, ?, ?)`,
    ).bind(newId(), auth.operatorId, target, contentPointer, recordedAt),
  ]);

  return ok();
}

export async function handleRoutingPolicyCanary(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "canary") {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<CohortPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!Array.isArray(body.installation_ids) || body.installation_ids.length === 0) {
    return reject(400, "missing_installation_ids");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<{ policy_id: string }>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET canary_installation_ids = ?
       WHERE policy_id = ? AND version = ?`,
    ).bind(
      JSON.stringify(body.installation_ids),
      route.policyId,
      route.version,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_canary', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  ]);

  return ok();
}

export async function handleRoutingPolicyRollback(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "rollback") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<{ policy_id: string }>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_rollback', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  ]);

  return ok();
}

export async function handleDelete(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const recordedAt = nowIso();
  const auditId = newId();

  await DB.batch([
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(INSTALLATION_DELETED_STATUS, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'delete', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);

  return ok();
}

const CONTROL_ACTION_PATTERN =
  /^\/control\/installations\/[^/]+\/(enroll|rotate|suspend|resume|delete|purge)$/;

const CAPABILITY_LIFECYCLE_PATTERN =
  /^\/control\/capabilities\/[^/]+\/versions\/[^/]+\/(deprecate|retire)$/;

const SUPPORT_LOOKUP_PATTERN = /^\/control\/support\/lookup$/;

const ROUTING_POLICY_PATTERN =
  /^\/control\/routing-policies\/[^/]+\/versions\/[^/]+\/(publish|canary|rollback)$/;

const COHORT_CAPABILITY_PATTERN =
  /^\/control\/capabilities\/[^/]+\/versions\/[^/]+\/(activate|promote)$/;

export function isControlRoute(pathname: string): boolean {
  return (
    CONTROL_ACTION_PATTERN.test(pathname) ||
    CAPABILITY_LIFECYCLE_PATTERN.test(pathname) ||
    COHORT_CAPABILITY_PATTERN.test(pathname) ||
    ROUTING_POLICY_PATTERN.test(pathname) ||
    SUPPORT_LOOKUP_PATTERN.test(pathname)
  );
}

export async function handleSupportLookup(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  if (!bindings.R2) {
    return reject(500, "missing_r2_binding");
  }

  const url = new URL(request.url);
  const reference = url.searchParams.get("reference");
  if (!reference) {
    return reject(400, "missing_reference");
  }

  const result = await supportLookup(reference, {
    db: bindings.DB,
    r2: bindings.R2,
  });

  if (!result.found) {
    return reject(404, "not_found");
  }

  return ok({
    request: result.request,
    attempts: result.attempts,
    envelope: result.envelope,
  });
}

export async function handleInstallationPurge(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  if (!bindings.R2) {
    return reject(500, "missing_r2_binding");
  }

  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/purge$/,
  );
  const targetId = match?.[1];
  if (!targetId) {
    return reject(400, "invalid_route");
  }

  await purgeByInstallationId(targetId, auth.operatorId, {
    db: bindings.DB,
    r2: bindings.R2,
  });

  return ok();
}

export async function dispatchControlRequest(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth = defaultOperatorAuth,
): Promise<Response> {
  const pathname = new URL(request.url).pathname;

  if (SUPPORT_LOOKUP_PATTERN.test(pathname)) {
    return handleSupportLookup(request, bindings, operatorAuth);
  }

  if (CAPABILITY_LIFECYCLE_PATTERN.test(pathname)) {
    const route = parseCapabilityRoute(request);
    if (!route) {
      return reject(400, "invalid_route");
    }
    if (route.action === "deprecate") {
      return handleDeprecate(request, bindings, operatorAuth);
    }
    return handleRetire(request, bindings, operatorAuth);
  }

  if (COHORT_CAPABILITY_PATTERN.test(pathname)) {
    const route = parseCohortCapabilityRoute(request);
    if (!route) {
      return reject(400, "invalid_route");
    }
    if (route.action === "activate") {
      return handleCohortActivate(request, bindings, operatorAuth);
    }
    return handleCohortPromote(request, bindings, operatorAuth);
  }

  if (ROUTING_POLICY_PATTERN.test(pathname)) {
    const route = parseRoutingPolicyRoute(request);
    if (!route) {
      return reject(400, "invalid_route");
    }
    if (route.action === "publish") {
      return handleRoutingPolicyPublish(request, bindings, operatorAuth);
    }
    if (route.action === "canary") {
      return handleRoutingPolicyCanary(request, bindings, operatorAuth);
    }
    return handleRoutingPolicyRollback(request, bindings, operatorAuth);
  }

  const action = pathname.split("/").pop();

  switch (action) {
    case "enroll":
      return handleEnroll(request, bindings, operatorAuth);
    case "rotate":
      return handleRotate(request, bindings, operatorAuth);
    case "suspend":
      return handleSuspend(request, bindings, operatorAuth);
    case "resume":
      return handleResume(request, bindings, operatorAuth);
    case "delete":
      return handleDelete(request, bindings, operatorAuth);
    case "purge":
      return handleInstallationPurge(request, bindings, operatorAuth);
    default:
      return new Response("Not Found", { status: 404 });
  }
}
