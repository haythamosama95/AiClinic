import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireOperator,
} from "./http";
import type {
  CohortPayload,
  ControlBindings,
  OperatorAuth,
  PublishPayload,
  RoutingPolicyRoute,
} from "./types";

type RoutingPolicyRow = {
  policy_id: string;
  version: string;
  status: string;
  canary_installation_ids: string | null;
  active_from: string;
};

async function assertInstallationsExist(
  db: D1Database,
  ids: string[],
): Promise<Response | null> {
  for (const id of ids) {
    const row = await db
      .prepare(
        `SELECT installation_id FROM installation WHERE installation_id = ?`,
      )
      .bind(id)
      .first<{ installation_id: string }>();
    if (!row) {
      return reject(404, "installation_not_found");
    }
  }
  return null;
}

export function parseRoutingPolicyRoute(
  request: Request,
): RoutingPolicyRoute | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/(publish|canary|promote|rollback)$/,
  );
  if (!match) {
    return null;
  }
  return {
    policyId: match[1],
    version: match[2],
    action: match[3] as "publish" | "canary" | "promote" | "rollback",
  };
}

export async function handleRoutingPolicyPublish(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "publish") {
    return reject(400, "invalid_route");
  }

  if (!bindings.R2) {
    return reject(500, "missing_r2_binding");
  }

  const body = await parseJsonBody<PublishPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!body.document || typeof body.document !== "object") {
    return reject(400, "missing_document");
  }

  const { DB, R2 } = bindings;
  const recordedAt = nowIso();
  const contentPointer = `control/routing-policy/${route.policyId}/${route.version}.json`;
  const target = `${route.policyId}@${route.version}`;

  await R2.put(contentPointer, JSON.stringify(body.document), {
    httpMetadata: { contentType: "application/json" },
  });

  await DB.batch([
    DB.prepare(
      `INSERT INTO routing_policy (
         policy_id, version, content_pointer, active_from, activated_by,
         canary_installation_ids, status
       ) VALUES (?, ?, ?, ?, ?, NULL, 'published')`,
    ).bind(
      route.policyId,
      route.version,
      contentPointer,
      recordedAt,
      auth.operatorId,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_publish', ?, NULL, ?, ?)`,
    ).bind(newId(), auth.operatorId, target, contentPointer, recordedAt),
  ]);

  return ok();
}

export async function handleRoutingPolicyCanary(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "canary") {
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
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  if (existing.status !== "published" && existing.status !== "canary") {
    return reject(409, "illegal_policy_transition");
  }

  const missingInstallations = await assertInstallationsExist(
    DB,
    body.installation_ids,
  );
  if (missingInstallations) {
    return missingInstallations;
  }

  const priorCanary = await DB.prepare(
    `SELECT canary_installation_ids FROM routing_policy
     WHERE policy_id = ? AND status = 'canary'
     ORDER BY active_from DESC, version DESC LIMIT 1`,
  )
    .bind(route.policyId)
    .first<{ canary_installation_ids: string | null }>();

  const beforePointer = priorCanary?.canary_installation_ids ?? null;
  const afterPointer = JSON.stringify(body.installation_ids);

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'canary', canary_installation_ids = ?
       WHERE policy_id = ? AND version = ?`,
    ).bind(afterPointer, route.policyId, route.version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_canary', ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      target,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  ]);

  return ok();
}

export async function handleRoutingPolicyPromote(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "promote") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  const priorActive = await DB.prepare(
    `SELECT version FROM routing_policy
     WHERE policy_id = ? AND status = 'active'
     ORDER BY active_from DESC, version DESC LIMIT 1`,
  )
    .bind(route.policyId)
    .first<{ version: string }>();

  const beforePointer = priorActive
    ? `${route.policyId}@${priorActive.version}`
    : null;
  const afterPointer = target;

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND status = 'active' AND version != ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND status = 'canary' AND version != ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'active', canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_promote', ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      target,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  ]);

  return ok();
}

export async function handleRoutingPolicyRollback(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "rollback") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  const statements: D1PreparedStatement[] = [];
  let beforePointer: string | null = `${route.policyId}@${route.version}`;
  let afterPointer: string | null = null;

  if (existing.status === "canary") {
    const active = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'active'
       ORDER BY active_from DESC, version DESC LIMIT 1`,
    )
      .bind(route.policyId)
      .first<{ version: string }>();

    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'published', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(route.policyId, route.version),
    );
    afterPointer = active
      ? `${route.policyId}@${active.version}`
      : null;
  } else if (existing.status === "active") {
    const prior = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'superseded'
       ORDER BY active_from DESC, version DESC LIMIT 1`,
    )
      .bind(route.policyId)
      .first<{ version: string }>();

    if (!prior) {
      return reject(409, "illegal_policy_transition");
    }

    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'superseded', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(route.policyId, route.version),
    );
    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'active', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(route.policyId, prior.version),
    );
    afterPointer = `${route.policyId}@${prior.version}`;
  } else {
    // published (or other): succeed, clear any canary split on this policy
    beforePointer = existing.canary_installation_ids
      ? `${route.policyId}@${route.version}`
      : null;
    const active = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'active'
       ORDER BY active_from DESC, version DESC LIMIT 1`,
    )
      .bind(route.policyId)
      .first<{ version: string }>();
    afterPointer = active
      ? `${route.policyId}@${active.version}`
      : null;
  }

  // Always clear canary split on this policy_id.
  statements.push(
    DB.prepare(
      `UPDATE routing_policy
       SET status = CASE WHEN status = 'canary' THEN 'published' ELSE status END,
           canary_installation_ids = NULL
       WHERE policy_id = ? AND (status = 'canary' OR canary_installation_ids IS NOT NULL)`,
    ).bind(route.policyId),
  );

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_rollback', ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      target,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  );

  await DB.batch(statements);
  return ok();
}
