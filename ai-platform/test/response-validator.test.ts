import { describe, expect, it, vi } from "vitest";
import { isTaxonomyCode } from "../src/errors";
import type { Manifest } from "../src/manifest";
import {
  runValidationPhases,
  validateAndRepair,
  type AssembledOutput,
  type BusinessRuleRegistry,
  type RepairJournalSink,
  type RepairCostSink,
  type ReaskPort,
  type SchemaRegistry,
  type SafetyMarkers,
  type ValidationPhase,
} from "../src/validate";

const FIXTURE_TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const FIXTURE_REQUEST_ID = "req-d6-001";

const SCHEMA_REF = "schemas/visit-summary@v1";
const RULE_ENUM = "rules/enumeration@v1";
const RULE_REFERENTIAL = "rules/referential@v1";
const RULE_NUMERIC = "rules/numeric-range@v1";
const RULE_REQUIRED_SECTION = "rules/required-section@v1";

const SAFETY_MARKERS: SafetyMarkers = {
  leakedInstructionNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
  refusalPrefixes: ["I'm sorry, I can't assist"],
  injectionEchoNeedle: "IGNORE_PREVIOUS_INSTRUCTIONS_TEST",
};

const VALID_DOCUMENT = {
  summary: "Patient presents with mild headache.",
  severity: "mild",
  patientRef: "patient-001",
  painScore: 3,
  sections: { assessment: "Stable", plan: "Rest and fluids" },
};

function createSchemaRegistry(): SchemaRegistry {
  const registry: SchemaRegistry = new Map();
  registry.set(SCHEMA_REF, (parsed: unknown) => {
    if (typeof parsed !== "object" || parsed === null) {
      return "expected object";
    }
    const doc = parsed as Record<string, unknown>;
    if (typeof doc.summary !== "string") {
      return "summary required";
    }
    return null;
  });
  return registry;
}

function createBusinessRuleRegistry(): BusinessRuleRegistry {
  const registry: BusinessRuleRegistry = new Map();

  registry.set(RULE_ENUM, (parsed: unknown) => {
    const doc = parsed as Record<string, unknown>;
    const allowed = ["mild", "moderate", "severe"];
    if (!allowed.includes(String(doc.severity))) {
      return "enumeration violation";
    }
    return null;
  });

  registry.set(RULE_REFERENTIAL, (parsed: unknown, context: unknown) => {
    const doc = parsed as Record<string, unknown>;
    const ctx = context as { patientId?: string };
    if (doc.patientRef !== ctx.patientId) {
      return "referential violation";
    }
    return null;
  });

  registry.set(RULE_NUMERIC, (parsed: unknown) => {
    const doc = parsed as Record<string, unknown>;
    const score = Number(doc.painScore);
    if (Number.isNaN(score) || score < 0 || score > 10) {
      return "numeric range violation";
    }
    return null;
  });

  registry.set(RULE_REQUIRED_SECTION, (parsed: unknown) => {
    const doc = parsed as Record<string, unknown>;
    const sections = doc.sections as Record<string, unknown> | undefined;
    if (!sections?.assessment || !sections?.plan) {
      return "required section missing";
    }
    return null;
  });

  return registry;
}

function outputCapability(overrides: {
  mode?: Manifest["Output"]["mode"];
  outputSchemaRef?: string | null;
  businessValidationRuleRefs?: string[];
  repairPolicy?: { allowed: boolean; maxAttempts: number };
} = {}) {
  return {
    mode: overrides.mode ?? "structured",
    outputSchemaRef: overrides.outputSchemaRef ?? SCHEMA_REF,
    businessValidationRuleRefs:
      overrides.businessValidationRuleRefs ?? [
        RULE_ENUM,
        RULE_REFERENTIAL,
        RULE_NUMERIC,
        RULE_REQUIRED_SECTION,
      ],
    repairPolicy: overrides.repairPolicy ?? { allowed: false, maxAttempts: 0 },
  };
}

