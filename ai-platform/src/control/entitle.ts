import { toCanonicalUuid } from "../platform-vocabulary";
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
  OverridePayload,
} from "./types";

function parseInstallationId(request: Request): string | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/entitle$/,
  );
  return match?.[1] ?? null;
}

function parseOverrideInstallationId(request: Request): string | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/override$/,
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

const ISO8601_INSTANT_RE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;

function parseIsoInstant(value: string): number | null {
  if (!ISO8601_INSTANT_RE.test(value)) {
    return null;
  }
  const ms = Date.parse(value);
  if (!Number.isFinite(ms)) {
    return null;
  }
  return ms;
}

function validatePeriodBounds(
  periodStart: string,
  periodEnd: string,
): { period_start: string; period_end: string } | Response {
  const startMs = parseIsoInstant(periodStart);
  const endMs = parseIsoInstant(periodEnd);
  if (startMs === null || endMs === null || startMs >= endMs) {
    return reject(400, "invalid_payload");
  }
  return { period_start: periodStart, period_end: periodEnd };
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

  const periodStartRaw = requireNonEmptyString(body.period_start);
  const periodEndRaw = requireNonEmptyString(body.period_end);
  if (!periodStartRaw || !periodEndRaw) {
    return reject(400, "invalid_payload");
  }
  const periodBounds = validatePeriodBounds(periodStartRaw, periodEndRaw);
  if (periodBounds instanceof Response) {
    return periodBounds;
  }
  const { period_start, period_end } = periodBounds;

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

  const rawId = parseInstallationId(request);
  if (!rawId) {
    // Unreachable via HTTP because dispatch pre-filters with identical regexes; reachable via direct handler invocation in tests; kept as a safety net.
    return reject(400, "invalid_route");
  }
  const installationId = toCanonicalUuid(rawId);

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

  const planRow = await DB.prepare(
    `SELECT credit_budget, request_quota, max_cost_class, soft_threshold, allowed_capabilities
     FROM plan WHERE name = ?`,
  )
    .bind(entitlement.plan)
    .first<{
      credit_budget: number;
      request_quota: number;
      max_cost_class: string;
      soft_threshold: number;
      allowed_capabilities: string;
    }>();

  if (!planRow) {
    return reject(404, "plan_not_found");
  }

  const recordedAt = nowIso();
  const planAllowedCapabilitiesJson = planRow.allowed_capabilities;
  const planScope = `plan:${entitlement.plan}`;
  const installationScope = `installation:${installationId}`;
  const existingLivePlanGrantCapabilityIds = new Set<string>();
  if (body.grants.some((grant) => grant.scope === "plan")) {
    const existingPlanGrants = await DB.prepare(
      `SELECT capability_id FROM capability_grant
       WHERE scope = ? AND revoked_at IS NULL`,
    )
      .bind(planScope)
      .all<{ capability_id: string }>();
    for (const row of existingPlanGrants.results ?? []) {
      existingLivePlanGrantCapabilityIds.add(row.capability_id);
    }
  }
  const existingLiveInstallationGrantCapabilityIds = new Set<string>();
  if (body.grants.some((grant) => grant.scope !== "plan")) {
    const existingInstallationGrants = await DB.prepare(
      `SELECT capability_id FROM capability_grant
       WHERE scope = ? AND revoked_at IS NULL`,
    )
      .bind(installationScope)
      .all<{ capability_id: string }>();
    for (const row of existingInstallationGrants.results ?? []) {
      existingLiveInstallationGrantCapabilityIds.add(row.capability_id);
    }
  }

  const statements: D1PreparedStatement[] = [
    DB.prepare(
      `UPDATE entitlement
       SET period_start = ?, period_end = ?, request_quota = ?, token_budget = ?,
           cost_budget = ?, credit_budget = ?, max_cost_class = ?,
           allowed_capabilities = ?, soft_threshold = ?, status = 'active'
       WHERE installation_id = ?`,
    ).bind(
      body.period_start,
      body.period_end,
      planRow.request_quota,
      body.token_budget,
      body.cost_budget,
      planRow.credit_budget,
      planRow.max_cost_class,
      planAllowedCapabilitiesJson,
      planRow.soft_threshold,
      installationId,
    ),
  ];

  for (const grant of body.grants) {
    const scope =
      grant.scope === "plan" ? planScope : installationScope;
    if (
      grant.scope === "plan" &&
      existingLivePlanGrantCapabilityIds.has(grant.capability_id)
    ) {
      continue;
    }
    if (
      grant.scope !== "plan" &&
      existingLiveInstallationGrantCapabilityIds.has(grant.capability_id)
    ) {
      continue;
    }
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
      planAllowedCapabilitiesJson,
      recordedAt,
    ),
  );

  const batchError = await runControlBatch(DB, statements);
  if (batchError) {
    return batchError;
  }

  return ok({ installation_id: installationId, status: "active" });
}

