import { isCapabilityVersionRegistered } from "../capability";
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

function parseAllowedCapabilities(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw.every((entry) => typeof entry === "string")
      ? (raw as string[])
      : [];
  }
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (
        !Array.isArray(parsed) ||
        !parsed.every((entry) => typeof entry === "string")
      ) {
        return [];
      }
      return parsed as string[];
    } catch {
      return [];
    }
  }
  return [];
}

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

  if (!isCapabilityVersionRegistered(route.capabilityId, route.version)) {
    return reject(404, "capability_not_found");
  }

  const body = await parseJsonBody<CohortPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!Array.isArray(body.installation_ids) || body.installation_ids.length === 0) {
    return reject(400, "missing_installation_ids");
  }

  const { DB } = bindings;
  const missingInstallations = await assertInstallationsExist(
    DB,
    body.installation_ids,
  );
  if (missingInstallations) {
    return missingInstallations;
  }

  const recordedAt = nowIso();
  const target = body.cohort_name
    ? `${route.capabilityId}@${route.version}:${body.cohort_name}`
    : `${route.capabilityId}@${route.version}`;

  const priorVersions: Record<string, string | null> = {};
  const statements: D1PreparedStatement[] = [];

  for (const installationId of body.installation_ids) {
    const existing = await DB.prepare(
      `SELECT grant_id, capability_version FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(`installation:${installationId}`, route.capabilityId)
      .first<{ grant_id: string; capability_version: string }>();

    priorVersions[installationId] = existing?.capability_version ?? null;

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

  const beforePointer =
    Object.values(priorVersions).some((v) => v !== null)
      ? JSON.stringify(priorVersions)
      : null;
  const afterPointer = route.version;

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'cohort_activate', ?, ?, ?, ?)`,
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

  if (!isCapabilityVersionRegistered(route.capabilityId, route.version)) {
    return reject(404, "capability_not_found");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.capabilityId}@${route.version}`;

  const liveInstallationGrants = await DB.prepare(
    `SELECT grant_id, scope, capability_version FROM capability_grant
     WHERE capability_id = ? AND scope LIKE 'installation:%' AND revoked_at IS NULL`,
  )
    .bind(route.capabilityId)
    .all<{ grant_id: string; scope: string; capability_version: string }>();

  const livePlanGrants = await DB.prepare(
    `SELECT grant_id, scope, capability_version FROM capability_grant
     WHERE capability_id = ? AND scope LIKE 'plan:%' AND revoked_at IS NULL`,
  )
    .bind(route.capabilityId)
    .all<{ grant_id: string; scope: string; capability_version: string }>();

  const beforePointer = JSON.stringify({
    installation: (liveInstallationGrants.results ?? []).map((g) => ({
      scope: g.scope,
      version: g.capability_version,
    })),
    plan: (livePlanGrants.results ?? []).map((g) => ({
      scope: g.scope,
      version: g.capability_version,
    })),
  });
  const afterPointer = route.version;

  const statements: D1PreparedStatement[] = [];

  for (const grant of liveInstallationGrants.results ?? []) {
    statements.push(
      DB.prepare(
        `UPDATE capability_grant
         SET capability_version = ?, changed_at = ?, changed_by = ?
         WHERE grant_id = ?`,
      ).bind(route.version, recordedAt, auth.operatorId, grant.grant_id),
    );
  }

  for (const grant of livePlanGrants.results ?? []) {
    statements.push(
      DB.prepare(
        `UPDATE capability_grant
         SET capability_version = ?, changed_at = ?, changed_by = ?
         WHERE grant_id = ?`,
      ).bind(route.version, recordedAt, auth.operatorId, grant.grant_id),
    );
  }

  // Upsert plan grants for distinct plans on active entitlements that allow this capability.
  const entitlements = await DB.prepare(
    `SELECT installation_id, plan, allowed_capabilities FROM entitlement
     WHERE status = 'active'`,
  ).all<{
    installation_id: string;
    plan: string;
    allowed_capabilities: string;
  }>();

  const existingPlanScopes = new Set(
    (livePlanGrants.results ?? []).map((g) => g.scope),
  );
  const plansNeedingGrant = new Set<string>();
  const installationsWithLiveGrant = new Set(
    (liveInstallationGrants.results ?? []).map((g) =>
      g.scope.replace(/^installation:/, ""),
    ),
  );

  const entitledInstallations: string[] = [];

  for (const ent of entitlements.results ?? []) {
    const allowed = parseAllowedCapabilities(ent.allowed_capabilities);
    if (!allowed.includes(route.capabilityId)) {
      continue;
    }
    entitledInstallations.push(ent.installation_id);
    if (!existingPlanScopes.has(`plan:${ent.plan}`)) {
      plansNeedingGrant.add(ent.plan);
    }
  }

  for (const plan of plansNeedingGrant) {
    const scope = `plan:${plan}`;
    const existing = await DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(scope, route.capabilityId)
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
          scope,
          route.capabilityId,
          route.version,
          recordedAt,
          recordedAt,
          auth.operatorId,
        ),
      );
    }
  }

  // Materialize installation grants for entitled installations missing a live grant.
  for (const installationId of entitledInstallations) {
    if (installationsWithLiveGrant.has(installationId)) {
      continue;
    }

    const existing = await DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
       ORDER BY changed_at DESC LIMIT 1`,
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
       VALUES (?, ?, 'cohort_promote', ?, ?, ?, ?)`,
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
