import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertSseSequence,
  bootstrapE2e,
  canaryPolicy,
  CAPABILITY_ID,
  clearConfigCache,
  controlFetch,
  count,
  enrollInstallation,
  entitleInstallation,
  env,
  getAiRequest,
  getAttempts,
  getAudits,
  getR2Json,
  getRoutingPolicy,
  getUsageEvents,
  isolateConfigCache,
  newScenario,
  OPERATOR_ID,
  postRequest,
  promotePolicy,
  publishPolicy,
  r2Exists,
  REQUEST_REFERENCE_PATTERN,
  resetE2eState,
  rollbackPolicy,
  seedSql,
  visitSummaryInvokeBody,
  type HttpResult,
  type InvokeResult,
  type Scenario,
} from "./harness";

// HARNESS-GAP: Register 5 #26 — createD1ConfigReader / selectCandidateChain
// are production exports but not on the frozen harness barrel.
import { createD1ConfigReader } from "../../src/config-cache";
import { selectCandidateChain } from "../../src/router";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const INST_A = "018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f";
const INST_B = "018e4f2a-9d4c-7a2b-8e3f-6d7b9c1e2f3a";
const POLICY_ID = "standard";
const STANDARD_V1_POINTER = "control/routing-policy/standard/1.json";
const STANDARD_V2_POINTER = "control/routing-policy/standard/2.json";

/** Verbatim `ai-platform/control/routing-policy/platform-default/1.json`. */
const PLATFORM_DEFAULT_DOCUMENT = {
  schema_version: 1,
  policy_id: "standard",
  policy_version: 1,
  defaults: {
    cost_class: "standard",
    max_parallel_attempts: 1,
  },
  rules: [
    {
      rule_id: "platform-default-fallback",
      match: {},
      requires: {
        structured_output: false,
        min_context_window: 0,
        languages: [] as string[],
      },
      targets: [
        {
          provider_id: "deepseek",
          model_id: "deepseek-v4-flash",
          features: {
            structured_output: true,
            min_context_window: 128000,
            languages: ["en"],
            latency_class: "standard",
            cost_class: "standard",
          },
          max_attempts: 2,
          timeout_ms: 30000,
        },
        {
          provider_id: "gemini",
          model_id: "gemini-3.5-flash",
          features: {
            structured_output: true,
            min_context_window: 128000,
            languages: ["en"],
            latency_class: "standard",
            cost_class: "standard",
          },
          max_attempts: 2,
          timeout_ms: 30000,
        },
      ],
    },
  ],
  overrides: [] as unknown[],
};

const GEMINI_FIXTURE_TARGET = {
  provider_id: "gemini",
  model_id: "gemini-3.5-flash",
  features: {
    structured_output: true,
    min_context_window: 128000,
    languages: ["en"],
    latency_class: "standard",
    cost_class: "standard",
  },
  max_attempts: 2,
  timeout_ms: 30000,
};

/** S05-051 / S05-054 canary document: single gemini target, rule_id `v2-catch-all`. */
const V2_CANARY_DOCUMENT = {
  schema_version: 1,
  policy_id: "standard",
  policy_version: 2,
  defaults: {
    cost_class: "standard",
    max_parallel_attempts: 1,
  },
  rules: [
    {
      rule_id: "v2-catch-all",
      match: {},
      requires: {
        structured_output: false,
        min_context_window: 0,
        languages: [] as string[],
      },
      targets: [GEMINI_FIXTURE_TARGET],
    },
  ],
  overrides: [] as unknown[],
};

