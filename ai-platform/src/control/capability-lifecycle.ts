import { OVERLAP_WINDOW_MS } from "../capability";
import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireOperator,
} from "./http";
import type {
  CapabilityRoute,
  ControlBindings,
  DeprecatePayload,
  OperatorAuth,
} from "./types";

export function parseCapabilityRoute(request: Request): CapabilityRoute | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/(deprecate|retire)$/,
  );
  if (!match) {
    return null;
  }
  return {
    capabilityId: match[1],
    version: match[2],
    action: match[3] as "deprecate" | "retire",
  };
}

async function loadGlobalOverlay(
  db: D1Database,
  capabilityId: string,
  version: string,
): Promise<Record<string, unknown> | null> {
  const row = await db
    .prepare(
      `SELECT lifecycle_state, successor_id, deprecated_at, retire_after
       FROM capability_grant
       WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
       ORDER BY changed_at DESC LIMIT 1`,
    )
    .bind(capabilityId, version)
    .first<Record<string, unknown>>();
  return row ?? null;
}

export async function handleDeprecate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCapabilityRoute(request);
  if (!route || route.action !== "deprecate") {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<DeprecatePayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!body.successor_id) {
    return reject(400, "missing_successor_id");
  }

  const { DB } = bindings;
  const deprecatedAt = nowIso();
  const retireAfter = new Date(
    new Date(deprecatedAt).getTime() + OVERLAP_WINDOW_MS,
  ).toISOString();
  const grantId = newId();
  const target = `${route.capabilityId}@${route.version}`;

  await DB.batch([
    DB.prepare(
      `INSERT INTO capability_grant (
         grant_id, scope, capability_id, capability_version,
         granted_at, revoked_at, changed_at, changed_by,
         lifecycle_state, successor_id, deprecated_at, retire_after
       ) VALUES (?, 'global', ?, ?, ?, NULL, ?, ?, 'deprecated', ?, ?, ?)`,
    ).bind(
      grantId,
      route.capabilityId,
      route.version,
      deprecatedAt,
      deprecatedAt,
      auth.operatorId,
      body.successor_id,
      deprecatedAt,
      retireAfter,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'deprecate', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, deprecatedAt),
  ]);

  return ok();
}

export async function handleRetire(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseCapabilityRoute(request);
  if (!route || route.action !== "retire") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const overlay = await loadGlobalOverlay(DB, route.capabilityId, route.version);

  if (
    !overlay ||
    overlay.lifecycle_state !== "deprecated" ||
    typeof overlay.successor_id !== "string" ||
    !overlay.successor_id
  ) {
    return reject(400, "not_deprecated");
  }

  const retireAfter =
    typeof overlay.retire_after === "string" ? overlay.retire_after : null;
  if (!retireAfter || nowIso() < retireAfter) {
    return reject(400, "overlap_window_active");
  }

  const recordedAt = nowIso();
  const grantId = newId();
  const target = `${route.capabilityId}@${route.version}`;

  await DB.batch([
    DB.prepare(
      `INSERT INTO capability_grant (
         grant_id, scope, capability_id, capability_version,
         granted_at, revoked_at, changed_at, changed_by,
         lifecycle_state, successor_id, deprecated_at, retire_after
       ) VALUES (?, 'global', ?, ?, ?, NULL, ?, ?, 'retired', ?, ?, ?)`,
    ).bind(
      grantId,
      route.capabilityId,
      route.version,
      recordedAt,
      recordedAt,
      auth.operatorId,
      overlay.successor_id,
      overlay.deprecated_at,
      overlay.retire_after,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'retire', ?, NULL, NULL, ?)`,
    ).bind(newId(), auth.operatorId, target, recordedAt),
  ]);

  return ok();
}
