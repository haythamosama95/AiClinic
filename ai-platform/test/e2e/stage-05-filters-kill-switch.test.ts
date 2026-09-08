import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertSseSequence,
  bootstrapE2e,
  CAPABILITY_ID,
  clearConfigCache,
  controlFetch,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
  generateTestKeypair,
  getAiRequest,
  getAttempts,
  getAudits,
  getUsageEvents,
  getR2Json,
  getRoutingPolicy,
  isolateConfigCache,
  mintAat,
  newScenario,
  OPERATOR_BEARER,
  POLICY_ID,
  POLICY_REF,
  postRequest,
  promotePolicy,
  publishPolicy,
  queryOne,
  REQUEST_REFERENCE_PATTERN,
  resetE2eState,
  visitSummaryInvokeBody,
  type HttpResult,
  type InvokeResult,
  type Scenario,
} from "./harness";

// HARNESS-GAP: Register 5 #26 — createD1ConfigReader / selectCandidateChain
// are production exports but not on the frozen harness barrel.
import { createD1ConfigReader } from "../../src/config-cache";
import {
  selectCandidateChain,
  type CostClass,
  type RouterContext,
} from "../../src/router";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

/** Catalog inst-A (canary / override cohort). */
const INST_A = "018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f";
/** Catalog inst-B (non-override sibling). */
const INST_B = "018e4f2a-9d4c-7a2b-8e3f-6d7b9c1e2f3a";

const WRONG_CANARY_BEARER = "op_wrong-secret-9f8d7c6b5a";

const CATCH_ALL_REQUIRES = {
  structured_output: false,
  min_context_window: 0,
  languages: [] as string[],
};

const FIXTURE_FEATURES = {
  structured_output: true,
  min_context_window: 128000,
  languages: ["en"],
  latency_class: "standard",
  cost_class: "standard",
} as const;

type RoutingChainEntry = {
  ordinal: number;
  provider_id: string;
  model_id: string;
  max_attempts: number;
  timeout_ms: number;
};

type RoutingExcludedEntry = {
  provider_id: string;
  model_id: string;
  reason_code: string;
};

type RoutingDecision = {
  policy_id?: string;
  policy_version?: number;
  rule_id?: string;
  effective_cost_class?: string;
  cost_class_source?: string;
  routing_tier?: string;
  required_features?: Record<string, unknown>;
  chain?: RoutingChainEntry[];
  excluded?: RoutingExcludedEntry[];
};

function fixtureFeatures(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return { ...FIXTURE_FEATURES, ...overrides };
}

function fixtureTarget(
  providerId: string,
  modelId: string,
  featureOverrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    provider_id: providerId,
    model_id: modelId,
    features: fixtureFeatures(featureOverrides),
    max_attempts: 2,
    timeout_ms: 30000,
  };
}

const DEEPSEEK_FLASH = fixtureTarget("deepseek", "deepseek-v4-flash");
const GEMINI_FLASH = fixtureTarget("gemini", "gemini-3.5-flash");

const GEMINI_ONLY_CHAIN: RoutingChainEntry[] = [
  {
    ordinal: 0,
    provider_id: "gemini",
    model_id: "gemini-3.5-flash",
    max_attempts: 2,
    timeout_ms: 30000,
  },
];

const BOTH_FIXTURE_CHAIN: RoutingChainEntry[] = [
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

function catchAllRule(
  targets: Record<string, unknown>[],
  opts: {
    ruleId?: string;
    requires?: Record<string, unknown>;
    match?: Record<string, unknown>;
  } = {},
): Record<string, unknown> {
  return {
    rule_id: opts.ruleId ?? "platform-default-fallback",
    match: opts.match ?? {},
    requires: opts.requires ?? CATCH_ALL_REQUIRES,
    targets,
  };
}

function policyDocument(
  version: number,
  opts: {
    rules?: Record<string, unknown>[];
    targets?: Record<string, unknown>[];
    overrides?: Record<string, unknown>[];
    requires?: Record<string, unknown>;
    ruleId?: string;
  } = {},
): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: POLICY_ID,
    policy_version: version,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules:
      opts.rules ??
      [
        catchAllRule(opts.targets ?? [DEEPSEEK_FLASH, GEMINI_FLASH], {
          ruleId: opts.ruleId,
          requires: opts.requires,
        }),
      ],
    overrides: opts.overrides ?? [],
  };
}

