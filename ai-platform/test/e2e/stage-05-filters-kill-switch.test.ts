import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertSseSequence,
  bootstrapE2e,
  clearConfigCache,
  controlFetch,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  generateTestKeypair,
  getAiRequest,
  getAttempts,
  getAudits,
  getR2Json,
  getRoutingPolicy,
  mintAat,
  newScenario,
  OPERATOR_BEARER,
  POLICY_ID,
  postRequest,
  promotePolicy,
  publishPolicy,
  REQUEST_REFERENCE_PATTERN,
  resetE2eState,
  visitSummaryInvokeBody,
  type HttpResult,
  type InvokeResult,
  type Scenario,
} from "./harness";

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

async function invokeVisitSummary(
  scenario: Scenario,
  idempotencyKey: string,
): Promise<InvokeResult> {
  const token = await mintAat(scenario);
  return postRequest(scenario, {
    token,
    idempotencyKey,
    body: visitSummaryInvokeBody(scenario, {
      user_intent: "Summarize today's visit for the chart.",
    }),
  });
}

async function invokeAccepted(
  scenario: Scenario,
  idempotencyKey: string,
): Promise<{ result: InvokeResult; ref: string }> {
  const result = await invokeVisitSummary(scenario, idempotencyKey);
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  assertSseSequence(result.events, ["accepted"]);
  const ref = String(result.events[0]?.data.request_reference);
  expect(ref).toMatch(REQUEST_REFERENCE_PATTERN);
  return { result, ref };
}

async function loadDecision(ref: string): Promise<{
  row: Record<string, unknown>;
  decision: RoutingDecision;
}> {
  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  expect(row?.routing_decision).toBeTruthy();
  return {
    row: row as Record<string, unknown>,
    decision: JSON.parse(String(row?.routing_decision)) as RoutingDecision,
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

  const { row, decision } = await loadDecision(ref);
  expect(decision.chain).toEqual([]);
  expect(row.state).toBe("Failed");
  expect(row.terminal_error_code).toBe("provider_unavailable");

  const attempts = await getAttempts(String(row.request_id));
  expect(attempts).toHaveLength(1);
  expect(attempts[0]?.outcome).toBe("terminal_failure");
  expect(attempts[0]?.error_code).toBe("provider_unavailable");
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

    const a = await invokeAccepted(instA, "idem-s05-075a-0001");
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

    const b = await invokeAccepted(instB, "idem-s05-075b-0001");
    const { decision: decisionB } = await loadDecision(b.ref);
    expect(decisionB.effective_cost_class).toBe("standard");
    expect(decisionB.cost_class_source).toBe("manifest");
    expect(decisionB.excluded ?? []).toEqual([]);
    expect(decisionB.chain).toEqual(BOTH_FIXTURE_CHAIN);
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

  it.skip(
    "S05-078 — Inputs the bundled manifest set cannot produce (multi-language match clause; Register 5 #26 router-seam; selectCandidateChain is not on the frozen harness barrel)",
    () => {},
  );

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

    const { ref } = await invokeAccepted(scenario, "idem-s05-079-0001");
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

  it.skip(
    "S05-082 — Inputs the bundled manifest set cannot produce (non-hardwired cost sources; Register 5 #26 router-seam; selectCandidateChain is not on the frozen harness barrel)",
    () => {},
  );

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
