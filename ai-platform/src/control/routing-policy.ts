import { buildEntrypointAuditStatement, newId, nowIso } from "./audit";
import type { ControlActionResult, ControlBindings } from "./types";
import {
  parseRoutingPolicyDocument,
  sha256HexOfBytes,
} from "../router/policy-document";
import visitSummaryPublished from "../../manifests/published/clinic.visit_summary@1.0.0.json";

type RoutingPolicyRow = {
  policy_id: string;
  version: string;
  status: string;
  canary_installation_ids: string | null;
  active_from: string;
  content_pointer?: string | null;
  content_sha256?: string | null;
};

/**
 * R8-ROUTE1 step 2 / R8-PUB1: loads the stored bytes for one routing row and
 * verifies them before any serving-state change. Returns null when the bytes
 * are present, digest-consistent (when recorded) and parse as a complete
 * document for this row's identity; otherwise returns invalid_policy_document.
 */
async function verifyStoredRoutingPolicy(
  R2: R2Bucket,
  row: RoutingPolicyRow,
): Promise<ControlActionResult | null> {
  const invalid: ControlActionResult = {
    ok: false,
    status: 422,
    error: "invalid_policy_document",
  };
  if (typeof row.content_pointer !== "string") {
    return invalid;
  }
  const object = await R2.get(row.content_pointer);
  if (!object) {
    return invalid;
  }
  const bytes = await object.arrayBuffer();
  if (
    typeof row.content_sha256 === "string" &&
    (await sha256HexOfBytes(bytes)) !== row.content_sha256
  ) {
    return invalid;
  }
  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return invalid;
  }
  const parsed = parseRoutingPolicyDocument(parsedJson);
  if (!parsed.ok) {
    return invalid;
  }
  if (
    parsed.document.policy_id !== row.policy_id ||
    String(parsed.document.policy_version) !== row.version
  ) {
    return invalid;
  }
  return null;
}

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
  const target = `${policyId}@${version}`;

  // R8-ROUTE1 step 1: full shape validation precedes any R2 or D1 write.
  const parsed = parseRoutingPolicyDocument(document);
  if (!parsed.ok) {
    return { ok: false, status: 422, error: "invalid_policy_document" };
  }
  // R8-PUB1: digest-keyed immutable content; distinct bytes never share a key.
  const contentBytes = new TextEncoder().encode(JSON.stringify(document));
  const contentSha256 = await sha256HexOfBytes(contentBytes);
  const contentPointer = `control/routing-policy/${policyId}/${version}/sha256-${contentSha256}.json`;

  const alreadyPublished = await DB.prepare(
    `SELECT policy_id FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first();
  if (alreadyPublished) {
    return { ok: false, status: 409, error: "already_published" };
  }

  await R2.put(contentPointer, contentBytes, {
    httpMetadata: { contentType: "application/json" },
  });

  try {
    await DB.batch([
      DB.prepare(
        `INSERT INTO routing_policy (
           policy_id, version, content_pointer, content_sha256, active_from, activated_by,
           canary_installation_ids, status
         ) VALUES (?, ?, ?, ?, ?, ?, NULL, 'published')`,
      ).bind(policyId, version, contentPointer, contentSha256, recordedAt, actor),
      // R8-ROLLBACK1: first version of a policy has no predecessor; existing rows are kept.
      DB.prepare(
        `INSERT OR IGNORE INTO routing_policy_activation
           (policy_id, generation, active_version, predecessor_version, predecessor_state)
         VALUES (?, 0, NULL, NULL, 'none')`,
      ).bind(policyId),
      buildEntrypointAuditStatement(
        DB,
        actor,
        "routing_policy_publish",
        target,
        null,
        null,
        contentPointer,
        false,
        recordedAt,
      ),
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

  if (!bindings.R2) {
    return { ok: false, status: 500, error: "missing_r2_binding" };
  }
  const { DB } = bindings;
  const target = `${policyId}@${version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from,
            content_pointer, content_sha256
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

  const storedInvalid = await verifyStoredRoutingPolicy(bindings.R2, existing);
  if (storedInvalid) {
    return storedInvalid;
  }

  const beforePointer = priorCanary?.canary_installation_ids ?? null;
  const afterPointer =
    typeof cohortName === "string" && cohortName.length > 0
      ? JSON.stringify({
          installation_ids: installationIds,
          details: { cohort_name: cohortName },
        })
      : JSON.stringify(installationIds);

  if (
    existing.status === "canary" &&
    existing.canary_installation_ids === JSON.stringify(installationIds)
  ) {
    return { ok: true, body: {} };
  }

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'canary', canary_installation_ids = ?
       WHERE policy_id = ? AND version = ? AND status = ?`,
    ).bind(JSON.stringify(installationIds), policyId, version, existing.status),
    buildEntrypointAuditStatement(
      DB,
      actor,
      "routing_policy_canary",
      target,
      null,
      beforePointer,
      afterPointer,
      true,
    ),
  ]);
  if (batchError) {
    return batchError;
  }

  return { ok: true, body: {} };
}

type ActivationRow = {
  policy_id: string;
  generation: number;
  active_version: string | null;
  predecessor_version: string | null;
  predecessor_state: "unknown" | "none" | "known";
};

const GENERATION_CONFLICT: ControlActionResult = {
  ok: false,
  status: 409,
  error: "generation_conflict",
};

async function readActivation(
  db: D1Database,
  policyId: string,
): Promise<ActivationRow | null> {
  return db
    .prepare(
      `SELECT policy_id, generation, active_version, predecessor_version, predecessor_state
       FROM routing_policy_activation WHERE policy_id = ?`,
    )
    .bind(policyId)
    .first<ActivationRow>();
}

/**
 * R8-ROLLBACK1: audit row that exists only when the immediately preceding
 * statement (the generation-guarded activation UPDATE) changed a row. Later
 * statements in the same batch are gated on this audit row's presence.
 */
function guardedAuditStatement(
  db: D1Database,
  auditId: string,
  actor: string,
  action: string,
  target: string,
  beforePointer: string | null,
  afterPointer: string | null,
  recordedAt: string,
): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, actor, action, target, assertion_sha256, before_pointer, after_pointer, recorded_at)
       SELECT ?, ?, ?, ?, ?, NULL, ?, ?, ? WHERE changes() > 0`,
    )
    .bind(auditId, actor, actor, action, target, beforePointer, afterPointer, recordedAt);
}

