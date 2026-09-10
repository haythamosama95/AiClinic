import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireNonEmptyString,
  requireOperator,
} from "./http";
import type { ControlBindings, OperatorAuth, PlanPayload } from "./types";

async function runControlBatch(
  db: D1Database,
  statements: D1PreparedStatement[],
): Promise<Response | null> {
  try {
    await db.batch(statements);
    return null;
  } catch {
    return reject(500, "storage_error");
  }
}

function parsePlanNameFromPath(
  request: Request,
  action: "update" | "delete",
): string | null {
  const match = new URL(request.url).pathname.match(
    new RegExp(`^/control/plans/([^/]+)/${action}$`),
  );
  return match?.[1] ?? null;
}

function validatePlanPayload(body: unknown): PlanPayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }

  const raw = body as PlanPayload;
  const name = requireNonEmptyString(raw.name);
  if (!name) {
    return reject(400, "invalid_payload");
  }

  const credit_budget = raw.credit_budget;
  const request_quota = raw.request_quota;
  if (
    !Number.isInteger(credit_budget) ||
    credit_budget < 0 ||
    !Number.isInteger(request_quota) ||
    request_quota < 0
  ) {
    return reject(400, "invalid_payload");
  }

  const max_cost_class = requireNonEmptyString(raw.max_cost_class);
  if (max_cost_class === null) {
    return reject(400, "invalid_payload");
  }

  const soft_threshold = raw.soft_threshold;
  if (typeof soft_threshold !== "number" || !Number.isFinite(soft_threshold)) {
    return reject(400, "invalid_payload");
  }

  if (
    !Array.isArray(raw.allowed_capabilities) ||
    !raw.allowed_capabilities.every((entry) => typeof entry === "string")
  ) {
    return reject(400, "invalid_payload");
  }

  const status = requireNonEmptyString(raw.status);
  if (!status) {
    return reject(400, "invalid_payload");
  }

  return {
    name,
    credit_budget,
    request_quota,
    max_cost_class,
    soft_threshold,
    allowed_capabilities: raw.allowed_capabilities,
    status,
  };
}

function validatePlanUpdatePayload(body: unknown): Omit<PlanPayload, "name"> | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }

  const raw = body as Partial<PlanPayload>;
  const credit_budget = raw.credit_budget;
  const request_quota = raw.request_quota;
  if (
    credit_budget === undefined ||
    request_quota === undefined ||
    !Number.isInteger(credit_budget) ||
    credit_budget < 0 ||
    !Number.isInteger(request_quota) ||
    request_quota < 0
  ) {
    return reject(400, "invalid_payload");
  }

  const max_cost_class = requireNonEmptyString(raw.max_cost_class);
  if (max_cost_class === null) {
    return reject(400, "invalid_payload");
  }

  const soft_threshold = raw.soft_threshold;
  if (typeof soft_threshold !== "number" || !Number.isFinite(soft_threshold)) {
    return reject(400, "invalid_payload");
  }

  if (
    !Array.isArray(raw.allowed_capabilities) ||
    !raw.allowed_capabilities.every((entry) => typeof entry === "string")
  ) {
    return reject(400, "invalid_payload");
  }

  const status = requireNonEmptyString(raw.status);
  if (!status) {
    return reject(400, "invalid_payload");
  }

  return {
    credit_budget,
    request_quota,
    max_cost_class,
    soft_threshold,
    allowed_capabilities: raw.allowed_capabilities,
    status,
  };
}

export async function handlePlanCreate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const rawBody = await parseJsonBody<PlanPayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validatePlanPayload(rawBody);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const allowedCapabilitiesJson = JSON.stringify(body.allowed_capabilities);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `INSERT INTO plan (
         name, credit_budget, request_quota, max_cost_class,
         soft_threshold, allowed_capabilities, status
       ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      body.name,
      body.credit_budget,
      body.request_quota,
      body.max_cost_class,
      body.soft_threshold,
      allowedCapabilitiesJson,
      body.status,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'plan_create', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, body.name, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok({ name: body.name });
}

export async function handlePlanUpdate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const name = parsePlanNameFromPath(request, "update");
  if (!name) {
    return reject(400, "invalid_route");
  }

  const rawBody = await parseJsonBody<Partial<PlanPayload>>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validatePlanUpdatePayload(rawBody);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const existing = await DB.prepare("SELECT name FROM plan WHERE name = ?")
    .bind(name)
    .first<{ name: string }>();
  if (!existing) {
    return reject(404, "plan_not_found");
  }

  const recordedAt = nowIso();
  const allowedCapabilitiesJson = JSON.stringify(body.allowed_capabilities);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE plan
       SET credit_budget = ?, request_quota = ?, max_cost_class = ?,
           soft_threshold = ?, allowed_capabilities = ?, status = ?
       WHERE name = ?`,
    ).bind(
      body.credit_budget,
      body.request_quota,
      body.max_cost_class,
      body.soft_threshold,
      allowedCapabilitiesJson,
      body.status,
      name,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'plan_update', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, name, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok({ name });
}

export async function handlePlanDelete(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const name = parsePlanNameFromPath(request, "delete");
  if (!name) {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const existing = await DB.prepare("SELECT name FROM plan WHERE name = ?")
    .bind(name)
    .first<{ name: string }>();
  if (!existing) {
    return reject(404, "plan_not_found");
  }

  const recordedAt = nowIso();

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'plan_delete', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, name, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok({ name });
}
