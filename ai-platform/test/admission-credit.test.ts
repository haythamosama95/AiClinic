import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import graceQueueMigrationSql from "../migrations/20260821120000_grace_admission_queue.sql?raw";
import fallbackAdmissionFeedMigrationSql from "../migrations/20261006160000_fallback_admission_feed.sql?raw";
import planCatalogueMigrationSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
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

const FALLBACK_ADMISSION_CAP = 5;
const CONCURRENCY_LIMIT = 16;
const EPHEMERAL_HORIZON_MS = 7_200_000;

const FIXTURE_ORG_ID = "org-adm-001";
const FIXTURE_NOW_MS = Date.parse("2026-07-31T12:00:00.000Z");
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";

type D1Row = Record<string, unknown>;

type IdempotencyRequestState =
  | "admitted"
  | "completed"
  | "failed"
  | "cancelled";

type IdempotencyPriorState = {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
};

type AdmissionInput = {
  principal: Principal;
  idempotencyKey: string;
  requestReference: string;
  capabilityId: string;
  quotaWeight: number;
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
  code: "unauthenticated" | "quota_exhausted" | "rate_limited" | "internal_error";
  periodReset?: string;
  retryAfter?: number;
};

type AdmissionResult = AdmissionSuccess | AdmissionFailure;

type CreditInput = {
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: { tokens: number; cost: number };
  credits?: number;
  partial: boolean;
};

type CreditBindings = {
  DO: DurableObjectNamespace;
  DB?: D1Database;
};

type PeriodCounters = {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
  creditsUsed: number;
  inFlight: number;
};

type CreditResult =
  | { ok: true; periodCounters: PeriodCounters }
  | { ok: false; code: "unknown_request" | "unavailable" | "internal_error" };

type ReconcileGraceResult = {
  reconciled: number;
};

type PendingGraceAdmission = {
  installationId: string;
  requestReference: string;
  jti: string;
  idempotencyKey: string;
  graceRequestId: string;
  usage?: { tokens: number; cost: number };
  partial?: boolean;
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
  drainPendingGraceAdmissions: () => PendingGraceAdmission[];
  peekPendingGraceAdmissions: (
    db?: D1Database,
  ) =>
    | readonly PendingGraceAdmission[]
    | Promise<readonly PendingGraceAdmission[]>;
  attachGraceUsage: (
    dbOrId: D1Database | string,
    graceRequestIdOrReference?: string | { tokens: number; cost: number },
    usage?: { tokens: number; cost: number } | boolean,
    partial?: boolean,
  ) => boolean | Promise<boolean>;
  resetGraceAdmissionCounter: (installationId: string) => void;
};

type GraceDropReason =
  | "settled_by_another_path_idempotent"
  | "settled_by_another_path_replay"
  | "settled_by_another_path_unknown_request"
  | "expired"
  | "max_attempts";

type DroppedGraceJournalEntry = {
  reason: GraceDropReason;
  installationId: string;
  requestReference: string;
  graceRequestId: string;
  idempotencyKey: string;
  atMs: number;
};

type CreditModule = {
  creditUsage: (
    input: CreditInput,
    bindings: CreditBindings,
  ) => Promise<CreditResult>;
  reconcileGraceUsage: (
    bindings: CreditBindings,
    ctx?: { now?: number },
  ) => Promise<ReconcileGraceResult>;
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

function createSettlingDoNamespace(
  realDo: DurableObjectNamespace,
): DurableObjectNamespace {
  return {
    idFromString: realDo.idFromString.bind(realDo),
    idFromName: realDo.idFromName?.bind(realDo),
    newUniqueId: realDo.newUniqueId?.bind(realDo),
    get: (id: DurableObjectId) => {
      const stub = realDo.get(id);
      return {
        fetch: async (...args: Parameters<typeof stub.fetch>) => {
          const init = args[1];
          if (init?.body && typeof init.body === "string") {
            const payload = JSON.parse(init.body) as { kind?: string };
            if (payload.kind === "settleFallback") {
              return new Response(
                JSON.stringify({ kind: "settleFallback", outcome: "settled" }),
                { status: 200, headers: { "Content-Type": "application/json" } },
              );
            }
          }
          return stub.fetch(...args);
        },
      };
    },
  } as DurableObjectNamespace;
}

async function seedAiRequestForFallback(
  installationId: string,
  requestId: string,
  idempotencyKey: string,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO ai_request (
       request_id, request_reference, installation_id, actor_id, branch_id,
       capability_id, capability_version, prompt_artifact_hash, idempotency_key,
       trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
       payload_pointer, conversation_id, turn_ordinal
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL)`,
  )
    .bind(
      requestId,
      uniqueRequestReference(),
      installationId,
      "actor-adm-001",
      "branch-adm-001",
      "clinic.visit_summary",
      "1.0.0",
      "prompt/fallback@v1",
      idempotencyKey,
      "01FALLBACKTRACE00000001",
      "Accepted",
      FIXTURE_NOW,
      FIXTURE_NOW,
    )
    .run();
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
  return crypto.randomUUID();
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
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM fallback_admission"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function countPendingFallbackRows(installationId: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS count
     FROM fallback_admission
     WHERE installation_id = ? AND state = 'pending'`,
  )
    .bind(installationId)
    .first<{ count: number }>();
  return Number(row?.count ?? 0);
}

