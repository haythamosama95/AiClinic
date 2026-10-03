import { isCanonicalUuid, toCanonicalUuid } from "../platform-vocabulary";
import {
  newId,
  nowIso,
  ok,
  reject,
  requireOperator,
} from "./http";
import type { ControlBindings, OperatorAuth } from "./types";

const INSTALLATION_ACTIVE_STATUS = "active";
const INSTALLATION_SUSPENDED_STATUS = "suspended";
const INSTALLATION_DELETED_STATUS = "deleted";

function parseInstallationId(request: Request): string | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/(?:suspend|resume|delete)$/,
  );
  return match?.[1] ?? null;
}

function requireValidInstallationId(
  installationId: string | null,
): string | Response {
  if (!installationId) {
    // Unreachable via HTTP because dispatch pre-filters with identical regexes; reachable via direct handler invocation in tests; kept as a safety net.
    return reject(400, "invalid_route");
  }
  if (!isCanonicalUuid(installationId)) {
    return reject(400, "invalid_payload");
  }
  return toCanonicalUuid(installationId);
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

async function runControlBatch(
  db: D1Database,
  statements: D1PreparedStatement[],
): Promise<Response | null> {
  try {
    await db.batch(statements);
    return null;
  } catch (err) {
    if (isUniqueConstraint(err)) {
      return reject(409, "already_enrolled");
    }
    return reject(500, "storage_error");
  }
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

  const installationId = requireValidInstallationId(parseInstallationId(request));
  if (installationId instanceof Response) {
    return installationId;
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

  const installationId = requireValidInstallationId(parseInstallationId(request));
  if (installationId instanceof Response) {
    return installationId;
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

  const installationId = requireValidInstallationId(parseInstallationId(request));
  if (installationId instanceof Response) {
    return installationId;
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
