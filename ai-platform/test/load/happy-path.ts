/**
 * Drive the full happy path under load with D2 FakeAdapter:
 * admission + credit + one R2 envelope on real Miniflare D1/R2/QUOTA_DO bindings.
 */

import {
  ConfigCache,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../../src/config-cache";
import type { CanonicalResult } from "../../src/contracts/canonical";
import type { Principal } from "../../src/identity";
import {
  createRequestRow,
  recordTerminalState,
  writePostResponseDetail,
  type AttemptInput,
  type PostResponseInput,
} from "../../src/journal";
import { load, type Manifest } from "../../src/manifest";
import { FakeAdapter } from "../../src/provider/fake";
import type { D1Spy, DoSpy, R2Spy } from "./binding-spies";
import {
  CONCURRENCY_FIXTURE,
  buildMeasurementReport,
  type LoadMeasurementReport,
} from "./measurement-report";

const FIXTURE_ORG_ID = "org-f5-load-001";
const FIXTURE_NOW_MS = Date.parse("2026-07-31T12:00:00.000Z");
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_CAPABILITY_ID = "ai.visit_summary";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_TRACE_ID = "01F5LOADTRACE00000000001";
const FIXTURE_PERIOD = "2026-08";
const FIXTURE_PROMPT_HASH = "prompt/visit-summary-system@v1";

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

type ManifestWire = Record<string, unknown>;

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

let jtiCounter = 0;
let idempotencyKeyCounter = 0;
let requestReferenceCounter = 0;

async function loadAdmissionModule(): Promise<AdmissionModule> {
  return import(/* @vite-ignore */ "../../src/admission") as Promise<AdmissionModule>;
}

async function loadCreditModule(): Promise<CreditModule> {
  return import(/* @vite-ignore */ "../../src/credit") as Promise<CreditModule>;
}

function uniqueJti(): string {
  jtiCounter += 1;
  return `f5000000-0000-4000-8000-${String(jtiCounter).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `01F5LOAD${String(idempotencyKeyCounter).padStart(14, "0")}`;
}

function uniqueRequestReference(): string {
  requestReferenceCounter += 1;
  return `AI-F5-${String(requestReferenceCounter).padStart(6, "0")}`;
}

function validManifest(): Manifest {
  const wire: ManifestWire = {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      version: FIXTURE_CAPABILITY_VERSION,
      title: "F5 load fixture",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: `ai.${FIXTURE_CAPABILITY_ID}`,
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
  return load(wire);
}

function makePrincipal(installationId: string): Principal {
  return {
    installationId,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-f5-001",
    actorId: "actor-f5-001",
    role: "clinician",
    scopes: ["ai.visit_summary"],
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

function scopeReaderForKind(reader: D1Reader, kind: ConfigEntityKind): D1Reader {
  return {
    read: (key) => reader.read(`${kind}:${key}`),
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
      JSON.stringify(["ai.visit_summary"]),
      0.8,
      "active",
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

function canonicalResult(): CanonicalResult {
  return {
    "final content": { type: "text", text: "Load fixture summary." },
    "usage counters": { input: 10, output: 20, cached: 0 },
    "provider+model actually used": { provider: "fake", model: "fake-v1" },
    "finish reason": "stop",
    "provider request id": "fake-load-req",
    "timing breakdown": { queue_ms: 1, provider_ms: 5, total_ms: 6 },
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
    providerRequestId: `fake-${attemptNo}`,
    rawBody: { completion: "Load fixture summary." },
  };
}

function buildPostResponseInput(
  requestId: string,
  installationId: string,
  requestReference: string,
): PostResponseInput {
  const attempts = [buildAttempt(1)];
  return {
    requestId,
    installationId,
    period: FIXTURE_PERIOD,
    quotaWeight: 1,
    totalTokens: 30,
    totalCost: 0.001,
    filteredContext: { "visit.chief_complaint@v1": "Headache." },
    composedPrompt: { system: "Summarise.", messages: [] },
    attempts,
    validatedResult: canonicalResult(),
    recordedAt: FIXTURE_NOW,
  };
}

function assertAdmitted(
  result: AdmissionResult,
): asserts result is AdmissionSuccess {
  if (!result.ok || result.outcome !== "admitted") {
    throw new Error(`Expected admitted outcome, got ${JSON.stringify(result)}`);
  }
}

type PreparedRequest = {
  installationId: string;
  cache: ConfigCache;
  reader: D1Reader;
};

async function prepareRequest(
  db: D1Database,
  realDo: DurableObjectNamespace,
): Promise<PreparedRequest> {
  const installationId = realDo.newUniqueId().toString();
  await seedInstallation(db, installationId);
  await seedEntitlement(db, installationId);
  const cache = new ConfigCache();
  const reader = makePlatformD1Reader(db);
  await loadConfig(
    cache,
    scopeReaderForKind(reader, "entitlements"),
    "entitlements",
    installationId,
  );
  return { installationId, cache, reader };
}

async function runSingleHappyPath(input: {
  prepared: PreparedRequest;
  admission: AdmissionModule;
  credit: CreditModule;
  bindings: LoadHappyPathBindings;
  manifest: Manifest;
}): Promise<number> {
  const { prepared, admission, credit, bindings, manifest } = input;
  const { installationId, cache, reader } = prepared;
  const principal = makePrincipal(installationId);
  const idempotencyKey = uniqueIdempotencyKey();
  const requestReference = uniqueRequestReference();

  const guardStart = performance.now();
  const admissionResult = await admission.runAdmission(
    { principal, idempotencyKey, requestReference, cache, reader },
    { DB: bindings.db, DO: bindings.do },
    { now: FIXTURE_NOW_MS },
  );
  const guardLatencyMs = performance.now() - guardStart;

  assertAdmitted(admissionResult);
  const { requestId } = admissionResult;

  const createResult = await createRequestRow(
    {
      requestId,
      requestReference,
      principal,
      manifest,
      idempotencyKey,
      traceId: FIXTURE_TRACE_ID,
    },
    bindings.db,
  );
  if (!createResult.ok) {
    throw new Error("createRequestRow failed during load happy path");
  }

  const adapter = new FakeAdapter(["success"]);
  const invokeResult = adapter.invoke({
    "ordered role-tagged message parts": [{ role: "user", content: "Summarise." }],
    "output format directive": { type: "text" },
    "sampling constraints": { temperature: 0.2 },
    "max output tokens": 256,
    "stop conditions": [],
    "tool/function declarations (reserved for future)": [],
    "stream flag": false,
    deadline: 30_000,
    "correlation ids": {
      request_reference: requestReference,
      trace_id: FIXTURE_TRACE_ID,
    },
  });
  if (invokeResult.kind !== "success") {
    throw new Error("FakeAdapter did not return success during load happy path");
  }

  await recordTerminalState(requestId, "Completed", undefined, FIXTURE_NOW, bindings.db);

  const ctx = createFakeCtx();
  writePostResponseDetail(buildPostResponseInput(requestId, installationId, requestReference), {
    db: bindings.db,
    r2: bindings.r2,
    ctx,
  });
  await ctx.drainWaitUntil();

  await credit.creditUsage(
    {
      installationId,
      requestId,
      requestReference,
      usage: { tokens: 30, cost: 0.001 },
      partial: false,
    },
    { DO: bindings.do },
  );

  return guardLatencyMs;
}

export async function runLoadHappyPath(
  bindings: LoadHappyPathBindings,
): Promise<{ report: LoadMeasurementReport }> {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;

  const manifest = validManifest();
  const admission = await loadAdmissionModule();
  const credit = await loadCreditModule();

  const prepared = await Promise.all(
    Array.from({ length: CONCURRENCY_FIXTURE }, () =>
      prepareRequest(bindings.db, bindings.realDo),
    ),
  );

  for (const request of prepared) {
    const principal = makePrincipal(request.installationId);
    await admission.runAdmission(
      {
        principal,
        idempotencyKey: uniqueIdempotencyKey(),
        requestReference: uniqueRequestReference(),
        cache: request.cache,
        reader: request.reader,
      },
      { DB: bindings.db, DO: bindings.do },
      { now: FIXTURE_NOW_MS },
    );
  }

  bindings.db.resetCounts();
  bindings.r2.resetCounts();
  bindings.do.resetCounts();

  const guardLatenciesMs: number[] = [];
  for (const request of prepared) {
    guardLatenciesMs.push(
      await runSingleHappyPath({
        prepared: request,
        admission,
        credit,
        bindings,
        manifest,
      }),
    );
  }

  const report = buildMeasurementReport({
    guardLatenciesMs,
    r2OpsTotal: bindings.r2.putCallCount(),
    doFetchesTotal: bindings.do.fetchCount(),
    d1HotPathWritesTotal: bindings.db.hotPathWriteCount(),
    requestCount: CONCURRENCY_FIXTURE,
    concurrency: CONCURRENCY_FIXTURE,
  });

  return { report };
}
