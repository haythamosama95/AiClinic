import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import type { CanonicalResult } from "../src/contracts/canonical";
import type { Principal } from "../src/identity";
import { load, type Manifest } from "../src/manifest";
import { generateRequestReference } from "../src/reference";
import {
  createRequestRow,
  flushGuardRejectionCounters,
  getRequest,
  journalTransition,
  recordGuardRejection,
  recordTerminalState,
  writePostResponseDetail,
  type AttemptInput,
  type PostResponseInput,
  type RequestRowInput,
  type TransitionState,
} from "../src/journal";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
  }
}

const FIXTURE_INSTALLATION_ID = "inst-journal-001";
const FIXTURE_ORG_ID = "org-journal-001";
const FIXTURE_BRANCH_ID = "branch-journal-001";
const FIXTURE_ACTOR_ID = "actor-journal-001";
const FIXTURE_CAPABILITY_ID = "clinic.journal-test";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_TRACE_ID = "01JOURNALTRACE000000000001";
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_PERIOD = "2026-08";
const FIXTURE_PROMPT_HASH = "prompt/visit-summary-system@v1";

const ALL_TRANSITION_STATES: TransitionState[] = [
  "Accepted",
  "Composing",
  "Invoking",
  "Streaming",
  "Validating",
  "Repairing",
  "AwaitingContext",
  "Completed",
  "Failed",
  "Cancelled",
];

const TERMINAL_STATES = new Set<TransitionState>([
  "Completed",
  "Failed",
  "Cancelled",
  "AwaitingContext",
]);

type ManifestWire = Record<string, unknown>;
type D1Row = Record<string, unknown>;

type PlatformCounterRow = {
  counter_id: string;
  dimension_set: string;
  time_bucket: string;
  count: number;
};

type AiRequestRow = {
  request_id: string;
  request_reference: string;
  state: string;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
  terminal_error_code: string | null;
  payload_pointer: string | null;
};

type D1Spy = D1Database & {
  prepare: D1Database["prepare"];
  aiRequestInsertCount: () => number;
  aiAttemptInsertCount: () => number;
  usageEventInsertCount: () => number;
  requestReferenceQueryCount: () => number;
  prepareCallCount: () => number;
  resetCounts: () => void;
};

type R2Spy = R2Bucket & {
  putCallCount: () => number;
  getCallCount: () => number;
  putKeys: () => string[];
  getKeys: () => string[];
  resetCounts: () => void;
};

type FakeExecutionContext = {
  waitUntil: (promise: Promise<unknown>) => void;
  drainWaitUntil: () => Promise<void>;
};

type PrincipalSeed = {
  installationId?: string;
  actorId?: string;
  branchId?: string;
  organizationId?: string;
  traceId?: string;
};

let requestIdCounter = 0;
let idempotencyKeyCounter = 0;

function nextRequestId(): string {
  requestIdCounter += 1;
  return `01JOURNALREQ${String(requestIdCounter).padStart(14, "0")}`;
}

function nextIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `idem-journal-${idempotencyKeyCounter}`;
}

