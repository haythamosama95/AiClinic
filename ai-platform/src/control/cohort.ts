import { isCapabilityVersionRegistered } from "../capability";
import { toCanonicalUuid } from "../platform-vocabulary";
import { newId, nowIso } from "./audit";
import type { ControlActionResult, ControlBindings } from "./types";
import { requireNonEmptyString } from "./types";

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

function parseTermSnapshotCapabilities(termSnapshot: string): string[] {
  try {
    const parsed = JSON.parse(termSnapshot) as { capabilities?: unknown };
    if (!Array.isArray(parsed.capabilities)) {
      return [];
    }
    if (!parsed.capabilities.every((entry) => typeof entry === "string")) {
      return [];
    }
    return parsed.capabilities as string[];
  } catch {
    return [];
  }
}

async function assertInstallationsExist(
  db: D1Database,
  ids: string[],
): Promise<ControlActionResult | null> {
  for (const id of ids) {
    const row = await db
      .prepare(
        `SELECT installation_id FROM installation WHERE installation_id = ?`,
      )
      .bind(id)
      .first<{ installation_id: string }>();
    if (!row) {
      return { ok: false, status: 404, error: "installation_not_found" };
    }
  }
  return null;
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

async function installationIdsWithCapability(
  db: D1Database,
  capabilityId: string,
): Promise<string[]> {
  const rows = await db
    .prepare(
      `SELECT tb.installation_id, cm.term_snapshot
       FROM tenant_binding tb
       INNER JOIN coverage_mirror cm ON cm.installation_id = tb.installation_id
       WHERE tb.status = 'active'`,
    )
    .all<{ installation_id: string; term_snapshot: string }>();

  const installationIds: string[] = [];
  for (const row of rows.results ?? []) {
    const capabilities = parseTermSnapshotCapabilities(row.term_snapshot);
    if (capabilities.includes(capabilityId)) {
      installationIds.push(row.installation_id);
    }
  }
  return installationIds;
}

async function publishedPlansAllowingCapability(
  db: D1Database,
  capabilityId: string,
): Promise<string[]> {
  const rows = await db
    .prepare(
      `SELECT plan_id, capabilities FROM plan_version WHERE status = 'published'`,
    )
    .all<{ plan_id: string; capabilities: string }>();

  const planIds: string[] = [];
  for (const row of rows.results ?? []) {
    const allowed = parseAllowedCapabilities(row.capabilities);
    if (allowed.includes(capabilityId)) {
      planIds.push(row.plan_id);
    }
  }
  return planIds;
}

export async function activateCohortAction(
  bindings: ControlBindings,
  actor: string,
  args: Record<string, unknown>,
): Promise<ControlActionResult> {
  const capabilityId = requireNonEmptyString(args.capability_id);
  const version = requireNonEmptyString(args.capability_version);
  if (!capabilityId || !version) {
    return { ok: false, status: 400, error: "invalid_payload" };
  }

  if (!isCapabilityVersionRegistered(capabilityId, version)) {
    return { ok: false, status: 404, error: "capability_not_found" };
  }

  const installationIdsRaw = args.installation_ids;
  if (!Array.isArray(installationIdsRaw) || installationIdsRaw.length === 0) {
    return { ok: false, status: 400, error: "missing_installation_ids" };
  }

  const installationIds = [
    ...new Set(
      installationIdsRaw.map((id) => toCanonicalUuid(String(id))),
    ),
  ];

  const { DB } = bindings;
  const missingInstallations = await assertInstallationsExist(
    DB,
    installationIds,
  );
  if (missingInstallations) {
    return missingInstallations;
  }

  const cohortName =
    typeof args.cohort_name === "string" ? args.cohort_name : undefined;
  const recordedAt = nowIso();
  const target = cohortName
    ? `${capabilityId}@${version}:${cohortName}`
    : `${capabilityId}@${version}`;

  const priorVersions: Record<string, string | null> = {};
  const statements: D1PreparedStatement[] = [];

  for (const installationId of installationIds) {
    const existing = await DB.prepare(
      `SELECT grant_id, capability_version FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(`installation:${installationId}`, capabilityId)
      .first<{ grant_id: string; capability_version: string }>();

    priorVersions[installationId] = existing?.capability_version ?? null;

    if (existing) {
      statements.push(
        DB.prepare(
          `UPDATE capability_grant
           SET capability_version = ?, changed_at = ?, changed_by = ?
           WHERE grant_id = ?`,
        ).bind(version, recordedAt, actor, existing.grant_id),
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
          capabilityId,
          version,
          recordedAt,
          recordedAt,
          actor,
        ),
      );
    }
  }

  const beforePointer =
    Object.values(priorVersions).some((v) => v !== null)
      ? JSON.stringify(priorVersions)
      : null;
  const afterPointer = version;

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'cohort_activate', ?, ?, ?, ?)`,
    ).bind(newId(), actor, target, beforePointer, afterPointer, recordedAt),
  );

  const batchError = await runControlBatch(DB, statements);
  if (batchError) {
    return batchError;
  }
  return { ok: true, body: {} };
}

export async function promoteCohortAction(
  bindings: ControlBindings,
  actor: string,
  args: Record<string, unknown>,
): Promise<ControlActionResult> {
  const capabilityId = requireNonEmptyString(args.capability_id);
  const version = requireNonEmptyString(args.capability_version);
  if (!capabilityId || !version) {
    return { ok: false, status: 400, error: "invalid_payload" };
  }

  if (!isCapabilityVersionRegistered(capabilityId, version)) {
    return { ok: false, status: 404, error: "capability_not_found" };
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${capabilityId}@${version}`;

  const liveInstallationGrants = await DB.prepare(
    `SELECT grant_id, scope, capability_version FROM capability_grant
     WHERE capability_id = ? AND scope LIKE 'installation:%' AND revoked_at IS NULL`,
  )
    .bind(capabilityId)
    .all<{ grant_id: string; scope: string; capability_version: string }>();

  const livePlanGrants = await DB.prepare(
    `SELECT grant_id, scope, capability_version FROM capability_grant
     WHERE capability_id = ? AND scope LIKE 'plan:%' AND revoked_at IS NULL`,
  )
    .bind(capabilityId)
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
  const afterPointer = version;

  const statements: D1PreparedStatement[] = [];

  for (const grant of liveInstallationGrants.results ?? []) {
    statements.push(
      DB.prepare(
        `UPDATE capability_grant
         SET capability_version = ?, changed_at = ?, changed_by = ?
         WHERE grant_id = ?`,
      ).bind(version, recordedAt, actor, grant.grant_id),
    );
  }

  for (const grant of livePlanGrants.results ?? []) {
    statements.push(
      DB.prepare(
        `UPDATE capability_grant
         SET capability_version = ?, changed_at = ?, changed_by = ?
         WHERE grant_id = ?`,
      ).bind(version, recordedAt, actor, grant.grant_id),
    );
  }

  const existingPlanScopes = new Set(
    (livePlanGrants.results ?? []).map((g) => g.scope),
  );
  const plansNeedingGrant = new Set<string>();
  for (const planId of await publishedPlansAllowingCapability(
    DB,
    capabilityId,
  )) {
    if (!existingPlanScopes.has(`plan:${planId}`)) {
      plansNeedingGrant.add(planId);
    }
  }

  const installationsWithLiveGrant = new Set(
    (liveInstallationGrants.results ?? []).map((g) =>
      g.scope.replace(/^installation:/, ""),
    ),
  );

  const entitledInstallations = await installationIdsWithCapability(
    DB,
    capabilityId,
  );

  for (const plan of plansNeedingGrant) {
    const scope = `plan:${plan}`;
    const existing = await DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(scope, capabilityId)
      .first<{ grant_id: string }>();

    if (existing) {
      statements.push(
        DB.prepare(
          `UPDATE capability_grant
           SET capability_version = ?, changed_at = ?, changed_by = ?
           WHERE grant_id = ?`,
        ).bind(version, recordedAt, actor, existing.grant_id),
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
          capabilityId,
          version,
          recordedAt,
          recordedAt,
          actor,
        ),
      );
    }
  }

  for (const installationId of entitledInstallations) {
    if (installationsWithLiveGrant.has(installationId)) {
      continue;
    }

    const existing = await DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(`installation:${installationId}`, capabilityId)
      .first<{ grant_id: string }>();

    if (existing) {
      statements.push(
        DB.prepare(
          `UPDATE capability_grant
           SET capability_version = ?, changed_at = ?, changed_by = ?
           WHERE grant_id = ?`,
        ).bind(version, recordedAt, actor, existing.grant_id),
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
          capabilityId,
          version,
          recordedAt,
          recordedAt,
          actor,
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
      actor,
      target,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  );

  const batchError = await runControlBatch(DB, statements);
  if (batchError) {
    return batchError;
  }
  return { ok: true, body: {} };
}
