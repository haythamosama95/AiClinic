import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Principal } from "../src/identity";
import { load, type Manifest } from "../src/manifest";
import {
  validateContext,
  type Transcript,
  type ValidateResult,
} from "../src/context/validator";
import * as preflightModule from "../src/context/preflight";
import { composeRequest } from "../src/prompt/composer";

type ManifestWire = Record<string, unknown>;

const FIXTURE_CAPABILITY_ID = "clinic.chat_assistant";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_ORG_ID = "org-h2-001";
const FIXTURE_BRANCH_ID = "branch-h2-001";

const PERMITTED_KEY_COMPLAINT = "visit.chief_complaint@v1";
const PERMITTED_KEY_DEMOGRAPHICS = "patient.demographics@v1";
const UNPERMITTED_KEY = "medication.active_list@v1";

const nextStage = vi.fn<(payload: unknown) => void>();

function conversationalManifest(
  overrides: Partial<ManifestWire> = {},
): ManifestWire {
  return {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
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
      transcriptSizeLimit: 50_000,
    },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: "transcript",
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": {
      permittedKeySet: [PERMITTED_KEY_COMPLAINT, PERMITTED_KEY_DEMOGRAPHICS],
    },
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
      perRequestCostCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/chat@v1",
    },
    ...overrides,
  };
}

function singleShotManifest(): ManifestWire {
  return {
    Identity: {
      capabilityId: "clinic.visit_summary",
      version: "1.0.0",
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
        key: PERMITTED_KEY_COMPLAINT,
        required: true,
        shapeRef: PERMITTED_KEY_COMPLAINT,
        maxSize: 4_096,
        freshnessHint: "session",
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

function buildPrincipal(): Principal {
  return Object.freeze({
    installationId: "inst-h2-001",
    organizationId: FIXTURE_ORG_ID,
    branchId: FIXTURE_BRANCH_ID,
    actorId: "actor-h2-001",
    role: "clinician",
    scopes: Object.freeze([`ai.${FIXTURE_CAPABILITY_ID}`]),
    jti: "jti-h2-001",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
  });
}

function loadedConversationalManifest(
  overrides: Partial<ManifestWire> = {},
): Manifest {
  return load(conversationalManifest(overrides));
}

function validTranscript(): Transcript {
  return [
    { turn_ordinal: 1, kind: "user", text: "What is the chief complaint?" },
    {
      turn_ordinal: 2,
      kind: "model",
      text: "The patient reports a persistent headache.",
    },
    {
      turn_ordinal: 3,
      kind: "context_requested",
      requests: [
        {
          key: PERMITTED_KEY_COMPLAINT,
          arguments: { visit_id: "550e8400-e29b-41d4-a716-446655440000" },
        },
      ],
    },
    {
      turn_ordinal: 4,
      kind: "context_resolved",
      context: {
        [PERMITTED_KEY_COMPLAINT]: {
          visit_id: "550e8400-e29b-41d4-a716-446655440000",
          complaint: "Persistent headache for three days.",
        },
      },
    },
  ];
}

function validateConversational(
  manifest: Manifest,
  transcript: unknown,
  suppliedContext: Record<string, unknown> = {},
  legTurnOrdinal = 5,
): ValidateResult {
  return validateContext(manifest, suppliedContext, buildPrincipal(), {
    transcript,
    legTurnOrdinal,
  });
}

beforeEach(() => {
  nextStage.mockClear();
  vi.restoreAllMocks();
});

describe("valid_transcript_passes", () => {
  it("accepts a well-formed transcript with strictly increasing turn ordinals below the leg's own", () => {
    const manifest = loadedConversationalManifest();
    const transcript = validTranscript();

    const result = validateConversational(manifest, transcript);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.validatedTranscript).toEqual(transcript);
    }
  });
});

describe("out_of_order_turn_ordinal_rejected_context_invalid", () => {
  it("rejects duplicate turn ordinals with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "Hello" },
      { turn_ordinal: 1, kind: "model", text: "Hi" },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });

  it("rejects non-increasing turn ordinals with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      { turn_ordinal: 2, kind: "user", text: "Hello" },
      { turn_ordinal: 1, kind: "model", text: "Hi" },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });

  it("rejects turn ordinals not strictly less than the leg's own with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      { turn_ordinal: 5, kind: "user", text: "Hello" },
    ];

    const result = validateConversational(manifest, transcript, {}, 5);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });

  it("rejects missing turn ordinals with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [{ kind: "user", text: "Hello" }];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });

  it("rejects non-integer turn ordinals with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [{ turn_ordinal: 1.5, kind: "user", text: "Hello" }];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });
});