function validAssembledOutput(): AssembledOutput {
  return {
    raw: JSON.stringify(VALID_DOCUMENT),
    transportValid: true,
  };
}

function createJournalSpy(): {
  sink: RepairJournalSink;
  records: Array<{ attempt: number; errors: unknown[] }>;
} {
  const records: Array<{ attempt: number; errors: unknown[] }> = [];
  return {
    records,
    sink: (record) => {
      records.push(record);
    },
  };
}

function createCostSpy(): {
  sink: RepairCostSink;
  calls: Array<{ tokens: number; cost: number }>;
} {
  const calls: Array<{ tokens: number; cost: number }> = [];
  return {
    calls,
    sink: (usage) => {
      calls.push(usage);
    },
  };
}

type TerminalEvent = {
  type: "completed" | "failed";
  data: Record<string, unknown>;
};

function assertNoInvalidSuccessPayload(
  result: Awaited<ReturnType<typeof validateAndRepair>>,
  invalidRaw: string,
): void {
  if (result.ok) {
    expect(JSON.stringify(result.validated)).not.toContain(invalidRaw);
    return;
  }
  expect(result.code).toBe("validation_failed");
  expect(isTaxonomyCode(result.code)).toBe(true);
}

describe("T-D6-01 valid_output_passes", () => {
  it("passes transport-valid, schema-conformant, business-valid output through every safety guard", async () => {
    const capability = outputCapability();
    const schemaRegistry = createSchemaRegistry();
    const ruleRegistry = createBusinessRuleRegistry();
    const context = { patientId: "patient-001" };

    const phaseResult = runValidationPhases({
      output: validAssembledOutput(),
      mode: capability.mode as "structured",
      outputSchemaRef: capability.outputSchemaRef,
      businessValidationRuleRefs: capability.businessValidationRuleRefs,
      schemaRegistry,
      ruleRegistry,
      context,
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(phaseResult.ok).toBe(true);
    if (phaseResult.ok) {
      expect(phaseResult.validated).toEqual(VALID_DOCUMENT);
    }

    const repairResult = await validateAndRepair({
      output: validAssembledOutput(),
      mode: capability.mode as "structured",
      outputSchemaRef: capability.outputSchemaRef,
      businessValidationRuleRefs: capability.businessValidationRuleRefs,
      repairPolicy: capability.repairPolicy,
      schemaRegistry,
      ruleRegistry,
      context,
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(repairResult.ok).toBe(true);

    const terminal: TerminalEvent = {
      type: "completed",
      data: {
        result: {
          finalContent: {
            document: repairResult.ok ? repairResult.validated : null,
            authoritative: true,
          },
        },
        trace_id: FIXTURE_TRACE_ID,
      },
    };
    expect(terminal.type).toBe("completed");
    expect(terminal.data.result).toBeDefined();
  });
});

describe("T-D6-02 parse_failure", () => {
  it("reports transport/parse failure and does not accept invalid content", async () => {
    const output: AssembledOutput = {
      raw: "{not valid json",
      transportValid: false,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("transport_parse");
    }

    const repairResult = await validateAndRepair({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    assertNoInvalidSuccessPayload(repairResult, output.raw);
  });
});

describe("T-D6-03 schema_violation", () => {
  it("fails at schema-conformance phase without emitting invalid content", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("schema");
    }

    const repairResult = await validateAndRepair({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    assertNoInvalidSuccessPayload(repairResult, "severity");
  });
});

describe("T-D6-04 business_rule_violation", () => {
  const baseInput = {
    mode: "structured" as const,
    outputSchemaRef: SCHEMA_REF,
    schemaRegistry: createSchemaRegistry(),
    ruleRegistry: createBusinessRuleRegistry(),
    context: { patientId: "patient-001" },
    safetyMarkers: SAFETY_MARKERS,
  };

  it("fails at business-constraint phase for enumeration violation", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({ ...VALID_DOCUMENT, severity: "critical" }),
      transportValid: true,
    };

    const result = runValidationPhases({
      ...baseInput,
      output,
      businessValidationRuleRefs: [RULE_ENUM],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("business");
    }
  });

  it("fails at business-constraint phase for referential sanity violation", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({ ...VALID_DOCUMENT, patientRef: "wrong-patient" }),
      transportValid: true,
    };

    const result = runValidationPhases({
      ...baseInput,
      output,
      businessValidationRuleRefs: [RULE_REFERENTIAL],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("business");
    }
  });

  it("fails at business-constraint phase for numeric range violation", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({ ...VALID_DOCUMENT, painScore: 99 }),
      transportValid: true,
    };

    const result = runValidationPhases({
      ...baseInput,
      output,
      businessValidationRuleRefs: [RULE_NUMERIC],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("business");
    }
  });

  it("fails at business-constraint phase for required-section presence violation", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({
        ...VALID_DOCUMENT,
        sections: { assessment: "Stable" },
      }),
      transportValid: true,
    };

    const result = runValidationPhases({
      ...baseInput,
      output,
      businessValidationRuleRefs: [RULE_REQUIRED_SECTION],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("business");
    }
  });
});

describe("T-D6-05 safety_guard_leaked_instruction", () => {
  it("fails at safety phase when system instructions leak", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({
        ...VALID_DOCUMENT,
        summary: `Note ${SAFETY_MARKERS.leakedInstructionNeedle}`,
      }),
      transportValid: true,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("safety");
    }
  });
});

