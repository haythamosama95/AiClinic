/** Shared control_audit operator-identity assert helper (J3 Clarification Q3). */

export type ControlAuditRow = {
  operator_id: string;
  action: string;
  target: string;
};

export async function assertControlAudit(
  db: D1Database,
  expected: {
    operatorId: string;
    action: string;
    target?: string;
  },
): Promise<ControlAuditRow> {
  const row = await db
    .prepare(
      `SELECT operator_id, action, target FROM control_audit
       WHERE action = ? AND operator_id = ?
       ORDER BY recorded_at DESC LIMIT 1`,
    )
    .bind(expected.action, expected.operatorId)
    .first<ControlAuditRow>();

  if (!row) {
    throw new Error(
      `Expected control_audit row action=${expected.action} operator=${expected.operatorId}`,
    );
  }

  if (expected.target !== undefined && row.target !== expected.target) {
    throw new Error(
      `Expected control_audit target ${expected.target}, got ${row.target}`,
    );
  }

  return row;
}

export async function countControlAuditsForAction(
  db: D1Database,
  action: string,
): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) AS count FROM control_audit WHERE action = ?")
    .bind(action)
    .first<{ count: number }>();
  return row?.count ?? 0;
}