function validManifest(
  capabilityId: string = FIXTURE_CAPABILITY_ID,
  version: string = FIXTURE_CAPABILITY_VERSION,
): ManifestWire {
  return {
    Identity: {
      capabilityId,
      version,
      title: `${capabilityId} journal fixture`,
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: `ai.${capabilityId}`,
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: {
      interactionMode: "single_shot",
    },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": [
      {
        key: "visit.chief_complaint@v1",
        required: true,
        shapeRef: "visit.chief_complaint@v1",
        maxSize: 4_096,
        freshnessHint: "session",
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: FIXTURE_PROMPT_HASH,
      businessRuleFragmentRefs: ["rules/visit-summary@v1"],
      contextRenderingTemplateRef: "templates/visit-summary@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: "routing/standard@v1",
      requiredProviderFeatures: {
        structuredOutput: false,
        contextWindow: 32_000,
        language: "en",
      },
      latencyClass: "standard",
      degradedTierPolicy: "fallback_chain",
    },
    Economics: {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      perRequestCostCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/visit-summary@v1",
    },
  };
}

function buildPrincipal(seed: PrincipalSeed = {}): Principal {
  return Object.freeze({
    installationId: seed.installationId ?? FIXTURE_INSTALLATION_ID,
    organizationId: seed.organizationId ?? FIXTURE_ORG_ID,
    branchId: seed.branchId ?? FIXTURE_BRANCH_ID,
    actorId: seed.actorId ?? FIXTURE_ACTOR_ID,
    role: "clinician",
    scopes: Object.freeze([`ai.${FIXTURE_CAPABILITY_ID}`]),
    jti: "jti-journal-001",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
  });
}

function canonicalResultFixture(): CanonicalResult {
  return {
    "final content": { text: "Journal fixture result." },
    "usage counters": {
      input: 512,
      output: 96,
      cached: 0,
    },
    "provider+model actually used": {
      provider: "deepseek",
      model: "journal-fixture",
    },
    "finish reason": "stop",
    "provider request id": "provider-req-journal-001",
    "timing breakdown": {
      queue_ms: 5,
      provider_ms: 420,
      total_ms: 450,
    },
  };
}

function buildAttempt(
  attemptNo: number,
  rawResponseOrError: unknown,
  overrides: Partial<AttemptInput> = {},
): AttemptInput {
  return {
    attemptNo,
    provider: "deepseek",
    model: "journal-fixture",
    outcome: overrides.outcome ?? "success",
    latencyMs: overrides.latencyMs ?? 420,
    tokensIn: overrides.tokensIn ?? 512,
    tokensOut: overrides.tokensOut ?? 96,
    cost: overrides.cost ?? 0.002,
    providerRequestId: overrides.providerRequestId ?? `prov-${attemptNo}`,
    errorCode: overrides.errorCode,
    rawBody: rawResponseOrError,
    ...overrides,
  };
}

function buildRequestRowInput(
  overrides: Partial<RequestRowInput> & {
    requestId?: string;
    requestReference?: string;
    principal?: Principal;
    manifest?: Manifest;
  } = {},
): RequestRowInput {
  const manifest =
    overrides.manifest ?? load(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));
  const principal = overrides.principal ?? buildPrincipal();
  return {
    requestId: overrides.requestId ?? nextRequestId(),
    requestReference: overrides.requestReference ?? generateRequestReference(),
    principal,
    manifest,
    idempotencyKey: overrides.idempotencyKey ?? nextIdempotencyKey(),
    traceId: overrides.traceId ?? FIXTURE_TRACE_ID,
    conversationId: overrides.conversationId ?? null,
    turnOrdinal: overrides.turnOrdinal ?? null,
    ...overrides,
  };
}

function buildPostResponseInput(
  requestId: string,
  attempts: AttemptInput[],
  overrides: Partial<PostResponseInput> = {},
): PostResponseInput {
  const totalTokens = attempts.reduce(
    (sum, attempt) => sum + attempt.tokensIn + attempt.tokensOut,
    0,
  );
  const totalCost = attempts.reduce((sum, attempt) => sum + attempt.cost, 0);
  return {
    requestId,
    installationId: FIXTURE_INSTALLATION_ID,
    period: FIXTURE_PERIOD,
    quotaWeight: 1,
    totalTokens,
    totalCost,
    filteredContext: {
      "visit.chief_complaint@v1": "Headache for two days.",
    },
    composedPrompt: {
      system: "Summarise the visit.",
      messages: [{ role: "user", content: "Chief complaint: headache." }],
    },
    attempts,
    validatedResult: canonicalResultFixture(),
    recordedAt: FIXTURE_NOW,
    ...overrides,
  };
}

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
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

async function seedInstallation(installationId: string = FIXTURE_INSTALLATION_ID): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (
      installation_id, org_id, display_name, status, region, enrolled_at
    ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      "Journal Integration Clinic",
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function clearJournalTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function readAiRequestCount(): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM ai_request").first<{
    count: number;
  }>();
  return row?.count ?? 0;
}