/** S05-022 seed for S05-057: identity-valid, no catch-all, wrong-typed features. */
const NO_CATCH_ALL_V9_DOCUMENT = {
  schema_version: 1,
  policy_id: "standard",
  policy_version: 9,
  defaults: { cost_class: "standard", max_parallel_attempts: 1 },
  rules: [
    {
      rule_id: "narrow",
      match: { capability_ids: ["clinic.nonexistent"] },
      requires: {
        structured_output: false,
        min_context_window: 0,
        languages: [] as string[],
      },
      targets: [
        {
          provider_id: "deepseek",
          model_id: "deepseek-v4-flash",
          features: {
            structured_output: "yes",
            min_context_window: "big",
            languages: "en",
            latency_class: "standard",
            cost_class: "cheap",
          },
          max_attempts: 2,
          timeout_ms: 30000,
        },
      ],
    },
  ],
  overrides: [] as unknown[],
};

const FIXTURE_V1_CHAIN = [
  {
    ordinal: 0,
    provider_id: "deepseek",
    model_id: "deepseek-v4-flash",
    max_attempts: 2,
    timeout_ms: 30000,
  },
  {
    ordinal: 1,
    provider_id: "gemini",
    model_id: "gemini-3.5-flash",
    max_attempts: 2,
    timeout_ms: 30000,
  },
];

const ROUTER_CODES_NEVER_ON_WIRE = [
  "policy_identity_mismatch",
  "unsupported_schema_version",
  "missing_catch_all",
  "no_matching_rule",
  "active_routing_policy",
] as const;

function platformDefaultAt(version: number): Record<string, unknown> {
  return { ...PLATFORM_DEFAULT_DOCUMENT, policy_version: version };
}

function rollbackPath(version: string, policyId = POLICY_ID): string {
  return `/control/routing-policies/${policyId}/versions/${version}/rollback`;
}

function assertOkEmpty(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({});
}

function assertControlError(
  result: HttpResult,
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error });
}

async function catalogScenario(installationId: string): Promise<Scenario> {
  const scenario = await newScenario();
  return { ...scenario, installationId };
}

async function enrollCatalog(installationId: string): Promise<Scenario> {
  const scenario = await catalogScenario(installationId);
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  return scenario;
}

async function enrollAndEntitle(installationId: string): Promise<Scenario> {
  const scenario = await enrollCatalog(installationId);
  const entitled = await entitleInstallation(scenario);
  expect(entitled.status).toBe(200);
  return scenario;
}

async function publishStandard(
  document: Record<string, unknown>,
): Promise<HttpResult> {
  const version = String(document.policy_version);
  const result = await publishPolicy(POLICY_ID, version, document);
  expect(result.status).toBe(200);
  return result;
}

async function promoteStandard(version: string): Promise<HttpResult> {
  const result = await promotePolicy(POLICY_ID, version);
  expect(result.status).toBe(200);
  return result;
}

async function publishThenPromote(
  document: Record<string, unknown>,
): Promise<void> {
  await publishStandard(document);
  await promoteStandard(String(document.policy_version));
}

/** S05-035 then S05-036: v1 superseded, v2 active. */
async function setupV1SupersededV2Active(): Promise<void> {
  await publishThenPromote(platformDefaultAt(1));
  await publishThenPromote(platformDefaultAt(2));
}

/** S05-035 + S05-023 shape on v2: v1 active, v2 canary for inst-A. */
async function setupV1ActiveV2CanaryA(
  canaryDocument: Record<string, unknown> = platformDefaultAt(2),
): Promise<void> {
  await publishThenPromote(platformDefaultAt(1));
  await publishStandard(canaryDocument);
  const canary = await canaryPolicy(POLICY_ID, "2", [INST_A]);
  expect(canary.status).toBe(200);
}

async function invokeVisitSummary(
  scenario: Scenario,
  idempotencyKey: string,
): Promise<InvokeResult> {
  return postRequest(scenario, {
    idempotencyKey,
    body: visitSummaryInvokeBody(scenario, {
      user_intent: "Summarize today's visit for the chart.",
    }),
  });
}

function acceptedReference(result: InvokeResult): string {
  const accepted = result.events.find((event) => event.event === "accepted");
  expect(accepted).toBeDefined();
  const ref = String(accepted?.data.request_reference ?? "");
  expect(ref).toMatch(REQUEST_REFERENCE_PATTERN);
  return ref;
}

