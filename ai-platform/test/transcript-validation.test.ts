import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Principal } from "../src/identity";
import { load, type Manifest } from "../src/manifest";
import {
  validateContext,
  type Transcript,
  type ValidateResult,
} from "../src/context/validator";
import * as preflightModule from "../src/context/preflight";

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

describe("key_outside_permitted_set_dropped", () => {
  it("drops a key inside context_resolved that is outside the permitted set", () => {
    const manifest = loadedConversationalManifest();
    const transcript = [
      {
        turn_ordinal: 1,
        kind: "context_resolved",
        context: {
          [PERMITTED_KEY_COMPLAINT]: { complaint: "Headache" },
          [UNPERMITTED_KEY]: { drug: "Aspirin" },
        },
      },
    ];

    const result = validateConversational(manifest, transcript);

    expect(result.ok).toBe(true);
    if (result.ok) {
      const resolvedTurn = result.validatedTranscript?.[0];
      expect(resolvedTurn?.kind).toBe("context_resolved");
      if (resolvedTurn?.kind === "context_resolved") {
        expect(resolvedTurn.context).toEqual({
          [PERMITTED_KEY_COMPLAINT]: { complaint: "Headache" },
        });
        expect(resolvedTurn.context).not.toHaveProperty(UNPERMITTED_KEY);
      }
    }
  });
});

describe("oversized_transcript_request_too_large", () => {
  it("fails the existing cost pre-flight with request_too_large for an oversized transcript", () => {
    const manifest = loadedConversationalManifest({
      Economics: {
        maxInputTokens: 10,
        maxOutputTokens: 1_024,
        perRequestCostCeiling: 20,
        quotaWeight: 1,
      },
    });
    const transcript = validTranscript();
    const serializedInput = JSON.stringify({ transcript, userIntent: "x".repeat(10_000) });

    const preflightSpy = vi.spyOn(preflightModule, "runCostPreflight");
    const result = preflightModule.runCostPreflight(manifest, serializedInput);

    expect(preflightSpy).toHaveBeenCalledWith(manifest, serializedInput);
    expect(result).toEqual({ ok: false, code: "request_too_large" });
  });
});

describe("per_turn_cost_ceiling_uses_existing_preflight_no_new_mechanism", () => {
  it("prices transcript growth only through the existing runCostPreflight export", async () => {
    const validatorModule = await import("../src/context/validator");
    const preflightExports = Object.keys(preflightModule);
    const validatorExports = Object.keys(validatorModule);

    expect(preflightExports).toContain("runCostPreflight");
    expect(preflightExports).toContain("estimateInputTokens");
    expect(validatorExports).not.toContain("runConversationCostTotal");
    expect(validatorExports).not.toContain("reservePreflightBudget");

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