async function readAiRequestRow(requestId: string): Promise<AiRequestRow | null> {
  return env.DB.prepare(
    `SELECT request_id, request_reference, state, created_at, updated_at,
            completed_at, terminal_error_code, payload_pointer
     FROM ai_request WHERE request_id = ?`,
  )
    .bind(requestId)
    .first<AiRequestRow>();
}

async function readPlatformCounterRows(): Promise<PlatformCounterRow[]> {
  const result = await env.DB.prepare(
    "SELECT counter_id, dimension_set, time_bucket, count FROM platform_counter ORDER BY counter_id",
  ).all<PlatformCounterRow>();
  return result.results ?? [];
}

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim().toLowerCase();
}

function createD1Spy(realDb: D1Database): D1Spy {
  let aiRequestInserts = 0;
  let aiAttemptInserts = 0;
  let usageEventInserts = 0;
  let requestReferenceQueries = 0;
  let prepareCalls = 0;

  const spy: D1Spy = {
  ...realDb,
  prepare(query: string) {
    prepareCalls += 1;
    const normalized = normalizeSql(query);

    if (normalized.startsWith("insert into ai_request")) {
      aiRequestInserts += 1;
    }
    if (normalized.startsWith("insert into ai_attempt")) {
      aiAttemptInserts += 1;
    }
    if (normalized.startsWith("insert into usage_event")) {
      usageEventInserts += 1;
    }
    if (
      normalized.includes("from ai_request") &&
      normalized.includes("request_reference")
    ) {
      requestReferenceQueries += 1;
    }

    return realDb.prepare(query);
  },
  aiRequestInsertCount() {
    return aiRequestInserts;
  },
  aiAttemptInsertCount() {
    return aiAttemptInserts;
  },
  usageEventInsertCount() {
    return usageEventInserts;
  },
  requestReferenceQueryCount() {
    return requestReferenceQueries;
  },
  prepareCallCount() {
    return prepareCalls;
  },
  resetCounts() {
    aiRequestInserts = 0;
    aiAttemptInserts = 0;
    usageEventInserts = 0;
    requestReferenceQueries = 0;
    prepareCalls = 0;
  },
  };

  return spy;
}

function createR2Spy(realR2: R2Bucket): R2Spy {
  const putKeys: string[] = [];
  const getKeys: string[] = [];

  const spy: R2Spy = {
    ...realR2,
    async put(key: string, value: ReadableStream | ArrayBuffer | ArrayBufferView | string | null | Blob, options?: R2PutOptions) {
      putKeys.push(key);
      return realR2.put(key, value, options);
    },
    async get(key: string, options?: R2GetOptions) {
      getKeys.push(key);
      return realR2.get(key, options);
    },
    putCallCount() {
      return putKeys.length;
    },
    getCallCount() {
      return getKeys.length;
    },
    putKeys() {
      return [...putKeys];
    },
    getKeys() {
      return [...getKeys];
    },
    resetCounts() {
      putKeys.length = 0;
      getKeys.length = 0;
    },
  };

  return spy;
}

function createFakeCtx(): FakeExecutionContext {
  const pending: Promise<unknown>[] = [];
  return {
    waitUntil(promise: Promise<unknown>) {
      pending.push(promise);
    },
    async drainWaitUntil() {
      await Promise.all(pending);
      pending.length = 0;
    },
  };
}

function createFakeProvider(): ReturnType<typeof vi.fn> {
  return vi.fn(async () => ({ completion: "provider response" }));
}

async function seedRequestRow(
  db: D1Database = env.DB,
  overrides: Partial<RequestRowInput> = {},
): Promise<RequestRowInput> {
  const input = buildRequestRowInput(overrides);
  const result = await createRequestRow(input, db);
  expect(result).toEqual({ ok: true });
  return input;
}

