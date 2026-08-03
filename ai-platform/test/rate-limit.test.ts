import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  getTaxonomyEntry,
  supplementaryFieldsForCode,
} from "../src/errors";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const FIXTURE_INSTALLATION_ID = "inst-rate-limit-001";
const FIXTURE_ACTOR_ID = "actor-rate-limit-001";
const FIXTURE_CAPABILITY_ID = "cap-rate-limit-001";

/** Burst limit for the binding under test; other bindings stay permissive. */
const TRIP_LIMIT = 2;

type PlatformCounterRow = {
  counter_id: string;
  dimension_set: string;
  time_bucket: string;
  count: number;
};

type RateLimitBindings = {
  DB: D1Database;
  RATE_LIMITER_INSTALLATION: RateLimit;
  RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
  RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
};

type RateLimitInput = {
  installationId: string;
  actorId: string;
  capabilityId: string;
};

type RateLimitSuccess = { ok: true };
type RateLimitFailure = {
  ok: false;
  code: "rate_limited";
  retryAfter: number;
};
type RateLimitResult = RateLimitSuccess | RateLimitFailure;

type RateLimitModule = {
  checkRateLimit: (
    input: RateLimitInput,
    bindings: RateLimitBindings,
  ) => Promise<RateLimitResult>;
  flushRejectionCounters: (
    bindings: Pick<RateLimitBindings, "DB">,
  ) => Promise<void>;
  recordGuardRejection: (dimensions: {
    error_code: string;
    installation_id: string;
    composite_key?: CompositeKeyKind;
  }) => void;
};

type CompositeKeyKind =
  | "installation"
  | "installation+actor"
  | "installation+capability";

type RateLimitBindingFixture = RateLimit & {
  reset: () => void;
  setLimit: (limit: number) => void;
};

/** Loads rate-limit handlers from `src/rate-limit/` (absent until Phase 3). */
async function loadRateLimitModule(): Promise<RateLimitModule> {
  return import(/* @vite-ignore */ "../src/rate-limit") as Promise<RateLimitModule>;
}

function defaultRateLimitInput(): RateLimitInput {
  return {
    installationId: FIXTURE_INSTALLATION_ID,
    actorId: FIXTURE_ACTOR_ID,
    capabilityId: FIXTURE_CAPABILITY_ID,
  };
}

/**
 * In-memory Workers Rate Limiting binding fixture (§4.3.3).
 * Each composite key uses its own binding so keys trip independently.
 */
function createRateLimitBindingFixture(
  initialLimit = 10_000,
): RateLimitBindingFixture {
  let limit = initialLimit;
  const counts = new Map<string, number>();

  return {
    async limit({ key }: RateLimitOptions): Promise<RateLimitOutcome> {
      const next = (counts.get(key) ?? 0) + 1;
      counts.set(key, next);
      return { success: next <= limit };
    },
    reset() {
      counts.clear();
    },
    setLimit(nextLimit: number) {
      limit = nextLimit;
    },
  };
}

function createRateLimitBindings(
  options: Partial<{
    installationLimit: number;
    installationActorLimit: number;
    installationCapabilityLimit: number;
  }> = {},
): {
  bindings: RateLimitBindings;
  fixtures: Record<
    | "RATE_LIMITER_INSTALLATION"
    | "RATE_LIMITER_INSTALLATION_ACTOR"
    | "RATE_LIMITER_INSTALLATION_CAPABILITY",
    RateLimitBindingFixture
  >;
} {
  const installation = createRateLimitBindingFixture(
    options.installationLimit ?? 10_000,
  );
  const installationActor = createRateLimitBindingFixture(
    options.installationActorLimit ?? 10_000,
  );
  const installationCapability = createRateLimitBindingFixture(
    options.installationCapabilityLimit ?? 10_000,
  );

  return {
    bindings: {
      DB: env.DB,
      RATE_LIMITER_INSTALLATION: installation,
      RATE_LIMITER_INSTALLATION_ACTOR: installationActor,
      RATE_LIMITER_INSTALLATION_CAPABILITY: installationCapability,
    },
    fixtures: {
      RATE_LIMITER_INSTALLATION: installation,
      RATE_LIMITER_INSTALLATION_ACTOR: installationActor,
      RATE_LIMITER_INSTALLATION_CAPABILITY: installationCapability,
    },
  };
}

function bindingForKey(
  fixtures: ReturnType<typeof createRateLimitBindings>["fixtures"],
  keyKind: CompositeKeyKind,
): RateLimitBindingFixture {
  switch (keyKind) {
    case "installation":
      return fixtures.RATE_LIMITER_INSTALLATION;
    case "installation+actor":
      return fixtures.RATE_LIMITER_INSTALLATION_ACTOR;
    case "installation+capability":
      return fixtures.RATE_LIMITER_INSTALLATION_CAPABILITY;
  }
}

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function readAiRequestCount(): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM ai_request")
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function readPlatformCounterRows(): Promise<PlatformCounterRow[]> {
  const result = await env.DB.prepare(
    "SELECT counter_id, dimension_set, time_bucket, count FROM platform_counter ORDER BY counter_id",
  ).all<PlatformCounterRow>();
  return result.results ?? [];
}

