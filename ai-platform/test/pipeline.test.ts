/**
 * §5.1 / final-review — pipeline guard failure-path coverage (stages 1–10).
 * Workers-pool: real D1 + Quota DO; assert per-stage codes and later sinks untouched.
 */

import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import conversationIndexSql from "../migrations/20260805180000_h3_conversation_index.sql?raw";
import planCatalogueSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "../src/capability";
import {
  ConfigCache,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import type { CanonicalRequest } from "../src/contracts/canonical";
import type { Principal, TokenVerifier } from "../src/identity";
import { INGRESS_BODY_SIZE_LIMIT } from "../src/adapter";
import { load, type Manifest } from "../src/manifest";
import { creditUsage } from "../src/credit";
import {
  runGuard,
  type ComposeRequestFn,
  type GuardBindings,
  type GuardInput,
} from "../src/pipeline";
import type { RateLimitBindings } from "../src/rate-limit";
import type { Transcript } from "../src/context/validator";
import {
  estimateInputTokens,
  serializePreflightInput,
} from "../src/context/preflight";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    DO: DurableObjectNamespace;
  }
}

const FIXTURE_ORG_ID = "org-pipeline-001";
const FIXTURE_NOW_MS = Date.parse("2026-07-31T12:00:00.000Z");
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
/** Seconds clock matching JWT NumericDate / GuardInput.now contract. */
const FIXTURE_NOW_SECONDS = Math.floor(FIXTURE_NOW_MS / 1000);
const FIXTURE_CAPABILITY_ID = "clinic.visit_summary";
const FIXTURE_CHAT_CAPABILITY_ID = "clinic.chat_assistant";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_TRACE_ID = "01PIPELINE0TRACE00000001";

type D1Row = Record<string, unknown>;
type ManifestWire = Record<string, unknown>;

let jtiCounter = 0;
let idempotencyKeyCounter = 0;
let requestReferenceCounter = 0;

