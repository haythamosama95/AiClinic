import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  ConfigCache,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import type { CanonicalResult } from "../src/contracts/canonical";
import type { Principal } from "../src/identity";
import {
  createRequestRow,
  listConversationLegs,
  recordTerminalState,
  writePostResponseDetail,
  type AttemptInput,
  type PostResponseInput,
  type TransitionState,
} from "../src/journal";
import { load, type Manifest } from "../src/manifest";
import { FakeAdapter } from "../src/provider/fake";
import {
  createBindingSpies,
  type BindingSpies,
  type DoSpy,
} from "./load/binding-spies";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    DO: DurableObjectNamespace;
  }
}

const FIXTURE_ORG_ID = "org-h3-journal-001";
const FIXTURE_NOW_MS = Date.parse("2026-07-31T12:00:00.000Z");
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_CAPABILITY_ID = "clinic.chat_assistant";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_TRACE_ID = "01H3JOURNALTRACE00000001";
const FIXTURE_PERIOD = "2026-08";
const FIXTURE_PROMPT_HASH = "prompt/chat-assistant-system@v1";

type D1Row = Record<string, unknown>;
type ManifestWire = Record<string, unknown>;

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

type AdmissionSuccess = {
  ok: true;
  outcome: "admitted";
  requestId: string;
};

type AdmissionResult = AdmissionSuccess | { ok: false; code: string };

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

type AdmissionModule = {
  runAdmission: (
    input: AdmissionInput,
    bindings: AdmissionBindings,
    ctx?: AdmissionContext,
  ) => Promise<AdmissionResult>;
};

type CreditModule = {
  creditUsage: (input: CreditInput, bindings: CreditBindings) => Promise<unknown>;
};

type FakeExecutionContext = {
  waitUntil: (promise: Promise<unknown>) => void;
  drainWaitUntil: () => Promise<void>;
};

type ConversationalLegInput = {
  installationId: string;
  cache: ConfigCache;
  reader: D1Reader;
  spies: BindingSpies;
  admission: AdmissionModule;
  credit: CreditModule;
  manifest: Manifest;
  conversationId: string;
  turnOrdinal: number;
  terminalState?: TransitionState;
  usageTokens?: number;
};

type ConversationalLegOutcome = {
  requestId: string;
  requestReference: string;
  idempotencyKey: string;
};

let jtiCounter = 0;
let idempotencyKeyCounter = 0;
let requestReferenceCounter = 0;

async function loadAdmissionModule(): Promise<AdmissionModule> {
  return import(/* @vite-ignore */ "../src/admission") as Promise<AdmissionModule>;
}

async function loadCreditModule(): Promise<CreditModule> {
  return import(/* @vite-ignore */ "../src/credit") as Promise<CreditModule>;
}

