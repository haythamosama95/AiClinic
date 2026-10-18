import { clockNowIso, type ClockEnv } from "../clock.js";

export type RawEvidenceEnv = ClockEnv & {
  DB: D1Database;
  R2: R2Bucket;
};

export type RawEvidenceClaim = {
  evidenceId: string;
  orgId: string | null;
  checkoutId: string | null;
  kind: "notification" | "inquiry";
  r2Key: string;
  sha256: string;
  expectedGeneration?: number;
};

/** Reserve an evidence object against the current tenant erasure generation. */
export async function claimRawEvidence(
  env: RawEvidenceEnv,
  claim: RawEvidenceClaim,
): Promise<number | null> {
  const now = await clockNowIso(env);
  if (claim.orgId === null) {
    await env.DB.prepare(
      `INSERT INTO raw_evidence_registry (
         evidence_id, org_id, checkout_id, evidence_kind, generation,
         r2_key, raw_sha256, state, created_at, updated_at
       ) VALUES (?, NULL, ?, ?, NULL, ?, ?, 'quarantined', ?, ?)`,
    )
      .bind(claim.evidenceId, claim.checkoutId, claim.kind, claim.r2Key, claim.sha256, now, now)
      .run();
    return null;
  }
  await env.DB.prepare(
    `INSERT INTO org_erasure_fence (org_id, generation, updated_at)
     VALUES (?, 0, ?) ON CONFLICT(org_id) DO NOTHING`,
  )
    .bind(claim.orgId, now)
    .run();
  await env.DB.prepare(
    `INSERT INTO raw_evidence_registry (
       evidence_id, org_id, checkout_id, evidence_kind, generation,
       r2_key, raw_sha256, state, created_at, updated_at
     ) SELECT ?, ?, ?, ?, generation, ?, ?, 'claimed', ?, ?
       FROM org_erasure_fence WHERE org_id = ?
         AND (? IS NULL OR generation = ?)
     ON CONFLICT(evidence_id) DO NOTHING`,
  )
    .bind(
      claim.evidenceId,
      claim.orgId,
      claim.checkoutId,
      claim.kind,
      claim.r2Key,
      claim.sha256,
      now,
      now,
      claim.orgId,
      claim.expectedGeneration ?? null,
      claim.expectedGeneration ?? null,
    )
    .run();
  const row = await env.DB.prepare(
    `SELECT generation FROM raw_evidence_registry
     WHERE evidence_id = ? AND org_id = ? AND state = 'claimed'`,
  )
    .bind(claim.evidenceId, claim.orgId)
    .first<{ generation: number }>();
  return row?.generation ?? null;
}

/** Upload only while the claim is current, then fence late completions. */
export async function putClaimedRawEvidence(
  env: RawEvidenceEnv,
  claim: RawEvidenceClaim,
  generation: number,
  body: string | Uint8Array,
): Promise<boolean> {
  const before = await env.DB.prepare(
    `SELECT 1 AS current
     FROM raw_evidence_registry r
     JOIN org_erasure_fence f ON f.org_id = r.org_id AND f.generation = r.generation
     WHERE r.evidence_id = ? AND r.r2_key = ? AND r.generation = ? AND r.state = 'claimed'`,
  )
    .bind(claim.evidenceId, claim.r2Key, generation)
    .first<{ current: number }>();
  if (before === null) {
    await queueRawEvidenceDelete(env, claim, "stale_claim");
    await drainRawEvidenceDeletes(env, 100, claim.orgId ?? undefined);
    return false;
  }
  try {
    await env.R2.put(claim.r2Key, body);
  } catch (error) {
    await queueRawEvidenceDelete(env, claim, "upload_uncertain");
    throw error;
  }
  const now = await clockNowIso(env);
  const finalized = await env.DB.prepare(
    `UPDATE raw_evidence_registry SET state = 'retained', updated_at = ?
     WHERE evidence_id = ? AND generation = ? AND state = 'claimed'
       AND EXISTS (
         SELECT 1 FROM org_erasure_fence f
         WHERE f.org_id = raw_evidence_registry.org_id AND f.generation = ?
       )`,
  )
    .bind(now, claim.evidenceId, generation, generation)
    .run();
  if ((finalized.meta.changes ?? 0) > 0) return true;
  await queueRawEvidenceDelete(env, claim, "erasure_raced_upload");
  await drainRawEvidenceDeletes(env, 100, claim.orgId ?? undefined);
  return false;
}