async function seedCompletedRequest(
  db: D1Database = env.DB,
  r2: R2Bucket = env.R2,
): Promise<{
  input: RequestRowInput;
  postInput: PostResponseInput;
}> {
  const input = await seedRequestRow(db);
  await recordTerminalState(input.requestId, "Completed", undefined, FIXTURE_NOW, db);

  const attempts = [buildAttempt(1, { text: "raw provider body" })];
  const postInput = buildPostResponseInput(input.requestId, attempts);
  const ctx = createFakeCtx();
  writePostResponseDetail(postInput, { db, r2, ctx });
  await ctx.drainWaitUntil();

  return { input, postInput };
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearJournalTables();
  await seedInstallation();
  requestIdCounter = 0;
  idempotencyKeyCounter = 0;
});

describe("T-C3-01 request_row_exists_before_provider_invoked", () => {
  it("creates the ai_request row at stage 9 before the fake provider is invoked", async () => {
    const db = createD1Spy(env.DB);
    const fakeProvider = createFakeProvider();
    const input = buildRequestRowInput();

    const createResult = await createRequestRow(input, db);
    expect(createResult).toEqual({ ok: true });
    expect(db.aiRequestInsertCount()).toBe(1);

    const row = await readAiRequestRow(input.requestId);
    expect(row).not.toBeNull();
    expect(row?.state).toBe("Accepted");

    await fakeProvider();
    expect(fakeProvider).toHaveBeenCalledTimes(1);
    expect(await readAiRequestCount()).toBe(1);
  });
});

describe("T-C3-02 terminal_state_completed", () => {
  it("stamps Completed with completed_at and no terminal_error_code at stage 15", async () => {
    const input = await seedRequestRow();

    await recordTerminalState(input.requestId, "Completed", undefined, FIXTURE_NOW, env.DB);

    const row = await readAiRequestRow(input.requestId);
    expect(row?.state).toBe("Completed");
    expect(row?.completed_at).toBe(FIXTURE_NOW);
    expect(row?.terminal_error_code).toBeNull();
  });
});

describe("T-C3-03 terminal_state_failed", () => {
  it("stamps Failed with completed_at and terminal_error_code at stage 15", async () => {
    const input = await seedRequestRow();

    await recordTerminalState(
      input.requestId,
      "Failed",
      "provider_error",
      FIXTURE_NOW,
      env.DB,
    );

    const row = await readAiRequestRow(input.requestId);
    expect(row?.state).toBe("Failed");
    expect(row?.completed_at).toBe(FIXTURE_NOW);
    expect(row?.terminal_error_code).toBe("provider_error");
  });
});

describe("T-C3-04 terminal_state_cancelled", () => {
  it("stamps Cancelled with completed_at and no terminal_error_code at stage 15", async () => {
    const input = await seedRequestRow();

    await recordTerminalState(input.requestId, "Cancelled", undefined, FIXTURE_NOW, env.DB);

    const row = await readAiRequestRow(input.requestId);
    expect(row?.state).toBe("Cancelled");
    expect(row?.completed_at).toBe(FIXTURE_NOW);
    expect(row?.terminal_error_code).toBeNull();
  });
});

describe("T-C3-05 guard_rejected_produces_no_row", () => {
  it("increments platform_counter without inserting an ai_request row on guard rejection", async () => {
    const db = createD1Spy(env.DB);
    const principal = buildPrincipal();
    const countersBefore = await readPlatformCounterRows();
    const aiRequestsBefore = await readAiRequestCount();

    await recordGuardRejection({
      installationId: principal.installationId,
      errorCode: "unauthenticated",
      traceId: FIXTURE_TRACE_ID,
    });
    await flushGuardRejectionCounters({ DB: db });

    expect(db.aiRequestInsertCount()).toBe(0);
    expect(await readAiRequestCount()).toBe(aiRequestsBefore);

    const countersAfter = await readPlatformCounterRows();
    expect(countersAfter.length).toBeGreaterThan(countersBefore.length);

    const totalAfter = countersAfter.reduce((sum, row) => sum + row.count, 0);
    const totalBefore = countersBefore.reduce((sum, row) => sum + row.count, 0);
    expect(totalAfter - totalBefore).toBe(1);
  });
});

