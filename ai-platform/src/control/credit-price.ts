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
  CreditPriceActivatePayload,
  OperatorAuth,
} from "./types";

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

function validateCreditPricePayload(
  body: unknown,
): CreditPriceActivatePayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }

  const raw = body as CreditPriceActivatePayload;
  const version = requireNonEmptyString(raw.version);
  if (!version) {
    return reject(400, "invalid_payload");
  }

  const price_per_credit = raw.price_per_credit;
  if (
    typeof price_per_credit !== "number" ||
    !Number.isFinite(price_per_credit) ||
    price_per_credit < 0
  ) {
    return reject(400, "invalid_payload");
  }

  const currency = requireNonEmptyString(raw.currency);
  if (!currency) {
    return reject(400, "invalid_payload");
  }

  const active_from = requireNonEmptyString(raw.active_from);
  if (!active_from) {
    return reject(400, "invalid_payload");
  }

  return {
    version,
    price_per_credit,
    currency,
    active_from,
  };
}

export async function handleCreditPriceActivate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const rawBody = await parseJsonBody<CreditPriceActivatePayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateCreditPricePayload(rawBody);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const recordedAt = nowIso();

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `INSERT INTO credit_price (
         version, price_per_credit, currency, active_from, activated_by
       ) VALUES (?, ?, ?, ?, ?)`,
    ).bind(
      body.version,
      body.price_per_credit,
      body.currency,
      body.active_from,
      auth.operatorId,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'credit_price_activate', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, body.version, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok({ version: body.version });
}
