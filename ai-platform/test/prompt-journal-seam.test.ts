/**
 * D1-R7 — journal seam: resolvePromptVersion must equal the field C3 binds
 * into ai_request.prompt_artifact_hash (journal/index.ts createRequestRow).
 * Do not change journal.ts; this test only proves the single-answer property.
 */
import { describe, expect, it } from "vitest";
import { load, type Manifest } from "../src/manifest";
import { resolvePromptVersion } from "../src/prompt/registry";

const SYSTEM_INSTRUCTION_REF = "clinic.visit_summary/system@v1";
const RULES_FRAGMENT_REF = "clinic.visit_summary/rules-visit-summary@v1";
const TEMPLATE_REF = "clinic.visit_summary/template-visit-summary@v1";

function fixtureManifest(): Manifest {
  return load({
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
      systemInstructionArtifactRef: SYSTEM_INSTRUCTION_REF,
      businessRuleFragmentRefs: [RULES_FRAGMENT_REF],
      contextRenderingTemplateRef: TEMPLATE_REF,
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
  });
}

describe("D1-R7 prompt journal seam", () => {
  it("resolvePromptVersion equals Prompt binding.systemInstructionArtifactRef", () => {
    const manifest = fixtureManifest();
    expect(resolvePromptVersion(manifest)).toBe(
      manifest["Prompt binding"].systemInstructionArtifactRef,
    );
  });

  it("equals the expression C3 binds into prompt_artifact_hash", () => {
    const manifest = fixtureManifest();
    // Exact field expression used by createRequestRow in src/journal/index.ts
    // (bind slot for prompt_artifact_hash):
    const c3JournalPromptBinding =
      manifest["Prompt binding"].systemInstructionArtifactRef;

    expect(resolvePromptVersion(manifest)).toBe(c3JournalPromptBinding);
    expect(c3JournalPromptBinding).toBe(SYSTEM_INSTRUCTION_REF);
  });
});
