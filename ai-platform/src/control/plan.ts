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

type PlanA17Fields = {
  price_cents?: number;
  currency?: string;
  display_name?: string;
  description?: string;
  grace_days?: number;
};

type PlanUpdatePayload = {
  credit_budget?: number;
  request_quota?: number;
  max_cost_class?: string;
  soft_threshold?: number;
  allowed_capabilities?: string[];
  status?: string;
} & PlanA17Fields;

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

function validateA17Fields(
  raw: Partial<PlanPayload>,
  options: { requireAll: boolean },
): PlanA17Fields | Response {
  const { requireAll } = options;
  const hasPrice = raw.price_cents !== undefined;
  const hasCurrency = raw.currency !== undefined;
  const hasDisplayName = raw.display_name !== undefined;
  const hasDescription = raw.description !== undefined;
  const hasGrace = raw.grace_days !== undefined;

  if (requireAll) {
    if (!hasPrice || !hasCurrency || !hasDisplayName || !hasDescription) {
      return reject(400, "invalid_payload");
    }
  }

  const result: PlanA17Fields = {};

  if (hasPrice) {
    const price_cents = raw.price_cents;
    if (!Number.isInteger(price_cents) || price_cents! < 0) {
      return reject(400, "invalid_payload");
    }
    result.price_cents = price_cents;
  }

  if (hasCurrency) {
    const currency = requireNonEmptyString(raw.currency);
    if (currency === null) {
      return reject(400, "invalid_payload");
    }
    result.currency = currency;
  }

  if (hasDisplayName) {
    const display_name = requireNonEmptyString(raw.display_name);
    if (display_name === null) {
      return reject(400, "invalid_payload");
    }
    result.display_name = display_name;
  }

  if (hasDescription) {
    if (typeof raw.description !== "string") {
      return reject(400, "invalid_payload");
    }
    result.description = raw.description;
  }

  if (hasGrace) {
    const grace_days = raw.grace_days;
    if (!Number.isInteger(grace_days) || grace_days! < 0) {
      return reject(400, "invalid_payload");
    }
    result.grace_days = grace_days;
  }

  return result;
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

  const a17 = validateA17Fields(raw, { requireAll: true });
  if (a17 instanceof Response) {
    return a17;
  }

  return {
    name,
    credit_budget,
    request_quota,
    max_cost_class,
    soft_threshold,
    allowed_capabilities: raw.allowed_capabilities,
    status,
    price_cents: a17.price_cents!,
    currency: a17.currency!,
    display_name: a17.display_name!,
    description: a17.description!,
    ...(a17.grace_days !== undefined ? { grace_days: a17.grace_days } : {}),
  };
}

function validatePlanUpdatePayload(
  body: unknown,
): PlanUpdatePayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }

  const raw = body as Partial<PlanPayload>;
  const result: PlanUpdatePayload = {};

  const hasG1Economics =
    raw.credit_budget !== undefined ||
    raw.request_quota !== undefined ||
    raw.max_cost_class !== undefined ||
    raw.soft_threshold !== undefined ||
    raw.allowed_capabilities !== undefined ||
    raw.status !== undefined;

  if (hasG1Economics) {
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

    result.credit_budget = credit_budget;
    result.request_quota = request_quota;
    result.max_cost_class = max_cost_class;
    result.soft_threshold = soft_threshold;
    result.allowed_capabilities = raw.allowed_capabilities;
    result.status = status;
  }

  const hasA17 =
    raw.price_cents !== undefined ||
    raw.currency !== undefined ||
    raw.display_name !== undefined ||
    raw.description !== undefined ||
    raw.grace_days !== undefined;

  if (hasA17) {
    const a17 = validateA17Fields(raw, { requireAll: false });
    if (a17 instanceof Response) {
      return a17;
    }
    Object.assign(result, a17);
  }

  if (!hasG1Economics && !hasA17) {
    return reject(400, "invalid_payload");
  }

  return result;
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

  const includeGrace = body.grace_days !== undefined;
  const insertSql = includeGrace
    ? `INSERT INTO plan (
         name, credit_budget, request_quota, max_cost_class,
         soft_threshold, allowed_capabilities, status,
         price_cents, currency, display_name, description, grace_days
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    : `INSERT INTO plan (
         name, credit_budget, request_quota, max_cost_class,
         soft_threshold, allowed_capabilities, status,
         price_cents, currency, display_name, description
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

  const insertBind = includeGrace
    ? [
        body.name,
        body.credit_budget,
        body.request_quota,
        body.max_cost_class,
        body.soft_threshold,
        allowedCapabilitiesJson,
        body.status,
        body.price_cents,
        body.currency,
        body.display_name,
        body.description,
        body.grace_days,
      ]
    : [
        body.name,
        body.credit_budget,
        body.request_quota,
        body.max_cost_class,
        body.soft_threshold,
        allowedCapabilitiesJson,
        body.status,
        body.price_cents,
        body.currency,
        body.display_name,
        body.description,
      ];

  const batchError = await runControlBatch(DB, [
    DB.prepare(insertSql).bind(...insertBind),
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
  const setClauses: string[] = [];
  const bindValues: unknown[] = [];

  if (body.credit_budget !== undefined) {
    setClauses.push("credit_budget = ?");
    bindValues.push(body.credit_budget);
  }
  if (body.request_quota !== undefined) {
    setClauses.push("request_quota = ?");
    bindValues.push(body.request_quota);
  }
  if (body.max_cost_class !== undefined) {
    setClauses.push("max_cost_class = ?");
    bindValues.push(body.max_cost_class);
  }
  if (body.soft_threshold !== undefined) {
    setClauses.push("soft_threshold = ?");
    bindValues.push(body.soft_threshold);
  }
  if (body.allowed_capabilities !== undefined) {
    setClauses.push("allowed_capabilities = ?");
    bindValues.push(JSON.stringify(body.allowed_capabilities));
  }
  if (body.status !== undefined) {
    setClauses.push("status = ?");
    bindValues.push(body.status);
  }
  if (body.price_cents !== undefined) {
    setClauses.push("price_cents = ?");
    bindValues.push(body.price_cents);
  }
  if (body.currency !== undefined) {
    setClauses.push("currency = ?");
    bindValues.push(body.currency);
  }
  if (body.display_name !== undefined) {
    setClauses.push("display_name = ?");
    bindValues.push(body.display_name);
  }
  if (body.description !== undefined) {
    setClauses.push("description = ?");
    bindValues.push(body.description);
  }
  if (body.grace_days !== undefined) {
    setClauses.push("grace_days = ?");
    bindValues.push(body.grace_days);
  }

  bindValues.push(name);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE plan
       SET ${setClauses.join(", ")}
       WHERE name = ?`,
    ).bind(...bindValues),
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
    DB.prepare("DELETE FROM plan WHERE name = ?").bind(name),
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