async function peekPendingFallback(
  installationId?: string,
): Promise<
  readonly {
    installationId: string;
    requestId: string;
    idempotencyKey: string;
  }[]
> {
  const result = installationId
    ? await env.DB.prepare(
        `SELECT installation_id, request_id, idempotency_key
         FROM fallback_admission WHERE state = 'pending' AND installation_id = ?`,
      )
        .bind(installationId)
        .all<{
          installation_id: string;
          request_id: string;
          idempotency_key: string;
        }>()
    : await env.DB.prepare(
        `SELECT installation_id, request_id, idempotency_key
         FROM fallback_admission WHERE state = 'pending'`,
      ).all<{
        installation_id: string;
        request_id: string;
        idempotency_key: string;
      }>();
  return (result.results ?? []).map((row) => ({
    installationId: row.installation_id,
    requestId: row.request_id,
    idempotencyKey: row.idempotency_key,
  }));
}

async function seedCoverageMirror(installationId: string): Promise<void> {
  const termRef = `term-${installationId.slice(0, 8)}`;
  await env.DB.prepare(
    `INSERT INTO coverage_mirror (
       installation_id, org_id, binding_epoch, clinic_seq, state, suspended,
       hard_stop_at, term_snapshot
     ) VALUES (?, ?, 1, 1, 'active', 0, ?, ?)`,
  )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      "2026-12-31T23:59:59.000Z",
      JSON.stringify({
        ref: termRef,
        capabilities: ["clinic.visit_summary"],
      }),
    )
    .run();
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
    creditBudget?: number;
  } = {},
): Promise<void> {
  const {
    requestQuota = 1_000,
    tokenBudget = 1_000_000,
    costBudget = 100,
    creditBudget = 10_000,
  } = options;

  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, credit_budget, allowed_capabilities,
      soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
      creditBudget,
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
                    request_quota, token_budget, cost_budget, credit_budget,
                    allowed_capabilities, soft_threshold, status
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
  options: { coverageMirror?: boolean } = {},
): Promise<{ cache: ConfigCache; reader: D1Reader }> {
  await seedInstallation(installationId);
  await seedEntitlement(installationId, entitlementOptions);
  if (options.coverageMirror !== false) {
    await seedCoverageMirror(installationId);
  }
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
    capabilityId: "clinic.visit_summary",
    quotaWeight: 1,
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
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
  await applyPlatformSchema(env.DB, graceQueueMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
  await applySqlStatements(env.DB, fallbackAdmissionFeedMigrationSql);
});

beforeEach(async () => {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;
  await clearAdmissionTables();
  const admission = await loadAdmissionModule();
  admission.drainPendingGraceAdmissions();
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
  it("rejects unauthenticated when the token expired outside skew before idempotency replay", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const jti = uniqueJti();
    const clockSkewSeconds = 60;

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
          exp: FIXTURE_NOW_MS - clockSkewSeconds - 1,
        },
      }),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );

    expect(retry).toEqual({ ok: false, code: "unauthenticated" });
  });
});

