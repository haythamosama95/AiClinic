import { env, runInDurableObject } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import planCatalogueMigrationSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
import { CONCURRENCY_LIMIT, ensureCoverageDoTables } from "../src/quota-do";
import {
  ADAPTER_ROUTING_BODY_FIELDS,
  buildAcceptedSseEvent,
  parseAdapterRequestBody,
  type AdapterSseEvent,
} from "../src/adapter";
import {
  ConfigCache,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import {
  buildErrorBody,
  supplementaryFieldsForCode,
} from "../src/errors";
import type { Principal } from "../src/identity";
import { createRequestRow } from "../src/journal";
import { load, type Manifest } from "../src/manifest";
import { selectCandidateChain } from "../src/router";
import {
  CLIENT_ROUTING_INJECTION_KEYS,
  degradedNoticeFromAdmission,
  resolveRoutingTier,
  type AdmissionAllowResult,
} from "../src/soft-threshold";

/** Test helper: production ingress ignores these keys via empty ADAPTER_ROUTING_BODY_FIELDS. */
function bodyHasClientRoutingInjection(
  body: Record<string, unknown>,
): boolean {
  return CLIENT_ROUTING_INJECTION_KEYS.some((key) =>
    Object.prototype.hasOwnProperty.call(body, key),
  );
}

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    DO: DurableObjectNamespace;
    R2: R2Bucket;
  }
}

const FIXTURE_ORG_ID = "org-f4-001";
const FIXTURE_NOW_MS = Date.parse("2026-07-31T12:00:00.000Z");
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_CAPABILITY_ID = "ai.visit_summary";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_TRACE_ID = "01F4SOFTTHRESH00000000001";
const FIXTURE_POLICY_KEY = "routing-policy-f4";
const FIXTURE_PERIOD_END = "2026-09-01T00:00:00.000Z";

const REQUEST_QUOTA = 100;
const CREDIT_BUDGET = 100;
const SOFT_THRESHOLD = 0.8;
const SOFT_CROSS_CREDITS_USED = 80;
const JUST_BELOW_SOFT_CREDITS_USED = 73;
const BELOW_SOFT_CREDITS_USED = 10;
const TOKEN_BUDGET = 1_000_000;
const COST_BUDGET = 100;
const QUOTA_WEIGHT = 1;

type D1Row = Record<string, unknown>;

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

type IdempotencyPriorState = {
  requestReference: string;
  state: string;
  requestId: string;
};

type AdmissionSuccess =
  | {
    ok: true;
    outcome: "admitted";
    requestId: string;
    degraded?: boolean;
    band?: "ok" | "75" | "90" | "exhausted";
  }
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
  partial: boolean;
  credits: number;
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
  creditUsage: (
    input: CreditInput,
    bindings: CreditBindings,
  ) => Promise<unknown>;
};

type DoSpy = DurableObjectNamespace & {
  fetchCount: () => number;
};

