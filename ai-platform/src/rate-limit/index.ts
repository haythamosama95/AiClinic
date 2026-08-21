import { retryAfterSecondsForRateLimited } from "../errors";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";

type CompositeKeyKind =
  | "installation"
  | "installation+actor"
  | "installation+capability";

export type RateLimitBindings = {
  DB: D1Database;
  RATE_LIMITER_INSTALLATION: RateLimit;
  RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
  RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
};

export type RateLimitInput = {
  installationId: string;
  actorId: string;
  capabilityId: string;
};

export type RateLimitSuccess = { ok: true };
export type RateLimitFailure = {
  ok: false;
  code: "rate_limited";
  retryAfter: number;
};
export type RateLimitResult = RateLimitSuccess | RateLimitFailure;

/** Dimensions for a guard rejection flushed into `platform_counter` (§4.3.12). */
export type GuardRejectionDimensions = {
  error_code: string;
  installation_id: string;
  composite_key?: CompositeKeyKind;
};

/** In-isolate rejection tally keyed by time bucket + dimension set (§4.3.12). */
const rejectionTally = new Map<string, number>();

type CompositeKeyCheck = {
  kind: CompositeKeyKind;
  binding: RateLimit;
  key: string;
};

function currentTimeBucket(now = new Date()): string {
  const iso = now.toISOString();
  return `${iso.slice(0, 16)}:00`;
}

function dimensionSetFor(dimensions: GuardRejectionDimensions): string {
  const payload: Record<string, string> = {
    error_code: dimensions.error_code,
    installation_id: dimensions.installation_id,
  };
  if (dimensions.composite_key !== undefined) {
    payload.composite_key = dimensions.composite_key;
  }
  return JSON.stringify(payload);
}

function tallyMapKey(timeBucket: string, dimensionSet: string): string {
  return `${timeBucket}\0${dimensionSet}`;
}

/**
 * Records a guard rejection from stages 2–4 (and B4 admission) into the in-isolate
 * tally flushed later to `platform_counter` (FR-011; §4.3.12).
 */
export function recordGuardRejection(dimensions: GuardRejectionDimensions): void {
  const timeBucket = currentTimeBucket();
  const dimensionSet = dimensionSetFor(dimensions);
  const key = tallyMapKey(timeBucket, dimensionSet);
  rejectionTally.set(key, (rejectionTally.get(key) ?? 0) + 1);
}

async function counterIdFor(
  dimensionSet: string,
  timeBucket: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${timeBucket}:${dimensionSet}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function retryAfterSecondsFromAdmission(outcome: RateLimitOutcome): number {
  return retryAfterSecondsForRateLimited(
    (outcome as RateLimitOutcome & { retryAfter?: unknown }).retryAfter,
  );
}

function compositeKeyChecks(
  input: RateLimitInput,
  bindings: RateLimitBindings,
): CompositeKeyCheck[] {
  return [
    {
      kind: "installation",
      binding: bindings.RATE_LIMITER_INSTALLATION,
      key: input.installationId,
    },
    {
      kind: "installation+actor",
      binding: bindings.RATE_LIMITER_INSTALLATION_ACTOR,
      key: `${input.installationId}:${input.actorId}`,
    },
    {
      kind: "installation+capability",
      binding: bindings.RATE_LIMITER_INSTALLATION_CAPABILITY,
      key: `${input.installationId}:${input.capabilityId}`,
    },
  ];
}

export async function checkRateLimit(
  input: RateLimitInput,
  bindings: RateLimitBindings,
  logger: Logger = noopLogger,
): Promise<RateLimitResult> {
  for (const check of compositeKeyChecks(input, bindings)) {
    const outcome = await check.binding.limit({ key: check.key });
    if (!outcome.success) {
      const retryAfter = retryAfterSecondsFromAdmission(outcome);
      logger.info("Rate limit exceeded", {
        installation_id: input.installationId,
        composite_key: check.kind,
        retry_after: retryAfter,
      });
      recordGuardRejection({
        error_code: "rate_limited",
        installation_id: input.installationId,
        composite_key: check.kind,
      });
      return {
        ok: false,
        code: "rate_limited",
        retryAfter,
      };
    }
  }

  return { ok: true };
}

/**
 * Flushes this isolate's in-memory tally to bucketed `platform_counter` rows.
 * Snapshot-and-clear before writing so a mid-flush D1 failure cannot double-count
 * on the next flush (under-count on failure is preferred to double-apply).
 *
 * Only the isolate that happens to run cron drains its map. Tallies in other
 * isolates are lost on eviction, so `platform_counter.count` is a **lower bound**,
 * not an exact rejection count. An accurate count would flush at request end
 * batched with the journal write — not implemented; document the lower bound
 * wherever the counter is consumed.
 */
export async function flushRejectionCounters(
  bindings: Pick<RateLimitBindings, "DB">,
  logger: Logger = noopLogger,
): Promise<void> {
  if (rejectionTally.size === 0) {
    return;
  }

  const snapshot = [...rejectionTally.entries()];
  const totalRows = snapshot.length;
  const totalRejections = snapshot.reduce((sum, [, count]) => sum + count, 0);
  rejectionTally.clear();

  logger.info("Flushing guard rejection counters", {
    bucket_count: totalRows,
    rejection_count: totalRejections,
  });

  for (const [mapKey, count] of snapshot) {
    const separator = mapKey.indexOf("\0");
    const timeBucket = mapKey.slice(0, separator);
    const dimensionSet = mapKey.slice(separator + 1);
    const counterId = await counterIdFor(dimensionSet, timeBucket);

    await bindings.DB.prepare(
      `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(counter_id) DO UPDATE SET count = count + excluded.count`,
    )
      .bind(counterId, dimensionSet, timeBucket, count)
      .run();
  }
}
