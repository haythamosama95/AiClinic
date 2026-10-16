import { newId, nowIso } from "./audit";
import type { ControlActionResult, ControlBindings } from "./types";
import visitSummaryPublished from "../../manifests/published/clinic.visit_summary@1.0.0.json";

type RoutingPolicyRow = {
  policy_id: string;
  version: string;
  status: string;
  canary_installation_ids: string | null;
  active_from: string;
};

type PublishedCapabilityManifest = {
  Routing?: {
    routingPolicyRef?: unknown;
    latencyClass?: unknown;
  };
};

const PUBLISHED_CAPABILITY_MANIFESTS: readonly PublishedCapabilityManifest[] = [
  visitSummaryPublished,
];

function parseRoutingPolicyRef(ref: unknown): { policyId: string } | null {
  if (typeof ref !== "string") {
    return null;
  }
  const match = /^routing\/([^/]+)(?:@v\d+)?$/.exec(ref);
  if (!match) {
    return null;
  }
  return { policyId: match[1] };
}

function collectTargetLatencyClasses(
  document: Record<string, unknown>,
): Set<string> {
  const classes = new Set<string>();
  if (!Array.isArray(document.rules)) {
    return classes;
  }
  for (const rule of document.rules) {
    if (rule === null || typeof rule !== "object" || Array.isArray(rule)) {
      continue;
    }
    const targets = (rule as { targets?: unknown }).targets;
    if (!Array.isArray(targets)) {
      continue;
    }
    for (const target of targets) {
      if (target === null || typeof target !== "object" || Array.isArray(target)) {
        continue;
      }
      const features = (target as { features?: unknown }).features;
      if (
        features === null ||
        typeof features !== "object" ||
        Array.isArray(features)
      ) {
        continue;
      }
      const latencyClass = (features as { latency_class?: unknown }).latency_class;
      if (typeof latencyClass === "string") {
        classes.add(latencyClass);
      }
    }
  }
  return classes;
}