describe("T-D6-06 safety_guard_refusal", () => {
  it("fails at safety phase when the assembled raw starts with a refusal prefix", async () => {
    const output: AssembledOutput = {
      raw: "I'm sorry, I can't assist with that request.",
      transportValid: true,
    };

    const result = runValidationPhases({
      output,
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      schemaRegistry: new Map(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("safety");
      expect(result.failure.message).toBe("model refusal");
    }
  });

  it("does not treat a mid-sentence refusal phrase as a model refusal", async () => {
    const output: AssembledOutput = {
      raw: "Patient said: I'm sorry, I can't assist myself today.",
      transportValid: true,
    };

    const result = runValidationPhases({
      output,
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      schemaRegistry: new Map(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(true);
  });
});

describe("T-D6-07 safety_guard_empty", () => {
  it("fails at safety phase for empty output", async () => {
    const output: AssembledOutput = { raw: "   ", transportValid: true };

    const result = runValidationPhases({
      output,
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      schemaRegistry: new Map(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("safety");
    }
  });
});

describe("T-D6-08 safety_guard_truncated", () => {
  it("fails at safety phase for truncated output", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify(VALID_DOCUMENT),
      transportValid: true,
      truncated: true,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("safety");
    }
  });
});

describe("T-D6-09 safety_guard_injection_echo", () => {
  it("fails at safety phase for prompt-injection echo", async () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({
        ...VALID_DOCUMENT,
        summary: `Echo ${SAFETY_MARKERS.injectionEchoNeedle}`,
      }),
      transportValid: true,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("safety");
    }
  });
});

describe("T-D6-10 four_phases_run_in_stated_order", () => {
  const phaseOrder: ValidationPhase[] = [
    "transport_parse",
    "schema",
    "business",
    "safety",
  ];

  it("reports transport_parse before later phases when parse fails", () => {
    const output: AssembledOutput = {
      raw: "{invalid json with schema would also fail",
      transportValid: false,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [RULE_ENUM],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: createBusinessRuleRegistry(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("transport_parse");
      expect(phaseOrder.indexOf(result.failure.phase)).toBeLessThan(
        phaseOrder.indexOf("schema"),
      );
    }
  });

  it("reports schema before business when both would fail", () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({ severity: "critical", patientRef: "wrong" }),
      transportValid: true,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [RULE_ENUM, RULE_REFERENTIAL],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: createBusinessRuleRegistry(),
      context: { patientId: "patient-001" },
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("schema");
      expect(phaseOrder.indexOf(result.failure.phase)).toBeLessThan(
        phaseOrder.indexOf("business"),
      );
    }
  });

  it("reports business before safety when both would fail", () => {
    const output: AssembledOutput = {
      raw: JSON.stringify({
        ...VALID_DOCUMENT,
        severity: "critical",
        summary: SAFETY_MARKERS.leakedInstructionNeedle,
      }),
      transportValid: true,
    };

    const result = runValidationPhases({
      output,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [RULE_ENUM],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: createBusinessRuleRegistry(),
      context: { patientId: "patient-001" },
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("business");
      expect(phaseOrder.indexOf(result.failure.phase)).toBeLessThan(
        phaseOrder.indexOf("safety"),
      );
    }
  });
});

describe("T-D6-11 invalid_content_never_emitted", () => {
  const failureOutputs: AssembledOutput[] = [
    { raw: "{bad", transportValid: false },
    {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    },
    {
      raw: JSON.stringify({ ...VALID_DOCUMENT, severity: "critical" }),
      transportValid: true,
    },
    {
      raw: JSON.stringify({
        ...VALID_DOCUMENT,
        summary: SAFETY_MARKERS.leakedInstructionNeedle,
      }),
      transportValid: true,
    },
  ];

  for (const output of failureOutputs) {
    it(`never returns invalid content for fixture ${output.raw.slice(0, 24)}`, async () => {
      const result = await validateAndRepair({
        output,
        mode: "structured",
        outputSchemaRef: SCHEMA_REF,
        businessValidationRuleRefs: [
          RULE_ENUM,
          RULE_REFERENTIAL,
          RULE_NUMERIC,
          RULE_REQUIRED_SECTION,
        ],
        repairPolicy: { allowed: true, maxAttempts: 1 },
        schemaRegistry: createSchemaRegistry(),
        ruleRegistry: createBusinessRuleRegistry(),
        context: { patientId: "patient-001" },
        safetyMarkers: SAFETY_MARKERS,
        reask: async () => ({
          output,
          usage: { tokens: 0, cost: 0 },
        }),
      });

      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.code).toBe("validation_failed");
      }
    });
  }
});

describe("T-D6-12 repair_allowed_one_reask_success", () => {
  it("performs exactly one budgeted re-ask with errors appended and succeeds", async () => {
    const invalid: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };
    const reaskSpy = vi.fn<ReaskPort>(async () => ({
      output: validAssembledOutput(),
      usage: { tokens: 40, cost: 0.001 },
    }));

    const journal = createJournalSpy();
    const result = await validateAndRepair({
      output: invalid,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [
        RULE_ENUM,
        RULE_REFERENTIAL,
        RULE_NUMERIC,
        RULE_REQUIRED_SECTION,
      ],
      repairPolicy: { allowed: true, maxAttempts: 1 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: createBusinessRuleRegistry(),
      context: { patientId: "patient-001" },
      safetyMarkers: SAFETY_MARKERS,
      reask: reaskSpy,
      repairJournalSink: journal.sink,
    });

    expect(reaskSpy).toHaveBeenCalledOnce();
    expect(reaskSpy.mock.calls[0]?.[0]?.length).toBeGreaterThan(0);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.validated).toEqual(VALID_DOCUMENT);
    }
  });
});

