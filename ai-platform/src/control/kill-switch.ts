import { isCanonicalUuid } from "../platform-vocabulary";
import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireNonEmptyString,
  requireOperator,
} from "./http";
import type { ControlBindings, OperatorAuth } from "./types";

type KillSwitchScope = "global" | "capability" | "installation" | "provider";

type KillSwitchPayload = {
  scope: KillSwitchScope;
  target: string;
};

const KILL_SWITCH_SCOPES: ReadonlySet<string> = new Set([
  "global",
  "capability",
  "installation",
  "provider",
]);

type KillSwitchRouteAction = "arm" | "disarm";

type KillSwitchRow = {
  active: number | boolean;
};

export function parseKillSwitchRoute(
  request: Request,
): KillSwitchRouteAction | null {
  const pathname = new URL(request.url).pathname;
  const match = pathname.match(/^\/control\/kill-switches\/(arm|disarm)$/);
  return (match?.[1] as KillSwitchRouteAction | undefined) ?? null;
}

function isKillSwitchScope(value: string): value is KillSwitchScope {
  return KILL_SWITCH_SCOPES.has(value);
}

function validateKillSwitchPayload(body: unknown): KillSwitchPayload | Response {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return reject(400, "invalid_payload");
  }
  const scopeRaw = requireNonEmptyString((body as KillSwitchPayload).scope);
  const targetRaw = requireNonEmptyString((body as KillSwitchPayload).target);
  if (!scopeRaw || !targetRaw) {
    return reject(400, "invalid_payload");
  }
  if (!isKillSwitchScope(scopeRaw)) {
    return reject(400, "invalid_payload");
  }
  if (scopeRaw === "global" && targetRaw !== "global") {
    return reject(400, "invalid_payload");
  }
  if (scopeRaw === "installation" && !isCanonicalUuid(targetRaw)) {
    return reject(400, "invalid_payload");
  }
  return { scope: scopeRaw, target: targetRaw };
}

function auditTarget(scope: KillSwitchScope, target: string): string {
  return scope === "global" ? "global" : target;
}

function armAuditAction(scope: KillSwitchScope): string {
  return scope === "global" ? "kill_switch_global" : `kill_switch_${scope}`;
}

function disarmAuditAction(scope: KillSwitchScope): string {
  return scope === "global"
    ? "lift_kill_switch_global"
    : `lift_kill_switch_${scope}`;
}

function isKillSwitchRowActive(row: KillSwitchRow): boolean {
  return row.active === 1 || row.active === true;
}

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

async function assertInstallationExists(
  db: D1Database,
  installationId: string,
): Promise<Response | null> {
  const row = await db
    .prepare("SELECT installation_id FROM installation WHERE installation_id = ?")
    .bind(installationId)
    .first<{ installation_id: string }>();
  if (!row) {
    return reject(404, "installation_not_found");
  }
  return null;
}

async function loadKillSwitchRow(
  db: D1Database,
  scope: KillSwitchScope,
  target: string,
): Promise<KillSwitchRow | null> {
  return db
    .prepare(
      `SELECT active FROM kill_switch WHERE scope = ? AND target = ? LIMIT 1`,
    )
    .bind(scope, target)
    .first<KillSwitchRow>();
}

export async function handleKillSwitchArm(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseKillSwitchRoute(request);
  if (route !== "arm") {
    // Unreachable via HTTP: dispatch pre-filters with identical regexes; reachable via direct handler invocation in tests; kept as a safety net.
    return reject(400, "invalid_route");
  }

  const rawBody = await parseJsonBody<KillSwitchPayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateKillSwitchPayload(rawBody);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  if (body.scope === "installation") {
    const missingInstallation = await assertInstallationExists(DB, body.target);
    if (missingInstallation) {
      return missingInstallation;
    }
  }

  const existing = await loadKillSwitchRow(DB, body.scope, body.target);
  if (existing && isKillSwitchRowActive(existing)) {
    return reject(409, "illegal_kill_switch_transition");
  }

  const recordedAt = nowIso();
  const target = auditTarget(body.scope, body.target);
  const beforePointer = existing ? "0" : null;

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
       VALUES (?, ?, 1, ?, ?)
       ON CONFLICT(scope, target) DO UPDATE SET
         active = 1,
         changed_at = excluded.changed_at,
         changed_by = excluded.changed_by`,
    ).bind(body.scope, body.target, recordedAt, auth.operatorId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      armAuditAction(body.scope),
      target,
      beforePointer,
      "1",
      recordedAt,
    ),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok();
}

export async function handleKillSwitchDisarm(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseKillSwitchRoute(request);
  if (route !== "disarm") {
    // Unreachable via HTTP: dispatch pre-filters with identical regexes; reachable via direct handler invocation in tests; kept as a safety net.
    return reject(400, "invalid_route");
  }

  const rawBody = await parseJsonBody<KillSwitchPayload>(request);
  if (rawBody instanceof Response) {
    return rawBody;
  }

  const body = validateKillSwitchPayload(rawBody);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const existing = await loadKillSwitchRow(DB, body.scope, body.target);
  if (!existing || !isKillSwitchRowActive(existing)) {
    return reject(409, "illegal_kill_switch_transition");
  }

  const recordedAt = nowIso();
  const target = auditTarget(body.scope, body.target);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE kill_switch
       SET active = 0, changed_at = ?, changed_by = ?
       WHERE scope = ? AND target = ? AND active = 1`,
    ).bind(recordedAt, auth.operatorId, body.scope, body.target),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      disarmAuditAction(body.scope),
      target,
      "1",
      "0",
      recordedAt,
    ),
  ]);
  if (batchError) {
    return batchError;
  }

  return ok();
}