describe("malformed_turn_shape_rejected_context_invalid", () => {
  it("rejects a turn with no payload field", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [{ turn_ordinal: 1, kind: "user" }];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });

  it("rejects the wrong payload field for its kind", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      { turn_ordinal: 1, kind: "user", requests: [] },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });

  it("rejects a payload of the wrong type", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: 42 },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });
});

describe("unknown_turn_kind_rejected_context_invalid", () => {
  it("rejects a kind outside the four declared values with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      { turn_ordinal: 1, kind: "system", text: "Hello" },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });
});

describe("transcript_rejected_whole_not_coerced_or_dropped", () => {
  it("rejects the whole transcript when one turn is malformed", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "Valid turn" },
      { turn_ordinal: 2, kind: "bogus", text: "Bad turn" },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });
});

describe("shape_checked_before_budgets", () => {
  it("fails with context_invalid and emits no budget code when shape is bad and history limit exceeded", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 1,
        maxContextRoundsPerTurn: 3,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "One" },
      { turn_ordinal: 2, kind: "bogus", text: "Two" },
      { turn_ordinal: 3, kind: "user", text: "Three" },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
    expect(result).not.toEqual({
      ok: false,
      code: "conversation_budget_exhausted",
    });
  });
});

describe("history_turn_limit_breached_conversation_budget_exhausted", () => {
  it("yields conversation_budget_exhausted when max history turns is exceeded", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 2,
        maxContextRoundsPerTurn: 3,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "One" },
      { turn_ordinal: 2, kind: "model", text: "Two" },
      { turn_ordinal: 3, kind: "user", text: "Three" },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "conversation_budget_exhausted" });
  });
});

describe("budgets_counted_from_submitted_transcript_alone", () => {
  it("counts max history turns and context rounds only from the submitted transcript", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 1,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "One" },
      {
        turn_ordinal: 2,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_COMPLAINT, arguments: {} }],
      },
      {
        turn_ordinal: 3,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_DEMOGRAPHICS, arguments: {} }],
      },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result).toEqual({ ok: false, code: "conversation_budget_exhausted" });
  });
});

describe("context_rounds_at_tail_breached_conversation_budget_exhausted", () => {
  it("yields conversation_budget_exhausted when consecutive context_requested turns at the tail exceed the limit", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 2,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "Start" },
      {
        turn_ordinal: 2,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_COMPLAINT, arguments: {} }],
      },
      {
        turn_ordinal: 3,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_DEMOGRAPHICS, arguments: {} }],
      },
      {
        turn_ordinal: 4,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_COMPLAINT, arguments: {} }],
      },
    ];

    const result = validateConversational(manifest, transcript, {}, 5);

    expect(result).toEqual({ ok: false, code: "conversation_budget_exhausted" });
  });
});



describe("oversized_transcript_request_too_large", () => {
  it("fails existing pre-flight when serialized input includes an oversized transcript", () => {
    const manifest = loadedConversationalManifest({
      Economics: {
        maxInputTokens: 10,
        maxOutputTokens: 1_024,
        perRequestCostCeiling: 20,
        quotaWeight: 1,
      },
    });
    const transcript = validTranscript();
    const serializedInput = preflightModule.serializePreflightInput({
      filteredContext: {},
      userIntent: "x".repeat(10_000),
      transcript,
    });

    expect(serializedInput).toContain('"transcript"');
    expect(serializedInput).toContain("What is the chief complaint?");

    const result = preflightModule.runCostPreflight(manifest, serializedInput);
    expect(result).toEqual({ ok: false, code: "request_too_large" });
  });
});

