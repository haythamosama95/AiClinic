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

export function parseRoutingPolicyRoute(
  request: Request,
): RoutingPolicyRoute | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/(publish|canary|rollback)$/,
  );
  if (!match) {
    return null;
  }
  return {
    policyId: match[1],
    version: match[2],
    action: match[3] as "publish" | "canary" | "rollback",
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
         policy_id, version, content_pointer, active_from, activated_by, canary_installation_ids
       ) VALUES (?, ?, ?, ?, ?, NULL)`,
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
    `SELECT policy_id FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<{ policy_id: string }>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET canary_installation_ids = ?
       WHERE policy_id = ? AND version = ?`,
    ).bind(
      JSON.stringify(body.installation_ids),
      route.policyId,
      route.version,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_canary', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
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
    `SELECT policy_id FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<{ policy_id: string }>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_rollback', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  ]);

  return ok();
}