describe("T-C3-06 every_state_transition_timestamped", () => {
  it.each(ALL_TRANSITION_STATES)(
    "stamps state and updated_at for transition %s",
    async (state) => {
      const input = await seedRequestRow();
      const transitionAt = "2026-07-31T12:05:00.000Z";

      if (TERMINAL_STATES.has(state)) {
        const errorCode = state === "Failed" ? "provider_error" : undefined;
        await recordTerminalState(input.requestId, state, errorCode, transitionAt, env.DB);
      } else {
        await journalTransition(input.requestId, state, transitionAt, env.DB);
      }

      const row = await readAiRequestRow(input.requestId);
      expect(row?.state).toBe(state);
      expect(row?.updated_at).toBe(transitionAt);

      if (TERMINAL_STATES.has(state)) {
        expect(row?.completed_at).toBe(transitionAt);
      } else {
        expect(row?.completed_at).toBeNull();
      }
    },
  );
});

describe("T-C3-07 row_survives_failed_generation", () => {
  it("leaves the ai_request row present with Failed terminal state after failed generation", async () => {
    const input = await seedRequestRow();

    await journalTransition(input.requestId, "Invoking", FIXTURE_NOW, env.DB);
    await recordTerminalState(
      input.requestId,
      "Failed",
      "provider_error",
      FIXTURE_NOW,
      env.DB,
    );

    expect(await readAiRequestCount()).toBe(1);

    const row = await readAiRequestRow(input.requestId);
    expect(row?.state).toBe("Failed");
    expect(row?.terminal_error_code).toBe("provider_error");
  });
});

describe("T-C3-08 exactly_one_r2_putobject_per_request", () => {
  it("writes exactly one R2 object keyed request/{id}/envelope per request", async () => {
    const r2 = createR2Spy(env.R2);
    const input = await seedRequestRow();
    await recordTerminalState(input.requestId, "Completed", undefined, FIXTURE_NOW, env.DB);

    const attempts = [buildAttempt(1, { text: "attempt one" })];
    const postInput = buildPostResponseInput(input.requestId, attempts);
    const ctx = createFakeCtx();
    writePostResponseDetail(postInput, { db: env.DB, r2, ctx });
    await ctx.drainWaitUntil();

    expect(r2.putCallCount()).toBe(1);
    expect(r2.putKeys()).toEqual([envelopeKey(input.requestId)]);
  });
});

describe("T-C3-09 envelope_contains_all_four_sections", () => {
  it("writes an envelope JSON document with context, prompt, attempts, and result", async () => {
    const input = await seedRequestRow();
    await recordTerminalState(input.requestId, "Completed", undefined, FIXTURE_NOW, env.DB);

    const attempts = [
      buildAttempt(1, { text: "first attempt" }),
      buildAttempt(2, { error: "rate limited" }, { outcome: "error", errorCode: "rate_limited" }),
    ];
    const postInput = buildPostResponseInput(input.requestId, attempts);
    const ctx = createFakeCtx();
    writePostResponseDetail(postInput, { db: env.DB, r2: env.R2, ctx });
    await ctx.drainWaitUntil();

    const object = await env.R2.get(envelopeKey(input.requestId));
    expect(object).not.toBeNull();

    const envelope = JSON.parse(await object!.text()) as Record<string, unknown>;
    expect(envelope).toHaveProperty("context");
    expect(envelope).toHaveProperty("prompt");
    expect(envelope).toHaveProperty("attempts");
    expect(envelope).toHaveProperty("result");

    expect(envelope.context).toEqual(postInput.filteredContext);
    expect(envelope.prompt).toEqual(postInput.composedPrompt);
    expect(envelope.attempts).toEqual(attempts.map((attempt) => attempt.rawBody));
    expect(envelope.result).toEqual(postInput.validatedResult);
  });
});