describe("per_turn_cost_ceiling_uses_existing_preflight_no_new_mechanism", () => {
  it("prices transcript growth only through serializePreflightInput + runCostPreflight", async () => {
    const validatorModule = await import("../src/context/validator");
    const preflightExports = Object.keys(preflightModule);
    const validatorExports = Object.keys(validatorModule);

    expect(preflightExports).toContain("runCostPreflight");
    expect(preflightExports).toContain("estimateInputTokens");
    expect(preflightExports).toContain("serializePreflightInput");
    expect(validatorExports).not.toContain("runConversationCostTotal");
    expect(validatorExports).not.toContain("reservePreflightBudget");

    const withTranscript = preflightModule.serializePreflightInput({
      filteredContext: { a: 1 },
      userIntent: "hi",
      transcript: validTranscript(),
    });
    const withoutTranscript = preflightModule.serializePreflightInput({
      filteredContext: { a: 1 },
      userIntent: "hi",
    });
    expect(withTranscript.length).toBeGreaterThan(withoutTranscript.length);
    expect(withTranscript).toContain('"transcript"');
    expect(withoutTranscript).not.toContain('"transcript"');

    for (const exportName of validatorExports) {
      const lowered = exportName.toLowerCase();
      expect(lowered).not.toMatch(/reservation/);
      expect(lowered).not.toMatch(/conversationtotal/);
    }
  });
});

describe("trimmed_transcript_accepted_bounded_by_admission", () => {
  it("accepts a trimmed transcript with turn_ordinal gaps for budget counting", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 3,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "First" },
      { turn_ordinal: 5, kind: "model", text: "After trim" },
    ];

    const result = validateConversational(manifest, transcript, {}, 6);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.validatedTranscript).toHaveLength(2);
    }
  });
});

describe("no_per_request_server_state_from_h2", () => {
  it("introduces no conversation store or per-request durable/session exports from the validator", async () => {
    const validatorModule = await import("../src/context/validator");

    for (const exportName of Object.keys(validatorModule)) {
      const lowered = exportName.toLowerCase();
      expect(lowered).not.toMatch(/conversationstore/);
      expect(lowered).not.toMatch(/sessionstore/);
      expect(lowered).not.toMatch(/durableobject/);
      expect(lowered).not.toMatch(/requeststate/);
    }
  });
});

describe("context_requested_requests_elements_validated", () => {
  it("rejects context_requested turns whose requests elements fail validateContextRequest", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      {
        turn_ordinal: 1,
        kind: "context_requested",
        requests: ["garbage", 42],
      },
    ];

    expect(validateConversational(manifest, transcript)).toEqual({
      ok: false,
      code: "context_invalid",
    });
  });
});

describe("conversational_context_shape_and_size_validated", () => {
  it("rejects mistyped context_resolved values with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      {
        turn_ordinal: 1,
        kind: "context_resolved",
        context: {
          [PERMITTED_KEY_COMPLAINT]: { complaint: "missing visit_id" },
        },
      },
    ];

    expect(validateConversational(manifest, transcript)).toEqual({
      ok: false,
      code: "context_invalid",
    });
  });

  it("rejects oversized permitted context values with context_invalid", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 3,
        transcriptSizeLimit: 64,
      },
    });
    const transcript = [
      {
        turn_ordinal: 1,
        kind: "context_resolved",
        context: {
          [PERMITTED_KEY_COMPLAINT]: {
            visit_id: "550e8400-e29b-41d4-a716-446655440000",
            complaint: "x".repeat(200),
          },
        },
      },
    ];

    expect(validateConversational(manifest, transcript)).toEqual({
      ok: false,
      code: "context_invalid",
    });
  });

  it("rejects mistyped ordinary supplied context with context_invalid", () => {
    const manifest = loadedConversationalManifest();
    const result = validateConversational(manifest, [], {
      [PERMITTED_KEY_COMPLAINT]: { complaint: "missing visit_id" },
    });

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });
});

