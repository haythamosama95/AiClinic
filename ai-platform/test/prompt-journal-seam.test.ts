/**
 * D1-R7 — journal seam: resolvePromptVersion (content hash of resolved
 * artifact bytes) is what createRequestRow binds into
 * ai_request.prompt_artifact_hash via RequestRowInput.promptArtifactHash.
 */
import { describe, expect, it } from "vitest";
import { load, type Manifest } from "../src/manifest";
import {
  resolvePromptVersion,
  stableContentHash,
} from "../src/prompt/registry";
import businessRulesArtifact from "../prompts/clinic.visit_summary/rules-visit-summary.md?raw";
import contextTemplateArtifact from "../prompts/clinic.visit_summary/template-visit-summary.md?raw";
import systemInstructionArtifact from "../prompts/clinic.visit_summary/system.md?raw";
import journalSource from "../src/journal/index.ts?raw";
import pipelineSource from "../src/pipeline/index.ts?raw";

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
  });
}

describe("D1-R7 prompt journal seam", () => {
  it("resolvePromptVersion is the content hash of bound artifact bytes", () => {
    const manifest = fixtureManifest();
    const expected = stableContentHash(
      [
        systemInstructionArtifact,
        businessRulesArtifact,
        contextTemplateArtifact,
      ].join("\0"),
    );

    expect(resolvePromptVersion(manifest)).toBe(expected);
    expect(resolvePromptVersion(manifest)).not.toBe(
      manifest["Prompt binding"].systemInstructionArtifactRef,
    );
  });

  it("createRequestRow binds promptArtifactHash, and the pipeline supplies resolvePromptVersion", () => {
    expect(journalSource).toMatch(/input\.promptArtifactHash/);
    expect(pipelineSource).toMatch(
      /promptArtifactHash:\s*input\.resolvePromptVersion\?\.\(manifest\)/,
    );
  });
});