const PLATFORM_DEFAULT_V1 = policyDocument(1);

async function scenarioWithId(installationId: string): Promise<Scenario> {
  const scenario = await newScenario();
  const keypair = await generateTestKeypair();
  return { ...scenario, installationId, kid: keypair.kid, keypair };
}

async function enrollAndEntitle(
  scenario: Scenario,
  entitle = DEFAULT_ENTITLE_PAYLOAD,
): Promise<void> {
  const keypair = await generateTestKeypair(scenario.kid);
  scenario.keypair = keypair;
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(scenario, entitle);
  expect(entitled.status).toBe(200);
}

async function publishAndPromote(
  document: Record<string, unknown>,
): Promise<void> {
  const version = String(document.policy_version);
  const published = await publishPolicy(POLICY_ID, version, document);
  expect(published.status).toBe(200);
  const promoted = await promotePolicy(POLICY_ID, version);
  expect(promoted.status).toBe(200);
}

/**
 * Pool TTL is 100 ms. Parallel files share isolateConfigCache and call
 * clear(); preload→consult can then miss
 * `active_routing_policy:routing/standard` (ConfigCacheMissError → Failed
 * with routing_decision null). Raise TTL and re-stamp the just-promoted
 * policy immediately before POST so the post-accept consult cannot miss.
 */
const SERVE_CACHE_TTL_MS = 30_000;

async function loadServingPolicyRow(
  policyVersion?: string,
): Promise<Record<string, unknown>> {
  const row = policyVersion
    ? await getRoutingPolicy(POLICY_ID, policyVersion)
    : await queryOne(
        `SELECT * FROM routing_policy
         WHERE policy_id = ? AND status = 'active'
         ORDER BY active_from DESC, rowid DESC LIMIT 1`,
        [POLICY_ID],
      );
  expect(row?.status).toBe("active");
  const pointer = String(row!.content_pointer ?? "");
  const document = await getR2Json(pointer);
  return { ...row!, document };
}

function pinServingRoutingPolicy(
  policyRow: Record<string, unknown>,
  installationIds: readonly string[],
): void {
  isolateConfigCache.setTtlMs(SERVE_CACHE_TTL_MS);
  isolateConfigCache.remember("active_routing_policy", POLICY_REF, policyRow);
  for (const installationId of installationIds) {
    isolateConfigCache.remember(
      "active_routing_policy",
      `${POLICY_REF}/${installationId}`,
      policyRow,
    );
  }
}

async function invokeVisitSummary(
  scenario: Scenario,
  idempotencyKey: string,
  policyRow: Record<string, unknown>,
): Promise<InvokeResult> {
  const token = await mintAat(scenario);
  pinServingRoutingPolicy(policyRow, [scenario.installationId]);
  return postRequest(scenario, {
    token,
    idempotencyKey,
    body: visitSummaryInvokeBody(scenario, {
      user_intent: "Summarize today's visit for the chart.",
    }),
  });
}

async function invokeAcceptedPinned(
  scenario: Scenario,
  idempotencyKey: string,
  policyRow: Record<string, unknown>,
): Promise<{ result: InvokeResult; ref: string }> {
  const result = await invokeVisitSummary(scenario, idempotencyKey, policyRow);
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  assertSseSequence(result.events, ["accepted"]);
  const ref = String(result.events[0]?.data.request_reference);
  expect(ref).toMatch(REQUEST_REFERENCE_PATTERN);
  return { result, ref };
}

async function invokeAccepted(
  scenario: Scenario,
  idempotencyKey: string,
): Promise<{ result: InvokeResult; ref: string }> {
  const policyRow = await loadServingPolicyRow();
  return invokeAcceptedPinned(scenario, idempotencyKey, policyRow);
}