function failedEvent(result: InvokeResult) {
  const failed = result.events.find((event) => event.event === "failed");
  expect(failed).toBeDefined();
  return failed!;
}

function assertAccepted(result: InvokeResult): string {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  assertSseSequence(result.events, ["accepted"]);
  return acceptedReference(result);
}

function assertAcceptedThenFailedInternalError(result: InvokeResult): string {
  const ref = assertAccepted(result);
  assertSseSequence(result.events, ["accepted", "failed"], "subsequence");
  const failed = failedEvent(result);
  expect(failed.data.code).toBe("internal_error");
  for (const code of ROUTER_CODES_NEVER_ON_WIRE) {
    expect(failed.data.code).not.toBe(code);
  }
  return ref;
}

function parseRoutingDecision(
  row: Record<string, unknown> | null,
): Record<string, unknown> | null {
  const raw = row?.routing_decision;
  if (raw == null) {
    return null;
  }
  if (typeof raw === "string") {
    return JSON.parse(raw) as Record<string, unknown>;
  }
  expect(typeof raw).toBe("object");
  return raw as Record<string, unknown>;
}

/**
 * SSE `failed` is pushed (and the stream closed) before waitUntil settlement
 * finishes (`worker.ts` catch → `pushFailedTerminal` then
 * `settlePostAcceptInternalError`; `persistRoutingDecision` is likewise in
 * that background task). Under the parallel suite the harness 150 ms flush
 * is not always enough; poll D1 rather than weakening assertions.
 */