function uniqueJti(): string {
  jtiCounter += 1;
  return `h3000000-0000-4000-8000-${String(jtiCounter).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `01H3JOURNAL${String(idempotencyKeyCounter).padStart(14, "0")}`;
}

function uniqueRequestReference(): string {
  requestReferenceCounter += 1;
  return `AI-H3-${String(requestReferenceCounter).padStart(6, "0")}`;
}

function conversationalManifest(
  interactionMode: "conversational" | "single_shot" = "conversational",
): Manifest {
  const wire: ManifestWire = {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      version: FIXTURE_CAPABILITY_VERSION,
      title: "H3 chat assistant",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.chat_assistant",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction:
      interactionMode === "conversational"
        ? {
            interactionMode: "conversational",
            maxHistoryTurns: 10,
            maxContextRoundsPerTurn: 3,
            transcriptSizeLimit: 50_000,
          }
        : { interactionMode: "single_shot" },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: interactionMode === "conversational" ? "transcript" : null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements":
      interactionMode === "conversational"
        ? { permittedKeySet: ["visit.chief_complaint@v1"] }
        : [
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
      businessRuleFragmentRefs: ["rules/chat@v1"],
      contextRenderingTemplateRef: "templates/chat@v1",
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
      evalSuiteRef: "evals/chat@v1",
    },
  };
  return load(wire);
}

function makePrincipal(installationId: string): Principal {
  return {
    installationId,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-h3-001",
    actorId: "actor-h3-001",
    role: "clinician",
    scopes: ["ai.chat_assistant"],
    jti: uniqueJti(),
    iat: FIXTURE_NOW_MS - 30_000,
    exp: FIXTURE_NOW_MS + 300_000,
    ver: "1",
  };
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

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_attempt"),
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
      "H3 Journal Clinic",
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(installationId: string): Promise<void> {
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
      10_000,
      10_000_000,
      1_000,
      JSON.stringify(["ai.chat_assistant"]),
      0.8,
      "active",
    )
    .run();
}

async function prepareInstallation(
  installationId: string,
): Promise<{ cache: ConfigCache; reader: D1Reader }> {
  await seedInstallation(installationId);
  await seedEntitlement(installationId);
  const cache = new ConfigCache();
  const reader = makePlatformD1Reader(env.DB);
  await loadConfig(cache, reader, "entitlements", installationId);
  return { cache, reader };
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

function canonicalResult(): CanonicalResult {
  return {
    finalContent: { type: "text", text: "H3 fixture answer." },
    usage: { input: 10, output: 20, cached: 0 },
    providerModel: { provider: "fake", model: "fake-v1" },
    finishReason: "stop",
    providerRequestId: "fake-h3-req",
    timing: { queue_ms: 1, provider_ms: 5, total_ms: 6 },
  };
}

function buildAttempt(attemptNo: number): AttemptInput {
  return {
    attemptNo,
    provider: "fake",
    model: "fake-v1",
    outcome: "success",
    latencyMs: 5,
    tokensIn: 10,
    tokensOut: 20,
    cost: 0.001,
    providerRequestId: `fake-h3-${attemptNo}`,
    rawBody: { completion: "H3 fixture answer." },
  };
}

function buildPostResponseInput(
  requestId: string,
  installationId: string,
  totalTokens = 30,
): PostResponseInput {
  const attempts = [buildAttempt(1)];
  return {
    requestId,
    installationId,
    period: FIXTURE_PERIOD,
    quotaWeight: 1,
    totalTokens,
    totalCost: 0.001,
    filteredContext: { "visit.chief_complaint@v1": "Headache." },
    composedPrompt: { system: "Chat.", messages: [] },
    attempts,
    validatedResult: canonicalResult(),
    recordedAt: FIXTURE_NOW,
  };
}

function assertAdmitted(
  result: AdmissionResult,
): asserts result is AdmissionSuccess {
  expect(result.ok).toBe(true);
  if (!result.ok) {
    return;
  }
  expect(result.outcome).toBe("admitted");
}

async function runConversationalLeg(
  input: ConversationalLegInput,
): Promise<ConversationalLegOutcome> {
  const {
    installationId,
    cache,
    reader,
    spies,
    admission,
    credit,
    manifest,
    conversationId,
    turnOrdinal,
    terminalState = "Completed",
    usageTokens = 30,
  } = input;

  const principal = makePrincipal(installationId);
  const idempotencyKey = uniqueIdempotencyKey();
  const requestReference = uniqueRequestReference();

  const admissionResult = await admission.runAdmission(
    { principal, idempotencyKey, requestReference, cache, reader },
    { DB: spies.db, DO: spies.do },
    { now: FIXTURE_NOW_MS },
  );
  assertAdmitted(admissionResult);

  const createResult = await createRequestRow(
    {
      requestId: admissionResult.requestId,
      requestReference,
      principal,
      manifest,
      idempotencyKey,
      traceId: FIXTURE_TRACE_ID,
      conversationId,
      turnOrdinal,
    },
    spies.db,
  );
  expect(createResult.ok).toBe(true);

  const adapter = new FakeAdapter(["success"]);
  const invokeResult = adapter.invoke({
    parts: [{ role: "user", content: "Hello." }],
    formatDirective: { type: "text" },
    samplingConstraints: { temperature: 0.2 },
    maxOutputTokens: 256,
    stopConditions: [],
    toolDeclarations: [],
    stream: false,
    deadline: 30_000,
    correlationIds: {
      request_reference: requestReference,
      trace_id: FIXTURE_TRACE_ID,
    },
  });
  expect(invokeResult.kind).toBe("success");

  await recordTerminalState(
    admissionResult.requestId,
    terminalState,
    undefined,
    FIXTURE_NOW,
    spies.db,
  );

  const ctx = createFakeCtx();
  writePostResponseDetail(
    buildPostResponseInput(admissionResult.requestId, installationId, usageTokens),
    { db: spies.db, r2: spies.r2, ctx },
  );
  await ctx.drainWaitUntil();

  await credit.creditUsage(
    {
      installationId,
      requestId: admissionResult.requestId,
      requestReference,
      usage: { tokens: usageTokens, cost: 0.001 },
      partial: false,
    },
    { DO: spies.do },
  );

  return {
    requestId: admissionResult.requestId,
    requestReference,
    idempotencyKey,
  };
}

async function readAiRequestRow(requestId: string): Promise<D1Row | null> {
  return env.DB.prepare(
    `SELECT request_id, conversation_id, turn_ordinal, state
     FROM ai_request WHERE request_id = ?`,
  )
    .bind(requestId)
    .first<D1Row>();
}

async function readUsageEventCount(): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM usage_event").first<{
    count: number;
  }>();
  return row?.count ?? 0;
}

async function listSchemaTables(): Promise<string[]> {
  const result = await env.DB.prepare(
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
  ).all<{ name: string }>();
  return (result.results ?? []).map((row) => row.name);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;
  await clearTables();
});

describe("conversation_id_and_turn_ordinal_written_per_leg", () => {
  it("writes client-supplied conversation_id and turn_ordinal on each conversational leg", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest();
    const conversationId = "conv-h3-001";

    const leg1 = await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 1,
    });
    const leg2 = await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 2,
    });

    const row1 = await readAiRequestRow(leg1.requestId);
    const row2 = await readAiRequestRow(leg2.requestId);

    expect(row1?.conversation_id).toBe(conversationId);
    expect(row1?.turn_ordinal).toBe(1);
    expect(row2?.conversation_id).toBe(conversationId);
    expect(row2?.turn_ordinal).toBe(2);
  });
});

describe("one_indexed_query_returns_whole_conversation_ordered", () => {
  it("returns all legs ordered by turn_ordinal via listConversationLegs", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest();
    const conversationId = "conv-h3-ordered";

    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 3,
    });
    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 1,
    });
    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 2,
    });

    const legs = await listConversationLegs(conversationId, env.DB);
    expect(legs.map((leg) => leg.turn_ordinal)).toEqual([1, 2, 3]);
    expect(legs.every((leg) => leg.conversation_id === conversationId)).toBe(true);
  });
});

describe("each_leg_admitted_and_credited_independently", () => {
  it("produces N admissions and N usage credits for N legs", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest();
    const conversationId = "conv-h3-admit";

    spies.do.resetCounts();

    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 1,
    });
    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 2,
    });
    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 3,
    });

    const requestCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM ai_request WHERE conversation_id = ?",
    )
      .bind(conversationId)
      .first<{ count: number }>();

    expect(requestCount?.count).toBe(3);
    expect(await readUsageEventCount()).toBe(3);
    expect(spies.do.fetchCount()).toBeGreaterThanOrEqual(3);
  });
});

describe("context_requested_leg_credited_with_actual_usage", () => {
  it("credits a leg terminating as AwaitingContext with actual usage", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest();

    const outcome = await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId: "conv-h3-ctx",
      turnOrdinal: 1,
      terminalState: "AwaitingContext",
      usageTokens: 42,
    });

    const row = await readAiRequestRow(outcome.requestId);
    expect(row?.state).toBe("AwaitingContext");

    const usage = await env.DB.prepare(
      "SELECT tokens FROM usage_event WHERE request_id = ?",
    )
      .bind(outcome.requestId)
      .first<{ tokens: number }>();
    expect(usage?.tokens).toBe(42);
  });
});

describe("no_conversation_table_and_no_per_request_state_object", () => {
  it("has no conversation entity table and only ordinary ai_request rows", async () => {
    const tables = await listSchemaTables();
    expect(tables.some((name) => name === "conversation")).toBe(false);

    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest();

    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId: "conv-h3-no-entity",
      turnOrdinal: 1,
    });

    const rowCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM ai_request",
    ).first<{ count: number }>();
    expect(rowCount?.count).toBe(1);
  });
});

describe("platform_held_no_state_between_legs", () => {
  it("holds no conversation state between terminal leg 1 and leg 2 submit", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest();
    const conversationId = "conv-h3-no-state";

    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 1,
    });

    const betweenLegs = await listConversationLegs(conversationId, env.DB);
    expect(betweenLegs).toHaveLength(1);
    expect(betweenLegs[0]?.state).toBe("Completed");

    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId,
      turnOrdinal: 2,
    });

    const afterLeg2 = await listConversationLegs(conversationId, env.DB);
    expect(afterLeg2).toHaveLength(2);
    expect(afterLeg2[1]?.turn_ordinal).toBe(2);
  });
});

describe("no_second_r2_object_and_no_second_quota_do_round_trip_from_h3", () => {
  it("writes one R2 object and one DO fetch per leg", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest();

    spies.r2.resetCounts();
    spies.do.resetCounts();

    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId: "conv-h3-io",
      turnOrdinal: 1,
    });

    expect(spies.r2.putCallCount()).toBe(1);
    expect(spies.do.fetchCount()).toBeGreaterThanOrEqual(1);
    const doFetchesAfterLeg1 = spies.do.fetchCount();

    await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId: "conv-h3-io",
      turnOrdinal: 2,
    });

    expect(spies.r2.putCallCount()).toBe(2);
    expect(spies.do.fetchCount() - doFetchesAfterLeg1).toBeGreaterThanOrEqual(1);
  });
});

describe("single_shot_unaffected_by_h3", () => {
  it("writes null conversation_id and turn_ordinal for single_shot rows", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const spies = createBindingSpies(env);
    const admission = await loadAdmissionModule();
    const credit = await loadCreditModule();
    const manifest = conversationalManifest("single_shot");

    const outcome = await runConversationalLeg({
      installationId,
      cache,
      reader,
      spies,
      admission,
      credit,
      manifest,
      conversationId: "should-not-persist",
      turnOrdinal: 99,
    });

    const row = await readAiRequestRow(outcome.requestId);
    expect(row?.conversation_id).toBeNull();
    expect(row?.turn_ordinal).toBeNull();
  });
});