/**
 * R8-ROLLBACK1: runs one transition batch. The first statement is the
 * generation-guarded activation UPDATE; if it changed zero rows nothing is
 * committed and a generation conflict is returned.
 */
async function runFencedBatch(
  db: D1Database,
  statements: D1PreparedStatement[],
): Promise<ControlActionResult | null> {
  try {
    const results = await db.batch(statements);
    if (results[0]?.meta?.changes === 0) {
      return GENERATION_CONFLICT;
    }
    return null;
  } catch {
    return { ok: false, status: 500, error: "storage_error" };
  }
}

function cancelCanariesStatement(
  db: D1Database,
  policyId: string,
  auditId: string,
): D1PreparedStatement {
  return db
    .prepare(
      `UPDATE routing_policy
       SET status = CASE WHEN status = 'canary' THEN 'published' ELSE status END,
           canary_installation_ids = NULL
       WHERE policy_id = ?
         AND (status = 'canary' OR canary_installation_ids IS NOT NULL)
         AND EXISTS (SELECT 1 FROM control_audit WHERE audit_id = ?)`,
    )
    .bind(policyId, auditId);
}

export async function promoteRoutingPolicyAction(
  bindings: ControlBindings,
  actor: string,
  policyId: string,
  version: string,
  expectedGeneration?: number,
): Promise<ControlActionResult> {
  if (!bindings.R2) {
    return { ok: false, status: 500, error: "missing_r2_binding" };
  }
  const { DB } = bindings;
  const target = `${policyId}@${version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from,
            content_pointer, content_sha256
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return { ok: false, status: 404, error: "policy_version_not_found" };
  }

  if (existing.status === "active") {
    return { ok: true, body: {} };
  }
  if (existing.status === "superseded") {
    return { ok: false, status: 409, error: "illegal_policy_transition" };
  }

  const storedInvalid = await verifyStoredRoutingPolicy(bindings.R2, existing);
  if (storedInvalid) {
    return storedInvalid;
  }

  const activation = await readActivation(DB, policyId);
  if (!activation) {
    return { ok: false, status: 409, error: "activation_state_missing" };
  }
  if (
    expectedGeneration !== undefined &&
    expectedGeneration !== activation.generation
  ) {
    return GENERATION_CONFLICT;
  }

  const auditId = newId();
  const recordedAt = nowIso();
  const beforePointer = activation.active_version
    ? `${policyId}@${activation.active_version}`
    : null;

  const batchError = await runFencedBatch(DB, [
    DB.prepare(
      `UPDATE routing_policy_activation
       SET generation = generation + 1,
           predecessor_version = active_version,
           predecessor_state = CASE WHEN active_version IS NULL THEN 'none' ELSE 'known' END,
           active_version = ?
       WHERE policy_id = ? AND generation = ?`,
    ).bind(version, policyId, activation.generation),
    guardedAuditStatement(
      DB,
      auditId,
      actor,
      "routing_policy_promote",
      target,
      beforePointer,
      target,
      recordedAt,
    ),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND version != ? AND status IN ('active', 'canary')
         AND EXISTS (SELECT 1 FROM control_audit WHERE audit_id = ?)`,
    ).bind(policyId, version, auditId),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'active', canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ? AND status = ?
         AND EXISTS (SELECT 1 FROM control_audit WHERE audit_id = ?)`,
    ).bind(policyId, version, existing.status, auditId),
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
  expectedGeneration?: number,
): Promise<ControlActionResult> {
  const { DB } = bindings;
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

  const activation = await readActivation(DB, policyId);
  if (!activation) {
    return { ok: false, status: 409, error: "activation_state_missing" };
  }
  if (
    expectedGeneration !== undefined &&
    expectedGeneration !== activation.generation
  ) {
    return GENERATION_CONFLICT;
  }

  const auditId = newId();
  const recordedAt = nowIso();

  if (existing.status === "canary") {
    // Scoped canary cancellation: the canary row returns to published.
    const activeAfter = activation.active_version
      ? `${policyId}@${activation.active_version}`
      : null;
    const batchError = await runFencedBatch(DB, [
      DB.prepare(
        `UPDATE routing_policy_activation
         SET generation = generation + 1
         WHERE policy_id = ? AND generation = ?`,
      ).bind(policyId, activation.generation),
      guardedAuditStatement(
        DB,
        auditId,
        actor,
        "routing_policy_rollback",
        target,
        existing.canary_installation_ids,
        activeAfter,
        recordedAt,
      ),
      cancelCanariesStatement(DB, policyId, auditId),
    ]);
    return batchError ?? { ok: true, body: {} };
  }

  if (existing.status !== "active" || activation.active_version !== version) {
    return { ok: false, status: 409, error: "illegal_policy_transition" };
  }

  // R8-ROLLBACK1: the restore target is only the predecessor the activation
  // record names. Publication order and active_from are never consulted.
  if (activation.predecessor_state === "unknown") {
    return { ok: false, status: 409, error: "rollback_predecessor_unknown" };
  }
  const predecessorVersion = activation.predecessor_version;
  if (activation.predecessor_state !== "known" || predecessorVersion === null) {
    return { ok: false, status: 409, error: "illegal_policy_transition" };
  }

  const prior = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from,
            content_pointer, content_sha256
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, predecessorVersion)
    .first<RoutingPolicyRow>();
  if (!prior || prior.status !== "superseded") {
    return { ok: false, status: 409, error: "illegal_policy_transition" };
  }
  if (!bindings.R2) {
    return { ok: false, status: 500, error: "missing_r2_binding" };
  }
  // ROUTE1: the restored version's stored bytes must parse before any state change.
  const storedInvalid = await verifyStoredRoutingPolicy(bindings.R2, prior);
  if (storedInvalid) {
    return storedInvalid;
  }

  const batchError = await runFencedBatch(DB, [
    DB.prepare(
      `UPDATE routing_policy_activation
       SET generation = generation + 1,
           active_version = predecessor_version,
           predecessor_version = NULL,
           predecessor_state = 'unknown'
       WHERE policy_id = ? AND generation = ? AND active_version = ?
         AND predecessor_state = 'known' AND predecessor_version = ?`,
    ).bind(policyId, activation.generation, version, predecessorVersion),
    guardedAuditStatement(
      DB,
      auditId,
      actor,
      "routing_policy_rollback",
      target,
      target,
      `${policyId}@${predecessorVersion}`,
      recordedAt,
    ),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ? AND status = 'active'
         AND EXISTS (SELECT 1 FROM control_audit WHERE audit_id = ?)`,
    ).bind(policyId, version, auditId),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'active', canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ? AND status = 'superseded'
         AND EXISTS (SELECT 1 FROM control_audit WHERE audit_id = ?)`,
    ).bind(policyId, predecessorVersion, auditId),
    cancelCanariesStatement(DB, policyId, auditId),
  ]);
  if (batchError) {
    return batchError;
  }

  return { ok: true, body: {} };
}