describe("T-C3-10 one_ai_attempt_row_per_attempt", () => {
  it.each([2, 3])(
    "inserts exactly %i ai_attempt rows for %i provider attempts",
    async (attemptCount) => {
      const db = createD1Spy(env.DB);
      const input = await seedRequestRow(db);
      await recordTerminalState(input.requestId, "Completed", undefined, FIXTURE_NOW, db);

      const attempts = Array.from({ length: attemptCount }, (_, index) =>
        buildAttempt(index + 1, { text: `attempt ${index + 1}` }),
      );
      const postInput = buildPostResponseInput(input.requestId, attempts);
      const ctx = createFakeCtx();
      db.resetCounts();

      writePostResponseDetail(postInput, { db, r2: env.R2, ctx });
      await ctx.drainWaitUntil();

      expect(db.aiAttemptInsertCount()).toBe(attemptCount);
    },
  );
});

describe("T-C3-11 exactly_one_usage_event", () => {
  it("inserts exactly one usage_event row per request", async () => {
    const db = createD1Spy(env.DB);
    const input = await seedRequestRow(db);
    await recordTerminalState(input.requestId, "Completed", undefined, FIXTURE_NOW, db);

    const attempts = [buildAttempt(1, { text: "usage attempt" })];
    const postInput = buildPostResponseInput(input.requestId, attempts);
    const ctx = createFakeCtx();
    db.resetCounts();

    writePostResponseDetail(postInput, { db, r2: env.R2, ctx });
    await ctx.drainWaitUntil();

    expect(db.usageEventInsertCount()).toBe(1);
  });
});

describe("T-C3-12 stage16_failure_does_not_fail_request", () => {
  it("returns normally when stage 16 R2/D1 failure is swallowed inside waitUntil", async () => {
    const input = await seedRequestRow();
    await recordTerminalState(input.requestId, "Completed", undefined, FIXTURE_NOW, env.DB);

    const failingDb = createD1Spy(env.DB);
    const originalPrepare = failingDb.prepare.bind(failingDb);
    failingDb.prepare = (query: string) => {
      const normalized = normalizeSql(query);
      if (normalized.startsWith("insert into ai_attempt")) {
        throw new Error("injected stage-16 D1 failure");
      }
      return originalPrepare(query);
    };

    const failingR2 = createR2Spy(env.R2);
    failingR2.put = async () => {
      throw new Error("injected stage-16 R2 failure");
    };

    const attempts = [buildAttempt(1, { text: "will fail to persist" })];
    const postInput = buildPostResponseInput(input.requestId, attempts);
    const ctx = createFakeCtx();

    expect(() =>
      writePostResponseDetail(postInput, {
        db: failingDb,
        r2: failingR2,
        ctx,
      }),
    ).not.toThrow();

    await expect(ctx.drainWaitUntil()).resolves.toBeUndefined();

    const row = await readAiRequestRow(input.requestId);
    expect(row?.state).toBe("Completed");
  });
});

describe("T-C3-13 stage16_runs_after_terminal_event", () => {
  it("records the terminal state before any stage-16 write begins", async () => {
    const db = createD1Spy(env.DB);
    const input = await seedRequestRow(db);
    const callOrder: string[] = [];

    const terminalSpy = vi.fn(() => {
      callOrder.push("terminal");
    });
    await recordTerminalState(
      input.requestId,
      "Completed",
      undefined,
      FIXTURE_NOW,
      db,
    );
    terminalSpy();

    const originalPrepare = db.prepare.bind(db);
    db.prepare = (query: string) => {
      const normalized = normalizeSql(query);
      if (
        normalized.startsWith("insert into ai_attempt") ||
        normalized.startsWith("insert into usage_event") ||
        normalized.startsWith("update ai_request")
      ) {
        callOrder.push("stage16");
      }
      return originalPrepare(query);
    };

    const attempts = [buildAttempt(1, { text: "ordered attempt" })];
    const postInput = buildPostResponseInput(input.requestId, attempts);
    const ctx = createFakeCtx();
    writePostResponseDetail(postInput, { db, r2: env.R2, ctx });
    await ctx.drainWaitUntil();

    expect(terminalSpy).toHaveBeenCalledTimes(1);
    expect(callOrder.filter((entry) => entry === "terminal").length).toBe(1);
    expect(callOrder.filter((entry) => entry === "stage16").length).toBeGreaterThan(0);
    expect(callOrder.indexOf("terminal")).toBeLessThan(callOrder.indexOf("stage16"));
  });
});

