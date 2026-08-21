/**
 * Drive the full happy path under load via the production pipeline module
 * (`src/pipeline`): §6.1 stages 1–10 (`runGuard`) + FakeAdapter settle
 * (`settleHappyPath`: credit + one R2 envelope) on real Miniflare D1/R2/QUOTA_DO.
 *
 * F5_HARNESS_POOL16_v1
 *
 * One shared installation; a bounded worker pool of size
 * `Math.min(CONCURRENCY_FIXTURE, CONCURRENCY_LIMIT)` runs all 20 requests so the
 * Quota DO concurrency cap (16) is never exceeded while still measuring real
 * overlap (observed in-flight peak). No warm-up / discarded admissions.
 *
 * Prompt registry uses `import.meta.glob(..., { query: "?raw" })`, which breaks
 * under vitest-pool-workers text module rules. Mock the registry with the same
 * prompt bytes so production `composeRequest` still runs for stage 10.
 */

import { vi } from "vitest";

const { resolveArtifactMock, resolvePromptVersionMock } = vi.hoisted(() => {
  const artifactByRef: Record<string, string> = {
    "clinic.visit_summary/system@v1":
      "You are a clinical documentation assistant for outpatient visit summaries. Your role is advisory only: produce clear, professional prose that helps clinicians review and refine visit documentation before it enters the record.\n\nDraft a concise visit summary based on the supplied clinical context and the clinician's stated intent. Use neutral, factual language organized for quick review by a licensed clinician who retains full clinical responsibility.\n\nYour output is displayed for advisory review only. It does not enter the medical record until a clinician explicitly accepts it.\n",
    "clinic.visit_summary/rules-visit-summary@v1":
      "## Visit summary business rules\n\n- Do not state or imply a definitive diagnosis. Use observational language (\"presents with\", \"reports\") and defer diagnostic conclusions to the reviewing clinician.\n- Do not recommend specific medications, dosages, or treatment plans. Frame any therapeutic discussion as documentation assistance, not prescription.\n- Do not fabricate clinical findings, test results, or patient history not present in the supplied context.\n- Flag missing or ambiguous information rather than inferring undocumented details.\n- Maintain patient confidentiality: include only information relevant to the summary.\n- If the supplied context is insufficient for a meaningful summary, state what is missing instead of generating speculative content.\n",
    "clinic.visit_summary/template-visit-summary@v1":
      '<key name="visit.chief_complaint@v1" shape="visit.chief_complaint@v1">\n{{visit.chief_complaint@v1}}\n</key>\n',
  };

  function fnv1a(content: string): string {
    let hash = 0x811c9dc5;
    for (let index = 0; index < content.length; index += 1) {
      hash ^= content.charCodeAt(index);
      hash = Math.imul(hash, 0x01000193);
    }
    return (hash >>> 0).toString(16).padStart(8, "0");
  }

  return {
    resolveArtifactMock(ref: string): string | undefined {
      return artifactByRef[ref];
    },
    resolvePromptVersionMock(manifest: {
      "Prompt binding": {
        systemInstructionArtifactRef: unknown;
        businessRuleFragmentRefs?: unknown;
        contextRenderingTemplateRef?: unknown;
      };
    }): string {
      const binding = manifest["Prompt binding"];
      const refs = [
        String(binding.systemInstructionArtifactRef),
        ...(Array.isArray(binding.businessRuleFragmentRefs)
          ? binding.businessRuleFragmentRefs.map(String)
          : []),
        ...(binding.contextRenderingTemplateRef != null &&
        String(binding.contextRenderingTemplateRef).length > 0
          ? [String(binding.contextRenderingTemplateRef)]
          : []),
      ];
      const parts = refs
        .map((ref) => artifactByRef[ref])
        .filter((content): content is string => content !== undefined);
      return fnv1a(parts.join("\0"));
    },
  };
});

vi.mock("../../src/prompt/registry", () => ({
  resolveArtifact: resolveArtifactMock,
  resolvePromptVersion: resolvePromptVersionMock,
}));