async function clearCounterAndJournalTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM ai_request"),
  ]);
}

function parseDimensionSet(raw: string): Record<string, string> {
  return JSON.parse(raw) as Record<string, string>;
}

function assertRateLimitedResult(result: RateLimitResult): asserts result is RateLimitFailure {
  expect(result.ok).toBe(false);
  if (result.ok) {
    return;
  }

  expect(result.code).toBe("rate_limited");
  expect(getTaxonomyEntry(result.code).httpStatus).toBe(429);
  expect(result.retryAfter).toBeGreaterThan(0);
  expect(
    supplementaryFieldsForCode(result.code, { retryAfter: result.retryAfter }),
  ).toEqual({ retry_after: result.retryAfter });
}

async function overflowCompositeKey(
  module: RateLimitModule,
  bindings: RateLimitBindings,
  fixtures: ReturnType<typeof createRateLimitBindings>["fixtures"],
  keyKind: CompositeKeyKind,
  input: RateLimitInput = defaultRateLimitInput(),
): Promise<RateLimitFailure> {
  bindingForKey(fixtures, keyKind).setLimit(TRIP_LIMIT);

  let last: RateLimitResult = { ok: true };
  for (let attempt = 0; attempt < TRIP_LIMIT + 1; attempt += 1) {
    last = await module.checkRateLimit(input, bindings);
    if (!last.ok) {
      break;
    }
  }

  assertRateLimitedResult(last);
  return last;
}

async function assertCounterForKey(
  keyKind: CompositeKeyKind,
  input: RateLimitInput,
  expectedIncrement = 1,
): Promise<void> {
  const rows = await readPlatformCounterRows();
  const matching = rows.filter((row) => {
    const dimensions = parseDimensionSet(row.dimension_set);
    return (
      dimensions.error_code === "rate_limited" &&
      dimensions.composite_key === keyKind &&
      dimensions.installation_id === input.installationId
    );
  });

  expect(
    matching.length,
    `expected a platform_counter row for ${keyKind}`,
  ).toBeGreaterThan(0);

  const total = matching.reduce((sum, row) => sum + row.count, 0);
  expect(total).toBeGreaterThanOrEqual(expectedIncrement);

  for (const row of matching) {
    expect(row.time_bucket).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/,
    );
  }
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearCounterAndJournalTables();
});

describe("rate_limit_installation_key_trips", () => {
  it("overflows the installation composite key with rate_limited and counter increment", async () => {
    const module = await loadRateLimitModule();
    const { bindings, fixtures } = createRateLimitBindings();
    fixtures.RATE_LIMITER_INSTALLATION.setLimit(TRIP_LIMIT);

    const input = defaultRateLimitInput();
    const aiRequestsBefore = await readAiRequestCount();

    const result = await overflowCompositeKey(
      module,
      bindings,
      fixtures,
      "installation",
      input,
    );
    expect(result.retryAfter).toBeGreaterThan(0);

    await module.flushRejectionCounters(bindings);

    expect(await readAiRequestCount()).toBe(aiRequestsBefore);
    await assertCounterForKey("installation", input);
  });
});

describe("rate_limit_installation_actor_key_trips", () => {
  it("trips the installation+actor key independently of the other composite keys", async () => {
    const module = await loadRateLimitModule();
    const { bindings, fixtures } = createRateLimitBindings();
    fixtures.RATE_LIMITER_INSTALLATION_ACTOR.setLimit(TRIP_LIMIT);
    fixtures.RATE_LIMITER_INSTALLATION.setLimit(10_000);
    fixtures.RATE_LIMITER_INSTALLATION_CAPABILITY.setLimit(10_000);

    const input = defaultRateLimitInput();

    const underInstallationOnly = await module.checkRateLimit(input, bindings);
    expect(underInstallationOnly.ok).toBe(true);

    const result = await overflowCompositeKey(
      module,
      bindings,
      fixtures,
      "installation+actor",
      input,
    );
    expect(result.code).toBe("rate_limited");

    await module.flushRejectionCounters(bindings);
    await assertCounterForKey("installation+actor", input);
  });
});

describe("rate_limit_installation_capability_key_trips", () => {
  it("trips the installation+capability key independently of the other composite keys", async () => {
    const module = await loadRateLimitModule();
    const { bindings, fixtures } = createRateLimitBindings();
    fixtures.RATE_LIMITER_INSTALLATION_CAPABILITY.setLimit(TRIP_LIMIT);
    fixtures.RATE_LIMITER_INSTALLATION.setLimit(10_000);
    fixtures.RATE_LIMITER_INSTALLATION_ACTOR.setLimit(10_000);

    const input = defaultRateLimitInput();

    const underActorOnly = await module.checkRateLimit(input, bindings);
    expect(underActorOnly.ok).toBe(true);

    const result = await overflowCompositeKey(
      module,
      bindings,
      fixtures,
      "installation+capability",
      input,
    );
    expect(result.code).toBe("rate_limited");

    await module.flushRejectionCounters(bindings);
    await assertCounterForKey("installation+capability", input);
  });
});