/**
 * Routing and Failed settlement run in waitUntil after SSE frames
 * (worker.ts createProductionEventSource → persistRoutingDecision L987,
 * recordTerminalState L1204). Poll D1; do not weaken the asserts.
 */
async function waitForAiRequest(
  ref: string,
  predicate: (row: Record<string, unknown>) => boolean,
  label: string,
  timeoutMs = 8000,
): Promise<Record<string, unknown>> {
  const started = Date.now();
  let row: Record<string, unknown> | null = null;
  while (Date.now() - started < timeoutMs) {
    row = await getAiRequest(ref);
    if (row && predicate(row)) {
      return row;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(
    `timed out waiting for ${label} (last state=${String(row?.state)} routing_decision=${row?.routing_decision == null ? "null" : "set"})`,
  );
}

async function loadDecision(ref: string): Promise<{
  row: Record<string, unknown>;
  decision: RoutingDecision;
}> {
  const row = await waitForAiRequest(
    ref,
    (candidate) => Boolean(candidate.routing_decision),
    `ai_request.routing_decision for ${ref}`,
  );
  expect(row).not.toBeNull();
  expect(row.routing_decision).toBeTruthy();
  return {
    row,
    decision: JSON.parse(String(row.routing_decision)) as RoutingDecision,
  };
}

function failedEvent(result: InvokeResult): Record<string, unknown> | undefined {
  return result.events.find((event) => event.event === "failed")?.data;
}

async function expectEmptyChainProviderUnavailable(
  result: InvokeResult,
  ref: string,
): Promise<{
  row: Record<string, unknown>;
  decision: RoutingDecision;
  attempts: Record<string, unknown>[];
}> {
  assertSseSequence(result.events, ["accepted", "failed"], "subsequence");
  const failed = failedEvent(result);
  expect(failed?.code).toBe("provider_unavailable");
  expect(failed?.code).not.toBe("internal_error");

  const settled = await waitForAiRequest(
    ref,
    (candidate) =>
      candidate.state === "Failed" && Boolean(candidate.routing_decision),
    `ai_request Failed + routing_decision for ${ref}`,
  );
  expect(settled.routing_decision).toBeTruthy();
  const decision = JSON.parse(
    String(settled.routing_decision),
  ) as RoutingDecision;
  expect(decision.chain).toEqual([]);
  expect(settled.state).toBe("Failed");
  expect(settled.terminal_error_code).toBe("provider_unavailable");
  const row = settled;

  const attempts = await getAttempts(String(row.request_id));
  expect(attempts).toHaveLength(1);
  expect(attempts[0]?.outcome).toBe("terminal_failure");
  expect(attempts[0]?.error_code).toBe("provider_unavailable");

  const usage = await getUsageEvents(String(row.request_id));
  expect(usage).toHaveLength(1);
  expect(usage[0]?.tokens).toBe(0);
  expect(Number(usage[0]?.cost)).toBe(0);
  return { row, decision, attempts };
}

async function syntheticAttemptPayload(
  row: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const pointer =
    typeof row.payload_pointer === "string" && row.payload_pointer.length > 0
      ? row.payload_pointer
      : `request/${String(row.request_id)}/envelope`;
  const envelope = await getR2Json(pointer);
  const attempts = envelope.attempts as unknown[];
  expect(Array.isArray(attempts)).toBe(true);
  expect(attempts.length).toBeGreaterThan(0);
  return attempts[0] as Record<string, unknown>;
}

async function armProviderKill(target: string): Promise<HttpResult> {
  const result = await controlFetch("/control/kill-switches/arm", {
    auth: { bearer: OPERATOR_BEARER },
    body: { scope: "provider", target },
  });
  expect(result.status).toBe(200);
  clearConfigCache();
  return result;
}

const CONVENTIONS_REQUIREMENTS = {
  structured_output_required: false,
  min_context_window: 32000,
  languages: ["en"] as readonly string[],
  latency_class: "standard",
};

async function loadActivePolicyFromReader(
  installationId: string,
): Promise<Record<string, unknown>> {
  const reader = createD1ConfigReader(env.DB, env.R2);
  const row = await reader.read(
    `active_routing_policy:${POLICY_REF}/${installationId}`,
  );
  expect(row).not.toBe("miss");
  return row as Record<string, unknown>;
}

function selectChainViaSeam(
  preloadedPolicy: Record<string, unknown>,
  overrides: {
    installationId: string;
    requirements?: Partial<RouterContext["requirements"]>;
    manifestCostClass?: CostClass;
    entitlementMaxCostClass?: CostClass;
  },
) {
  return selectCandidateChain({
    cache: isolateConfigCache,
    policyCacheKey: POLICY_REF,
    preloadedPolicy,
    context: {
      installationId: overrides.installationId,
      capabilityId: CAPABILITY_ID,
      routingTier: "standard",
      requirements: {
        ...CONVENTIONS_REQUIREMENTS,
        ...overrides.requirements,
      },
      manifestCostClass: overrides.manifestCostClass ?? "standard",
      entitlementMaxCostClass: overrides.entitlementMaxCostClass ?? "premium",
      killedProviderIds: [],
    },
  });
}

describe("Stage 05 — routing filters, kill switch, and invoke auth (S05-063…S05-085)", () => {
  it("S05-063 — Target window below the required floor", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(6, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", {
            min_context_window: 16000,
          }),
          GEMINI_FLASH,
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-063-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "context_window_too_small",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);

    await publishAndPromote(
      policyDocument(60, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", {
            min_context_window: 32000,
          }),
          GEMINI_FLASH,
        ],
      }),
    );
    const boundary = await invokeAccepted(scenario, "idem-s05-063-boundary");
    const { decision: exactFloor } = await loadDecision(boundary.ref);
    expect(
      exactFloor.excluded?.some(
        (entry) =>
          entry.provider_id === "deepseek" &&
          entry.reason_code === "context_window_too_small",
      ),
    ).toBe(false);
    expect(exactFloor.chain?.[0]).toEqual(BOTH_FIXTURE_CHAIN[0]);
  });

  it("S05-064 — Non-array languages fail closed as feature_unsupported", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(7, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", { languages: "en" }),
          GEMINI_FLASH,
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-064-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "feature_unsupported",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-065 — Target missing a required language", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(8, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", { languages: ["fr"] }),
          GEMINI_FLASH,
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-065-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "language_unsupported",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-066 — Latency class mismatch maps to feature_unsupported", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(10, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", {
            latency_class: "batch",
          }),
          GEMINI_FLASH,
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-066-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "feature_unsupported",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-067 — Unknown cost_class fails closed as feature_unsupported", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(11, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", { cost_class: "cheap" }),
          GEMINI_FLASH,
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-067-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "feature_unsupported",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-068 — Cost class above the effective ceiling", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(12, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-pro", { cost_class: "premium" }),
          GEMINI_FLASH,
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-068-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.effective_cost_class).toBe("standard");
    expect(decision.cost_class_source).toBe("manifest");
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-pro",
      reason_code: "cost_class_excluded",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-069 — Provider kill switch fails over to the next target", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(PLATFORM_DEFAULT_V1);

    await armProviderKill("deepseek");

    const { ref } = await invokeAccepted(scenario, "idem-s05-069-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded).toEqual([
      {
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "kill_switch",
      },
    ]);
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-070 — Kill switch on every target yields empty chain", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(PLATFORM_DEFAULT_V1);

    await armProviderKill("deepseek");
    await armProviderKill("gemini");

    const { result, ref } = await invokeAccepted(scenario, "idem-s05-070-0001");
    const { row, decision } = await expectEmptyChainProviderUnavailable(
      result,
      ref,
    );
    expect(decision.excluded).toEqual([
      {
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "kill_switch",
      },
      {
        provider_id: "gemini",
        model_id: "gemini-3.5-flash",
        reason_code: "kill_switch",
      },
    ]);

    const payload = await syntheticAttemptPayload(row);
    expect(payload.payload).toEqual({
      reason: "no_provider_attempt",
      excluded: decision.excluded,
    });
  });

  it("S05-071 — All targets feature-excluded yield provider_unavailable", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(13, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", {
            min_context_window: 8000,
          }),
        ],
      }),
    );

    const { result, ref } = await invokeAccepted(scenario, "idem-s05-071-0001");
    const { row, decision } = await expectEmptyChainProviderUnavailable(
      result,
      ref,
    );
    expect(decision.excluded).toEqual([
      {
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "context_window_too_small",
      },
    ]);

    const payload = await syntheticAttemptPayload(row);
    expect(payload.payload).toEqual({
      reason: "no_provider_attempt",
      excluded: decision.excluded,
    });
  });

  it("S05-072 — Installation override exclude_providers", async () => {
    const instA = await scenarioWithId(INST_A);
    const instB = await scenarioWithId(INST_B);
    await enrollAndEntitle(instA);
    await enrollAndEntitle(instB);
    await publishAndPromote(
      policyDocument(14, {
        overrides: [
          { installation_id: INST_A, exclude_providers: ["deepseek"] },
        ],
      }),
    );

    const a = await invokeAccepted(instA, "idem-s05-072a-0001");
    const { decision: decisionA } = await loadDecision(a.ref);
    expect(decisionA.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "installation_excluded",
    });
    expect(decisionA.chain).toEqual(GEMINI_ONLY_CHAIN);

    const b = await invokeAccepted(instB, "idem-s05-072b-0001");
    const { decision: decisionB } = await loadDecision(b.ref);
    expect(decisionB.excluded ?? []).toEqual([]);
    expect(decisionB.chain).toEqual(BOTH_FIXTURE_CHAIN);
  });

  it("S05-073 — Installation override pin_target", async () => {
    const instA = await scenarioWithId(INST_A);
    await enrollAndEntitle(instA);
    await publishAndPromote(
      policyDocument(15, {
        overrides: [
          {
            installation_id: INST_A,
            pin_target: {
              provider_id: "gemini",
              model_id: "gemini-3.5-flash",
            },
          },
        ],
      }),
    );

    const { ref } = await invokeAccepted(instA, "idem-s05-073-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
    expect(decision.excluded).toEqual([
      {
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "installation_excluded",
      },
    ]);
  });

  it("S05-074 — pin_target absent from the matched rule yields empty chain", async () => {
    const instA = await scenarioWithId(INST_A);
    await enrollAndEntitle(instA);
    await publishAndPromote(
      policyDocument(16, {
        overrides: [
          {
            installation_id: INST_A,
            pin_target: { provider_id: "openai", model_id: "gpt-6" },
          },
        ],
      }),
    );

    const { result, ref } = await invokeAccepted(instA, "idem-s05-074-0001");
    const { row, decision } = await expectEmptyChainProviderUnavailable(
      result,
      ref,
    );
    expect(decision.excluded).toEqual([
      {
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "installation_excluded",
      },
      {
        provider_id: "gemini",
        model_id: "gemini-3.5-flash",
        reason_code: "installation_excluded",
      },
    ]);

    const payload = await syntheticAttemptPayload(row);
    expect(
      (payload.payload as { reason?: string } | undefined)?.reason,
    ).toBe("no_provider_attempt");
  });

  it("S05-075 — Override force_cost_class lowers the ceiling", async () => {
    const instA = await scenarioWithId(INST_A);
    const instB = await scenarioWithId(INST_B);
    await enrollAndEntitle(instA);
    await enrollAndEntitle(instB);
    await publishAndPromote(
      policyDocument(17, {
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", {
            cost_class: "economy",
          }),
          fixtureTarget("gemini", "gemini-3.5-flash", {
            cost_class: "standard",
          }),
        ],
        overrides: [
          { installation_id: INST_A, force_cost_class: "economy" },
        ],
      }),
    );

    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(SERVE_CACHE_TTL_MS);
    try {
      const policyRow = await loadServingPolicyRow("17");
      const a = await invokeAcceptedPinned(instA, "idem-s05-075a-0001", policyRow);
      const { decision: decisionA } = await loadDecision(a.ref);
      expect(decisionA.effective_cost_class).toBe("economy");
      expect(decisionA.cost_class_source).toBe("installation_override");
      expect(decisionA.excluded).toEqual([
        {
          provider_id: "gemini",
          model_id: "gemini-3.5-flash",
          reason_code: "cost_class_excluded",
        },
      ]);
      expect(decisionA.chain).toEqual([
        {
          ordinal: 0,
          provider_id: "deepseek",
          model_id: "deepseek-v4-flash",
          max_attempts: 2,
          timeout_ms: 30000,
        },
      ]);

      const b = await invokeAcceptedPinned(instB, "idem-s05-075b-0001", policyRow);
      const { decision: decisionB } = await loadDecision(b.ref);
      expect(decisionB.effective_cost_class).toBe("standard");
      expect(decisionB.cost_class_source).toBe("manifest");
      expect(decisionB.excluded ?? []).toEqual([]);
      expect(decisionB.chain).toEqual(BOTH_FIXTURE_CHAIN);
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
    }
  });

  it("S05-076 — capability_ids clause skips a non-matching rule", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(18, {
        rules: [
          catchAllRule([DEEPSEEK_FLASH], {
            ruleId: "image-only",
            match: { capability_ids: ["clinic.image_caption"] },
          }),
          catchAllRule([DEEPSEEK_FLASH, GEMINI_FLASH]),
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-076-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.rule_id).toBe("platform-default-fallback");
    expect(decision.chain).toEqual(BOTH_FIXTURE_CHAIN);
  });

  it("S05-077 — Tiers clause skips a standard-only rule when degraded", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario, {
      ...DEFAULT_ENTITLE_PAYLOAD,
      request_quota: 2,
      soft_threshold: 0.5,
    });
    await publishAndPromote(
      policyDocument(19, {
        rules: [
          catchAllRule([DEEPSEEK_FLASH], {
            ruleId: "standard-tier-only",
            match: { tiers: ["standard"] },
          }),
          catchAllRule([DEEPSEEK_FLASH, GEMINI_FLASH]),
        ],
      }),
    );

    const standard = await invokeAccepted(scenario, "idem-s05-077-control");
    const { row: standardRow, decision: standardDecision } = await loadDecision(
      standard.ref,
    );
    expect(standardRow.routing_tier).toBe("standard");
    expect(standardDecision.routing_tier).toBe("standard");
    expect(standardDecision.rule_id).toBe("standard-tier-only");
    expect(standardDecision.chain).toEqual([
      {
        ordinal: 0,
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        max_attempts: 2,
        timeout_ms: 30000,
      },
    ]);

    const degraded = await invokeAccepted(scenario, "idem-s05-077-0001");
    const { row: degradedRow, decision: degradedDecision } = await loadDecision(
      degraded.ref,
    );
    expect(degradedRow.routing_tier).toBe("degraded");
    expect(degradedDecision.routing_tier).toBe("degraded");
    expect(degradedDecision.rule_id).toBe("platform-default-fallback");
  });

  it("S05-078 — Rule match: languages clause requires every required language", async () => {
    const instA = await scenarioWithId(INST_A);
    await enrollAndEntitle(instA);
    await publishAndPromote(
      policyDocument(20, {
        rules: [
          catchAllRule([DEEPSEEK_FLASH], {
            ruleId: "en-only",
            match: { languages: ["en"] },
          }),
          catchAllRule([DEEPSEEK_FLASH, GEMINI_FLASH]),
        ],
      }),
    );

    const preloadedPolicy = await loadActivePolicyFromReader(INST_A);

    const multiLanguage = selectChainViaSeam(preloadedPolicy, {
      installationId: INST_A,
      requirements: { languages: ["en", "ar"] },
    });
    expect(multiLanguage.routing_decision.rule_id).toBe(
      "platform-default-fallback",
    );

    const englishOnly = selectChainViaSeam(preloadedPolicy, {
      installationId: INST_A,
      requirements: { languages: ["en"] },
    });
    expect(englishOnly.routing_decision.rule_id).toBe("en-only");
  });

  it("S05-079 — Rule requires floor raises min_context_window", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(21, {
        requires: {
          structured_output: false,
          min_context_window: 64000,
          languages: [],
        },
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", {
            min_context_window: 32000,
          }),
          fixtureTarget("gemini", "gemini-3.5-flash", {
            min_context_window: 128000,
          }),
        ],
      }),
    );

    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(SERVE_CACHE_TTL_MS);
    try {
      const policyRow = await loadServingPolicyRow("21");
      const { ref } = await invokeAcceptedPinned(
        scenario,
        "idem-s05-079-0001",
        policyRow,
      );
      const { decision } = await loadDecision(ref);
      expect(decision.excluded?.[0]).toEqual({
        provider_id: "deepseek",
        model_id: "deepseek-v4-flash",
        reason_code: "context_window_too_small",
      });
      expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
      expect(decision.required_features).toEqual({
        structured_output_required: false,
        min_context_window: 32000,
        languages: ["en"],
        latency_class: "standard",
      });
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
    }
  });

  it("S05-080 — Rule requires structured_output forces the OR floor", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(22, {
        requires: {
          structured_output: true,
          min_context_window: 0,
          languages: [],
        },
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", {
            structured_output: false,
          }),
          fixtureTarget("gemini", "gemini-3.5-flash", {
            structured_output: true,
          }),
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-080-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "feature_unsupported",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-081 — Rule requires languages union adds a missing language", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(
      policyDocument(23, {
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: ["ar"],
        },
        targets: [
          fixtureTarget("deepseek", "deepseek-v4-flash", { languages: ["en"] }),
          fixtureTarget("gemini", "gemini-3.5-flash", {
            languages: ["en", "ar"],
          }),
        ],
      }),
    );

    const { ref } = await invokeAccepted(scenario, "idem-s05-081-0001");
    const { decision } = await loadDecision(ref);
    expect(decision.excluded?.[0]).toEqual({
      provider_id: "deepseek",
      model_id: "deepseek-v4-flash",
      reason_code: "language_unsupported",
    });
    expect(decision.chain).toEqual(GEMINI_ONLY_CHAIN);
  });

  it("S05-082 — Effective cost class: three-source minimum with source-priority tie-break", async () => {
    const instA = await scenarioWithId(INST_A);
    await enrollAndEntitle(instA);
    const threeCostTargets = [
      fixtureTarget("deepseek", "econ", { cost_class: "economy" }),
      fixtureTarget("gemini", "std", { cost_class: "standard" }),
      fixtureTarget("anthropic", "prem", { cost_class: "premium" }),
    ];
    await publishAndPromote(policyDocument(24, { targets: threeCostTargets }));

    const preloadedPolicy = await loadActivePolicyFromReader(INST_A);
    const expectedChain = [
      {
        ordinal: 0,
        provider_id: "deepseek",
        model_id: "econ",
        max_attempts: 2,
        timeout_ms: 30000,
      },
      {
        ordinal: 1,
        provider_id: "gemini",
        model_id: "std",
        max_attempts: 2,
        timeout_ms: 30000,
      },
    ];
    const premiumExcluded = [
      {
        provider_id: "anthropic",
        model_id: "prem",
        reason_code: "cost_class_excluded",
      },
    ];

    const manifestWins = selectChainViaSeam(preloadedPolicy, {
      installationId: INST_A,
      manifestCostClass: "standard",
      entitlementMaxCostClass: "premium",
    });
    expect(manifestWins.routing_decision.effective_cost_class).toBe("standard");
    expect(manifestWins.routing_decision.cost_class_source).toBe("manifest");
    expect(manifestWins.routing_decision.chain).toEqual(expectedChain);
    expect(manifestWins.routing_decision.excluded).toEqual(premiumExcluded);

    const entitlementCap = selectChainViaSeam(preloadedPolicy, {
      installationId: INST_A,
      manifestCostClass: "premium",
      entitlementMaxCostClass: "standard",
    });
    expect(entitlementCap.routing_decision.effective_cost_class).toBe(
      "standard",
    );
    expect(entitlementCap.routing_decision.cost_class_source).toBe(
      "entitlement_cap",
    );
    expect(entitlementCap.routing_decision.chain).toEqual(expectedChain);

    const tied = selectChainViaSeam(preloadedPolicy, {
      installationId: INST_A,
      manifestCostClass: "standard",
      entitlementMaxCostClass: "standard",
    });
    expect(tied.routing_decision.effective_cost_class).toBe("standard");
    expect(tied.routing_decision.cost_class_source).toBe("entitlement_cap");
    expect(tied.routing_decision.chain).toEqual(expectedChain);

    await publishAndPromote(
      policyDocument(25, {
        targets: threeCostTargets,
        overrides: [
          { installation_id: INST_A, force_cost_class: "premium" },
        ],
      }),
    );
    const withOverride = await loadActivePolicyFromReader(INST_A);
    const overrideCannotRaise = selectChainViaSeam(withOverride, {
      installationId: INST_A,
      manifestCostClass: "standard",
      entitlementMaxCostClass: "premium",
    });
    expect(overrideCannotRaise.routing_decision.effective_cost_class).toBe(
      "standard",
    );
    expect(overrideCannotRaise.routing_decision.chain).toEqual(expectedChain);
    expect(overrideCannotRaise.routing_decision.excluded).toEqual(
      premiumExcluded,
    );
  });

  it("S05-083 — Chain ordinals and routing_decision persistence", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(PLATFORM_DEFAULT_V1);

    const { ref } = await invokeAccepted(scenario, "idem-s05-083-0001");
    const { decision } = await loadDecision(ref);
    expect(decision).toEqual({
      policy_id: "standard",
      policy_version: 1,
      rule_id: "platform-default-fallback",
      effective_cost_class: "standard",
      cost_class_source: "manifest",
      routing_tier: "standard",
      required_features: {
        structured_output_required: false,
        min_context_window: 32000,
        languages: ["en"],
        latency_class: "standard",
      },
      chain: BOTH_FIXTURE_CHAIN,
      excluded: [],
    });
    expect(decision).not.toHaveProperty("max_parallel_attempts");
  });

  it("S05-084 — Canary with a wrong operator bearer", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    const published = await publishPolicy(POLICY_ID, "1", PLATFORM_DEFAULT_V1);
    expect(published.status).toBe(200);

    const auditsBefore = await count("control_audit");
    const result = await controlFetch(
      "/control/routing-policies/standard/versions/1/canary",
      {
        auth: { bearer: WRONG_CANARY_BEARER },
        body: {
          installation_ids: ["8f3c2a1e-4b5d-4e6f-9a0b-1c2d3e4f5a6b"],
        },
      },
    );

    expect(result.status).toBe(401);
    expect(result.headers.get("content-type")).toContain("application/json");
    expect(result.json).toEqual({ error: "unauthorized" });
    expect(result.text).toBe(JSON.stringify({ error: "unauthorized" }));

    const row = await getRoutingPolicy(POLICY_ID, "1");
    expect(row?.status).toBe("published");
    expect(row?.canary_installation_ids).toBeNull();
    expect(await getAudits("routing_policy_canary", "standard@1")).toEqual([]);
    expect(await count("control_audit")).toBe(auditsBefore);
  });

  it("S05-085 — Rollback with a wrong operator bearer", async () => {
    const scenario = await newScenario();
    await enrollAndEntitle(scenario);
    await publishAndPromote(PLATFORM_DEFAULT_V1);

    const auditsBefore = await count("control_audit");
    const result = await controlFetch(
      "/control/routing-policies/standard/versions/1/rollback",
      {
        auth: { bearer: WRONG_CANARY_BEARER },
        body: {},
      },
    );

    expect(result.status).toBe(401);
    expect(result.headers.get("content-type")).toContain("application/json");
    expect(result.json).toEqual({ error: "unauthorized" });
    expect(result.text).toBe(JSON.stringify({ error: "unauthorized" }));

    const row = await getRoutingPolicy(POLICY_ID, "1");
    expect(row?.status).toBe("active");
    expect(await getAudits("routing_policy_rollback", "standard@1")).toEqual([]);
    expect(await count("control_audit")).toBe(auditsBefore);
  });
});