describe("T-D6-13 repair_disallowed_immediate_validation_failed", () => {
  it("fails immediately with validation_failed and zero re-ask calls", async () => {
    const invalid: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };
    const reaskSpy = vi.fn<ReaskPort>();

    const result = await validateAndRepair({
      output: invalid,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
      reask: reaskSpy,
    });

    expect(reaskSpy).not.toHaveBeenCalled();
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("validation_failed");
    }
  });
});

describe("T-D6-14 repair_fails_validation_failed", () => {
  it("terminates with validation_failed when re-ask output still fails", async () => {
    const invalid: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };
    const reaskSpy = vi.fn<ReaskPort>(async () => ({
      output: invalid,
      usage: { tokens: 10, cost: 0 },
    }));

    const result = await validateAndRepair({
      output: invalid,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: true, maxAttempts: 1 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
      reask: reaskSpy,
    });

    expect(reaskSpy).toHaveBeenCalledOnce();
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("validation_failed");
    }
  });
});

describe("T-D6-15 repair_attempt_cap_enforced_and_journaled", () => {
  it("enforces maxAttempts, journals each attempt, and fails on exhaustion", async () => {
    const invalid: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };
    const reaskSpy = vi.fn<ReaskPort>(async () => ({
      output: invalid,
      usage: { tokens: 10, cost: 0 },
    }));
    const journal = createJournalSpy();

    const result = await validateAndRepair({
      output: invalid,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: true, maxAttempts: 2 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
      reask: reaskSpy,
      repairJournalSink: journal.sink,
    });

    expect(reaskSpy).toHaveBeenCalledTimes(2);
    expect(journal.records).toHaveLength(2);
    expect(journal.records.map((r) => r.attempt)).toEqual([1, 2]);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("validation_failed");
    }
  });
});