export async function queueRawEvidenceDelete(
  env: RawEvidenceEnv,
  claim: RawEvidenceClaim,
  reason: string,
): Promise<void> {
  const now = await clockNowIso(env);
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE raw_evidence_registry SET state = 'delete_pending', updated_at = ?
       WHERE evidence_id = ? AND state != 'deleted'`,
    ).bind(now, claim.evidenceId),
    env.DB.prepare(
      `INSERT INTO raw_evidence_cleanup_outbox (
         r2_key, evidence_id, reason, state, attempts, next_attempt_at,
         last_error, created_at, updated_at
       ) VALUES (?, ?, ?, 'open', 0, ?, NULL, ?, ?)
       ON CONFLICT(r2_key) DO UPDATE SET
         state = 'open', reason = excluded.reason, next_attempt_at = excluded.next_attempt_at,
         updated_at = excluded.updated_at`,
    ).bind(claim.r2Key, claim.evidenceId, reason, now, now, now),
  ]);
}

/** Delete prior quarantined copies once an authenticated callback resolves ownership. */
export async function deleteQuarantinedRawEvidence(
  env: RawEvidenceEnv,
  sha256: string,
): Promise<void> {
  const now = await clockNowIso(env);
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE raw_evidence_registry SET state = 'delete_pending', updated_at = ?
       WHERE org_id IS NULL AND raw_sha256 = ? AND state = 'quarantined'`,
    ).bind(now, sha256),
    env.DB.prepare(
      `INSERT INTO raw_evidence_cleanup_outbox (
         r2_key, evidence_id, reason, state, attempts, next_attempt_at,
         last_error, created_at, updated_at
       ) SELECT r2_key, evidence_id, 'quarantine_owner_resolved', 'open', 0, ?, NULL, ?, ?
         FROM raw_evidence_registry
         WHERE org_id IS NULL AND raw_sha256 = ? AND state = 'delete_pending'
       ON CONFLICT(r2_key) DO UPDATE SET
         state = 'open', reason = excluded.reason, next_attempt_at = excluded.next_attempt_at,
         updated_at = excluded.updated_at`,
    ).bind(now, now, now, sha256),
  ]);
  await drainRawEvidenceDeletes(env, 100);
}

export async function eraseOrgRawEvidence(
  env: RawEvidenceEnv,
  orgId: string,
): Promise<void> {
  const now = await clockNowIso(env);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO org_erasure_fence (org_id, generation, updated_at)
       VALUES (?, 1, ?)
       ON CONFLICT(org_id) DO UPDATE SET
         generation = org_erasure_fence.generation + 1, updated_at = excluded.updated_at`,
    ).bind(orgId, now),
    env.DB.prepare(
      `UPDATE raw_evidence_registry SET state = 'delete_pending', updated_at = ?
       WHERE org_id = ? AND state IN ('claimed', 'retained')`,
    ).bind(now, orgId),
    env.DB.prepare(
      `INSERT INTO raw_evidence_cleanup_outbox (
         r2_key, evidence_id, reason, state, attempts, next_attempt_at,
         last_error, created_at, updated_at
       ) SELECT r2_key, evidence_id, 'tenant_erasure', 'open', 0, ?, NULL, ?, ?
         FROM raw_evidence_registry
         WHERE org_id = ? AND state = 'delete_pending'
       ON CONFLICT(r2_key) DO UPDATE SET
         state = 'open', reason = 'tenant_erasure', next_attempt_at = excluded.next_attempt_at,
         updated_at = excluded.updated_at`,
    ).bind(now, now, now, orgId),
  ]);
  await drainRawEvidenceDeletes(env, 100, orgId);
}

export async function drainRawEvidenceDeletes(
  env: RawEvidenceEnv,
  limit: number,
  orgId?: string,
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT o.r2_key, o.evidence_id, o.attempts
     FROM raw_evidence_cleanup_outbox o
     LEFT JOIN raw_evidence_registry r ON r.evidence_id = o.evidence_id
     WHERE o.state = 'open' AND o.next_attempt_at <= ? AND (? IS NULL OR r.org_id = ?)
     ORDER BY o.created_at, o.r2_key LIMIT ?`,
  )
    .bind(await clockNowIso(env), orgId ?? null, orgId ?? null, limit)
    .all<{ r2_key: string; evidence_id: string; attempts: number }>();
  for (const row of rows.results ?? []) {
    try {
      await env.R2.delete(row.r2_key);
      const now = await clockNowIso(env);
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE raw_evidence_registry SET state = 'deleted', updated_at = ?
           WHERE evidence_id = ?`,
        ).bind(now, row.evidence_id),
        env.DB.prepare(
          `UPDATE raw_evidence_cleanup_outbox SET state = 'done', attempts = attempts + 1,
             last_error = NULL, updated_at = ? WHERE r2_key = ?`,
        ).bind(now, row.r2_key),
      ]);
    } catch (error) {
      const now = await clockNowIso(env);
      const retryMs = Math.min(15 * 60_000, 60_000 * 2 ** Math.min(row.attempts, 4));
      const nextAttempt = new Date(Date.parse(now) + retryMs).toISOString();
      await env.DB.prepare(
        `UPDATE raw_evidence_cleanup_outbox SET attempts = attempts + 1,
           next_attempt_at = ?, last_error = ?, updated_at = ? WHERE r2_key = ?`,
      )
        .bind(nextAttempt, String(error).slice(0, 500), now, row.r2_key)
        .run();
    }
  }
}