describe("missing_transcript_field_rejected_context_invalid", () => {
  it("rejects conversational validation when transcript is omitted", () => {
    const manifest = loadedConversationalManifest();
    const result = validateContext(manifest, {}, buildPrincipal(), {
      legTurnOrdinal: 1,
    });

    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });

  it("accepts an explicit empty transcript as a first leg", () => {
    const manifest = loadedConversationalManifest();
    const result = validateConversational(manifest, []);

    expect(result.ok).toBe(true);
  });
});

describe("transcript_size_limit_enforced", () => {
  it("yields conversation_budget_exhausted when serialized transcript exceeds transcriptSizeLimit", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 3,
        transcriptSizeLimit: 40,
      },
    });
    const transcript = [
      {
        turn_ordinal: 1,
        kind: "user",
        text: "This user turn is long enough to exceed the declared transcript size limit.",
      },
    ];

    expect(validateConversational(manifest, transcript)).toEqual({
      ok: false,
      code: "conversation_budget_exhausted",
    });
  });
});

describe("context_rounds_mid_transcript_not_counted_against_tail_budget", () => {
  it("passes when prior context_requested rounds are not at the transcript tail", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 1,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "Start" },
      {
        turn_ordinal: 2,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_COMPLAINT, arguments: {} }],
      },
      {
        turn_ordinal: 3,
        kind: "context_resolved",
        context: {
          [PERMITTED_KEY_COMPLAINT]: {
            visit_id: "550e8400-e29b-41d4-a716-446655440000",
            complaint: "Headache",
          },
        },
      },
      {
        turn_ordinal: 4,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_DEMOGRAPHICS, arguments: {} }],
      },
      {
        turn_ordinal: 5,
        kind: "context_resolved",
        context: {
          [PERMITTED_KEY_DEMOGRAPHICS]: { display_name: "Pat" },
        },
      },
      { turn_ordinal: 6, kind: "user", text: "Continue" },
    ];

    const result = validateConversational(manifest, transcript, {}, 7);
    expect(result.ok).toBe(true);
  });
});

describe("key_outside_permitted_set_dropped", () => {
  it("drops a key inside context_resolved that is outside the permitted set even when requested by the model", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      {
        turn_ordinal: 1,
        kind: "context_requested",
        requests: [{ key: UNPERMITTED_KEY, arguments: {} }],
      },
      {
        turn_ordinal: 2,
        kind: "context_resolved",
        context: {
          [PERMITTED_KEY_COMPLAINT]: {
            visit_id: "550e8400-e29b-41d4-a716-446655440000",
            complaint: "Headache",
          },
          [UNPERMITTED_KEY]: { drug: "Aspirin" },
        },
      },
    ];

    const result = validateConversational(manifest, transcript, {}, 3);
    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }

    const resolvedTurn = result.validatedTranscript?.[1];
    expect(resolvedTurn?.kind).toBe("context_resolved");
    if (resolvedTurn?.kind === "context_resolved") {
      expect(resolvedTurn.context).not.toHaveProperty(UNPERMITTED_KEY);
      expect(resolvedTurn.context).toHaveProperty(PERMITTED_KEY_COMPLAINT);
    }

    // Spec SC-006: unpermitted key must be absent from composer *data* input
    // even when a prior model turn requested it (requests payload may still
    // name the key — allowlist drops at resolution, not at request).
    const composed = composeRequest({
      manifest,
      filteredContext: result.filteredContext,
      transcript: result.validatedTranscript,
      userIntent: "Continue",
      principal: buildPrincipal(),
      requestReference: "H2QK-ALLOW",
    });
    expect(composed.ok).toBe(true);
    if (!composed.ok) {
      return;
    }
    const dataContents = composed.request.parts
      .filter((part) => part.role === "data")
      .map((part) => part.content)
      .join("\n");
    expect(dataContents).not.toContain(UNPERMITTED_KEY);
    expect(dataContents).toContain(PERMITTED_KEY_COMPLAINT);
  });

  it("drops unpermitted keys from ordinary supplied context before composer input", () => {
    const manifest = loadedConversationalManifest();
    const result = validateConversational(
      manifest,
      [],
      {
        [PERMITTED_KEY_DEMOGRAPHICS]: { display_name: "Pat" },
        [UNPERMITTED_KEY]: { drug: "Aspirin" },
      },
      1,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }
    expect(result.filteredContext).not.toHaveProperty(UNPERMITTED_KEY);
    expect(result.filteredContext).toHaveProperty(PERMITTED_KEY_DEMOGRAPHICS);

    const composed = composeRequest({
      manifest,
      filteredContext: result.filteredContext,
      transcript: result.validatedTranscript,
      userIntent: "Continue",
      principal: buildPrincipal(),
      requestReference: "H2QK-ALLOW2",
    });
    expect(composed.ok).toBe(true);
    if (!composed.ok) {
      return;
    }
    expect(JSON.stringify(composed.request)).not.toContain(UNPERMITTED_KEY);
  });
});