describe("rate_limit_rejection_no_ai_request_row", () => {
  it("increments platform_counter without creating an ai_request journal row", async () => {
    const module = await loadRateLimitModule();
    const { bindings, fixtures } = createRateLimitBindings();
    fixtures.RATE_LIMITER_INSTALLATION.setLimit(TRIP_LIMIT);

    const countersBefore = await readPlatformCounterRows();
    const aiRequestsBefore = await readAiRequestCount();

    await overflowCompositeKey(module, bindings, fixtures, "installation");
    await module.flushRejectionCounters(bindings);

    expect(await readAiRequestCount()).toBe(aiRequestsBefore);

    const countersAfter = await readPlatformCounterRows();
    expect(countersAfter.length).toBeGreaterThan(countersBefore.length);

    const totalCount = countersAfter.reduce((sum, row) => sum + row.count, 0);
    const priorTotal = countersBefore.reduce((sum, row) => sum + row.count, 0);
    expect(totalCount).toBeGreaterThan(priorTotal);
  });
});

describe("rate_limit_counters_flush_bucketed", () => {
  it("writes bucketed platform_counter rows, never one row per rejection event", async () => {
    const module = await loadRateLimitModule();
    const { bindings, fixtures } = createRateLimitBindings();
    fixtures.RATE_LIMITER_INSTALLATION.setLimit(0);

    const rejectionCount = 5;
    const input = defaultRateLimitInput();

    for (let i = 0; i < rejectionCount; i += 1) {
      const result = await module.checkRateLimit(input, bindings);
      assertRateLimitedResult(result);
    }

    const rowsBeforeFlush = await readPlatformCounterRows();
    expect(rowsBeforeFlush.length).toBeLessThan(rejectionCount);

    await module.flushRejectionCounters(bindings);

    const rows = await readPlatformCounterRows();
    expect(rows.length).toBeGreaterThan(0);
    expect(rows.length).toBeLessThan(rejectionCount);

    const totalCount = rows.reduce((sum, row) => sum + row.count, 0);
    expect(totalCount).toBe(rejectionCount);

    const buckets = new Set(rows.map((row) => row.time_bucket));
    expect(buckets.size).toBe(1);

    const dimensionSets = new Set(rows.map((row) => row.dimension_set));
    expect(dimensionSets.size).toBe(1);
  });
});

describe("guard_rejection_counters_stages_2_3", () => {
  it("flushes identity and entitlement rejection codes into platform_counter", async () => {
    const module = await loadRateLimitModule();
    const { bindings } = createRateLimitBindings();

    module.recordGuardRejection({
      error_code: "unauthenticated",
      installation_id: FIXTURE_INSTALLATION_ID,
    });
    module.recordGuardRejection({
      error_code: "installation_suspended",
      installation_id: FIXTURE_INSTALLATION_ID,
    });
    module.recordGuardRejection({
      error_code: "forbidden_capability",
      installation_id: FIXTURE_INSTALLATION_ID,
    });
    module.recordGuardRejection({
      error_code: "capability_disabled",
      installation_id: FIXTURE_INSTALLATION_ID,
    });

    await module.flushRejectionCounters(bindings);

    const rows = await readPlatformCounterRows();
    const codes = rows.map((row) => JSON.parse(row.dimension_set).error_code as string);
    expect(codes.sort()).toEqual([
      "capability_disabled",
      "forbidden_capability",
      "installation_suspended",
      "unauthenticated",
    ]);
  });
});

describe("flush_rejection_counters_snapshot_clears_before_write", () => {
  it("does not double-count when a subsequent flush follows a completed flush", async () => {
    const module = await loadRateLimitModule();
    const { bindings } = createRateLimitBindings();

    module.recordGuardRejection({
      error_code: "unauthenticated",
      installation_id: FIXTURE_INSTALLATION_ID,
    });
    await module.flushRejectionCounters(bindings);
    await module.flushRejectionCounters(bindings);

    const rows = await readPlatformCounterRows();
    const total = rows.reduce((sum, row) => sum + row.count, 0);
    expect(total).toBe(1);
  });
});

describe("worker_scheduled_exports_flush", () => {
  it("shares flushRejectionCounters between rate-limit and admission modules", async () => {
    const rateLimit = await loadRateLimitModule();
    const admission = await import(/* @vite-ignore */ "../src/admission");
    expect(typeof rateLimit.flushRejectionCounters).toBe("function");
    expect(admission.flushRejectionCounters).toBe(rateLimit.flushRejectionCounters);
  });
});