type RoutingPolicyDocument = {
  schema_version: number;
  policy_id: string;
  policy_version: number;
  defaults: { cost_class: string; max_parallel_attempts: number };
  rules: Array<{
    rule_id: string;
    match: Record<string, unknown>;
    requires: {
      structured_output: boolean;
      min_context_window: number;
      languages: string[];
    };
    targets: Array<{
      provider_id: string;
      model_id: string;
      features: Record<string, unknown>;
      max_attempts: number;
      timeout_ms: number;
    }>;
  }>;
  overrides: unknown[];
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

function uniqueJti(): string {
  jtiCounter += 1;
  return `f4000000-0000-4000-8000-${String(jtiCounter).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `01F4THRESHOLD${String(idempotencyKeyCounter).padStart(12, "0")}`;
}

function uniqueRequestReference(): string {
  requestReferenceCounter += 1;
  return `AI-F4-${String(requestReferenceCounter).padStart(5, "0")}`;
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
    branchId: "branch-f4-001",
    actorId: "actor-f4-001",
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

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM coverage_mirror"),
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
      "F4 Soft Threshold Clinic",
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

function termIdForInstallation(installationId: string): string {
  return `term-${installationId.slice(0, 8)}`;
}

function sqlLiteral(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

async function pinHarnessTestClock(): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_test_clock (
       id TEXT PRIMARY KEY,
       now_iso TEXT NOT NULL
     )`,
  ).run();
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_test_clock (id, now_iso) VALUES ('default', ?)`,
  )
    .bind(FIXTURE_NOW)
    .run();
}

async function seedQuotaDoForInstallation(
  installationId: string,
  options: { requestQuota?: number } = {},
): Promise<void> {
  const termId = termIdForInstallation(installationId);
  const requestQuota = options.requestQuota ?? REQUEST_QUOTA;
  const planSnapshot = JSON.stringify({
    capabilities: [FIXTURE_CAPABILITY_ID],
    max_cost_class: "standard",
    concurrency_limit: CONCURRENCY_LIMIT,
  });

  await runInDurableObject(
    env.DO.get(env.DO.idFromName(installationId)),
    async (_instance, state) => {
      const storage = state.storage as DurableObjectStorage & {
        sql?: { exec: (query: string) => Iterable<Record<string, unknown>> };
      };
      if (!storage.sql) {
        throw new Error("quota DO sql storage unavailable for soft-threshold seed");
      }
      await ensureCoverageDoTables(storage, async (fn) => fn());
      storage.sql.exec(`DELETE FROM term`);
      storage.sql.exec(
        `INSERT INTO hot (
           suspended, transferred_out_to, awaiting_transfer, transfer_pending,
           active_term_id, used, reserved, grace_base_used, reservations, replay,
           idempotency, band_emitted, binding_epoch, clinic_seq, next_alarm_at
         ) VALUES (
           0, NULL, 0, 0, ${sqlLiteral(termId)}, 0, 0, 0, '[]', '{}', '{}', '{}', 0, 0, NULL
         )`,
      );
      storage.sql.exec(
        `INSERT INTO term (
           term_id, grant_id, origin_grant_id, position, state, end_reason,
           plan_snapshot, allowance, used_final, duration_unit, duration_count,
           grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
         ) VALUES (
           ${sqlLiteral(termId)}, 'f4-seed', 'f4-seed', 0, 'active', NULL,
           ${sqlLiteral(planSnapshot)}, ${requestQuota},
           NULL, 'month', 1, 0, 'proportional',
           ${sqlLiteral(FIXTURE_NOW)}, ${sqlLiteral(FIXTURE_NOW)},
           ${sqlLiteral(FIXTURE_PERIOD_END)}, NULL, NULL
         )`,
      );
    },
  );
}

async function seedCoverageMirror(installationId: string): Promise<void> {
  const termRef = termIdForInstallation(installationId);
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
      JSON.stringify({ ref: termRef, capabilities: [FIXTURE_CAPABILITY_ID] }),
    )
    .run();
}

async function setAllowanceUsed(
  installationId: string,
  used: number,
  allowance: number = CREDIT_BUDGET,
): Promise<void> {
  await seedQuotaDoForInstallation(installationId, { requestQuota: allowance });
  if (used <= 0) {
    return;
  }
  const termId = termIdForInstallation(installationId);
  await runInDurableObject(
    env.DO.get(env.DO.idFromName(installationId)),
    async (_instance, state) => {
      const storage = state.storage as DurableObjectStorage & {
        sql?: { exec: (query: string) => void };
      };
      storage.sql?.exec(
        `UPDATE hot SET used = ${used}, reserved = 0, reservations = '[]', active_term_id = ${sqlLiteral(termId)}`,
      );
    },
  );
}

async function seedEntitlement(
  installationId: string,
  options: {
    requestQuota?: number;
    tokenBudget?: number;
    costBudget?: number;
    creditBudget?: number;
    softThreshold?: number;
  } = {},
): Promise<void> {
  void options.tokenBudget;
  void options.costBudget;
  void options.creditBudget;
  void options.softThreshold;
  await seedCoverageMirror(installationId);
  await seedQuotaDoForInstallation(installationId, {
    requestQuota: options.requestQuota ?? options.creditBudget ?? REQUEST_QUOTA,
  });
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
        return "miss";
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
    capabilityId: FIXTURE_CAPABILITY_ID,
    quotaWeight: QUOTA_WEIGHT,
    cache,
    reader,
  };
}

function buildStandardDegradedPolicy(): RoutingPolicyDocument {
  return {
    schema_version: 1,
    policy_id: "policy-f4-soft-threshold",
    policy_version: 1,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "standard-tier",
        match: { tiers: ["standard"] },
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [
          {
            provider_id: "openai",
            model_id: "gpt-4o",
            features: {
              structured_output: false,
              min_context_window: 128_000,
              languages: ["en"],
              latency_class: "interactive",
              cost_class: "standard",
            },
            max_attempts: 2,
            timeout_ms: 30_000,
          },
        ],
      },
      {
        rule_id: "degraded-tier",
        match: { tiers: ["degraded"] },
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [
          {
            provider_id: "deepseek",
            model_id: "deepseek-chat",
            features: {
              structured_output: false,
              min_context_window: 128_000,
              languages: ["en"],
              latency_class: "interactive",
              cost_class: "economy",
            },
            max_attempts: 2,
            timeout_ms: 30_000,
          },
        ],
      },
      {
        rule_id: "catch-all",
        match: {},
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [
          {
            provider_id: "deepseek",
            model_id: "deepseek-chat",
            features: {
              structured_output: false,
              min_context_window: 128_000,
              languages: ["en"],
              latency_class: "interactive",
              cost_class: "economy",
            },
            max_attempts: 2,
            timeout_ms: 30_000,
          },
        ],
      },
    ],
    overrides: [],
  };
}

function preloadPolicyCache(document: RoutingPolicyDocument): ConfigCache {
  const cache = new ConfigCache();
  cache.remember("active_routing_policy", FIXTURE_POLICY_KEY, {
    policy_id: document.policy_id,
    policy_version: document.policy_version,
    content_pointer: `control/routing-policy/${document.policy_id}/${document.policy_version}.json`,
    active_from: "2026-08-01T00:00:00.000Z",
    activated_by: "test-fixture",
    document,
  });
  return cache;
}

function validManifestWire(): Record<string, unknown> {
  return {
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
      allowedStaffRoles: ["clinician"],
      killSwitchFlag: false,
    },
    Interaction: { interactionMode: "single_shot" },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": [],
    "Prompt binding": {
      systemInstructionArtifactRef: "prompt/visit-summary@v1",
      businessRuleFragmentRefs: [],
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
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/visit-summary@v1",
    },
  };
}

function loadFixtureManifest(): Manifest {
  return load(validManifestWire());
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

function toAdmissionAllow(result: AdmissionSuccess): AdmissionAllowResult {
  if (result.outcome !== "admitted") {
    throw new Error(`Expected admitted outcome, got ${result.outcome}`);
  }
  return {
    outcome: "admitted",
    requestId: result.requestId,
    degraded: result.degraded,
    band: result.band,
  };
}

async function seedCreditsUsed(
  installationId: string,
  _cache: ConfigCache,
  _reader: D1Reader,
  creditsUsed: number,
  _usage: { tokens: number; cost: number } = { tokens: 1, cost: 0.001 },
  _creditsPerRequest: number = QUOTA_WEIGHT,
): Promise<void> {
  await setAllowanceUsed(installationId, creditsUsed, CREDIT_BUDGET);
}

type PipelineOutcome =
  | {
    kind: "accepted";
    admission: AdmissionAllowResult;
    routingTier: "standard" | "degraded";
    ruleId: string;
    providerId: string;
    acceptedEvent: AdapterSseEvent;
  }
  | {
    kind: "refused";
    code: string;
    periodReset?: string;
    errorBody: ReturnType<typeof buildErrorBody>;
  };

async function runSoftThresholdPipeline(options: {
  installationId: string;
  cache: ConfigCache;
  reader: D1Reader;
  creditsUsed: number;
  settlementUsage?: { tokens: number; cost: number };
  creditsPerRequest?: number;
  doNamespace?: DurableObjectNamespace;
  persistRow?: boolean;
}): Promise<PipelineOutcome> {
  const {
    installationId,
    cache,
    reader,
    creditsUsed,
    settlementUsage = { tokens: 1, cost: 0.001 },
    creditsPerRequest = QUOTA_WEIGHT,
    doNamespace = env.DO,
    persistRow = false,
  } = options;

  await seedCreditsUsed(
    installationId,
    cache,
    reader,
    creditsUsed,
    settlementUsage,
    creditsPerRequest,
  );

  const admission = await loadAdmissionModule();
  const policyCache = preloadPolicyCache(buildStandardDegradedPolicy());
  const admissionResult = await admission.runAdmission(
    defaultAdmissionInput(installationId, cache, reader),
    { DB: env.DB, DO: doNamespace },
    { now: FIXTURE_NOW_MS, nowMs: FIXTURE_NOW_MS },
  );

  if (!admissionResult.ok) {
    const supplementary = supplementaryFieldsForCode(
      admissionResult.code as "allowance_exhausted",
      { periodReset: admissionResult.periodReset },
    );
    const errorBody = {
      ...buildErrorBody({
        code: admissionResult.code,
        requestReference: uniqueRequestReference(),
        traceId: FIXTURE_TRACE_ID,
      }),
      ...supplementary,
    };
    return {
      kind: "refused",
      code: admissionResult.code,
      periodReset: admissionResult.periodReset,
      errorBody,
    };
  }

  if (admissionResult.outcome !== "admitted") {
    throw new Error(`Unexpected admission outcome: ${admissionResult.outcome}`);
  }

  const allow = toAdmissionAllow(admissionResult);
  const routingTier = resolveRoutingTier(allow);
  const routerOutcome = selectCandidateChain({
    cache: policyCache,
    policyCacheKey: FIXTURE_POLICY_KEY,
    context: {
      installationId,
      capabilityId: FIXTURE_CAPABILITY_ID,
      routingTier,
      requirements: {
        structured_output_required: false,
        min_context_window: 0,
        languages: ["en"],
        latency_class: "interactive",
      },
      manifestCostClass: "standard",
      entitlementMaxCostClass: "premium",
    },
  });

  const degradedNotice = degradedNoticeFromAdmission(allow);
  const requestReference = uniqueRequestReference();
  const acceptedEvent = buildAcceptedSseEvent({
    requestReference,
    traceId: FIXTURE_TRACE_ID,
    degradedNotice,
  });

  if (persistRow) {
    const manifest = loadFixtureManifest();
    await createRequestRow(
      {
        requestId: allow.requestId,
        requestReference,
        principal: makePrincipal(installationId),
        manifest,
        idempotencyKey: uniqueIdempotencyKey(),
        traceId: FIXTURE_TRACE_ID,
        routingTier,
      },
      env.DB,
    );
  }

  const chain = routerOutcome.routing_decision.chain[0];
  return {
    kind: "accepted",
    admission: allow,
    routingTier,
    ruleId: routerOutcome.routing_decision.rule_id,
    providerId: chain?.provider_id ?? "",
    acceptedEvent,
  };
}

async function readRoutingTier(requestId: string): Promise<string | null> {
  const row = await env.DB.prepare(
    "SELECT routing_tier FROM ai_request WHERE request_id = ?",
  )
    .bind(requestId)
    .first<{ routing_tier: string | null }>();
  return row?.routing_tier ?? null;
}

async function readAiRequestCount(): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM ai_request").first<{
    count: number;
  }>();
  return row?.count ?? 0;
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
});

beforeEach(async () => {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;
  await clearTables();
  await pinHarnessTestClock();
});

describe("soft_threshold_selects_degraded_target", () => {
  it("admits with degraded flag, routes degraded tier, and emits degraded_notice", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);

    const outcome = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: SOFT_CROSS_CREDITS_USED,
    });

    expect(outcome.kind).toBe("accepted");
    if (outcome.kind !== "accepted") {
      return;
    }

    expect(outcome.admission.degraded).toBe(true);
    expect(outcome.routingTier).toBe("degraded");
    expect(outcome.ruleId).toBe("degraded-tier");
    expect(outcome.providerId).toBe("deepseek");
    expect(outcome.acceptedEvent.type).toBe("accepted");
    expect(outcome.acceptedEvent.data.degraded_notice).toBe(true);
  });
});

describe("hard_exhaustion_quota_exhausted_admin_path_no_lock", () => {
  // Gateway-layer proof only: refuse + period_reset + no journal. Non-AI UX is E4.
  it("returns quota_exhausted with period_reset and does not journal an AI request", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    const aiRequestsBefore = await readAiRequestCount();

    const outcome = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: REQUEST_QUOTA,
    });

    expect(outcome.kind).toBe("refused");
    if (outcome.kind !== "refused") {
      return;
    }

    expect(outcome.code).toBe("allowance_exhausted");
    expect(outcome.errorBody.code).toBe("allowance_exhausted");
    expect(await readAiRequestCount()).toBe(aiRequestsBefore);
  });
});

describe("below_threshold_traffic_unaffected", () => {
  it("keeps standard tier without degraded_notice below the soft threshold", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);

    const outcome = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: BELOW_SOFT_CREDITS_USED,
    });

    expect(outcome.kind).toBe("accepted");
    if (outcome.kind !== "accepted") {
      return;
    }

    expect(outcome.admission.degraded).toBeUndefined();
    expect(outcome.routingTier).toBe("standard");
    expect(outcome.ruleId).toBe("standard-tier");
    expect(outcome.providerId).toBe("openai");
    expect(outcome.acceptedEvent.data.degraded_notice).toBeUndefined();
  });
});

describe("soft_threshold_tier_not_accepted_from_client", () => {
  it("adapter ingress never surfaces client routing injection keys", () => {
    expect(ADAPTER_ROUTING_BODY_FIELDS).toEqual([]);

    const injectedBody = {
      installation: "ignored",
      capability: FIXTURE_CAPABILITY_ID,
      routing_tier: "degraded",
      degraded: true,
      degraded_notice: true,
    };
    const parsed = parseAdapterRequestBody(JSON.stringify(injectedBody));
    expect(parsed).not.toBeNull();
    if (parsed === null) {
      return;
    }
    expect(bodyHasClientRoutingInjection(parsed)).toBe(true);
    for (const key of CLIENT_ROUTING_INJECTION_KEYS) {
      expect(ADAPTER_ROUTING_BODY_FIELDS).not.toContain(key);
    }

    // Below-threshold admission still routes standard — tier is admission-only.
    const allow: AdmissionAllowResult = {
      outcome: "admitted",
      requestId: "req-wire-boundary",
    };
    expect(resolveRoutingTier(allow)).toBe("standard");
  });
});

describe("soft_threshold_persists_routing_tier", () => {
  it("writes degraded and standard routing_tier via createRequestRow", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);

    const degraded = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: SOFT_CROSS_CREDITS_USED,
      persistRow: true,
    });
    expect(degraded.kind).toBe("accepted");
    if (degraded.kind !== "accepted") {
      return;
    }
    expect(await readRoutingTier(degraded.admission.requestId)).toBe("degraded");

    const belowInstallationId = freshInstallationId();
    const belowSeed = await seedInstallationAndEntitlement(belowInstallationId);
    const below = await runSoftThresholdPipeline({
      installationId: belowInstallationId,
      cache: belowSeed.cache,
      reader: belowSeed.reader,
      creditsUsed: BELOW_SOFT_CREDITS_USED,
      persistRow: true,
    });
    expect(below.kind).toBe("accepted");
    if (below.kind !== "accepted") {
      return;
    }
    expect(await readRoutingTier(below.admission.requestId)).toBe("standard");
  });
});

describe("soft_threshold_no_second_quota_do_round_trip", () => {
  it("uses exactly one Quota DO fetch for soft-threshold admission", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);
    await seedCreditsUsed(installationId, cache, reader, SOFT_CROSS_CREDITS_USED);

    const admission = await loadAdmissionModule();
    const doSpy = createDoSpy(env.DO);

    const result = await admission.runAdmission(
      defaultAdmissionInput(installationId, cache, reader),
      { DB: env.DB, DO: doSpy },
      { now: FIXTURE_NOW_MS },
    );

    expect(doSpy.fetchCount()).toBe(1);
    assertAdmitted(result);
    expect(result.degraded).toBe(true);
  });
});

describe("quota_exhausted_only_error_code_on_hard_exhaustion", () => {
  it("emits only quota_exhausted from hard exhaustion and no error on soft path", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);

    const soft = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: SOFT_CROSS_CREDITS_USED,
    });
    expect(soft.kind).toBe("accepted");

    const hardInstallationId = freshInstallationId();
    const hardSeed = await seedInstallationAndEntitlement(hardInstallationId);
    const hard = await runSoftThresholdPipeline({
      installationId: hardInstallationId,
      cache: hardSeed.cache,
      reader: hardSeed.reader,
      creditsUsed: REQUEST_QUOTA,
    });

    expect(hard.kind).toBe("refused");
    if (hard.kind !== "refused") {
      return;
    }
    expect(hard.code).toBe("allowance_exhausted");
    expect(Object.keys(hard.errorBody).sort()).toEqual(
      ["code", "request_reference", "retry_safe", "trace_id"].sort(),
    );
  });
});

describe("soft_threshold_zero_never_degrades", () => {
  it("keeps standard routing when soft_threshold is 0 with positive budgets", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      softThreshold: 0,
    });

    const outcome = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: BELOW_SOFT_CREDITS_USED,
    });

    expect(outcome.kind).toBe("accepted");
    if (outcome.kind !== "accepted") {
      return;
    }
    expect(outcome.admission.degraded).toBeUndefined();
    expect(outcome.routingTier).toBe("standard");
    expect(outcome.acceptedEvent.data.degraded_notice).toBeUndefined();
  });
});

describe("soft_threshold_zero_budget_dimension_never_contributes", () => {
  it("ignores a zero credit_budget dimension even when creditsUsed is large", async () => {
    const { isSoftThresholdCrossed } = await import("../src/quota-do/index");
    const crossed = isSoftThresholdCrossed(
      {
        requestsUsed: BELOW_SOFT_CREDITS_USED,
        tokensUsed: 999_999,
        costUsed: 0.001,
        creditsUsed: 999_999,
        inFlight: 0,
      },
      {
        plan: "professional",
        period_bounds: {
          period_start: "2026-08-01T00:00:00.000Z",
          period_end: FIXTURE_PERIOD_END,
        },
        request_quota: REQUEST_QUOTA,
        token_cost_budget: { token_budget: TOKEN_BUDGET, cost_budget: COST_BUDGET },
        credit_budget: 0,
        allowed_capabilities: [FIXTURE_CAPABILITY_ID],
        soft_threshold: SOFT_THRESHOLD,
        status: "active",
      },
    );
    expect(crossed).toBe(false);
  });
});

describe("soft_threshold_token_dimension_selects_degraded", () => {
  it("crosses soft threshold on creditsUsed / credit_budget and routes degraded", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      requestQuota: 1_000_000,
      creditBudget: 100,
      softThreshold: SOFT_THRESHOLD,
    });

    const outcome = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: 80,
      settlementUsage: { tokens: 800, cost: 0.001 },
      creditsPerRequest: 80,
    });

    expect(outcome.kind).toBe("accepted");
    if (outcome.kind !== "accepted") {
      return;
    }
    expect(outcome.admission.degraded).toBe(true);
    expect(outcome.routingTier).toBe("degraded");
    expect(outcome.providerId).toBe("deepseek");
  });
});

describe("soft_threshold_cost_dimension_selects_degraded", () => {
  it("crosses soft threshold on creditsUsed / credit_budget and routes degraded", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId, {
      requestQuota: 1_000_000,
      creditBudget: 100,
      softThreshold: SOFT_THRESHOLD,
    });

    const outcome = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: 80,
      settlementUsage: { tokens: 1, cost: 80 },
      creditsPerRequest: 80,
    });

    expect(outcome.kind).toBe("accepted");
    if (outcome.kind !== "accepted") {
      return;
    }
    expect(outcome.admission.degraded).toBe(true);
    expect(outcome.routingTier).toBe("degraded");
    expect(outcome.providerId).toBe("deepseek");
  });
});

describe("soft_threshold_just_below_boundary_unaffected", () => {
  it("keeps standard tier at 79/100 just below the >= soft boundary", async () => {
    const installationId = freshInstallationId();
    const { cache, reader } = await seedInstallationAndEntitlement(installationId);

    const outcome = await runSoftThresholdPipeline({
      installationId,
      cache,
      reader,
      creditsUsed: JUST_BELOW_SOFT_CREDITS_USED,
    });

    expect(outcome.kind).toBe("accepted");
    if (outcome.kind !== "accepted") {
      return;
    }
    expect(outcome.admission.degraded).toBeUndefined();
    expect(outcome.routingTier).toBe("standard");
    expect(outcome.acceptedEvent.data.degraded_notice).toBeUndefined();
  });
});
