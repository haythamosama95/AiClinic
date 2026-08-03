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

/** Default retry-after when the binding does not supply one (§4.3.3 simple limiter window). */
const DEFAULT_RETRY_AFTER_SECONDS = 60;

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

function dimensionSetFor(
  compositeKey: CompositeKeyKind,
  installationId: string,
): string {
  return JSON.stringify({
    error_code: "rate_limited",
    composite_key: compositeKey,
    installation_id: installationId,
  });
}

function tallyMapKey(timeBucket: string, dimensionSet: string): string {
  return `${timeBucket}\0${dimensionSet}`;
}

function recordRejection(
  compositeKey: CompositeKeyKind,
  installationId: string,
): void {
  const timeBucket = currentTimeBucket();
  const dimensionSet = dimensionSetFor(compositeKey, installationId);
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
): Promise<RateLimitResult> {
  for (const check of compositeKeyChecks(input, bindings)) {
    const outcome = await check.binding.limit({ key: check.key });
    if (!outcome.success) {
      recordRejection(check.kind, input.installationId);
      return {
        ok: false,
        code: "rate_limited",
        retryAfter: DEFAULT_RETRY_AFTER_SECONDS,
      };
    }
  }

  return { ok: true };
}

export async function flushRejectionCounters(
  bindings: Pick<RateLimitBindings, "DB">,
): Promise<void> {
  if (rejectionTally.size === 0) {
    return;
  }

  for (const [mapKey, count] of rejectionTally) {
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

  rejectionTally.clear();
}
