export function nowIso(): string {
  return new Date().toISOString();
}

export function newId(): string {
  return crypto.randomUUID();
}

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
  beforePointer: string | null = null,
  afterPointer: string | null = null,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, actor, action, target, assertion_sha256, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      newId(),
      actor,
      actor,
      action,
      target,
      assertionSha256,
      beforePointer,
      afterPointer,
      nowIso(),
    )
    .run();
}
