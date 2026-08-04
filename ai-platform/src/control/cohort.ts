import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireOperator,
} from "./http";
import type {
  CohortCapabilityRoute,
  CohortPayload,
  ControlBindings,
  OperatorAuth,
} from "./types";

export function parseCohortCapabilityRoute(
  request: Request,
): CohortCapabilityRoute | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/(activate|promote)$/,
  );
  if (!match) {
    return null;
  }
  return {
    capabilityId: match[1],
    version: match[2],
    action: match[3] as "activate" | "promote",
  };
}

export async function handleCohortActivate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCohortCapabilityRoute(request);
  if (!route || route.action !== "activate") {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<CohortPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!Array.isArray(body.installation_ids) || body.installation_ids.length === 0) {
    return reject(400, "missing_installation_ids");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = body.cohort_name
    ? `${route.capabilityId}@${route.version}:${body.cohort_name}`
    : `${route.capabilityId}@${route.version}`;

  const statements: D1PreparedStatement[] = [];
  for (const installationId of body.installation_ids) {
    const existing = await DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL`,
    )
      .bind(`installation:${installationId}`, route.capabilityId)
      .first<{ grant_id: string }>();

    if (existing) {
      statements.push(
        DB.prepare(
          `UPDATE capability_grant
           SET capability_version = ?, changed_at = ?, changed_by = ?
           WHERE grant_id = ?`,
        ).bind(route.version, recordedAt, auth.operatorId, existing.grant_id),
      );
    } else {
      statements.push(
        DB.prepare(
          `INSERT INTO capability_grant (
             grant_id, scope, capability_id, capability_version,
             granted_at, revoked_at, changed_at, changed_by
           ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
        ).bind(
          newId(),
          `installation:${installationId}`,
          route.capabilityId,
          route.version,
          recordedAt,
          recordedAt,
          auth.operatorId,
        ),
      );
    }
  }

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'cohort_activate', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  );

  await DB.batch(statements);
  return ok();
}

export async function handleCohortPromote(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCohortCapabilityRoute(request);
  if (!route || route.action !== "promote") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.capabilityId}@${route.version}`;

  const grants = await DB.prepare(
    `SELECT grant_id FROM capability_grant
     WHERE capability_id = ? AND scope LIKE 'installation:%' AND revoked_at IS NULL`,
  )
    .bind(route.capabilityId)
    .all<{ grant_id: string }>();

  const statements: D1PreparedStatement[] = (grants.results ?? []).map((grant) =>
    DB.prepare(
      `UPDATE capability_grant
       SET capability_version = ?, changed_at = ?, changed_by = ?
       WHERE grant_id = ?`,
    ).bind(route.version, recordedAt, auth.operatorId, grant.grant_id),
  );

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'cohort_promote', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  );

  if (statements.length > 0) {
    await DB.batch(statements);
  }

  return ok();
}