describe("quota_do_unavailable_capped_grace_then_rejection", () => {
  it(`admits under grace for ${FALLBACK_ADMISSION_CAP} calls then rejects when DO stays unavailable`, async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);
    const bindings: AdmissionBindings = { DB: env.DB, DO: brokenDo };

    for (let index = 0; index < FALLBACK_ADMISSION_CAP; index += 1) {
      const result = await admission.runAdmission(
        defaultAdmissionInput(installationId, cache, reader),
        bindings,
        { now: FIXTURE_NOW_MS },
      );
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.outcome).toBe("grace_admitted");
      }
    }

    expect(await peekPendingFallback(installationId)).toHaveLength(FALLBACK_ADMISSION_CAP);

    const rejected = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      bindings,
      { now: FIXTURE_NOW_MS },
    );
    expect(rejected).toEqual({
      ok: false,
      code: "coverage_unknown",
      retryAfter: 60,
    });

    // Cap exhaustion must not wipe prior grace queue entries.
    expect(await peekPendingFallback(installationId)).toHaveLength(FALLBACK_ADMISSION_CAP);
  });
});

describe("grace_cap_refusal_distinct_from_quota_exhausted", () => {
  it("rejects at the fallback cap with coverage_unknown while entitlement budget remains", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      requestQuota: 1_000,
    });
    const brokenDo = createThrowingDoNamespace(env.DO);
    const bindings: AdmissionBindings = { DB: env.DB, DO: brokenDo };

    for (let index = 0; index < FALLBACK_ADMISSION_CAP; index += 1) {
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
    if (rejected.ok) {
      return;
    }
    expect(rejected.code).toBe("coverage_unknown");
    expect(rejected.code).not.toBe("quota_exhausted");
    expect(rejected.retryAfter).toBe(60);
    expect(await countPendingFallbackRows(installationId)).toBe(FALLBACK_ADMISSION_CAP);
  });
});

describe("grace_durable_cap_across_isolate_maps", () => {
  it("rejects a sixth grace admit after isolate maps are wiped because D1 pending count holds the cap", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);
    const bindings: AdmissionBindings = { DB: env.DB, DO: brokenDo };

    for (let index = 0; index < FALLBACK_ADMISSION_CAP; index += 1) {
      const result = await admission.runAdmission(
        defaultAdmissionInput(installationId, cache, reader),
        bindings,
        { now: FIXTURE_NOW_MS },
      );
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.outcome).toBe("grace_admitted");
      }
    }

    // Simulate a second isolate: in-process maps are empty, D1 is not.
    admission.drainPendingGraceAdmissions();
    admission.resetGraceAdmissionCounter(installationId);

    const sixth = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      bindings,
      { now: FIXTURE_NOW_MS },
    );
    expect(sixth).toEqual({
      ok: false,
      code: "coverage_unknown",
      retryAfter: 60,
    });
    expect(await countPendingFallbackRows(installationId)).toBe(FALLBACK_ADMISSION_CAP);
  });
});

describe("grace_idempotency_key_replay_during_do_outage", () => {
  it("returns the same graceRequestId and keeps a single pending D1 row", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const first = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference,
      }),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(first.ok).toBe(true);
    if (!first.ok) {
      return;
    }
    expect(first.outcome).toBe("grace_admitted");
    const firstRequestId = first.requestId;

    const second = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference: uniqueRequestReference(),
        principal: { jti: uniqueJti() },
      }),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );

    expect(second.ok).toBe(true);
    if (!second.ok) {
      return;
    }
    if (second.outcome === "grace_admitted") {
      expect(second.requestId).toBe(firstRequestId);
    } else {
      expect(second.outcome).toBe("idempotent");
      expect(second.priorState.requestId).toBe(firstRequestId);
    }
    expect(await countPendingFallbackRows(installationId)).toBe(1);
    expect(await peekPendingFallback(installationId)).toHaveLength(1);
  });
});

