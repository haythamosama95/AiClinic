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
  EnrollPayload,
  OperatorAuth,
  RotatePayload,
} from "./types";

const INSTALLATION_ACTIVE_STATUS = "active";
const INSTALLATION_SUSPENDED_STATUS = "suspended";
const INSTALLATION_DELETED_STATUS = "deleted";

/** Hard TTL for `installation_key.valid_until`, measured from `valid_from`. */
export const INSTALLATION_KEY_TTL_DAYS = 365;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

function installationKeyValidUntil(validFromIso: string): string {
  return new Date(
    Date.parse(validFromIso) + INSTALLATION_KEY_TTL_DAYS * MS_PER_DAY,
  ).toISOString();
}

function parseInstallationId(request: Request): string | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/(?:enroll|rotate|revoke-key|suspend|resume|delete)$/,
  );
  return match?.[1] ?? null;
}

type RevokeKeyPayload = {
  kid: string;
};

function validateRevokeKeyPayload(
  body: RevokeKeyPayload,
): RevokeKeyPayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }
  const kid = requireNonEmptyString(body.kid);
  if (!kid) {
    return reject(400, "invalid_payload");
  }
  return { kid };
}

function validateEnrollPayload(
  body: EnrollPayload,
): EnrollPayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }
  const org_id = requireNonEmptyString(body.org_id);
  const display_name = requireNonEmptyString(body.display_name);
  const region = requireNonEmptyString(body.region);
  const plan = requireNonEmptyString(body.plan);
  const public_key = requireNonEmptyString(body.public_key);
  const algorithm = requireNonEmptyString(body.algorithm);
  const kid = requireNonEmptyString(body.kid);
  if (
    !org_id ||
    !display_name ||
    !region ||
    !plan ||
    !public_key ||
    !algorithm ||
    !kid
  ) {
    return reject(400, "invalid_payload");
  }
  return {
    org_id,
    display_name,
    region,
    plan,
    public_key,
    algorithm,
    kid,
  };
}

function validateRotatePayload(
  body: RotatePayload,
): RotatePayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }
  const kid = requireNonEmptyString(body.kid);
  const public_key = requireNonEmptyString(body.public_key);
  const algorithm = requireNonEmptyString(body.algorithm);
  if (!kid || !public_key || !algorithm) {
    return reject(400, "invalid_payload");
  }
  return { kid, public_key, algorithm };
}

function d1ErrorMessage(err: unknown): string {
  if (err instanceof Error) {
    return err.message;
  }
  return String(err);
}

function isUniqueConstraint(err: unknown): boolean {
  return /UNIQUE constraint failed|SQLITE_CONSTRAINT/i.test(
    d1ErrorMessage(err),
  );
}

function constraintTarget(
  err: unknown,
): "installation" | "installation_key" | "other" {
  const message = d1ErrorMessage(err);
  if (/installation_key/i.test(message)) {
    return "installation_key";
  }
  if (/installation\./i.test(message) || /installation /i.test(message)) {
    return "installation";
  }
  return "other";
}

async function runControlBatch(
  db: D1Database,
  statements: D1PreparedStatement[],
): Promise<Response | null> {
  try {
    await db.batch(statements);
    return null;
  } catch (err) {
    if (isUniqueConstraint(err)) {
      if (constraintTarget(err) === "installation_key") {
        return reject(409, "duplicate_kid");
      }
      return reject(409, "already_enrolled");
    }
    return reject(500, "storage_error");
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

  const rawBody = await parseJsonBody<EnrollPayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateEnrollPayload(rawBody);
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
  const validUntil = installationKeyValidUntil(enrolledAt);
  const entitlementId = newId();
  const auditId = newId();
  const platformBaseUrl = new URL(request.url).origin;

  const batchError = await runControlBatch(DB, [
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
       VALUES (?, ?, ?, ?, ?, ?, NULL)`,
    ).bind(
      body.kid,
      installationId,
      body.public_key,
      body.algorithm,
      enrolledAt,
      validUntil,
    ),
    // soft_threshold = 0 is the enroll sentinel (never degrades; F4 contract §2 /
    // isSoftThresholdFraction allows 0). Future entitlement writes must keep
    // soft_threshold in [0, 1] via coerceSoftThreshold / isSoftThresholdFraction.
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
  if (batchError) {
    return batchError;
  }

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

  const rawBody = await parseJsonBody<RotatePayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateRotatePayload(rawBody);
  if (body instanceof Response) {
    return body;
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

  if (installation.status === INSTALLATION_DELETED_STATUS) {
    return reject(409, "illegal_lifecycle_transition");
  }

  const existingKid = await DB.prepare(
    "SELECT key_id FROM installation_key WHERE key_id = ?",
  )
    .bind(body.kid)
    .first<{ key_id: string }>();
  if (existingKid) {
    return reject(409, "duplicate_kid");
  }

  const validFrom = nowIso();
  const validUntil = installationKeyValidUntil(validFrom);
  const auditId = newId();

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE installation_key
          SET revoked_at = ?
        WHERE installation_id = ? AND revoked_at IS NULL`,
    ).bind(validFrom, installationId),
    DB.prepare(
      `INSERT INTO installation_key
         (key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at)
       VALUES (?, ?, ?, ?, ?, ?, NULL)`,
    ).bind(
      body.kid,
      installationId,
      body.public_key,
      body.algorithm,
      validFrom,
      validUntil,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'rotate', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, validFrom),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok();
}

export async function handleRevokeKey(
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

  const rawBody = await parseJsonBody<RevokeKeyPayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateRevokeKeyPayload(rawBody);
  if (body instanceof Response) {
    return body;
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

  if (installation.status === INSTALLATION_DELETED_STATUS) {
    return reject(409, "illegal_lifecycle_transition");
  }

  const keyRow = await DB.prepare(
    `SELECT key_id, revoked_at FROM installation_key
     WHERE key_id = ? AND installation_id = ?`,
  )
    .bind(body.kid, installationId)
    .first<{ key_id: string; revoked_at: string | null }>();

  if (!keyRow) {
    return reject(404, "key_not_found");
  }

  if (keyRow.revoked_at != null) {
    return reject(409, "key_already_revoked");
  }

  const revokedAt = nowIso();
  const auditId = newId();

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE installation_key
          SET revoked_at = ?
        WHERE key_id = ? AND installation_id = ? AND revoked_at IS NULL`,
    ).bind(revokedAt, body.kid, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'revoke-key', ?, NULL, ?, ?)`,
    ).bind(auditId, auth.operatorId, installationId, body.kid, revokedAt),
  ]);
  if (batchError) {
    return batchError;
  }

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
    "SELECT installation_id, status FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string; status: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  if (
    installation.status === INSTALLATION_DELETED_STATUS ||
    installation.status === INSTALLATION_SUSPENDED_STATUS
  ) {
    return reject(409, "illegal_lifecycle_transition");
  }

  const recordedAt = nowIso();
  const auditId = newId();

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(INSTALLATION_SUSPENDED_STATUS, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'suspend', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

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

  if (installation.status !== INSTALLATION_SUSPENDED_STATUS) {
    return reject(409, "illegal_lifecycle_transition");
  }

  const recordedAt = nowIso();
  const auditId = newId();

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(INSTALLATION_ACTIVE_STATUS, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'resume', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

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
    "SELECT installation_id, status FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string; status: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  if (installation.status === INSTALLATION_DELETED_STATUS) {
    return reject(409, "illegal_lifecycle_transition");
  }

  const recordedAt = nowIso();
  const auditId = newId();

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(INSTALLATION_DELETED_STATUS, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'delete', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok();
}
