import {
  coerceSoftThreshold,
  isSoftThresholdFraction,
} from "../quota-do";
import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireNonEmptyString,
  requireOperator,
} from "./http";
import type {
  ControlBindings,
  EntitleGrantInput,
  EntitlePayload,
  OperatorAuth,
} from "./types";

function parseInstallationId(request: Request): string | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/entitle$/,
  );
  return match?.[1] ?? null;
}

async function runControlBatch(
  db: D1Database,
  statements: D1PreparedStatement[],
): Promise<Response | null> {
  try {
    await db.batch(statements);
    return null;
  } catch (err) {
    return reject(500, "storage_error");
  }
}

function validateGrantInput(
  grant: EntitleGrantInput,
): EntitleGrantInput | Response {
  const capability_id = requireNonEmptyString(grant.capability_id);
  const capability_version = requireNonEmptyString(grant.capability_version);
  if (!capability_id || !capability_version) {
    return reject(400, "invalid_payload");
  }
  const scope = grant.scope;
  if (scope !== undefined && scope !== "installation" && scope !== "plan") {
    return reject(400, "invalid_payload");
  }
  return {
    capability_id,
    capability_version,
    scope: scope ?? "installation",
  };
}

function validateEntitlePayload(body: EntitlePayload): EntitlePayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }

  const period_start = requireNonEmptyString(body.period_start);
  const period_end = requireNonEmptyString(body.period_end);
  if (!period_start || !period_end) {
    return reject(400, "invalid_payload");
  }

  const request_quota = body.request_quota;
  const token_budget = body.token_budget;
  const cost_budget = body.cost_budget;
  if (
    !Number.isInteger(request_quota) ||
    request_quota < 0 ||
    !Number.isInteger(token_budget) ||
    token_budget < 0 ||
    typeof cost_budget !== "number" ||
    !Number.isFinite(cost_budget) ||
    cost_budget < 0
  ) {
    return reject(400, "invalid_payload");
  }

  if (!isSoftThresholdFraction(body.soft_threshold)) {
    return reject(400, "invalid_payload");
  }

  if (
    !Array.isArray(body.allowed_capabilities) ||
    !body.allowed_capabilities.every((entry) => typeof entry === "string")
  ) {
    return reject(400, "invalid_payload");
  }

  if (!Array.isArray(body.grants) || body.grants.length === 0) {
    return reject(400, "invalid_payload");
  }

  const grants: EntitleGrantInput[] = [];
  for (const grant of body.grants) {
    const validated = validateGrantInput(grant);
    if (validated instanceof Response) {
      return validated;
    }
    grants.push(validated);
  }

  return {
    period_start,
    period_end,
    request_quota,
    token_budget,
    cost_budget,
    soft_threshold: coerceSoftThreshold(body.soft_threshold),
    allowed_capabilities: body.allowed_capabilities,
    grants,
  };
}

export async function handleEntitle(
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

  const rawBody = await parseJsonBody<EntitlePayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateEntitlePayload(rawBody);
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

  const entitlement = await DB.prepare(
    `SELECT entitlement_id, plan, status FROM entitlement WHERE installation_id = ?`,
  )
    .bind(installationId)
    .first<{ entitlement_id: string; plan: string; status: string }>();

  if (!entitlement) {
    return reject(404, "entitlement_not_found");
  }

  if (entitlement.status !== "pending") {
    return reject(409, "not_pending");
  }

  const recordedAt = nowIso();
  const allowedCapabilitiesJson = JSON.stringify(body.allowed_capabilities);
  const statements: D1PreparedStatement[] = [
    DB.prepare(
      `UPDATE entitlement
       SET period_start = ?, period_end = ?, request_quota = ?, token_budget = ?,
           cost_budget = ?, allowed_capabilities = ?, soft_threshold = ?, status = 'active'
       WHERE installation_id = ?`,
    ).bind(
      body.period_start,
      body.period_end,
      body.request_quota,
      body.token_budget,
      body.cost_budget,
      allowedCapabilitiesJson,
      body.soft_threshold,
      installationId,
    ),
  ];

  for (const grant of body.grants) {
    const scope =
      grant.scope === "plan"
        ? `plan:${entitlement.plan}`
        : `installation:${installationId}`;
    statements.push(
      DB.prepare(
        `INSERT INTO capability_grant (
           grant_id, scope, capability_id, capability_version,
           granted_at, revoked_at, changed_at, changed_by
         ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
      ).bind(
        newId(),
        scope,
        grant.capability_id,
        grant.capability_version,
        recordedAt,
        recordedAt,
        auth.operatorId,
      ),
    );
  }

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'entitle', ?, NULL, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      installationId,
      allowedCapabilitiesJson,
      recordedAt,
    ),
  );

  const batchError = await runControlBatch(DB, statements);
  if (batchError) {
    return batchError;
  }

  return ok({ installation_id: installationId, status: "active" });
}