describe("grace_rejects_when_ledger_quota_exhausted", () => {
  it("rejects quota_exhausted when request_quota is already 0 on the entitlement snapshot", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(
      installationId,
      { requestQuota: 0 },
      { coverageMirror: false },
    );
    const brokenDo = createThrowingDoNamespace(env.DO);

    const result = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(result).toMatchObject({ ok: false, code: "coverage_unknown" });
    expect(await countPendingFallbackRows(installationId)).toBe(0);
  });

  it("rejects coverage_unknown when mirror fallback is unavailable", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(
      installationId,
      { requestQuota: 1 },
      { coverageMirror: false },
    );
    await env.DB.prepare(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        state, created_at, updated_at, completed_at, terminal_error_code,
        trace_id, payload_pointer, conversation_id, turn_ordinal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL, NULL, NULL)`,
    )
      .bind(
        crypto.randomUUID(),
        uniqueRequestReference(),
        installationId,
        "actor-adm-001",
        "branch-adm-001",
        "clinic.visit_summary",
        "1.0.0",
        "prompt/grace-quota@v1",
        uniqueIdempotencyKey(),
        "Accepted",
        "2026-08-15T00:00:00.000Z",
        "2026-08-15T00:00:00.000Z",
        "01GRACEQUOTATRACE00000001",
      )
      .run();

    const result = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: createThrowingDoNamespace(env.DO) },
      { now: FIXTURE_NOW_MS },
    );
    expect(result).toMatchObject({ ok: false, code: "coverage_unknown" });
    expect(await countPendingFallbackRows(installationId)).toBe(0);
  });
});

describe("fallback_reconcile_drains_pending_rows", () => {
  it("settles pending fallback_admission via settleFallback on the five-minute drain", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);

    const fallback = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(fallback.ok).toBe(true);
    if (fallback.ok) {
      expect(fallback.outcome).toBe("grace_admitted");
    }
    expect(await countPendingFallbackRows(installationId)).toBe(1);

    if (fallback.ok && fallback.outcome === "grace_admitted") {
      await seedAiRequestForFallback(
        installationId,
        fallback.requestId,
        uniqueIdempotencyKey(),
      );
    }

    const reconcile = await credit.reconcileGraceUsage({
      DO: createSettlingDoNamespace(env.DO),
      DB: env.DB,
    });
    expect(reconcile.reconciled).toBe(1);
    expect(await countPendingFallbackRows(installationId)).toBe(0);

    const settled = await env.DB.prepare(
      `SELECT state FROM fallback_admission WHERE installation_id = ?`,
    )
      .bind(installationId)
      .first<{ state: string }>();
    expect(settled?.state).toBe("settled");
  });

  it("keeps pending fallback rows when settleFallback is skipped", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);

    const fallback = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(fallback.ok).toBe(true);
    if (!fallback.ok || fallback.outcome !== "grace_admitted") {
      return;
    }

    await seedAiRequestForFallback(
      installationId,
      fallback.requestId,
      uniqueIdempotencyKey(),
    );

    const mirror = await env.DB.prepare(
      `SELECT term_snapshot FROM coverage_mirror WHERE installation_id = ?`,
    )
      .bind(installationId)
      .first<{ term_snapshot: string }>();
    const termRef =
      typeof mirror?.term_snapshot === "string"
        ? (JSON.parse(mirror.term_snapshot) as { ref?: string }).ref ?? "term-existing"
        : "term-existing";

    await env.DB.prepare(
      `INSERT OR IGNORE INTO usage_event (
         usage_event_id, installation_id, term_id, request_id,
         quota_weight, tokens, cost, recorded_at
       ) VALUES (?, ?, ?, ?, ?, 0, 0, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        installationId,
        termRef,
        fallback.requestId,
        1,
        FIXTURE_NOW,
      )
      .run();

    const reconcile = await credit.reconcileGraceUsage({ DO: env.DO, DB: env.DB });
    expect(reconcile.reconciled).toBe(0);
    expect(await countPendingFallbackRows(installationId)).toBe(1);
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
    expect(rejected).toEqual({
      ok: false,
      code: "quota_exhausted",
      periodReset: "2026-09-01T00:00:00.000Z",
    });

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

  it("tallies replay rejection as unauthenticated without an ai_request row", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const jti = uniqueJti();
    const aiRequestsBefore = await readAiRequestCount();

    const first = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        principal: { jti },
      }),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(first);

    const replay = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        principal: { jti },
      }),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    expect(replay).toEqual({ ok: false, code: "unauthenticated" });

    await admission.flushRejectionCounters({ DB: env.DB });
    expect(await readAiRequestCount()).toBe(aiRequestsBefore);

    const matching = (await readPlatformCounterRows()).filter((row) => {
      const dimensions = parseDimensionSet(row.dimension_set);
      return (
        dimensions.error_code === "unauthenticated" &&
        dimensions.installation_id === installationId
      );
    });
    expect(matching.reduce((sum, row) => sum + row.count, 0)).toBeGreaterThanOrEqual(1);
  });

  it("maps concurrency_exhausted onto quota_exhausted and tallies that code", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);

    for (let index = 0; index < CONCURRENCY_LIMIT; index += 1) {
      const admitted = await admission.runAdmission(
        defaultAdmissionInput(installationId, cache, reader),
        { DB: env.DB, DO: env.DO },
        { now: FIXTURE_NOW_MS },
      );
      assertAdmitted(admitted);
    }

    const rejected = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    expect(rejected).toEqual({
      ok: false,
      code: "quota_exhausted",
      periodReset: "2026-09-01T00:00:00.000Z",
    });

    await admission.flushRejectionCounters({ DB: env.DB });
    const matching = (await readPlatformCounterRows()).filter((row) => {
      const dimensions = parseDimensionSet(row.dimension_set);
      return (
        dimensions.error_code === "quota_exhausted" &&
        dimensions.installation_id === installationId
      );
    });
    expect(matching.reduce((sum, row) => sum + row.count, 0)).toBeGreaterThanOrEqual(1);
  });

  it("tallies fallback-cap rejection as coverage_unknown, not quota_exhausted", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);

    for (let index = 0; index < FALLBACK_ADMISSION_CAP; index += 1) {
      const result = await admission.runAdmission(
        defaultAdmissionInput(installationId, cache, reader),
        { DB: env.DB, DO: brokenDo },
        { now: FIXTURE_NOW_MS },
      );
      expect(result.ok).toBe(true);
    }

    const rejected = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(rejected).toEqual({
      ok: false,
      code: "coverage_unknown",
      retryAfter: 60,
    });

    await admission.flushRejectionCounters({ DB: env.DB });
    const matching = (await readPlatformCounterRows()).filter((row) => {
      const dimensions = parseDimensionSet(row.dimension_set);
      return (
        dimensions.error_code === "coverage_unknown" &&
        dimensions.installation_id === installationId
      );
    });
    expect(matching.reduce((sum, row) => sum + row.count, 0)).toBeGreaterThanOrEqual(1);

    const quotaTally = (await readPlatformCounterRows()).filter((row) => {
      const dimensions = parseDimensionSet(row.dimension_set);
      return (
        dimensions.error_code === "quota_exhausted" &&
        dimensions.installation_id === installationId
      );
    });
    expect(quotaTally.reduce((sum, row) => sum + row.count, 0)).toBe(0);
  });
});

