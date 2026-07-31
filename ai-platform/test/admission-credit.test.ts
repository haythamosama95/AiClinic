import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  ConfigCache,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import type { Principal } from "../src/identity";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    DO: DurableObjectNamespace;
  }
}

const GRACE_ADMISSION_CAP = 5;
const CONCURRENCY_LIMIT = 16;
const EPHEMERAL_HORIZON_MS = 7_200_000;

const FIXTURE_ORG_ID = "org-adm-001";
const FIXTURE_NOW_MS = Date.parse("2026-07-31T12:00:00.000Z");
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";

type D1Row = Record<string, unknown>;

type IdempotencyRequestState =
  | "admitted"
  | "in_progress"
  | "completed"
  | "failed"
  | "cancelled"
  | "awaiting_context";

type IdempotencyPriorState = {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
};

type AdmissionInput = {
  principal: Principal;
  idempotencyKey: string;
  requestReference: string;
  cache: ConfigCache;
  reader: D1Reader;
};

type AdmissionBindings = {
  DB: D1Database;
  DO: DurableObjectNamespace;
};

type AdmissionContext = {
  now?: number;
};

type AdmissionSuccess =
  | { ok: true; outcome: "admitted"; requestId: string }
  | { ok: true; outcome: "grace_admitted"; requestId: string; requestReference: string }
  | { ok: true; outcome: "idempotent"; priorState: IdempotencyPriorState };

type AdmissionFailure = {
  ok: false;
  code: "unauthenticated" | "quota_exhausted" | "concurrency_exhausted" | "internal_error";
};

type AdmissionResult = AdmissionSuccess | AdmissionFailure;

type CreditInput = {
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: { tokens: number; cost: number };
  partial: boolean;
};

type CreditBindings = {
  DO: DurableObjectNamespace;
};

type PeriodCounters = {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
  inFlight: number;
};

type CreditResult =
  | { ok: true; periodCounters: PeriodCounters }
  | { ok: false; code: "unknown_request" };

type ReconcileGraceResult = {
  reconciled: number;
};

type AdmissionModule = {
  runAdmission: (
    input: AdmissionInput,
    bindings: AdmissionBindings,
    ctx?: AdmissionContext,
  ) => Promise<AdmissionResult>;
  flushRejectionCounters: (
    bindings: Pick<AdmissionBindings, "DB">,
  ) => Promise<void>;
};

type CreditModule = {
  creditUsage: (
    input: CreditInput,
    bindings: CreditBindings,
  ) => Promise<CreditResult>;
  reconcileGraceUsage: (bindings: CreditBindings) => Promise<ReconcileGraceResult>;
};

type PlatformCounterRow = {
  counter_id: string;
  dimension_set: string;
  time_bucket: string;
  count: number;
};

type DoSpy = DurableObjectNamespace & {
  fetchCount: () => number;
};

let jtiCounter = 0;
let idempotencyKeyCounter = 0;
let requestReferenceCounter = 0;

/** Loads stage-8 admission caller from `src/admission/` (absent until Phase 3). */
async function loadAdmissionModule(): Promise<AdmissionModule> {
  return import(/* @vite-ignore */ "../src/admission") as Promise<AdmissionModule>;
}

/** Loads stage-15 credit caller from `src/credit/` (absent until Phase 3). */
async function loadCreditModule(): Promise<CreditModule> {
  return import(/* @vite-ignore */ "../src/credit") as Promise<CreditModule>;
}

function createDoSpy(realDo: DurableObjectNamespace): DoSpy {
  let fetchCount = 0;
  const spy = {
    idFromString: realDo.idFromString.bind(realDo),
    idFromName: realDo.idFromName?.bind(realDo),
    newUniqueId: realDo.newUniqueId?.bind(realDo),
    get: (id: DurableObjectId) => {
      const stub = realDo.get(id);
      return {
        fetch: async (...args: Parameters<typeof stub.fetch>) => {
          fetchCount += 1;
          return stub.fetch(...args);
        },
      };
    },
    fetchCount: () => fetchCount,
  };
  return spy as DoSpy;
}

function createThrowingDoNamespace(realDo: DurableObjectNamespace): DurableObjectNamespace {
  return {
    idFromString: realDo.idFromString.bind(realDo),
    idFromName: realDo.idFromName?.bind(realDo),
    newUniqueId: realDo.newUniqueId?.bind(realDo),
    get: () => ({
      fetch: async () => {
        throw new Error("Quota DO unavailable");
      },
    }),
  } as DurableObjectNamespace;
}