function isUniqueConstraint(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return /UNIQUE constraint failed|SQLITE_CONSTRAINT/i.test(message);
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

function latencyMismatchWarnings(
  document: Record<string, unknown>,
  policyId: string,
): string[] {
  const referenced = PUBLISHED_CAPABILITY_MANIFESTS.filter((manifest) => {
    const parsed = parseRoutingPolicyRef(manifest.Routing?.routingPolicyRef);
    return parsed !== null && parsed.policyId === policyId;
  });
  if (referenced.length === 0) {
    return ["unreferenced_policy"];
  }

  const targetClasses = collectTargetLatencyClasses(document);
  for (const manifest of referenced) {
    const latencyClass = manifest.Routing?.latencyClass;
    if (typeof latencyClass !== "string" || latencyClass.length === 0) {
      continue;
    }
    if (!targetClasses.has(latencyClass)) {
      return ["latency_class_mismatch"];
    }
  }
  return [];
}

async function installationsExist(
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

export async function publishRoutingPolicyAction(
  bindings: ControlBindings,
  actor: string,
  document: Record<string, unknown>,
): Promise<ControlActionResult> {
  if (!bindings.R2) {
    return { ok: false, status: 500, error: "missing_r2_binding" };
  }

  const policyId = document.policy_id;
  const policyVersion = document.policy_version;
  if (
    typeof policyId !== "string" ||
    policyId.length === 0 ||
    typeof policyVersion !== "number" ||
    !Number.isInteger(policyVersion) ||
    policyVersion < 1
  ) {
    return { ok: false, status: 400, error: "invalid_policy_identity" };
  }
  const version = String(policyVersion);

  const { DB, R2 } = bindings;
  const recordedAt = nowIso();
  const contentPointer = `control/routing-policy/${policyId}/${version}.json`;
  const target = `${policyId}@${version}`;

  const alreadyPublished = await DB.prepare(
    `SELECT policy_id FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first();
  if (alreadyPublished) {
    return { ok: false, status: 409, error: "already_published" };
  }

  await R2.put(contentPointer, JSON.stringify(document), {
    httpMetadata: { contentType: "application/json" },
  });

  try {
    await DB.batch([
      DB.prepare(
        `INSERT INTO routing_policy (
           policy_id, version, content_pointer, active_from, activated_by,
           canary_installation_ids, status
         ) VALUES (?, ?, ?, ?, ?, NULL, 'published')`,
      ).bind(policyId, version, contentPointer, recordedAt, actor),
      DB.prepare(
        `INSERT INTO control_audit
           (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
         VALUES (?, ?, 'routing_policy_publish', ?, NULL, ?, ?)`,
      ).bind(newId(), actor, target, contentPointer, recordedAt),
    ]);
  } catch (err) {
    if (isUniqueConstraint(err)) {
      return { ok: false, status: 409, error: "already_published" };
    }
    return { ok: false, status: 500, error: "storage_error" };
  }

  const warnings = latencyMismatchWarnings(document, policyId);
  return warnings.length > 0 ? { ok: true, body: { warnings } } : { ok: true, body: {} };
}

export async function canaryRoutingPolicyAction(
  bindings: ControlBindings,
  actor: string,
  policyId: string,
  version: string,
  installationIds: string[],
  cohortName?: string,
): Promise<ControlActionResult> {
  if (!Array.isArray(installationIds) || installationIds.length === 0) {
    return { ok: false, status: 400, error: "missing_installation_ids" };
  }

  const missing = await installationsExist(bindings.DB, installationIds);
  if (missing) {
    return missing;
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${policyId}@${version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return { ok: false, status: 404, error: "policy_version_not_found" };
  }

  if (existing.status !== "published" && existing.status !== "canary") {
    return { ok: false, status: 409, error: "illegal_policy_transition" };
  }

  const priorCanary = await DB.prepare(
    `SELECT canary_installation_ids FROM routing_policy
     WHERE policy_id = ? AND status = 'canary'
     ORDER BY active_from DESC, rowid DESC LIMIT 1`,
  )
    .bind(policyId)
    .first<{ canary_installation_ids: string | null }>();

  const beforePointer = priorCanary?.canary_installation_ids ?? null;
  const afterPointer =
    typeof cohortName === "string" && cohortName.length > 0
      ? JSON.stringify({
          installation_ids: installationIds,
          details: { cohort_name: cohortName },
        })
      : JSON.stringify(installationIds);

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'canary', canary_installation_ids = ?
       WHERE policy_id = ? AND version = ?`,
    ).bind(JSON.stringify(installationIds), policyId, version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_canary', ?, ?, ?, ?)`,
    ).bind(newId(), actor, target, beforePointer, afterPointer, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

  return { ok: true, body: {} };
}

export async function promoteRoutingPolicyAction(
  bindings: ControlBindings,
  actor: string,
  policyId: string,
  version: string,
): Promise<ControlActionResult> {
  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${policyId}@${version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return { ok: false, status: 404, error: "policy_version_not_found" };
  }

  if (existing.status === "active" || existing.status === "superseded") {
    return { ok: false, status: 409, error: "illegal_policy_transition" };
  }

  const priorActive = await DB.prepare(
    `SELECT version FROM routing_policy
     WHERE policy_id = ? AND status = 'active'
     ORDER BY active_from DESC, rowid DESC LIMIT 1`,
  )
    .bind(policyId)
    .first<{ version: string }>();

  const beforePointer = priorActive
    ? `${policyId}@${priorActive.version}`
    : null;
  const afterPointer = target;

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND status = 'active' AND version != ?`,
    ).bind(policyId, version),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND status = 'canary' AND version != ?`,
    ).bind(policyId, version),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'active', canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ?`,
    ).bind(policyId, version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_promote', ?, ?, ?, ?)`,
    ).bind(newId(), actor, target, beforePointer, afterPointer, recordedAt),
  ]);
  if (batchError) {
    return batchError;
  }

  return { ok: true, body: {} };
}

export async function rollbackRoutingPolicyAction(
  bindings: ControlBindings,
  actor: string,
  policyId: string,
  version: string,
): Promise<ControlActionResult> {
  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${policyId}@${version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return { ok: false, status: 404, error: "policy_version_not_found" };
  }

  const statements: D1PreparedStatement[] = [];
  let beforePointer: string | null = `${policyId}@${version}`;
  let afterPointer: string | null = null;

  if (existing.status === "canary") {
    const active = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'active'
       ORDER BY active_from DESC, rowid DESC LIMIT 1`,
    )
      .bind(policyId)
      .first<{ version: string }>();

    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'published', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(policyId, version),
    );
    afterPointer = active ? `${policyId}@${active.version}` : null;
  } else if (existing.status === "active") {
    const prior = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'superseded'
       ORDER BY active_from DESC, rowid DESC LIMIT 1`,
    )
      .bind(policyId)
      .first<{ version: string }>();

    if (!prior) {
      return { ok: false, status: 409, error: "illegal_policy_transition" };
    }

    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'superseded', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(policyId, version),
    );
    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'active', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(policyId, prior.version),
    );
    afterPointer = `${policyId}@${prior.version}`;
  } else {
    return { ok: false, status: 409, error: "illegal_policy_transition" };
  }

  statements.push(
    DB.prepare(
      `UPDATE routing_policy
       SET status = CASE WHEN status = 'canary' THEN 'published' ELSE status END,
           canary_installation_ids = NULL
       WHERE policy_id = ? AND (status = 'canary' OR canary_installation_ids IS NOT NULL)`,
    ).bind(policyId),
  );

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_rollback', ?, ?, ?, ?)`,
    ).bind(newId(), actor, target, beforePointer, afterPointer, recordedAt),
  );

  const batchError = await runControlBatch(DB, statements);
  if (batchError) {
    return batchError;
  }

  return { ok: true, body: {} };
}