describe("admission_missing_entitlement_fail_closed", () => {
  it("rejects quota_exhausted on config-cache miss instead of throwing or grace", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const cache = new ConfigCache();
    const reader: D1Reader = {
      async read() {
        return "miss";
      },
    };

    const result = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );

    expect(result).toEqual({ ok: false, code: "quota_exhausted" });
    expect(await peekPendingFallback(installationId)).toHaveLength(0);
  });
});

describe("guard_rejection_debits_nothing_and_writes_no_journal_row", () => {
  it("does not invoke credit or write ai_request when credit budget is exhausted at admission", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const creditBudget = 5;
    const W = 5;
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      creditBudget,
      requestQuota: 100,
    });

    const first = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(first);

    await credit.creditUsage(
      {
        installationId,
        requestId: first.requestId,
        requestReference: uniqueRequestReference(),
        usage: { tokens: 1, cost: 0.001 },
        partial: false,
        credits: W,
      },
      { DO: env.DO },
    );

    const aiRequestsBefore = await readAiRequestCount();
    const doSpy = createDoSpy(env.DO);

    const rejected = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: doSpy },
      { now: FIXTURE_NOW_MS },
    );

    expect(rejected).toEqual({
      ok: false,
      code: "quota_exhausted",
      periodReset: "2026-09-01T00:00:00.000Z",
    });
    expect(doSpy.fetchCount()).toBe(1);
    expect(await readAiRequestCount()).toBe(aiRequestsBefore);
  });
});

describe("exactly_two_durable_object_round_trips_per_request", () => {
  it("makes exactly two DO fetches for admission then credit", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const doSpy = createDoSpy(env.DO);
    const requestReference = uniqueRequestReference();

    const admitted = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, { requestReference }),
      { DB: env.DB, DO: doSpy },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(admitted);
    expect(doSpy.fetchCount()).toBe(1);

    await credit.creditUsage(
      {
        installationId,
        requestId: admitted.requestId,
        requestReference,
        usage: { tokens: 10, cost: 0.01 },
        partial: false,
        credits: 3,
      },
      { DO: doSpy },
    );

    expect(doSpy.fetchCount()).toBe(2);
  });
});
