import { describe, expect, it } from "vitest";
import { isTaxonomyCode } from "../src/errors";
import { CONTEXT_REQUEST_SCHEMA_ID } from "../src/context/context-request";
import {
  runValidationPhases,
  validateAndRepair,
  type AssembledOutput,
  type BusinessRuleRegistry,
  type SchemaRegistry,
} from "../src/validate";

const PERMITTED_KEY_COMPLAINT = "visit.chief_complaint@v1";
const PERMITTED_KEY_DEMOGRAPHICS = "patient.demographics@v1";

const PERMITTED_KEY_SET = [
  PERMITTED_KEY_COMPLAINT,
  PERMITTED_KEY_DEMOGRAPHICS,
] as const;

const SAFETY_MARKERS = {
  leakedInstructionNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
  refusalPrefixes: ["I'm sorry, I can't assist"],
  injectionEchoNeedle: "IGNORE_PREVIOUS_INSTRUCTIONS_TEST",
};

function conversationalPhaseInput(output: AssembledOutput) {
  return {
    output,
    mode: "prose" as const,
    outputSchemaRef: null,
    businessValidationRuleRefs: [] as string[],
    schemaRegistry: new Map() as SchemaRegistry,
    ruleRegistry: new Map() as BusinessRuleRegistry,
    interactionMode: "conversational" as const,
    permittedKeySet: PERMITTED_KEY_SET,
    safetyMarkers: SAFETY_MARKERS,
  };
}

function validProseOutput(): AssembledOutput {
  return {
    raw: "The patient presents with a mild headache lasting three days.",
    transportValid: true,
  };
}

function validContextRequestOutput(): AssembledOutput {
  return {
    raw: JSON.stringify([
      {
        key: PERMITTED_KEY_COMPLAINT,
        arguments: { visit_id: "550e8400-e29b-41d4-a716-446655440000" },
      },
    ]),
    transportValid: true,
  };
}

describe("prose_answer_validates", () => {
  it("accepts a valid prose answer for a conversational capability", async () => {
    const phaseResult = runValidationPhases(
      conversationalPhaseInput(validProseOutput()),
    );

    expect(phaseResult.ok).toBe(true);
    if (phaseResult.ok) {
      expect(phaseResult.validated).toBe(
        "The patient presents with a mild headache lasting three days.",
      );
    }

    const repairResult = await validateAndRepair({
      ...conversationalPhaseInput(validProseOutput()),
      repairPolicy: { allowed: false, maxAttempts: 0 },
    });

    expect(repairResult.ok).toBe(true);
  });
});

describe("context_request_validates", () => {
  it("accepts a conforming context request drawn from the permitted set", async () => {
    const phaseResult = runValidationPhases(
      conversationalPhaseInput(validContextRequestOutput()),
    );

    expect(phaseResult.ok).toBe(true);
    if (phaseResult.ok) {
      expect(phaseResult.validated).toEqual([
        {
          key: PERMITTED_KEY_COMPLAINT,
          arguments: { visit_id: "550e8400-e29b-41d4-a716-446655440000" },
        },
      ]);
    }

    const repairResult = await validateAndRepair({
      ...conversationalPhaseInput(validContextRequestOutput()),
      repairPolicy: { allowed: false, maxAttempts: 0 },
    });

    expect(repairResult.ok).toBe(true);
    expect(CONTEXT_REQUEST_SCHEMA_ID).toBe("platform.context_request@v1");
  });
});

describe("output_neither_prose_nor_context_request_fails", () => {
  it("fails under validation_failed when output is neither valid prose nor a context request", async () => {
    const neitherOutput: AssembledOutput = {
      raw: JSON.stringify({ unexpected: "shape", not: "prose" }),
      transportValid: true,
    };

    const phaseResult = runValidationPhases(
      conversationalPhaseInput(neitherOutput),
    );

    expect(phaseResult.ok).toBe(false);

    const repairResult = await validateAndRepair({
      ...conversationalPhaseInput(neitherOutput),
      repairPolicy: { allowed: false, maxAttempts: 0 },
    });

    expect(repairResult.ok).toBe(false);
    if (!repairResult.ok) {
      expect(repairResult.code).toBe("validation_failed");
      expect(isTaxonomyCode(repairResult.code)).toBe(true);
    }
  });
});