describe("budget_boundaries_exactly_at_limit_pass", () => {
  it("accepts a transcript whose length equals maxHistoryTurns", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 2,
        maxContextRoundsPerTurn: 3,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "One" },
      { turn_ordinal: 2, kind: "model", text: "Two" },
    ];

    expect(validateConversational(manifest, transcript, {}, 3).ok).toBe(true);
  });

  it("accepts tail context rounds exactly equal to maxContextRoundsPerTurn", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 2,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      { turn_ordinal: 1, kind: "user", text: "Start" },
      {
        turn_ordinal: 2,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_COMPLAINT, arguments: {} }],
      },
      {
        turn_ordinal: 3,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_DEMOGRAPHICS, arguments: {} }],
      },
    ];

    expect(validateConversational(manifest, transcript, {}, 4).ok).toBe(true);
  });

  it("rejects turn_ordinal strictly greater than the leg's own", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [{ turn_ordinal: 6, kind: "user", text: "Hello" }];

    expect(validateConversational(manifest, transcript, {}, 5)).toEqual({
      ok: false,
      code: "context_invalid",
    });
  });
});

describe("shape_checked_before_rounds_budget", () => {
  it("fails with context_invalid when shape is bad and rounds budget would also breach", () => {
    const manifest = loadedConversationalManifest({
      Interaction: {
        interactionMode: "conversational",
        maxHistoryTurns: 10,
        maxContextRoundsPerTurn: 1,
        transcriptSizeLimit: 50_000,
      },
    });
    const transcript = [
      {
        turn_ordinal: 1,
        kind: "context_requested",
        requests: [{ key: PERMITTED_KEY_COMPLAINT, arguments: {} }],
      },
      {
        turn_ordinal: 2,
        kind: "context_requested",
        requests: ["garbage"],
      },
    ];

    const result = validateConversational(manifest, transcript, {}, 3);
    expect(result).toEqual({ ok: false, code: "context_invalid" });
  });
});

describe("single_shot_unaffected_by_h2", () => {
  it("does not apply transcript validation or budget codes to single_shot capabilities", () => {
    const manifest = load(singleShotManifest());
    const suppliedContext = {
      org: FIXTURE_ORG_ID,
      branch: FIXTURE_BRANCH_ID,
      [PERMITTED_KEY_COMPLAINT]: {
        visit_id: "550e8400-e29b-41d4-a716-446655440000",
        complaint: "Headache",
      },
    };

    const result = validateContext(manifest, suppliedContext, buildPrincipal(), {
      transcript: [{ turn_ordinal: 99, kind: "bogus", text: "ignored" }],
      legTurnOrdinal: 100,
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.validatedTranscript).toBeUndefined();
    }
  });
});