async function waitForAiRequest(
  ref: string,
  predicate: (row: Record<string, unknown>) => boolean,
  timeoutMs = 8000,
): Promise<Record<string, unknown>> {
  const started = Date.now();
  let row: Record<string, unknown> | null = null;
  while (Date.now() - started < timeoutMs) {
    row = await getAiRequest(ref);
    if (row != null && predicate(row)) {
      return row;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(
    `timed out waiting for ai_request ${ref} (state=${String(row?.state)}, routing_decision=${row?.routing_decision == null ? "null" : "set"})`,
  );
}

async function waitForPersistedDecision(
  ref: string,
): Promise<Record<string, unknown>> {
  const row = await waitForAiRequest(
    ref,
    (current) => current.routing_decision != null,
  );
  const decision = parseRoutingDecision(row);
  expect(decision).not.toBeNull();
  return decision as Record<string, unknown>;
}

function envelopePointer(row: Record<string, unknown>): string {
  if (typeof row.payload_pointer === "string" && row.payload_pointer.length > 0) {
    return row.payload_pointer;
  }
  return `request/${String(row.request_id)}/envelope`;
}

/**
 * Post-accept `internal_error` settlement runs in waitUntil after SSE `failed`.
 * Poll until the C-01 synthetic attempt, usage_event, and R2 envelope are all
 * present — the same gap class that let missing-handoff settlement drop them.
 */
async function assertPostAcceptInternalError(ref: string): Promise<void> {
  const started = Date.now();
  const timeoutMs = 8000;
  let row: Record<string, unknown> | null = null;
  let attempts: Record<string, unknown>[] = [];
  let usage: Record<string, unknown>[] = [];
  let pointer = "";
  let envelopeReady = false;
  while (Date.now() - started < timeoutMs) {
    row = await getAiRequest(ref);
    if (row != null && row.state === "Failed") {
      const requestId = String(row.request_id);
      attempts = await getAttempts(requestId);
      usage = await getUsageEvents(requestId);
      pointer = envelopePointer(row);
      envelopeReady = await r2Exists(pointer);
      if (attempts.length === 1 && usage.length === 1 && envelopeReady) {
        break;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  expect(row).not.toBeNull();
  expect(row!.state).toBe("Failed");
  expect(row!.terminal_error_code).toBe("internal_error");
  expect(row!.routing_decision).toBeNull();

  expect(attempts).toHaveLength(1);
  expect(attempts[0]?.outcome).toBe("terminal_failure");
  expect(attempts[0]?.error_code).toBe("internal_error");

  expect(usage).toHaveLength(1);
  expect(usage[0]?.tokens).toBe(0);
  expect(Number(usage[0]?.cost)).toBe(0);

  expect(envelopeReady).toBe(true);
  const envelope = await getR2Json(pointer);
  const envelopeAttempts = envelope.attempts as Array<{
    payload?: { reason?: string };
  }>;
  expect(envelopeAttempts[0]?.payload?.reason).toBe("no_provider_attempt");
}

describe("Stage 05 — rollback, serving, and post-accept routing failures (S05-042…S05-062)", () => {
  it("S05-042 — Rollback a canary version back to published", async () => {
    await enrollCatalog(INST_A);
    await setupV1ActiveV2CanaryA();
    const v1Before = await getRoutingPolicy(POLICY_ID, "1");
    const v2BytesBefore = JSON.stringify(await getR2Json(STANDARD_V2_POINTER));

    const result = await rollbackPolicy(POLICY_ID, "2");

    assertOkEmpty(result);

    const v2 = await getRoutingPolicy(POLICY_ID, "2");
    expect(v2?.status).toBe("published");
    expect(v2?.canary_installation_ids).toBeNull();
    expect(await getRoutingPolicy(POLICY_ID, "1")).toEqual(v1Before);
    expect(v1Before?.status).toBe("active");
    expect(await count("routing_policy", "status = ?", ["canary"])).toBe(0);

    const audits = await getAudits("routing_policy_rollback", "standard@2");
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.action).toBe("routing_policy_rollback");
    expect(audits[0]?.target).toBe("standard@2");
    expect(audits[0]?.before_pointer).toBe("standard@2");
    expect(audits[0]?.after_pointer).toBe("standard@1");

    expect(JSON.stringify(await getR2Json(STANDARD_V2_POINTER))).toBe(
      v2BytesBefore,
    );
  });

  it("S05-043 — Rollback a canary version with no active version", async () => {
    await enrollCatalog(INST_A);
    await publishStandard(platformDefaultAt(1));
    const canary = await canaryPolicy(POLICY_ID, "1", [INST_A]);
    expect(canary.status).toBe(200);

    const result = await rollbackPolicy(POLICY_ID, "1");

    assertOkEmpty(result);

    const row = await getRoutingPolicy(POLICY_ID, "1");
    expect(row?.status).toBe("published");
    expect(row?.canary_installation_ids).toBeNull();

    const audits = await getAudits("routing_policy_rollback", "standard@1");
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.before_pointer).toBe("standard@1");
    expect(audits[0]?.after_pointer).toBeNull();
  });

  it("S05-044 — Rollback an active version with a superseded prior", async () => {
    await setupV1SupersededV2Active();

    const result = await rollbackPolicy(POLICY_ID, "2");

    assertOkEmpty(result);

    const v2 = await getRoutingPolicy(POLICY_ID, "2");
    expect(v2?.status).toBe("superseded");
    const v1 = await getRoutingPolicy(POLICY_ID, "1");
    expect(v1?.status).toBe("active");

    const audits = await getAudits("routing_policy_rollback", "standard@2");
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.target).toBe("standard@2");
    expect(audits[0]?.before_pointer).toBe("standard@2");
    expect(audits[0]?.after_pointer).toBe("standard@1");
  });

  it("S05-045 — Rollback an active version with no superseded prior", async () => {
    await publishThenPromote(platformDefaultAt(1));
    const rowBefore = await getRoutingPolicy(POLICY_ID, "1");

    const result = await rollbackPolicy(POLICY_ID, "1");

    assertControlError(result, 409, "illegal_policy_transition");
    expect(await getRoutingPolicy(POLICY_ID, "1")).toEqual(rowBefore);
    expect(rowBefore?.status).toBe("active");
    expect(await getAudits("routing_policy_rollback", "standard@1")).toEqual(
      [],
    );
  });

  it("S05-046 — Rollback a published version", async () => {
    await enrollCatalog(INST_A);
    await setupV1ActiveV2CanaryA();
    await publishStandard(platformDefaultAt(3));
    const v1Before = await getRoutingPolicy(POLICY_ID, "1");
    const v2Before = await getRoutingPolicy(POLICY_ID, "2");
    const v3Before = await getRoutingPolicy(POLICY_ID, "3");
    expect(v3Before?.status).toBe("published");
    expect(v2Before?.status).toBe("canary");

    const result = await rollbackPolicy(POLICY_ID, "3");

    assertControlError(result, 409, "illegal_policy_transition");
    expect(await getRoutingPolicy(POLICY_ID, "1")).toEqual(v1Before);
    expect(await getRoutingPolicy(POLICY_ID, "2")).toEqual(v2Before);
    expect(await getRoutingPolicy(POLICY_ID, "3")).toEqual(v3Before);
    expect(await getAudits("routing_policy_rollback", "standard@3")).toEqual(
      [],
    );
  });

  it("S05-047 — Rollback a superseded version", async () => {
    await setupV1SupersededV2Active();
    const v1Before = await getRoutingPolicy(POLICY_ID, "1");
    const v2Before = await getRoutingPolicy(POLICY_ID, "2");
    expect(v1Before?.status).toBe("superseded");
    expect(v2Before?.status).toBe("active");

    const result = await rollbackPolicy(POLICY_ID, "1");

    assertControlError(result, 409, "illegal_policy_transition");
    expect(await getRoutingPolicy(POLICY_ID, "1")).toEqual(v1Before);
    expect(await getRoutingPolicy(POLICY_ID, "2")).toEqual(v2Before);
    expect(await getAudits("routing_policy_rollback", "standard@1")).toEqual(
      [],
    );
  });

  it("S05-048 — Rollback an unknown policy version", async () => {
    await publishStandard(platformDefaultAt(1));
    const v1Before = await getRoutingPolicy(POLICY_ID, "1");
    expect(await getRoutingPolicy(POLICY_ID, "77")).toBeNull();

    const result = await rollbackPolicy(POLICY_ID, "77");

    assertControlError(result, 404, "policy_version_not_found");
    expect(await getRoutingPolicy(POLICY_ID, "1")).toEqual(v1Before);
    expect(await getRoutingPolicy(POLICY_ID, "77")).toBeNull();
    expect(await getAudits("routing_policy_rollback", "standard@77")).toEqual(
      [],
    );
  });

  it("S05-049 — Rollback without operator auth", async () => {
    await publishStandard(platformDefaultAt(1));
    const rowBefore = await getRoutingPolicy(POLICY_ID, "1");

    const result = await controlFetch(rollbackPath("1"), { auth: "none" });

    assertControlError(result, 401, "unauthorized");
    expect(await getRoutingPolicy(POLICY_ID, "1")).toEqual(rowBefore);
    expect(await getAudits("routing_policy_rollback", "standard@1")).toEqual(
      [],
    );
  });

  it("S05-050 — Published-but-never-promoted policy is not served", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await publishStandard(platformDefaultAt(1));
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-050-0001");

    const ref = assertAcceptedThenFailedInternalError(result);
    await assertPostAcceptInternalError(ref);
  });

  it("S05-051 — Canary installation served canary version; sibling served active", async () => {
    const instA = await enrollAndEntitle(INST_A);
    const instB = await enrollAndEntitle(INST_B);
    await setupV1ActiveV2CanaryA(V2_CANARY_DOCUMENT);
    await clearConfigCache();

    const resultA = await invokeVisitSummary(instA, "idem-s05-051a-0001");
    const resultB = await invokeVisitSummary(instB, "idem-s05-051b-0001");

    const refA = assertAccepted(resultA);
    const refB = assertAccepted(resultB);

    const decisionA = await waitForPersistedDecision(refA);
    expect(decisionA).toMatchObject({
      policy_version: 2,
      rule_id: "v2-catch-all",
      chain: [
        {
          ordinal: 0,
          provider_id: "gemini",
          model_id: "gemini-3.5-flash",
          max_attempts: 2,
          timeout_ms: 30000,
        },
      ],
    });

    const decisionB = await waitForPersistedDecision(refB);
    expect(decisionB).toMatchObject({
      policy_version: 1,
      rule_id: "platform-default-fallback",
      chain: FIXTURE_V1_CHAIN,
    });
  });

  it("S05-052 — Malformed canary_installation_ids JSON falls through to active", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await publishThenPromote(platformDefaultAt(1));
    await publishStandard(platformDefaultAt(2));
    await seedSql([
      {
        sql: "UPDATE routing_policy SET status='canary', canary_installation_ids='not-json{' WHERE policy_id='standard' AND version='2'",
      },
    ]);
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-052-0001");

    const ref = assertAccepted(result);
    const decision = await waitForPersistedDecision(ref);
    expect(decision.policy_version).toBe(1);
  });

  it("S05-053 — Active row whose R2 object is missing", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await publishThenPromote(platformDefaultAt(1));
    await env.R2.delete(STANDARD_V1_POINTER);
    expect(await r2Exists(STANDARD_V1_POINTER)).toBe(false);
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-053-0001");

    const ref = assertAcceptedThenFailedInternalError(result);
    await assertPostAcceptInternalError(ref);
    // HARNESS-GAP: isolate console is not captured; routing_policy_r2_miss is not asserted.
  });

  it("S05-054 — Canary R2 miss does not fall back to active", async () => {
    const instA = await enrollAndEntitle(INST_A);
    const instB = await enrollAndEntitle(INST_B);
    await setupV1ActiveV2CanaryA(V2_CANARY_DOCUMENT);
    await env.R2.delete(STANDARD_V2_POINTER);
    expect(await r2Exists(STANDARD_V2_POINTER)).toBe(false);
    expect(await r2Exists(STANDARD_V1_POINTER)).toBe(true);
    await clearConfigCache();

    const resultA = await invokeVisitSummary(instA, "idem-s05-054a-0001");
    const resultB = await invokeVisitSummary(instB, "idem-s05-054b-0001");

    const refA = assertAcceptedThenFailedInternalError(resultA);
    await assertPostAcceptInternalError(refA);

    const refB = assertAccepted(resultB);
    const decisionB = await waitForPersistedDecision(refB);
    expect(decisionB.policy_version).toBe(1);
    expect(decisionB.rule_id).toBe("platform-default-fallback");
    // HARNESS-GAP: isolate console is not captured; routing_policy_r2_miss is not asserted.
  });

  it("S05-055 — R2 document identity overwritten out-of-band", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await publishThenPromote(platformDefaultAt(1));
    const tampered = platformDefaultAt(2);
    await env.R2.put(STANDARD_V1_POINTER, JSON.stringify(tampered), {
      httpMetadata: { contentType: "application/json" },
    });
    expect(await getR2Json(STANDARD_V1_POINTER)).toMatchObject({
      policy_id: "standard",
      policy_version: 2,
    });
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-055-0001");

    const ref = assertAcceptedThenFailedInternalError(result);
    await assertPostAcceptInternalError(ref);
  });

  it("S05-056 — Unsupported schema_version in served document", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await publishThenPromote({
      ...PLATFORM_DEFAULT_DOCUMENT,
      policy_version: 3,
      schema_version: 2,
    });
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-056-0001");

    const ref = assertAcceptedThenFailedInternalError(result);
    await assertPostAcceptInternalError(ref);
  });

  it("S05-057 — Served document without a catch-all last rule", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await publishThenPromote(NO_CATCH_ALL_V9_DOCUMENT);
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-057-0001");

    const ref = assertAcceptedThenFailedInternalError(result);
    await assertPostAcceptInternalError(ref);
  });

  it("S05-058 — no_matching_rule is unreachable through the serving path", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await setupV1ActiveV2CanaryA(V2_CANARY_DOCUMENT);
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-058-0001");

    const ref = assertAccepted(result);
    for (const event of result.events) {
      expect(event.data.code).not.toBe("no_matching_rule");
    }
    const row = await getAiRequest(ref);
    expect(row).not.toBeNull();
    const decision = parseRoutingDecision(row);
    expect(decision).not.toBeNull();
    expect(decision?.rule_id).toBe("v2-catch-all");
  });

  it("S05-059 — Config-cache staleness window after rollback", async () => {
    // Pool TTL is 0 (no cross-request cache). Raise a short TTL so the v2
    // warm entry survives rollback, then wait it out — real expiry, not
    // setTtlMs(30_000) + clearConfigCache(). Window must cover SSE drain.
    const staleTtlMs = 2_000;
    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(staleTtlMs);
    try {
      const instA = await enrollAndEntitle(INST_A);
      await setupV1SupersededV2Active();

      const warm = await invokeVisitSummary(instA, "idem-s05-059-warm-0001");
      const warmRef = assertAccepted(warm);
      const warmDecision = await waitForPersistedDecision(warmRef);
      expect(warmDecision.policy_version).toBe(2);

      const rolled = await controlFetch(rollbackPath("2"), { body: {} });
      assertOkEmpty(rolled);
      expect((await getRoutingPolicy(POLICY_ID, "1"))?.status).toBe("active");
      expect((await getRoutingPolicy(POLICY_ID, "2"))?.status).toBe("superseded");

      const afterRollback = await invokeVisitSummary(
        instA,
        "idem-s05-059a-0001",
      );
      const afterRollbackRef = assertAccepted(afterRollback);
      const staleDecision = await waitForPersistedDecision(afterRollbackRef);
      expect(staleDecision.policy_version).toBe(2);

      await new Promise((resolve) => setTimeout(resolve, staleTtlMs + 50));

      const fresh = await invokeVisitSummary(instA, "idem-s05-059b-0001");
      const freshRef = assertAccepted(fresh);
      const freshDecision = await waitForPersistedDecision(freshRef);
      expect(freshDecision.policy_version).toBe(1);
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
    }
  });

  it("S05-060 — Legacy @vN suffix on the policy cache key is tolerated and stripped", async () => {
    await publishThenPromote(platformDefaultAt(1));
    const reader = createD1ConfigReader(env.DB, env.R2);

    const globalSuffixed = await reader.read(
      "active_routing_policy:routing/standard@v1",
    );
    const installationSuffixed = await reader.read(
      `active_routing_policy:routing/standard@v1/${INST_A}`,
    );
    const unsuffixed = await reader.read(
      "active_routing_policy:routing/standard",
    );
    const neverPins = await reader.read(
      "active_routing_policy:routing/standard@v99",
    );

    expect(globalSuffixed).not.toBe("miss");
    expect(installationSuffixed).not.toBe("miss");
    expect(unsuffixed).not.toBe("miss");
    expect(neverPins).not.toBe("miss");

    const globalRow = globalSuffixed as Record<string, unknown>;
    const installationRow = installationSuffixed as Record<string, unknown>;
    expect(globalRow.policy_id).toBe("standard");
    expect(globalRow.version).toBe("1");
    expect(globalRow.status).toBe("active");
    expect(globalRow.document).toEqual(platformDefaultAt(1));
    expect(installationRow.policy_id).toBe(globalRow.policy_id);
    expect(installationRow.version).toBe(globalRow.version);
    expect(installationRow.content_pointer).toBe(globalRow.content_pointer);
    expect(installationRow.document).toEqual(globalRow.document);
    expect((unsuffixed as Record<string, unknown>).version).toBe("1");
    expect((neverPins as Record<string, unknown>).version).toBe("1");
    expect((neverPins as Record<string, unknown>).document).toEqual(
      globalRow.document,
    );
  });

  it("S05-061 — Target without structured_output excluded as feature_unsupported", async () => {
    await enrollAndEntitle(INST_A);
    await publishThenPromote({
      schema_version: 1,
      policy_id: "standard",
      policy_version: 4,
      defaults: { cost_class: "standard", max_parallel_attempts: 1 },
      rules: [
        {
          rule_id: "platform-default-fallback",
          match: {},
          requires: {
            structured_output: false,
            min_context_window: 0,
            languages: [] as string[],
          },
          targets: [
            {
              provider_id: "deepseek",
              model_id: "deepseek-v4-flash",
              features: {
                structured_output: false,
                min_context_window: 128000,
                languages: ["en"],
                latency_class: "standard",
                cost_class: "standard",
              },
              max_attempts: 2,
              timeout_ms: 30000,
            },
            GEMINI_FIXTURE_TARGET,
          ],
        },
      ],
      overrides: [],
    });

    const reader = createD1ConfigReader(env.DB, env.R2);
    const preloadedPolicy = await reader.read(
      `active_routing_policy:routing/standard/${INST_A}`,
    );
    expect(preloadedPolicy).not.toBe("miss");

    const { routing_decision } = selectCandidateChain({
      cache: isolateConfigCache,
      policyCacheKey: "routing/standard",
      preloadedPolicy: preloadedPolicy as Record<string, unknown>,
      context: {
        installationId: INST_A,
        capabilityId: CAPABILITY_ID,
        routingTier: "standard",
        requirements: {
          structured_output_required: true,
          min_context_window: 32000,
          languages: ["en"],
          latency_class: "standard",
        },
        manifestCostClass: "standard",
        entitlementMaxCostClass: "premium",
        killedProviderIds: [],
      },
    });

    expect(routing_decision.chain).toEqual([
      {
        ordinal: 0,
        provider_id: "gemini",
        model_id: "gemini-3.5-flash",
        max_attempts: 2,
        timeout_ms: 30000,
      },
    ]);
    expect(routing_decision.excluded).toEqual([
      {
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "feature_unsupported",
      },
    ]);
  });

  it("S05-062 — Missing/non-numeric min_context_window fails closed as feature_unsupported", async () => {
    const instA = await enrollAndEntitle(INST_A);
    await publishThenPromote({
      schema_version: 1,
      policy_id: "standard",
      policy_version: 5,
      defaults: { cost_class: "standard", max_parallel_attempts: 1 },
      rules: [
        {
          rule_id: "platform-default-fallback",
          match: {},
          requires: {
            structured_output: false,
            min_context_window: 0,
            languages: [],
          },
          targets: [
            {
              provider_id: "deepseek",
              model_id: "deepseek-v4-flash",
              features: {
                structured_output: true,
                min_context_window: "128000",
                languages: ["en"],
                latency_class: "standard",
                cost_class: "standard",
              },
              max_attempts: 2,
              timeout_ms: 30000,
            },
            GEMINI_FIXTURE_TARGET,
          ],
        },
      ],
      overrides: [],
    });
    await clearConfigCache();

    const result = await invokeVisitSummary(instA, "idem-s05-062-0001");

    const ref = assertAccepted(result);
    const decision = parseRoutingDecision(await getAiRequest(ref));
    expect(decision?.excluded).toEqual([
      {
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "feature_unsupported",
      },
    ]);
    expect(decision?.chain).toEqual([
      {
        ordinal: 0,
        provider_id: "gemini",
        model_id: "gemini-3.5-flash",
        max_attempts: 2,
        timeout_ms: 30000,
      },
    ]);
  });
});
