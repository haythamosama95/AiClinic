import { newId, nowIso } from "./http";

export async function writeAudit(
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

export async function writeEntrypointAudit(
  db: D1Database,
  actor: string,
  action: string,
  target: string,
  assertionSha256: string | null,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, actor, action, target, assertion_sha256, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?)`,
    )
    .bind(newId(), actor, actor, action, target, assertionSha256, nowIso())
    .run();
}