import {
  ConfigCache,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../../src/config-cache";
import { VISIT_CHIEF_COMPLAINT_V1 } from "../../src/context";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "../../src/capability";
import type { Principal } from "../../src/identity";
import { load, type Manifest } from "../../src/manifest";
import { composeRequest, promptScaffoldByteLength } from "../../src/prompt/composer";
import { resolvePromptVersion } from "../../src/prompt/registry";
import { runGuard, settleHappyPath } from "../../src/pipeline";
import { CONCURRENCY_LIMIT } from "../../src/quota-do";
import type { RateLimitBindings } from "../../src/rate-limit";
import type { D1Spy, DoSpy, R2Spy } from "./binding-spies";
import {
  CONCURRENCY_FIXTURE,
  buildMeasurementReport,
  type LoadMeasurementReport,
} from "./measurement-report";

const FIXTURE_ORG_ID = "org-f5-load-001";
const FIXTURE_BRANCH_ID = "branch-f5-001";
const FIXTURE_ACTOR_ID = "actor-f5-001";
const FIXTURE_NOW_MS = Date.parse("2026-07-31T12:00:00.000Z");
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_CAPABILITY_ID = "clinic.visit_summary";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_PROVIDER_ID = "fake";
const FIXTURE_PERIOD = "2026-08";
const FIXTURE_TRACE_ID = "01F5LOADTRACE00000000001";
const FIXTURE_INSTALLATION_ID = "inst-f5-load-shared-001";
const FIXTURE_USER_INTENT =
  "Draft a concise visit summary emphasising the chief complaint and timeline.";

/** Pool size — never exceed Quota DO CONCURRENCY_LIMIT on one installation. */
export const LOAD_POOL_SIZE = Math.min(CONCURRENCY_FIXTURE, CONCURRENCY_LIMIT);

type D1Row = Record<string, unknown>;
type ManifestWire = Record<string, unknown>;

type RequestCounters = {
  jti: number;
  idempotency: number;
  reference: number;
};

type FakeExecutionContext = {
  waitUntil: (promise: Promise<unknown>) => void;
  drainWaitUntil: () => Promise<void>;
};

export type LoadHappyPathBindings = {
  db: D1Spy;
  r2: R2Spy;
  do: DoSpy;
  realDo: DurableObjectNamespace;
};

function createRequestCounters(): RequestCounters {
  return { jti: 0, idempotency: 0, reference: 0 };
}

function uniqueJti(counters: RequestCounters): string {
  counters.jti += 1;
  return `f5000000-0000-4000-8000-${String(counters.jti).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(counters: RequestCounters): string {
  counters.idempotency += 1;
  return `01F5LOAD${String(counters.idempotency).padStart(14, "0")}`;
}

function uniqueRequestReference(counters: RequestCounters): string {
  counters.reference += 1;
  return `AI-F5-${String(counters.reference).padStart(6, "0")}`;
}

function makePrincipal(
  installationId: string,
  counters: RequestCounters,
): Principal {
  return {
    installationId,
    organizationId: FIXTURE_ORG_ID,
    branchId: FIXTURE_BRANCH_ID,
    actorId: FIXTURE_ACTOR_ID,
    role: "clinician",
    scopes: ["ai.visit_summary"],
    jti: uniqueJti(counters),
    iat: FIXTURE_NOW_MS - 30_000,
    exp: FIXTURE_NOW_MS + 300_000,
    ver: "1",
  };
}

function fixtureContext(): Record<string, unknown> {
  return {
    org: FIXTURE_ORG_ID,
    branch: FIXTURE_BRANCH_ID,
    [VISIT_CHIEF_COMPLAINT_V1]: {
      visit_id: "550e8400-e29b-41d4-a716-446655440000",
      complaint: "Persistent headache for three days.",
      recorded_at: "2026-07-31T12:00:00Z",
    },
  };
}

function visitSummaryManifest(): Manifest {
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
        key: VISIT_CHIEF_COMPLAINT_V1,
        required: true,
        shapeRef: VISIT_CHIEF_COMPLAINT_V1,
        maxSize: 4_096,
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: "clinic.visit_summary/system@v1",
      businessRuleFragmentRefs: ["clinic.visit_summary/rules-visit-summary@v1"],
      contextRenderingTemplateRef:
        "clinic.visit_summary/template-visit-summary@v1",
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
      perRequestTokenCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/visit-summary@v1",
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

      switch (kind) {
        case "installations": {
          const row = await db
            .prepare(
              "SELECT installation_id, org_id, display_name, status, region, enrolled_at FROM installation WHERE installation_id = ?",
            )
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "entitlements": {
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
        case "grants": {
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
        case "kill_switches":
          return "miss";
        default:
          return "miss";
      }
    },
  };
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

async function seedInstallation(db: D1Database, installationId: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      "F5 Load Clinic",
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(db: D1Database, installationId: string): Promise<void> {
  await db
    .prepare(
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
      JSON.stringify([FIXTURE_CAPABILITY_ID]),
      0.8,
      "active",
    )
    .run();
}

async function seedGrant(db: D1Database, installationId: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      `grant-${installationId}-${FIXTURE_CAPABILITY_ID}`,
      `installation:${installationId}`,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      FIXTURE_NOW,
      null,
      FIXTURE_NOW,
      "operator-f5-load",
    )
    .run();
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

async function runBoundedPool<T>(
  workItems: readonly T[],
  poolSize: number,
  worker: (item: T) => Promise<{ guardLatencyMs: number }>,
): Promise<{
  guardLatenciesMs: number[];
  observedConcurrency: number;
}> {
  const guardLatenciesMs = new Array<number>(workItems.length);
  let nextIndex = 0;
  let inFlight = 0;
  let observedConcurrency = 0;

  async function runWorker(): Promise<void> {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= workItems.length) {
        return;
      }
      inFlight += 1;
      observedConcurrency = Math.max(observedConcurrency, inFlight);
      try {
        const result = await worker(workItems[index]!);
        guardLatenciesMs[index] = result.guardLatencyMs;
      } finally {
        inFlight -= 1;
      }
    }
  }

  const workers = Math.min(poolSize, workItems.length);
  await Promise.all(Array.from({ length: workers }, () => runWorker()));
  return { guardLatenciesMs, observedConcurrency };
}

export async function runLoadHappyPath(
  bindings: LoadHappyPathBindings,
): Promise<{ report: LoadMeasurementReport }> {
  void bindings.realDo;

  const counters = createRequestCounters();
  const installationId = FIXTURE_INSTALLATION_ID;

  setCapabilityRegistry(createCapabilityRegistry([visitSummaryManifest()]), {
    replace: true,
  });

  await seedInstallation(bindings.db, installationId);
  await seedEntitlement(bindings.db, installationId);
  await seedGrant(bindings.db, installationId);

  const cache = new ConfigCache();
  const reader = makePlatformD1Reader(bindings.db);
  await loadConfig(cache, reader, "entitlements", installationId);
  await loadConfig(
    cache,
    reader,
    "grants",
    `${installationId}/${FIXTURE_CAPABILITY_ID}`,
  );

  const rateLimit = createAlwaysAllowRateLimitBindings(bindings.db);
  const suppliedContext = fixtureContext();

  const workItems = Array.from({ length: CONCURRENCY_FIXTURE }, () => {
    const requestReference = uniqueRequestReference(counters);
    const idempotencyKey = uniqueIdempotencyKey(counters);
    const principal = makePrincipal(installationId, counters);
    const bodyText = JSON.stringify({
      capability_id: FIXTURE_CAPABILITY_ID,
      capability_version: FIXTURE_CAPABILITY_VERSION,
      user_intent: FIXTURE_USER_INTENT,
      context: suppliedContext,
    });
    return { requestReference, idempotencyKey, principal, bodyText };
  });

  bindings.db.resetCounts();
  bindings.r2.resetCounts();
  bindings.do.resetCounts();

  const wallStart = performance.now();
  const { guardLatenciesMs, observedConcurrency } = await runBoundedPool(
    workItems,
    LOAD_POOL_SIZE,
    async (item) => {
      return bindings.do.withRequest(item.requestReference, () =>
        bindings.r2.withRequest(item.requestReference, async () => {
          const guard = await runGuard(
            {
              bodyText: item.bodyText,
              principal: item.principal,
              capabilityId: FIXTURE_CAPABILITY_ID,
              capabilityVersion: FIXTURE_CAPABILITY_VERSION,
              entitlement: {
                capabilityId: FIXTURE_CAPABILITY_ID,
                capabilityVersion: FIXTURE_CAPABILITY_VERSION,
                minimumPlanTier: "standard",
                providerId: FIXTURE_PROVIDER_ID,
              },
              suppliedContext,
              userIntent: FIXTURE_USER_INTENT,
              idempotencyKey: item.idempotencyKey,
              requestReference: item.requestReference,
              traceId: FIXTURE_TRACE_ID,
              cache,
              reader,
              now: FIXTURE_NOW_MS,
              composeRequest,
              promptScaffoldByteLength,
              resolvePromptVersion,
            },
            {
              DB: bindings.db,
              DO: bindings.do,
              rateLimit,
            },
          );

          if (!guard.ok) {
            throw new Error(
              `Guard failed at stage ${guard.stage}: ${guard.code} (${item.requestReference})`,
            );
          }

          const settled = await settleHappyPath(
            {
              requestId: guard.requestId,
              requestReference: item.requestReference,
              installationId,
              composed: guard.composed,
              filteredContext: guard.filteredContext,
              period: FIXTURE_PERIOD,
              quotaWeight: 1,
              recordedAt: FIXTURE_NOW,
            },
            {
              DB: bindings.db,
              R2: bindings.r2,
              DO: bindings.do,
              ctx: createFakeCtx(),
            },
          );

          if (!settled.ok) {
            throw new Error(
              `Settle failed: ${settled.code} (${item.requestReference})`,
            );
          }

          return { guardLatencyMs: guard.guardLatencyMs };
        }),
      );
    },
  );
  const wallClockMs = performance.now() - wallStart;

  const d1HotPathWritesTotal = bindings.db.hotPathWriteCount();
  const d1HotPathWritesMaxPerRequest =
    CONCURRENCY_FIXTURE > 0 ? d1HotPathWritesTotal / CONCURRENCY_FIXTURE : 0;

  const report = buildMeasurementReport({
    guardLatenciesMs,
    r2OpsTotal: bindings.r2.classAOpCount(),
    r2OpsMaxPerRequest: bindings.r2.maxR2ClassAOpsPerRequest(),
    doFetchesTotal: bindings.do.fetchCount(),
    doFetchesMaxPerRequest: bindings.do.maxDoFetchesPerRequest(),
    d1HotPathWritesTotal,
    d1HotPathWritesMaxPerRequest,
    // All requests share one installation — total DO fetches == pinned installation.
    doFetchesForPinnedInstallation: bindings.do.fetchCount(),
    wallClockMs,
    pinnedInstallationDurationMs: wallClockMs,
    observedConcurrency,
    requestCount: CONCURRENCY_FIXTURE,
  });

  return { report };
}