function uniqueJti(): string {
  jtiCounter += 1;
  return `pipe0000-0000-4000-8000-${String(jtiCounter).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `01PIPELINE${String(idempotencyKeyCounter).padStart(14, "0")}`;
}

function uniqueRequestReference(): string {
  requestReferenceCounter += 1;
  return `AI-PIPE-${String(requestReferenceCounter).padStart(6, "0")}`;
}

function makePrincipal(
  installationId: string,
  overrides: Partial<Principal> = {},
): Principal {
  return {
    installationId,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-pipe-001",
    actorId: "actor-pipe-001",
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.chat_assistant"],
    jti: uniqueJti(),
    iat: FIXTURE_NOW_SECONDS - 30,
    exp: FIXTURE_NOW_SECONDS + 300,
    ver: "1",
    ...overrides,
  };
}

function singleShotManifest(
  economicsOverrides: Partial<ManifestWire["Economics"]> = {},
): Manifest {
  const wire: ManifestWire = {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      version: FIXTURE_CAPABILITY_VERSION,
      title: "Visit summary",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.visit_summary",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: { interactionMode: "single_shot" },
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
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: "prompt/visit-summary@v1",
      businessRuleFragmentRefs: ["rules/visit@v1"],
      contextRenderingTemplateRef: "templates/visit@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: "routing/standard",
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
      perRequestTokenCeiling: 9_024,
      quotaWeight: 1,
      ...economicsOverrides,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/visit@v1",
    },
  };
  return load(wire);
}

function conversationalManifest(
  overrides: {
    transcriptSizeLimit?: number;
    maxInputTokens?: number;
    perRequestTokenCeiling?: number;
  } = {},
): Manifest {
  const wire: ManifestWire = {
    Identity: {
      capabilityId: FIXTURE_CHAT_CAPABILITY_ID,
      version: FIXTURE_CAPABILITY_VERSION,
      title: "Chat assistant",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.chat_assistant",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: {
      interactionMode: "conversational",
      maxHistoryTurns: 10,
      maxContextRoundsPerTurn: 3,
      transcriptSizeLimit: overrides.transcriptSizeLimit ?? 50_000,
    },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: "transcript",
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": {
      permittedKeySet: ["visit.chief_complaint@v1"],
    },
    "Prompt binding": {
      systemInstructionArtifactRef: "prompt/chat@v1",
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
      routingPolicyRef: "routing/standard",
      requiredProviderFeatures: {
        structuredOutput: false,
        contextWindow: 32_000,
        language: "en",
      },
      latencyClass: "standard",
      degradedTierPolicy: "fallback_chain",
    },
    Economics: {
      maxInputTokens: overrides.maxInputTokens ?? 8_000,
      maxOutputTokens: 1_024,
      perRequestTokenCeiling: overrides.perRequestTokenCeiling ?? 9_024,
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
      if (kind === "grants") {
        const [installationId, capabilityId] = key.split("/", 2);
        if (!installationId || !capabilityId) {
          return "miss";
        }
        const row = await db
          .prepare(
            `SELECT grant_id, scope, capability_id, capability_version,
                    granted_at, revoked_at, changed_at, changed_by
             FROM capability_grant
             WHERE scope = ? AND capability_id = ?
             ORDER BY CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END, granted_at DESC
             LIMIT 1`,
          )
          .bind(`installation:${installationId}`, capabilityId)
          .first<D1Row>();
        return row ?? "miss";
      }
      if (kind === "kill_switches") {
        return "miss";
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
    env.DB.prepare("DELETE FROM capability_grant"),
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
    .bind(installationId, FIXTURE_ORG_ID, "Pipeline Clinic", "active", "us-east-1", FIXTURE_NOW)
    .run();
}

async function seedEntitlement(
  installationId: string,
  overrides: {
    status?: string;
    requestQuota?: number;
    softThreshold?: number;
    allowedCapabilities?: string[];
    creditBudget?: number;
  } = {},
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, credit_budget,
      allowed_capabilities, soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `ent-${installationId}`,
      installationId,
      "professional",
      "2026-08-01T00:00:00.000Z",
      "2026-09-01T00:00:00.000Z",
      overrides.requestQuota ?? 10_000,
      10_000_000,
      1_000,
      // G2: positive default so admission is not immediately exhausted
      // (`creditsUsed >= credit_budget`; G1 pending DEFAULT is 0).
      overrides.creditBudget ?? 10_000,
      JSON.stringify(
        overrides.allowedCapabilities ?? [
          FIXTURE_CAPABILITY_ID,
          FIXTURE_CHAT_CAPABILITY_ID,
        ],
      ),
      overrides.softThreshold ?? 0.8,
      overrides.status ?? "active",
    )
    .run();
}

async function seedGrant(
  installationId: string,
  capabilityId: string = FIXTURE_CAPABILITY_ID,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO capability_grant (
      grant_id, scope, capability_id, capability_version,
      granted_at, revoked_at, changed_at, changed_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `grant-${installationId}-${capabilityId}`,
      `installation:${installationId}`,
      capabilityId,
      FIXTURE_CAPABILITY_VERSION,
      FIXTURE_NOW,
      null,
      FIXTURE_NOW,
      "operator-pipe",
    )
    .run();
}

async function prepareInstallation(
  installationId: string,
  options: {
    status?: string;
    requestQuota?: number;
    softThreshold?: number;
    capabilities?: string[];
    creditBudget?: number;
  } = {},
): Promise<{ cache: ConfigCache; reader: D1Reader }> {
  await seedInstallation(installationId);
  await seedEntitlement(installationId, {
    status: options.status,
    requestQuota: options.requestQuota,
    softThreshold: options.softThreshold,
    allowedCapabilities: options.capabilities,
    creditBudget: options.creditBudget,
  });
  const caps =
    options.capabilities ?? [FIXTURE_CAPABILITY_ID, FIXTURE_CHAT_CAPABILITY_ID];
  for (const cap of caps) {
    await seedGrant(installationId, cap);
  }
  const cache = new ConfigCache();
  const reader = makePlatformD1Reader(env.DB);
  await loadConfig(cache, reader, "entitlements", installationId);
  for (const cap of caps) {
    await loadConfig(cache, reader, "grants", `${installationId}/${cap}`);
  }
  return { cache, reader };
}

function createAlwaysAllowRateLimitBindings(db: D1Database): RateLimitBindings {
  const allow = {
    async limit(_options: { key: string }): Promise<{ success: boolean }> {
      return { success: true };
    },
  };
  return {
    DB: db,
    RATE_LIMITER_INSTALLATION: allow,
    RATE_LIMITER_INSTALLATION_ACTOR: allow,
    RATE_LIMITER_INSTALLATION_CAPABILITY: allow,
  };
}

function createDenyRateLimitBindings(
  db: D1Database,
  retryAfterHint?: number,
): RateLimitBindings {
  const deny = {
    async limit(_options: { key: string }): Promise<{ success: boolean }> {
      return retryAfterHint === undefined
        ? { success: false }
        : ({ success: false, retryAfter: retryAfterHint } as {
            success: boolean;
            retryAfter: number;
          });
    },
  };
  return {
    DB: db,
    RATE_LIMITER_INSTALLATION: deny,
    RATE_LIMITER_INSTALLATION_ACTOR: deny,
    RATE_LIMITER_INSTALLATION_CAPABILITY: deny,
  };
}

function countingDo(namespace: DurableObjectNamespace): {
  do: DurableObjectNamespace;
  fetchCount: () => number;
  releaseCount: () => number;
} {
  let fetches = 0;
  let releases = 0;

  const wrapStub = (stub: DurableObjectStub): DurableObjectStub =>
    new Proxy(stub, {
      get(target, prop, receiver) {
        if (prop === "fetch") {
          return async (input: RequestInfo | URL, init?: RequestInit) => {
            fetches += 1;
            const bodyText =
              typeof init?.body === "string"
                ? init.body
                : init?.body != null
                  ? String(init.body)
                  : "";
            if (bodyText.includes('"kind":"release"')) {
              releases += 1;
            }
            return target.fetch(input as RequestInfo, init);
          };
        }
        const value = Reflect.get(target, prop, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });

  return {
    fetchCount: () => fetches,
    releaseCount: () => releases,
    do: new Proxy(namespace, {
      get(target, prop, receiver) {
        if (prop === "get") {
          return (id: DurableObjectId, options?: DurableObjectNamespaceGetDurableObjectOptions) =>
            wrapStub(target.get(id, options));
        }
        if (prop === "getByName") {
          return (
            name: string,
            options?: DurableObjectNamespaceGetDurableObjectOptions,
          ) => wrapStub(target.getByName(name, options));
        }
        const value = Reflect.get(target, prop, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }),
  };
}

function failingInsertDb(): D1Database {
  return {
    prepare(_query: string) {
      return {
        bind(..._args: unknown[]) {
          return {
            async run() {
              throw new Error("forced_d1_insert_failure");
            },
            async first() {
              throw new Error("forced_d1_insert_failure");
            },
            async all() {
              throw new Error("forced_d1_insert_failure");
            },
          };
        },
      };
    },
  } as unknown as D1Database;
}

function stubComposeSuccess(): ReturnType<ComposeRequestFn> {
  return {
    ok: true,
    request: {
      parts: [{ role: "user", content: "Hello." }],
      formatDirective: { type: "text" },
      samplingConstraints: { temperature: 0.2 },
      maxOutputTokens: 256,
      stopConditions: [],
      toolDeclarations: [],
      stream: false,
      deadline: null,
      correlationIds: {
        request_reference: "AI-PIPE-STUB",
        trace_id: FIXTURE_TRACE_ID,
      },
    } satisfies CanonicalRequest,
    promptVersion: "prompt/visit-summary@v1",
    systemPromptLeakNeedle: "You are a clinical documentation assistant.",
  };
}

function fixtureContext(principal?: Principal): Record<string, unknown> {
  return {
    org: principal?.organizationId ?? FIXTURE_ORG_ID,
    branch: principal?.branchId ?? "branch-pipe-001",
    "visit.chief_complaint@v1": {
      visit_id: "550e8400-e29b-41d4-a716-446655440000",
      complaint: "Persistent headache.",
      recorded_at: "2026-07-31T12:00:00Z",
    },
  };
}

function baseBody(
  overrides: Record<string, unknown> = {},
  principal?: Principal,
): string {
  return JSON.stringify({
    capability_id: FIXTURE_CAPABILITY_ID,
    capability_version: FIXTURE_CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: fixtureContext(principal),
    ...overrides,
  });
}

function baseGuardInput(
  installationId: string,
  cache: ConfigCache,
  reader: D1Reader,
  overrides: Partial<GuardInput> & { composeRequest?: ComposeRequestFn } = {},
): GuardInput {
  const principal =
    "principal" in overrides
      ? overrides.principal
      : makePrincipal(installationId);
  const context = fixtureContext(
    principal ?? makePrincipal(installationId),
  );
  return {
    bodyText: baseBody({}, principal ?? makePrincipal(installationId)),
    principal,
    capabilityId: FIXTURE_CAPABILITY_ID,
    capabilityVersion: FIXTURE_CAPABILITY_VERSION,
    entitlement: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      capabilityVersion: FIXTURE_CAPABILITY_VERSION,
      minimumPlanTier: "standard",
      providerId: "fake",
    },
    suppliedContext: context,
    userIntent: "Summarize the visit.",
    idempotencyKey: uniqueIdempotencyKey(),
    requestReference: uniqueRequestReference(),
    traceId: FIXTURE_TRACE_ID,
    cache,
    reader,
    now: FIXTURE_NOW_SECONDS,
    composeRequest: () => stubComposeSuccess(),
    ...overrides,
  };
}

async function countAiRequests(): Promise<number> {
  const row = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM ai_request",
  ).first<{ count: number }>();
  return row?.count ?? 0;
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, conversationIndexSql);
  // G1 plan catalogue: adds entitlement.credit_budget consumed by G2 admission.
  await applyPlatformSchema(env.DB, planCatalogueSql);
});

beforeEach(async () => {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;
  await clearTables();
  setCapabilityRegistry(
    createCapabilityRegistry([singleShotManifest(), conversationalManifest()]),
    { replace: true },
  );
});

describe("pipeline_stage_failures", () => {
  it("stage 1 — oversized body → request_too_large; no DO / no journal", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);
    const huge = "x".repeat(INGRESS_BODY_SIZE_LIMIT + 1);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, { bodyText: huge }),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 1,
      code: "request_too_large",
    });
    expect(result.ok === false && result.guardLatencyMs).toBeGreaterThanOrEqual(0);
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 2 — missing token → unauthenticated; no DO / no journal", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);

    const result = await runGuard(
      {
        ...baseGuardInput(installationId, cache, reader),
        principal: undefined,
        token: undefined,
        verifier: undefined,
      },
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({ ok: false, stage: 2, code: "unauthenticated" });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 2 — verifier rejects suspended installation", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);
    const verifier: TokenVerifier = {
      async verify() {
        return { ok: false, code: "installation_suspended" };
      },
    };

    const result = await runGuard(
      {
        ...baseGuardInput(installationId, cache, reader),
        principal: undefined,
        token: "fake.token",
        verifier,
      },
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 2,
      code: "installation_suspended",
    });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 3 — suspended entitlement → forbidden_capability; no DO / no journal", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId, {
      status: "suspended",
    });
    const doSpy = countingDo(env.DO);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 3,
      code: "forbidden_capability",
    });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 4 — rate-limit deny → rate_limited; no DO / no journal", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createDenyRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({ ok: false, stage: 4, code: "rate_limited" });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 4 — rate_limited GuardFailure carries the binding retryAfter hint", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const hint = 15;

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader),
      {
        DB: env.DB,
        DO: env.DO,
        rateLimit: createDenyRateLimitBindings(env.DB, hint),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 4,
      code: "rate_limited",
      retryAfter: hint,
    });
  });

  it("stage 5 — unknown capability → capability_unknown; no DO / no journal", async () => {
    const unknownId = "clinic.does_not_exist";
    const installationId = env.DO.newUniqueId().toString();
    // Entitlement + grant allow the id so the guard reaches stage 5 resolve.
    const { cache, reader } = await prepareInstallation(installationId, {
      capabilities: [FIXTURE_CAPABILITY_ID, unknownId],
    });
    const doSpy = countingDo(env.DO);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        capabilityId: unknownId,
        entitlement: {
          capabilityId: unknownId,
          capabilityVersion: FIXTURE_CAPABILITY_VERSION,
          minimumPlanTier: "standard",
          providerId: "fake",
        },
      }),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 5,
      code: "capability_unknown",
    });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 6 — invalid context → context_invalid; no DO / no journal", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        bodyText: baseBody({ context: {} }),
        suppliedContext: {},
      }),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 6,
      code: expect.stringMatching(/context_invalid|context_required/),
    });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 7 — over-ceiling preflight → request_too_large; no DO / no journal", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);
    setCapabilityRegistry(
      createCapabilityRegistry([
        singleShotManifest({
          maxInputTokens: 10,
          perRequestTokenCeiling: 20,
          maxOutputTokens: 5,
        }),
      ]),
      { replace: true },
    );

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        promptArtifactByteLength: 100_000,
      }),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 7,
      code: "request_too_large",
    });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 7 — composer scaffold byte length is counted without numeric override", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);
    const principal = makePrincipal(installationId);
    const userIntent = "Summarize the visit.";
    const filteredContext = {
      "visit.chief_complaint@v1": fixtureContext(principal)[
        "visit.chief_complaint@v1"
      ],
    };
    const serialized = serializePreflightInput({ filteredContext, userIntent });
    const withoutScaffold = estimateInputTokens(serialized);
    const scaffoldBytes = 100_000;

    setCapabilityRegistry(
      createCapabilityRegistry([
        singleShotManifest({
          maxInputTokens: withoutScaffold,
          perRequestTokenCeiling: 1_000_000,
          maxOutputTokens: 1,
        }),
      ]),
      { replace: true },
    );

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        promptScaffoldByteLength: () => scaffoldBytes,
      }),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(estimateInputTokens(serialized, scaffoldBytes)).toBeGreaterThan(
      withoutScaffold,
    );
    expect(result).toMatchObject({
      ok: false,
      stage: 7,
      code: "request_too_large",
    });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 7 — oversized transcript priced via serializePreflightInput → request_too_large", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);
    setCapabilityRegistry(
      createCapabilityRegistry([
        conversationalManifest({
          transcriptSizeLimit: 50_000,
          maxInputTokens: 50,
          perRequestTokenCeiling: 100,
        }),
      ]),
      { replace: true },
    );

    const priorText = "prior turn text ".repeat(200);
    const transcript = [
      { turn_ordinal: 1, kind: "user" as const, text: priorText },
      { turn_ordinal: 2, kind: "model" as const, text: priorText },
    ];

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        capabilityId: FIXTURE_CHAT_CAPABILITY_ID,
        entitlement: {
          capabilityId: FIXTURE_CHAT_CAPABILITY_ID,
          capabilityVersion: FIXTURE_CAPABILITY_VERSION,
          minimumPlanTier: "standard",
          providerId: "fake",
        },
        bodyText: JSON.stringify({
          capability_id: FIXTURE_CHAT_CAPABILITY_ID,
          capability_version: FIXTURE_CAPABILITY_VERSION,
          user_intent: "Continue.",
          context: fixtureContext(),
          conversation_id: "conv-pipe-oversized",
          turn_ordinal: 3,
          transcript,
        }),
        suppliedContext: fixtureContext(),
        userIntent: "Continue.",
      }),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({
      ok: false,
      stage: 7,
      code: "request_too_large",
    });
    expect(doSpy.fetchCount()).toBe(0);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 8 — quota exhausted → quota_exhausted; no journal", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId, {
      requestQuota: 0,
    });
    const doSpy = countingDo(env.DO);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({ ok: false, stage: 8, code: "quota_exhausted" });
    expect(doSpy.fetchCount()).toBeGreaterThanOrEqual(1);
    expect(await countAiRequests()).toBe(0);
  });

  it("stage 8 — duplicate idempotency key → idempotent success with priorState", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const bindings: GuardBindings = {
      DB: env.DB,
      DO: env.DO,
      rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
    };
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const first = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference,
      }),
      bindings,
    );
    expect(first.ok).toBe(true);
    if (!first.ok || first.outcome === "idempotent") {
      expect.fail("first guard should be a fresh success");
    }

    const second = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        idempotencyKey,
        requestReference: uniqueRequestReference(),
        principal: makePrincipal(installationId),
      }),
      bindings,
    );

    expect(second).toMatchObject({
      ok: true,
      outcome: "idempotent",
      requestId: first.requestId,
      priorState: {
        requestId: first.requestId,
        requestReference,
        state: "admitted",
      },
    });
    expect(await countAiRequests()).toBe(1);
  });

  it("stage 9 — journals resolvePromptVersion into prompt_artifact_hash, not the artifact ref", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const composerHash = "c0ffee00";

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        resolvePromptVersion: () => composerHash,
      }),
      {
        DB: env.DB,
        DO: env.DO,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result.ok).toBe(true);
    if (!result.ok || result.outcome === "idempotent") {
      expect.fail("guard should be a fresh success");
    }

    const row = await env.DB.prepare(
      `SELECT prompt_artifact_hash FROM ai_request WHERE request_id = ?`,
    )
      .bind(result.requestId)
      .first<{ prompt_artifact_hash: string }>();

    expect(row?.prompt_artifact_hash).toBe(composerHash);
    expect(row?.prompt_artifact_hash).not.toBe("prompt/visit-summary@v1");
  });

  it("stage 9 — D1 insert failure → internal_error + release; key reusable", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const doSpy = countingDo(env.DO);
    const idempotencyKey = uniqueIdempotencyKey();
    const rateLimit = createAlwaysAllowRateLimitBindings(env.DB);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, { idempotencyKey }),
      {
        DB: failingInsertDb(),
        DO: doSpy.do,
        rateLimit,
      },
    );

    expect(result).toMatchObject({ ok: false, stage: 9, code: "internal_error" });
    expect(doSpy.releaseCount()).toBe(1);
    expect(await countAiRequests()).toBe(0);

    // After release, the same key can admit again (not stuck on idempotent).
    const retry = await runGuard(
      baseGuardInput(installationId, cache, reader, { idempotencyKey }),
      {
        DB: env.DB,
        DO: doSpy.do,
        rateLimit,
      },
    );
    expect(retry.ok).toBe(true);
    if (retry.ok) {
      expect(retry.outcome).not.toBe("idempotent");
    }
  });

  it("stage 10 — compose failure → Failed terminal + internal_error", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        composeRequest: () => ({ ok: false, code: "internal_error" }),
      }),
      {
        DB: env.DB,
        DO: env.DO,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result).toMatchObject({ ok: false, stage: 10, code: "internal_error" });
    const row = await env.DB.prepare(
      `SELECT state, terminal_error_code, routing_tier FROM ai_request LIMIT 1`,
    ).first<{
      state: string;
      terminal_error_code: string | null;
      routing_tier: string | null;
    }>();
    expect(row?.state).toBe("Failed");
    expect(row?.terminal_error_code).toBe("internal_error");
    expect(row?.routing_tier).toBe("standard");
  });
});

describe("pipeline_transcript_threading", () => {
  it("threads validatedTranscript into composeRequest and GuardSuccess", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    setCapabilityRegistry(
      createCapabilityRegistry([conversationalManifest()]),
      { replace: true },
    );

    const transcript: Transcript = [
      { turn_ordinal: 1, kind: "user", text: "First question." },
      { turn_ordinal: 2, kind: "model", text: "First answer." },
    ];
    let receivedTranscript: Transcript | undefined;
    const composeRequest: ComposeRequestFn = (input) => {
      receivedTranscript = input.transcript;
      return stubComposeSuccess();
    };

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        capabilityId: FIXTURE_CHAT_CAPABILITY_ID,
        entitlement: {
          capabilityId: FIXTURE_CHAT_CAPABILITY_ID,
          capabilityVersion: FIXTURE_CAPABILITY_VERSION,
          minimumPlanTier: "standard",
          providerId: "fake",
        },
        bodyText: JSON.stringify({
          capability_id: FIXTURE_CHAT_CAPABILITY_ID,
          capability_version: FIXTURE_CAPABILITY_VERSION,
          user_intent: "Follow up.",
          context: fixtureContext(),
          conversation_id: "conv-pipe-thread",
          turn_ordinal: 3,
          transcript,
        }),
        suppliedContext: fixtureContext(),
        userIntent: "Follow up.",
        composeRequest,
      }),
      {
        DB: env.DB,
        DO: env.DO,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result.ok).toBe(true);
    if (!result.ok || result.outcome === "idempotent") {
      expect.fail("expected fresh conversational success");
    }
    expect(receivedTranscript).toEqual(transcript);
    expect(result.transcript).toEqual(transcript);
  });
});

describe("pipeline_compose_stream_flag", () => {
  it("passes streamFlag true and the request deadline into composeRequest", async () => {
    const installationId = env.DO.newUniqueId().toString();
    const { cache, reader } = await prepareInstallation(installationId);
    const requestDeadlineMs = 45_000;

    let received:
      | Parameters<ComposeRequestFn>[0]
      | undefined;
    const composeRequest: ComposeRequestFn = (input) => {
      received = input;
      const stub = stubComposeSuccess();
      if (!stub.ok) {
        return stub;
      }
      return {
        ok: true,
        request: {
          ...stub.request,
          stream: input.streamFlag ?? false,
          deadline: input.deadline ?? null,
        },
        promptVersion: stub.promptVersion,
        systemPromptLeakNeedle: stub.systemPromptLeakNeedle,
      };
    };

    const result = await runGuard(
      baseGuardInput(installationId, cache, reader, {
        composeRequest,
        deadline: requestDeadlineMs,
      }),
      {
        DB: env.DB,
        DO: env.DO,
        rateLimit: createAlwaysAllowRateLimitBindings(env.DB),
      },
    );

    expect(result.ok).toBe(true);
    if (!result.ok || result.outcome === "idempotent") {
      expect.fail("expected fresh compose success");
    }
    expect(received?.streamFlag).toBe(true);
    expect(received).toHaveProperty("deadline");
    expect(received?.deadline).toBe(requestDeadlineMs);
    expect(result.composed.stream).toBe(true);
    expect(result.composed.deadline).toBe(requestDeadlineMs);
  });
});

describe("pipeline_soft_threshold_exposes_degraded_routing_tier", () => {
  it("returns routingTier degraded on GuardFreshSuccess after usage crosses soft_threshold", async () => {
    const installationId = env.DO.newUniqueId().toString();
    // G2: degraded is driven by the credit ratio (creditsUsed / credit_budget).
    // creditBudget 2 + one settled credit (quotaWeight 1) crosses the 0.5
    // threshold while leaving budget for the second admission.
    const { cache, reader } = await prepareInstallation(installationId, {
      requestQuota: 2,
      softThreshold: 0.5,
      creditBudget: 2,
    });
    const rateLimit = createAlwaysAllowRateLimitBindings(env.DB);

    const first = await runGuard(
      baseGuardInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO, rateLimit },
    );
    expect(first.ok).toBe(true);
    if (!first.ok || first.outcome === "idempotent") {
      expect.fail("expected first fresh admission");
    }
    expect(first.routingTier).toBe("standard");
    expect(first.degraded).toBeUndefined();

    const credited = await creditUsage(
      {
        installationId,
        requestId: first.requestId,
        requestReference: first.requestReference,
        usage: { tokens: 1, cost: 0.001 },
        partial: false,
        credits: 1,
      },
      { DO: env.DO },
    );
    expect(credited.ok).toBe(true);

    const second = await runGuard(
      baseGuardInput(installationId, cache, reader),
      { DB: env.DB, DO: env.DO, rateLimit },
    );
    expect(second.ok).toBe(true);
    if (!second.ok || second.outcome === "idempotent") {
      expect.fail("expected second fresh admission");
    }
    expect(second.degraded).toBe(true);
    expect(second.routingTier).toBe("degraded");

    const row = await env.DB
      .prepare(
        "SELECT routing_tier FROM ai_request WHERE request_id = ?",
      )
      .bind(second.requestId)
      .first<{ routing_tier: string | null }>();
    expect(row?.routing_tier).toBe("degraded");
  });
});