describe("T-D6-16 repair_cost_counted_against_request", () => {
  it("counts repair cost from the re-ask reported usage against the request", async () => {
    const invalid: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };
    const costSpy = createCostSpy();
    const repairUsage = { tokens: 120, cost: 0.002 };

    await validateAndRepair({
      output: invalid,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: true, maxAttempts: 1 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
      reask: async () => ({
        output: validAssembledOutput(),
        usage: repairUsage,
      }),
      repairCostSink: costSpy.sink,
    });

    expect(costSpy.calls).toEqual([repairUsage]);
  });
});

describe("T-D6-25 reask_throws_validation_failed", () => {
  it("terminates with validation_failed when the reask port throws", async () => {
    const invalid: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };
    const reaskSpy = vi.fn<ReaskPort>(async () => {
      throw new Error("provider abort");
    });

    const result = await validateAndRepair({
      output: invalid,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: true, maxAttempts: 1 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
      reask: reaskSpy,
    });

    expect(reaskSpy).toHaveBeenCalledOnce();
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("validation_failed");
      expect(result.message).toContain("reask failed");
      expect(isTaxonomyCode(result.code)).toBe(true);
    }
  });
});

describe("T-D6-26 unresolved_declared_refs_fail_closed", () => {
  it("fails schema phase when outputSchemaRef is missing from the registry", () => {
    const result = runValidationPhases({
      output: validAssembledOutput(),
      mode: "structured",
      outputSchemaRef: "schemas/missing@v1",
      businessValidationRuleRefs: [],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("schema");
      expect(result.failure.message).toContain("unresolved schema ref");
    }
  });

  it("fails business phase when a declared rule ref is missing from the registry", () => {
    const result = runValidationPhases({
      output: validAssembledOutput(),
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: ["rules/missing@v1"],
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: createBusinessRuleRegistry(),
      context: { patientId: "patient-001" },
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failure.phase).toBe("business");
      expect(result.failure.message).toContain("unresolved business rule ref");
    }
  });
});

describe("T-D6-27 validation_failed_carries_failure_detail", () => {
  it("includes phase and message on the terminal validation_failed result", async () => {
    const invalid: AssembledOutput = {
      raw: JSON.stringify({ severity: "mild" }),
      transportValid: true,
    };

    const result = await validateAndRepair({
      output: invalid,
      mode: "structured",
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
      schemaRegistry: createSchemaRegistry(),
      ruleRegistry: new Map(),
      safetyMarkers: SAFETY_MARKERS,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("validation_failed");
      expect(result.phase).toBe("schema");
      expect(typeof result.message).toBe("string");
      expect(result.message.length).toBeGreaterThan(0);
    }
  });
});