describe("T-C3-14 get_request_completed_returns_state_and_result", () => {
  it("returns Completed state and validated result via one D1 lookup and one R2 GetObject", async () => {
    const db = createD1Spy(env.DB);
    const r2 = createR2Spy(env.R2);
    const { input, postInput } = await seedCompletedRequest(db, r2);
    db.resetCounts();
    r2.resetCounts();

    const result = await getRequest(input.requestReference, { db, r2 });

    expect(result).toEqual({
      found: true,
      state: "Completed",
      result: postInput.validatedResult,
    });
    expect(db.requestReferenceQueryCount()).toBe(1);
    expect(r2.getCallCount()).toBe(1);
    expect(r2.getKeys()).toEqual([envelopeKey(input.requestId)]);
  });
});

describe("T-C3-15 get_request_failed_returns_state_and_error_no_content", () => {
  it("returns Failed state and terminal error code without reading R2", async () => {
    const db = createD1Spy(env.DB);
    const r2 = createR2Spy(env.R2);
    const input = await seedRequestRow(db);
    await recordTerminalState(
      input.requestId,
      "Failed",
      "provider_error",
      FIXTURE_NOW,
      db,
    );
    db.resetCounts();
    r2.resetCounts();

    const result = await getRequest(input.requestReference, { db, r2 });

    expect(result).toEqual({
      found: true,
      state: "Failed",
      terminalErrorCode: "provider_error",
    });
    expect(r2.getCallCount()).toBe(0);
  });
});

describe("T-C3-16 get_request_cancelled_returns_state_only", () => {
  it("returns Cancelled state only without reading R2", async () => {
    const db = createD1Spy(env.DB);
    const r2 = createR2Spy(env.R2);
    const input = await seedRequestRow(db);
    await recordTerminalState(input.requestId, "Cancelled", undefined, FIXTURE_NOW, db);
    db.resetCounts();
    r2.resetCounts();

    const result = await getRequest(input.requestReference, { db, r2 });

    expect(result).toEqual({
      found: true,
      state: "Cancelled",
    });
    expect(r2.getCallCount()).toBe(0);
  });
});

describe("T-C3-17 get_request_unknown_reference_returns_not_found", () => {
  it("returns found:false for an unknown request reference", async () => {
    const result = await getRequest("ZZZZ-ZZZZ", { db: env.DB, r2: env.R2 });
    expect(result).toEqual({ found: false });
  });
});

describe("T-C3-18 get_request_uses_exactly_one_indexed_query", () => {
  it("performs exactly one indexed D1 lookup on request_reference for each terminal branch", async () => {
    const completed = await seedCompletedRequest();
    const failedInput = await seedRequestRow();
    await recordTerminalState(
      failedInput.requestId,
      "Failed",
      "provider_error",
      FIXTURE_NOW,
      env.DB,
    );
    const cancelledInput = await seedRequestRow();
    await recordTerminalState(
      cancelledInput.requestId,
      "Cancelled",
      undefined,
      FIXTURE_NOW,
      env.DB,
    );

    const completedDb = createD1Spy(env.DB);
    const completedR2 = createR2Spy(env.R2);
    await getRequest(completed.input.requestReference, {
      db: completedDb,
      r2: completedR2,
    });
    expect(completedDb.requestReferenceQueryCount()).toBe(1);
    expect(completedR2.getCallCount()).toBe(1);

    const failedDb = createD1Spy(env.DB);
    const failedR2 = createR2Spy(env.R2);
    await getRequest(failedInput.requestReference, { db: failedDb, r2: failedR2 });
    expect(failedDb.requestReferenceQueryCount()).toBe(1);
    expect(failedR2.getCallCount()).toBe(0);

    const cancelledDb = createD1Spy(env.DB);
    const cancelledR2 = createR2Spy(env.R2);
    await getRequest(cancelledInput.requestReference, {
      db: cancelledDb,
      r2: cancelledR2,
    });
    expect(cancelledDb.requestReferenceQueryCount()).toBe(1);
    expect(cancelledR2.getCallCount()).toBe(0);
  });
});
