import {
  OVERLAP_WINDOW_MS,
  isCapabilityVersionRegistered,
  isSuccessorRegistered,
} from "../capability";
import { newId, nowIso, writeEntrypointAudit } from "./audit";
import type { ControlActionResult, ControlBindings } from "./types";
import { requireNonEmptyString } from "./types";

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

function requireRegisteredVersion(
  capabilityId: string,
  version: string,
): ControlActionResult | null {
  if (!isCapabilityVersionRegistered(capabilityId, version)) {
    return { ok: false, status: 404, error: "capability_not_found" };
  }
  return null;
}

function overlapWindowStillActive(retireAfter: string, now: string): boolean {
  const retireAfterMs = Date.parse(retireAfter);
  const nowMs = Date.parse(now);
  if (!Number.isFinite(retireAfterMs) || !Number.isFinite(nowMs)) {
    return true;
  }
  return nowMs < retireAfterMs;
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

export async function deprecateCapabilityAction(
  bindings: ControlBindings,
  actor: string,
  args: Record<string, unknown>,
): Promise<ControlActionResult> {
  const capabilityId = requireNonEmptyString(args.capability_id);
  const version = requireNonEmptyString(args.capability_version);
  if (!capabilityId || !version) {
    return { ok: false, status: 400, error: "invalid_payload" };
  }

  const missing = requireRegisteredVersion(capabilityId, version);
  if (missing) {
    return missing;
  }

  const successorId = requireNonEmptyString(args.successor_id);
  if (!successorId) {
    if (args.successor_id == null || args.successor_id === "") {
      return { ok: false, status: 400, error: "missing_successor_id" };
    }
    return { ok: false, status: 400, error: "invalid_payload" };
  }

  const { DB } = bindings;
  const overlay = await loadGlobalOverlay(DB, capabilityId, version);
  if (overlay?.lifecycle_state === "retired") {
    return { ok: false, status: 409, error: "already_retired" };
  }
  if (overlay?.lifecycle_state === "deprecated") {
    if (overlay.successor_id === successorId) {
      return { ok: true, body: {} };
    }
    return { ok: false, status: 409, error: "already_deprecated" };
  }
  if (!isSuccessorRegistered(successorId)) {
    return { ok: false, status: 400, error: "unknown_successor" };
  }

  const deprecatedAt = nowIso();
  const retireAfter = new Date(
    new Date(deprecatedAt).getTime() + OVERLAP_WINDOW_MS,
  ).toISOString();
  const grantId = newId();
  const target = `${capabilityId}@${version}`;

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `INSERT INTO capability_grant (
         grant_id, scope, capability_id, capability_version,
         granted_at, revoked_at, changed_at, changed_by,
         lifecycle_state, successor_id, deprecated_at, retire_after
       ) VALUES (?, 'global', ?, ?, ?, ?, ?, ?, 'deprecated', ?, ?, ?)`,
    ).bind(
      grantId,
      capabilityId,
      version,
      deprecatedAt,
      deprecatedAt,
      deprecatedAt,
      actor,
      successorId,
      deprecatedAt,
      retireAfter,
    ),
  ]);
  if (batchError) {
    return batchError;
  }

  await writeEntrypointAudit(
    DB,
    actor,
    "deprecate",
    target,
    null,
    null,
    successorId,
  );

  return { ok: true, body: {} };
}

export async function retireCapabilityAction(
  bindings: ControlBindings,
  actor: string,
  args: Record<string, unknown>,
): Promise<ControlActionResult> {
  const capabilityId = requireNonEmptyString(args.capability_id);
  const version = requireNonEmptyString(args.capability_version);
  if (!capabilityId || !version) {
    return { ok: false, status: 400, error: "invalid_payload" };
  }

  const missing = requireRegisteredVersion(capabilityId, version);
  if (missing) {
    return missing;
  }

  const { DB } = bindings;
  const overlay = await loadGlobalOverlay(DB, capabilityId, version);

  if (
    !overlay ||
    overlay.lifecycle_state !== "deprecated" ||
    typeof overlay.successor_id !== "string" ||
    !overlay.successor_id
  ) {
    return { ok: false, status: 400, error: "not_deprecated" };
  }

  const retireAfter =
    typeof overlay.retire_after === "string" ? overlay.retire_after : null;
  const recordedAt = nowIso();
  if (!retireAfter || overlapWindowStillActive(retireAfter, recordedAt)) {
    return { ok: false, status: 400, error: "overlap_window_active" };
  }

  const grantId = newId();
  const target = `${capabilityId}@${version}`;

  const batchError = await runControlBatch(DB, [
    DB.prepare(
      `INSERT INTO capability_grant (
         grant_id, scope, capability_id, capability_version,
         granted_at, revoked_at, changed_at, changed_by,
         lifecycle_state, successor_id, deprecated_at, retire_after
       ) VALUES (?, 'global', ?, ?, ?, ?, ?, ?, 'retired', ?, ?, ?)`,
    ).bind(
      grantId,
      capabilityId,
      version,
      recordedAt,
      recordedAt,
      recordedAt,
      actor,
      overlay.successor_id,
      overlay.deprecated_at,
      overlay.retire_after,
    ),
  ]);
  if (batchError) {
    return batchError;
  }

  await writeEntrypointAudit(
    DB,
    actor,
    "retire",
    target,
    null,
    null,
    overlay.successor_id,
  );

  return { ok: true, body: {} };
}
