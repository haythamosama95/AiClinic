import { isCanonicalUuid } from "../platform-vocabulary";
import { nowIso, writeEntrypointAudit } from "./audit";
import type { ControlActionResult, ControlBindings } from "./types";
import { requireNonEmptyString } from "./types";

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

type KillSwitchRow = {
  active: number | boolean;
};

function isKillSwitchScope(value: string): value is KillSwitchScope {
  return KILL_SWITCH_SCOPES.has(value);
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
): Promise<ControlActionResult | null> {
  try {
    await db.batch(statements);
    return null;
  } catch {
    return { ok: false, status: 500, error: "storage_error" };
  }
}

async function assertInstallationExists(
  db: D1Database,
  installationId: string,
): Promise<ControlActionResult | null> {
  const row = await db
    .prepare("SELECT installation_id FROM installation WHERE installation_id = ?")
    .bind(installationId)
    .first<{ installation_id: string }>();
  if (!row) {
    return { ok: false, status: 404, error: "installation_not_found" };
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

function payloadFromArgs(
  args: Record<string, unknown>,
): KillSwitchPayload | ControlActionResult {
  const scopeRaw = requireNonEmptyString(args.scope);
  const targetRaw = requireNonEmptyString(args.target);
  if (!scopeRaw || !targetRaw) {
    return { ok: false, status: 400, error: "invalid_payload" };
  }
  if (!isKillSwitchScope(scopeRaw)) {
    return { ok: false, status: 400, error: "invalid_payload" };
  }
  if (scopeRaw === "global" && targetRaw !== "global") {
    return { ok: false, status: 400, error: "invalid_payload" };
  }
  if (scopeRaw === "installation" && !isCanonicalUuid(targetRaw)) {
    return { ok: false, status: 400, error: "invalid_payload" };
  }
  return { scope: scopeRaw, target: targetRaw };
}

export async function armKillSwitchAction(
  bindings: ControlBindings,
  actor: string,
  args: Record<string, unknown>,
): Promise<ControlActionResult> {
  const body = payloadFromArgs(args);
  if ("ok" in body && body.ok === false) {
    return body;
  }
  const payload = body as KillSwitchPayload;
  const { DB } = bindings;

  if (payload.scope === "installation") {
    const missingInstallation = await assertInstallationExists(DB, payload.target);
    if (missingInstallation) {
      return missingInstallation;
    }
  }

  const existing = await loadKillSwitchRow(DB, payload.scope, payload.target);
  if (existing && isKillSwitchRowActive(existing)) {
    return { ok: false, status: 409, error: "illegal_kill_switch_transition" };
  }

  const recordedAt = nowIso();
  const target = auditTarget(payload.scope, payload.target);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
       VALUES (?, ?, 1, ?, ?)
       ON CONFLICT(scope, target) DO UPDATE SET
         active = 1,
         changed_at = excluded.changed_at,
         changed_by = excluded.changed_by`,
    ).bind(payload.scope, payload.target, recordedAt, actor),
  ]);
  if (batchError) {
    return batchError;
  }

  await writeEntrypointAudit(
    DB,
    actor,
    armAuditAction(payload.scope),
    target,
    null,
  );

  return { ok: true, body: {} };
}

export async function disarmKillSwitchAction(
  bindings: ControlBindings,
  actor: string,
  args: Record<string, unknown>,
): Promise<ControlActionResult> {
  const body = payloadFromArgs(args);
  if ("ok" in body && body.ok === false) {
    return body;
  }
  const payload = body as KillSwitchPayload;
  const { DB } = bindings;

  const existing = await loadKillSwitchRow(DB, payload.scope, payload.target);
  if (!existing || !isKillSwitchRowActive(existing)) {
    return { ok: false, status: 409, error: "illegal_kill_switch_transition" };
  }

  const recordedAt = nowIso();
  const target = auditTarget(payload.scope, payload.target);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE kill_switch
       SET active = 0, changed_at = ?, changed_by = ?
       WHERE scope = ? AND target = ? AND active = 1`,
    ).bind(recordedAt, actor, payload.scope, payload.target),
  ]);
  if (batchError) {
    return batchError;
  }

  await writeEntrypointAudit(
    DB,
    actor,
    disarmAuditAction(payload.scope),
    target,
    null,
  );

  return { ok: true, body: {} };
}