function uniqueJti(): string {
  jtiCounter += 1;
  return `f4000000-0000-4000-8000-${String(jtiCounter).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `01ARZ3NDEK${String(idempotencyKeyCounter).padStart(14, "0")}`;
}

function uniqueRequestReference(): string {
  requestReferenceCounter += 1;
  return `AI-${String(requestReferenceCounter).padStart(6, "0")}`;
}

function freshInstallationId(): string {
  return env.DO.newUniqueId().toString();
}

function makePrincipal(
  installationId: string,
  overrides: Partial<Principal> = {},
): Principal {
  return {
    installationId,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-adm-001",
    actorId: "actor-adm-001",
    role: "clinician",
    scopes: ["ai.visit_summary"],
    jti: uniqueJti(),
    iat: FIXTURE_NOW_MS - 30_000,
    exp: FIXTURE_NOW_MS + 300_000,
    ver: "1",
    ...overrides,
  };
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

async function clearAdmissionTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallation(installationId: string): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (
      installation_id, org_id, display_name, status, region, enrolled_at
    ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      "Admission Integration Clinic",
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(
  installationId: string,
  options: {
    requestQuota?: number;
    tokenBudget?: number;
    costBudget?: number;
  } = {},
): Promise<void> {
  const {
    requestQuota = 1_000,
    tokenBudget = 1_000_000,
    costBudget = 100,
  } = options;

  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, allowed_capabilities,
      soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `ent-${installationId}`,
      installationId,
      "professional",
      "2026-08-01T00:00:00.000Z",
      "2026-09-01T00:00:00.000Z",
      requestQuota,
      tokenBudget,
      costBudget,
      JSON.stringify(["ai.visit_summary"]),
      0.8,
      "active",
    )
    .run();
}

function makePlatformD1Reader(db: D1Database): D1Reader {
  return {
    async read(prefixedKey: string): Promise<D1Row | "miss"> {
      const separator = prefixedKey.indexOf(":");
      if (separator === -1) {
        return "miss";
      }

      const kind = prefixedKey.slice(0, separator) as ConfigEntityKind;
      const key = prefixedKey.slice(separator + 1);

      if (kind === "installations") {
        const row = await db
          .prepare(
            "SELECT installation_id, org_id, display_name, status, region, enrolled_at FROM installation WHERE installation_id = ?",
          )
          .bind(key)
          .first<D1Row>();
        return row ?? "miss";
      }

      if (kind === "entitlements") {
        const row = await db
          .prepare(
            `SELECT entitlement_id, installation_id, plan, period_start, period_end,
                    request_quota, token_budget, cost_budget, allowed_capabilities,
                    soft_threshold, status
             FROM entitlement WHERE installation_id = ?`,
          )
          .bind(key)
          .first<D1Row>();
        return row ?? "miss";
      }

      return "miss";
    },
  };
}

async function seedInstallationAndEntitlement(
  installationId: string,
  entitlementOptions: Parameters<typeof seedEntitlement>[1] = {},
): Promise<{ cache: ConfigCache; reader: D1Reader }> {
  await seedInstallation(installationId);
  await seedEntitlement(installationId, entitlementOptions);
  return {
    cache: new ConfigCache(),
    reader: makePlatformD1Reader(env.DB),
  };
}

function defaultAdmissionInput(
  installationId: string,
  cache: ConfigCache,
  reader: D1Reader,
  overrides: {
    principal?: Partial<Principal>;
    idempotencyKey?: string;
    requestReference?: string;
  } = {},
): AdmissionInput {
  return {
    principal: makePrincipal(installationId, overrides.principal),
    idempotencyKey: overrides.idempotencyKey ?? uniqueIdempotencyKey(),
    requestReference: overrides.requestReference ?? uniqueRequestReference(),
    cache,
    reader,
  };
}

async function readAiRequestCount(): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM ai_request").first<{
    count: number;
  }>();
  return row?.count ?? 0;
}

async function readPlatformCounterRows(): Promise<PlatformCounterRow[]> {
  const result = await env.DB.prepare(
    "SELECT counter_id, dimension_set, time_bucket, count FROM platform_counter ORDER BY counter_id",
  ).all<PlatformCounterRow>();
  return result.results ?? [];
}

function parseDimensionSet(raw: string): Record<string, string> {
  return JSON.parse(raw) as Record<string, string>;
}

function assertAdmitted(
  result: AdmissionResult,
): asserts result is Extract<AdmissionSuccess, { outcome: "admitted" }> {
  expect(result.ok).toBe(true);
  if (!result.ok) {
    return;
  }
  expect(result.outcome).toBe("admitted");
  expect(result.requestId.length).toBeGreaterThan(0);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;
  await clearAdmissionTables();
});

describe("admission_exactly_one_do_fetch_per_request", () => {
  it("makes exactly one Durable Object fetch per pipeline admission call", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const doSpy = createDoSpy(env.DO);

    const result = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: doSpy },
      { now: FIXTURE_NOW_MS },
    );

    expect(doSpy.fetchCount()).toBe(1);
    assertAdmitted(result);
  });
});

describe("admission_repeated_key_no_second_inference", () => {
  it("returns idempotent priorState with one DO fetch per call and no duplicate inference", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const firstSpy = createDoSpy(env.DO);
    const first = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference,
      }),
      { DB: env.DB, DO: firstSpy },
      { now: FIXTURE_NOW_MS },
    );
    expect(firstSpy.fetchCount()).toBe(1);
    assertAdmitted(first);

    const secondSpy = createDoSpy(env.DO);
    const second = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference: uniqueRequestReference(),
        principal: { jti: uniqueJti() },
      }),
      { DB: env.DB, DO: secondSpy },
      { now: FIXTURE_NOW_MS },
    );

    expect(secondSpy.fetchCount()).toBe(1);
    expect(second).toEqual({
      ok: true,
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "admitted",
        requestId: first.requestId,
      },
    });
  });
});

describe("admission_expired_token_same_key_unauthenticated", () => {
  it("rejects unauthenticated when the token expired before idempotency replay", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const jti = uniqueJti();

    const first = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference,
        principal: {
          jti,
          exp: FIXTURE_NOW_MS + 300_000,
        },
      }),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(first);

    const retry = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference: uniqueRequestReference(),
        principal: {
          jti,
          exp: FIXTURE_NOW_MS - 1,
        },
      }),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );

    expect(retry).toEqual({ ok: false, code: "unauthenticated" });
  });
});

describe("quota_do_unavailable_capped_grace_then_rejection", () => {
  it(`admits under grace for ${GRACE_ADMISSION_CAP} calls then rejects when DO stays unavailable`, async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);
    const bindings: AdmissionBindings = { DB: env.DB, DO: brokenDo };

    for (let index = 0; index < GRACE_ADMISSION_CAP; index += 1) {
      const result = await admission.runAdmission(
        defaultAdmissionInput(installationId, cache, reader),
        bindings,
        { now: FIXTURE_NOW_MS },
      );
      expect(result.ok).toBe(true);
    }

    const rejected = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      bindings,
      { now: FIXTURE_NOW_MS },
    );
    expect(rejected.ok).toBe(false);
  });
});

describe("grace_usage_reconciled_afterwards", () => {
  it("reconciles queued grace usage with one credit DO fetch once the DO is reachable", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);
    const requestReference = uniqueRequestReference();

    const graceResult = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, { requestReference }),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(graceResult.ok).toBe(true);

    const creditSpy = createDoSpy(env.DO);
    const reconcile = await credit.reconcileGraceUsage({ DO: creditSpy });

    expect(creditSpy.fetchCount()).toBe(1);
    expect(reconcile.reconciled).toBeGreaterThanOrEqual(1);
  });
});

describe("admission_rejection_counted_not_journaled", () => {
  it("tallies quota_exhausted to bucketed platform_counter without an ai_request row", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      requestQuota: 1,
    });

    const countersBefore = await readPlatformCounterRows();
    const aiRequestsBefore = await readAiRequestCount();

    const admitted = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(admitted);

    await credit.creditUsage(
      {
        installationId,
        requestId: admitted.requestId,
        requestReference: uniqueRequestReference(),
        usage: { tokens: 10, cost: 0.01 },
        partial: false,
      },
      { DO: env.DO },
    );

    const rejected = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    expect(rejected).toEqual({ ok: false, code: "quota_exhausted" });

    await admission.flushRejectionCounters({ DB: env.DB });

    expect(await readAiRequestCount()).toBe(aiRequestsBefore);

    const countersAfter = await readPlatformCounterRows();
    expect(countersAfter.length).toBeGreaterThan(countersBefore.length);

    const matching = countersAfter.filter((row) => {
      const dimensions = parseDimensionSet(row.dimension_set);
      return (
        dimensions.error_code === "quota_exhausted" &&
        dimensions.installation_id === installationId
      );
    });
    expect(matching.length).toBeGreaterThan(0);

    const totalRejected = matching.reduce((sum, row) => sum + row.count, 0);
    expect(totalRejected).toBeGreaterThanOrEqual(1);
  });
});
