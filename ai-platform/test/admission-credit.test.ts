import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import graceQueueMigrationSql from "../migrations/20260821120000_grace_admission_queue.sql?raw";
import planCatalogueMigrationSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
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
  drainDroppedGraceJournal: () => DroppedGraceJournalEntry[];
  peekDroppedGraceJournal: () => readonly DroppedGraceJournalEntry[];
  GRACE_RECONCILE_MAX_ATTEMPTS: number;
  GRACE_RECONCILE_TTL_MS: number;
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
    env.DB.prepare("DELETE FROM grace_admission_queue"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function countPendingGraceRows(installationId: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS count
     FROM grace_admission_queue
     WHERE installation_id = ? AND status = 'pending'`,
  )
    .bind(installationId)
    .first<{ count: number }>();
  return Number(row?.count ?? 0);
}

async function peekPendingGrace(
  admission: AdmissionModule,
): Promise<readonly PendingGraceAdmission[]> {
  return admission.peekPendingGraceAdmissions(env.DB);
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
  await applyPlatformSchema(env.DB, graceQueueMigrationSql);
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
});

beforeEach(async () => {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;
  await clearAdmissionTables();
  const admission = await loadAdmissionModule();
  admission.drainPendingGraceAdmissions();
  const credit = await loadCreditModule();
  credit.drainDroppedGraceJournal();
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
      if (result.ok) {
        expect(result.outcome).toBe("grace_admitted");
      }
    }

    expect(await peekPendingGrace(admission)).toHaveLength(GRACE_ADMISSION_CAP);

    const rejected = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      bindings,
      { now: FIXTURE_NOW_MS },
    );
    expect(rejected).toEqual({
      ok: false,
      code: "rate_limited",
      retryAfter: 60,
    });

    // Cap exhaustion must not wipe prior grace queue entries.
    expect(await peekPendingGrace(admission)).toHaveLength(GRACE_ADMISSION_CAP);
  });
});

describe("grace_cap_refusal_distinct_from_quota_exhausted", () => {
  it("rejects at the grace cap with rate_limited while entitlement budget remains", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      requestQuota: 1_000,
    });
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
    if (rejected.ok) {
      return;
    }
    expect(rejected.code).toBe("rate_limited");
    expect(rejected.code).not.toBe("quota_exhausted");
    expect(rejected.retryAfter).toBe(60);
    expect(await countPendingGraceRows(installationId)).toBe(GRACE_ADMISSION_CAP);
  });
});

describe("grace_durable_cap_across_isolate_maps", () => {
  it("rejects a sixth grace admit after isolate maps are wiped because D1 pending count holds the cap", async () => {
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
      code: "rate_limited",
      retryAfter: 60,
    });
    expect(await countPendingGraceRows(installationId)).toBe(GRACE_ADMISSION_CAP);
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
    expect(await countPendingGraceRows(installationId)).toBe(1);
    expect(await peekPendingGrace(admission)).toHaveLength(1);
  });
});

describe("grace_rejects_when_ledger_quota_exhausted", () => {
  it("rejects quota_exhausted when request_quota is already 0 on the entitlement snapshot", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      requestQuota: 0,
    });
    const brokenDo = createThrowingDoNamespace(env.DO);

    const result = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(result).toMatchObject({ ok: false, code: "quota_exhausted" });
    expect(await countPendingGraceRows(installationId)).toBe(0);
  });

  it("rejects quota_exhausted when in-period ai_request count already meets request_quota", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      requestQuota: 1,
    });
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
    expect(result).toMatchObject({ ok: false, code: "quota_exhausted" });
    expect(await countPendingGraceRows(installationId)).toBe(0);
  });
});

describe("grace_usage_attached_from_creditUsage_then_reconciled", () => {
  it("persists usage via creditUsage DB binding and reconciles those tokens, not zeros", async () => {
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
    if (!graceResult.ok) {
      return;
    }
    expect(graceResult.outcome).toBe("grace_admitted");

    const attachSpy = vi.spyOn(admission, "attachGraceUsage");
    const settled = await credit.creditUsage(
      {
        installationId,
        requestId: graceResult.requestId,
        requestReference,
        usage: { tokens: 10, cost: 0.01 },
        partial: false,
      },
      { DO: brokenDo, DB: env.DB },
    );
    expect(settled.ok).toBe(false);
    expect(attachSpy).toHaveBeenCalled();
    attachSpy.mockRestore();

    const stored = await env.DB.prepare(
      `SELECT usage_tokens, usage_cost FROM grace_admission_queue
       WHERE grace_request_id = ? OR request_reference = ?`,
    )
      .bind(graceResult.requestId, requestReference)
      .first<{ usage_tokens: number; usage_cost: number }>();
    expect(stored?.usage_tokens).toBe(10);

    const creditSpy = createDoSpy(env.DO);
    const reconcile = await credit.reconcileGraceUsage({
      DO: creditSpy,
      DB: env.DB,
    });
    expect(reconcile.reconciled).toBeGreaterThanOrEqual(1);

    const probe = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(probe);
    const probeCredit = await credit.creditUsage(
      {
        installationId,
        requestId: probe.requestId,
        requestReference: uniqueRequestReference(),
        usage: { tokens: 1, cost: 0 },
        partial: false,
      },
      { DO: env.DO },
    );
    expect(probeCredit.ok).toBe(true);
    if (probeCredit.ok) {
      expect(probeCredit.periodCounters.tokensUsed).toBeGreaterThanOrEqual(11);
      expect(probeCredit.periodCounters.requestsUsed).toBeGreaterThanOrEqual(2);
    }
  });
});

describe("grace_usage_reconciled_afterwards", () => {
  it("re-admits then credits so DO requestsUsed increases once the DO is reachable", async () => {
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
    if (graceResult.ok) {
      expect(graceResult.outcome).toBe("grace_admitted");
    }

    expect(
      await admission.attachGraceUsage(
        env.DB,
        requestReference,
        { tokens: 10, cost: 0.01 },
        false,
      ),
    ).toBe(true);

    const creditSpy = createDoSpy(env.DO);
    const reconcile = await credit.reconcileGraceUsage({ DO: creditSpy, DB: env.DB });

    // Re-admit + credit for the pending grace entry.
    expect(creditSpy.fetchCount()).toBe(2);
    expect(reconcile.reconciled).toBeGreaterThanOrEqual(1);

    // Probe DO counters: grace settlement already counted as 1 requestUsed.
    const probe = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(probe);

    const probeCredit = await credit.creditUsage(
      {
        installationId,
        requestId: probe.requestId,
        requestReference: uniqueRequestReference(),
        usage: { tokens: 1, cost: 0 },
        partial: false,
      },
      { DO: env.DO },
    );
    expect(probeCredit.ok).toBe(true);
    if (probeCredit.ok) {
      expect(probeCredit.periodCounters.requestsUsed).toBeGreaterThanOrEqual(2);
    }
  });
});

describe("grace_reconcile_settled_by_another_path", () => {
  it("drops on idempotent when a client retry already admitted and credited the key", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const jti = uniqueJti();

    const graceResult = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference,
        principal: { jti },
      }),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(graceResult.ok).toBe(true);
    if (graceResult.ok) {
      expect(graceResult.outcome).toBe("grace_admitted");
    }

    expect(
      await admission.attachGraceUsage(
        env.DB,
        requestReference,
        { tokens: 99, cost: 9.9 },
        false,
      ),
    ).toBe(true);

    // Client retry after DO recovery — same idempotency key, fresh jti so the
    // DO records the key without consuming the grace entry's jti (replay would
    // otherwise win on reconcile). Then stage-15 credit.
    const retry = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference,
        principal: { jti: uniqueJti() },
      }),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(retry);

    const retryCredit = await credit.creditUsage(
      {
        installationId,
        requestId: retry.requestId,
        requestReference,
        usage: { tokens: 5, cost: 0.05 },
        partial: false,
      },
      { DO: env.DO },
    );
    expect(retryCredit.ok).toBe(true);
    if (!retryCredit.ok) {
      return;
    }
    const requestsAfterRetry = retryCredit.periodCounters.requestsUsed;
    const tokensAfterRetry = retryCredit.periodCounters.tokensUsed;

    const reconcile = await credit.reconcileGraceUsage({ DO: env.DO, DB: env.DB });
    expect(reconcile.reconciled).toBe(0);
    expect(await peekPendingGrace(admission)).toHaveLength(0);

    const drops = credit.peekDroppedGraceJournal();
    expect(drops).toHaveLength(1);
    expect(drops[0]?.reason).toBe("settled_by_another_path_idempotent");
    expect(drops[0]?.requestReference).toBe(requestReference);

    // Stale grace usage must not settle the retry's requestId again.
    const probe = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(probe);
    const probeCredit = await credit.creditUsage(
      {
        installationId,
        requestId: probe.requestId,
        requestReference: uniqueRequestReference(),
        usage: { tokens: 1, cost: 0 },
        partial: false,
      },
      { DO: env.DO },
    );
    expect(probeCredit.ok).toBe(true);
    if (probeCredit.ok) {
      expect(probeCredit.periodCounters.tokensUsed).toBe(tokensAfterRetry + 1);
      expect(probeCredit.periodCounters.requestsUsed).toBe(requestsAfterRetry + 1);
    }
  });

  it("drops on replay when the grace jti was already consumed by a retry", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);
    const jti = uniqueJti();
    const requestReference = uniqueRequestReference();

    const graceResult = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        requestReference,
        principal: { jti },
      }),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(graceResult.ok).toBe(true);

    // Retry with the same jti (different idempotency key) after DO recovery.
    const retry = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader, {
        principal: { jti },
      }),
      { DB: env.DB, DO: env.DO },
      { now: FIXTURE_NOW_MS },
    );
    assertAdmitted(retry);

    const reconcile = await credit.reconcileGraceUsage({ DO: env.DO, DB: env.DB });
    expect(reconcile.reconciled).toBe(0);
    expect(await peekPendingGrace(admission)).toHaveLength(0);
    expect(credit.peekDroppedGraceJournal().map((d) => d.reason)).toEqual([
      "settled_by_another_path_replay",
    ]);
  });

  it("drops on unknown_request when the admitted id was already credited", async () => {
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
    expect(
      await admission.attachGraceUsage(
        env.DB,
        requestReference,
        { tokens: 10, cost: 0.01 },
        false,
      ),
    ).toBe(true);

    let fetchIndex = 0;
    const alreadySettledRequestId = crypto.randomUUID();
    const scriptedDo: DurableObjectNamespace = {
      idFromString: env.DO.idFromString.bind(env.DO),
      idFromName: env.DO.idFromName?.bind(env.DO),
      newUniqueId: env.DO.newUniqueId?.bind(env.DO),
      get: () => ({
        fetch: async () => {
          fetchIndex += 1;
          if (fetchIndex === 1) {
            return new Response(
              JSON.stringify({
                kind: "admission",
                outcome: "admitted",
                requestId: alreadySettledRequestId,
              }),
              { status: 200, headers: { "Content-Type": "application/json" } },
            );
          }
          return new Response(
            JSON.stringify({
              kind: "credit",
              ok: false,
              code: "unknown_request",
            }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          );
        },
      }),
    } as DurableObjectNamespace;

    const reconcile = await credit.reconcileGraceUsage({ DO: scriptedDo, DB: env.DB });
    expect(reconcile.reconciled).toBe(0);
    expect(await peekPendingGrace(admission)).toHaveLength(0);
    expect(credit.peekDroppedGraceJournal().map((d) => d.reason)).toEqual([
      "settled_by_another_path_unknown_request",
    ]);
    expect(fetchIndex).toBe(2);
  });

  it("drops after max reconcile attempts when the DO stays unavailable", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);

    const graceResult = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(graceResult.ok).toBe(true);

    for (let i = 0; i < credit.GRACE_RECONCILE_MAX_ATTEMPTS; i += 1) {
      const result = await credit.reconcileGraceUsage({ DO: brokenDo, DB: env.DB });
      expect(result.reconciled).toBe(0);
      expect(await peekPendingGrace(admission)).toHaveLength(1);
      expect(credit.peekDroppedGraceJournal()).toHaveLength(0);
    }

    const final = await credit.reconcileGraceUsage({ DO: brokenDo, DB: env.DB });
    expect(final.reconciled).toBe(0);
    expect(await peekPendingGrace(admission)).toHaveLength(0);
    expect(credit.peekDroppedGraceJournal().map((d) => d.reason)).toEqual([
      "max_attempts",
    ]);
  });

  it("drops expired grace entries without crediting", async () => {
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);

    const graceResult = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: brokenDo },
      { now: FIXTURE_NOW_MS },
    );
    expect(graceResult.ok).toBe(true);

    // First sighting stamps queuedAt; next pass past TTL drops.
    await credit.reconcileGraceUsage(
      { DO: brokenDo, DB: env.DB },
      { now: FIXTURE_NOW_MS },
    );
    expect(await peekPendingGrace(admission)).toHaveLength(1);

    const expired = await credit.reconcileGraceUsage(
      { DO: env.DO, DB: env.DB },
      { now: FIXTURE_NOW_MS + credit.GRACE_RECONCILE_TTL_MS + 1 },
    );
    expect(expired.reconciled).toBe(0);
    expect(await peekPendingGrace(admission)).toHaveLength(0);
    expect(credit.peekDroppedGraceJournal().map((d) => d.reason)).toEqual([
      "expired",
    ]);
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

  it("tallies grace-cap rejection as rate_limited, not quota_exhausted", async () => {
    const admission = await loadAdmissionModule();
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const brokenDo = createThrowingDoNamespace(env.DO);

    for (let index = 0; index < GRACE_ADMISSION_CAP; index += 1) {
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
      code: "rate_limited",
      retryAfter: 60,
    });

    await admission.flushRejectionCounters({ DB: env.DB });
    const matching = (await readPlatformCounterRows()).filter((row) => {
      const dimensions = parseDimensionSet(row.dimension_set);
      return (
        dimensions.error_code === "rate_limited" &&
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
    expect(await peekPendingGrace(admission)).toHaveLength(0);
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