function validateOverridePayload(body: unknown): OverridePayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }

  const raw = body as OverridePayload;
  const hasField =
    raw.credit_budget !== undefined ||
    raw.request_quota !== undefined ||
    raw.token_budget !== undefined ||
    raw.cost_budget !== undefined ||
    raw.period_start !== undefined ||
    raw.period_end !== undefined ||
    raw.soft_threshold !== undefined;

  if (!hasField) {
    return reject(400, "invalid_payload");
  }

  if (
    raw.credit_budget !== undefined &&
    (!Number.isInteger(raw.credit_budget) || raw.credit_budget < 0)
  ) {
    return reject(400, "invalid_payload");
  }

  if (
    raw.request_quota !== undefined &&
    (!Number.isInteger(raw.request_quota) || raw.request_quota < 0)
  ) {
    return reject(400, "invalid_payload");
  }

  if (
    raw.token_budget !== undefined &&
    (!Number.isInteger(raw.token_budget) || raw.token_budget < 0)
  ) {
    return reject(400, "invalid_payload");
  }

  if (
    raw.cost_budget !== undefined &&
    (typeof raw.cost_budget !== "number" ||
      !Number.isFinite(raw.cost_budget) ||
      raw.cost_budget < 0)
  ) {
    return reject(400, "invalid_payload");
  }

  if (
    raw.soft_threshold !== undefined &&
    !isSoftThresholdFraction(raw.soft_threshold)
  ) {
    return reject(400, "invalid_payload");
  }

  if (raw.period_start !== undefined || raw.period_end !== undefined) {
    const periodStartRaw = requireNonEmptyString(raw.period_start);
    const periodEndRaw = requireNonEmptyString(raw.period_end);
    if (!periodStartRaw || !periodEndRaw) {
      return reject(400, "invalid_payload");
    }
    const periodBounds = validatePeriodBounds(periodStartRaw, periodEndRaw);
    if (periodBounds instanceof Response) {
      return periodBounds;
    }
  }

  return raw;
}

export async function handleOverride(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const rawId = parseOverrideInstallationId(request);
  if (!rawId) {
    return reject(400, "invalid_route");
  }
  const installationId = toCanonicalUuid(rawId);

  const rawBody = await parseJsonBody<OverridePayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateOverridePayload(rawBody);
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
    `SELECT entitlement_id, credit_budget, request_quota, token_budget, cost_budget,
            period_start, period_end, soft_threshold
     FROM entitlement WHERE installation_id = ?`,
  )
    .bind(installationId)
    .first<{
      entitlement_id: string;
      credit_budget: number;
      request_quota: number;
      token_budget: number;
      cost_budget: number;
      period_start: string;
      period_end: string;
      soft_threshold: number;
    }>();

  if (!entitlement) {
    return reject(404, "entitlement_not_found");
  }

  const beforeSnapshot: Record<string, unknown> = {};
  const afterSnapshot: Record<string, unknown> = {};

  const credit_budget = body.credit_budget ?? entitlement.credit_budget;
  const request_quota = body.request_quota ?? entitlement.request_quota;
  const token_budget = body.token_budget ?? entitlement.token_budget;
  const cost_budget = body.cost_budget ?? entitlement.cost_budget;
  const period_start = body.period_start ?? entitlement.period_start;
  const period_end = body.period_end ?? entitlement.period_end;
  const soft_threshold =
    body.soft_threshold !== undefined
      ? coerceSoftThreshold(body.soft_threshold)
      : entitlement.soft_threshold;

  if (body.credit_budget !== undefined) {
    beforeSnapshot.credit_budget = entitlement.credit_budget;
    afterSnapshot.credit_budget = credit_budget;
  }
  if (body.request_quota !== undefined) {
    beforeSnapshot.request_quota = entitlement.request_quota;
    afterSnapshot.request_quota = request_quota;
  }
  if (body.token_budget !== undefined) {
    beforeSnapshot.token_budget = entitlement.token_budget;
    afterSnapshot.token_budget = token_budget;
  }
  if (body.cost_budget !== undefined) {
    beforeSnapshot.cost_budget = entitlement.cost_budget;
    afterSnapshot.cost_budget = cost_budget;
  }
  if (body.period_start !== undefined) {
    beforeSnapshot.period_start = entitlement.period_start;
    afterSnapshot.period_start = period_start;
  }
  if (body.period_end !== undefined) {
    beforeSnapshot.period_end = entitlement.period_end;
    afterSnapshot.period_end = period_end;
  }
  if (body.soft_threshold !== undefined) {
    beforeSnapshot.soft_threshold = entitlement.soft_threshold;
    afterSnapshot.soft_threshold = soft_threshold;
  }

  const recordedAt = nowIso();
  const beforePointer = JSON.stringify(beforeSnapshot);
  const afterPointer = JSON.stringify(afterSnapshot);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE entitlement
       SET credit_budget = ?, request_quota = ?, token_budget = ?, cost_budget = ?,
           period_start = ?, period_end = ?, soft_threshold = ?
       WHERE installation_id = ?`,
    ).bind(
      credit_budget,
      request_quota,
      token_budget,
      cost_budget,
      period_start,
      period_end,
      soft_threshold,
      installationId,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'override', ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      installationId,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok({ installation_id: installationId });
}
