import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  VISIT_CHIEF_COMPLAINT_V1,
  VISIT_CHIEF_COMPLAINT_V1_SHAPE,
  type KeyShape,
  type KeyShapeField,
} from "../src/context";
import type { Principal } from "../src/identity";
import { load, type Manifest } from "../src/manifest";
import type { Logger } from "../src/logger";
import {
  buildContextRequiredResponse,
  validateContext,
  type ValidateResult,
} from "../src/context/validator";
import {
  estimateInputTokens,
  runCostPreflight,
  type PreflightResult,
} from "../src/context/preflight";

type ManifestWire = Record<string, unknown>;
type ContextPayload = Record<string, unknown>;

const FIXTURE_CAPABILITY_ID = "clinic.context_validator";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_ORG_ID = "org-c2-001";
const FIXTURE_BRANCH_ID = "branch-c2-001";
const FIXTURE_REQUEST_REFERENCE = "ABCD-EFGH";
const FIXTURE_TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";

const REQUIRED_KEY_DEMOGRAPHICS = "patient.demographics@v1";
const REQUIRED_KEY_VITALS = "visit.vitals@v1";
const OPTIONAL_KEY_CHIEF_COMPLAINT = VISIT_CHIEF_COMPLAINT_V1;
const UNDECLARED_KEY = "medication.active_list@v1";

const nextStage = vi.fn<(payload: unknown) => void>();

function validManifest(overrides: Partial<ManifestWire> = {}): ManifestWire {
  return {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      version: FIXTURE_CAPABILITY_VERSION,
      title: "Context validator fixture",
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
        key: REQUIRED_KEY_DEMOGRAPHICS,
        required: true,
        shapeRef: REQUIRED_KEY_DEMOGRAPHICS,
        maxSize: 4_096,
      },
      {
        key: REQUIRED_KEY_VITALS,
        required: true,
        shapeRef: REQUIRED_KEY_VITALS,
        maxSize: 4_096,
      },
      {
        key: OPTIONAL_KEY_CHIEF_COMPLAINT,
        required: false,
        shapeRef: OPTIONAL_KEY_CHIEF_COMPLAINT,
        maxSize: 4_096,
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: "prompt/visit-summary-system@v1",
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
    ...overrides,
  };
}

function buildPrincipal(seed: {
  organizationId?: string;
  branchId?: string;
} = {}): Principal {
  return Object.freeze({
    installationId: "inst-c2-001",
    organizationId: seed.organizationId ?? FIXTURE_ORG_ID,
    branchId: seed.branchId ?? FIXTURE_BRANCH_ID,
    actorId: "actor-c2-001",
    role: "clinician",
    scopes: Object.freeze([`ai.${FIXTURE_CAPABILITY_ID}`]),
    jti: "jti-c2-001",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
  });
}

function loadedManifest(overrides: Partial<ManifestWire> = {}): Manifest {
  return load(validManifest(overrides));
}

function utf8ByteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

function expectedEstimate(serializedInput: string): number {
  return Math.ceil(utf8ByteLength(serializedInput) / 4) * 1.15;
}

function publishedShapeForKey(key: string): KeyShape | undefined {
  if (key === OPTIONAL_KEY_CHIEF_COMPLAINT) {
    return VISIT_CHIEF_COMPLAINT_V1_SHAPE;
  }
  return undefined;
}

function sampleValueForField(field: KeyShapeField): unknown {
  switch (field.type) {
    case "string":
      if (field.units === "uuid") {
        return "550e8400-e29b-41d4-a716-446655440000";
      }
      if (field.units === "iso8601") {
        return "2026-07-31T12:00:00Z";
      }
      return "Persistent headache for three days.";
    case "number":
      return 42;
    case "boolean":
      return true;
    default:
      return "fixture-value";
  }
}

function validChiefComplaintPayload(): ContextPayload {
  const payload: ContextPayload = {};
  for (const field of VISIT_CHIEF_COMPLAINT_V1_SHAPE.fields) {
    if (field.cardinality === "optional") {
      payload[field.name] = sampleValueForField(field);
    } else if (field.cardinality === "required") {
      payload[field.name] = sampleValueForField(field);
    } else if (
      typeof field.cardinality === "object" &&
      field.cardinality !== null
    ) {
      payload[field.name] = sampleValueForField(field);
    }
  }
  return payload;
}

function validDemographicsPayload(): ContextPayload {
  return {
    patient_id: "550e8400-e29b-41d4-a716-446655440001",
    display_name: "Test Patient",
  };
}

function validVitalsPayload(): ContextPayload {
  return {
    visit_id: "550e8400-e29b-41d4-a716-446655440002",
    heart_rate: 72,
  };
}

function validSuppliedContext(
  overrides: ContextPayload = {},
): ContextPayload {
  return {
    org: FIXTURE_ORG_ID,
    branch: FIXTURE_BRANCH_ID,
    [REQUIRED_KEY_DEMOGRAPHICS]: validDemographicsPayload(),
    [REQUIRED_KEY_VITALS]: validVitalsPayload(),
    [OPTIONAL_KEY_CHIEF_COMPLAINT]: validChiefComplaintPayload(),
    ...overrides,
  };
}

function declaredContextKeys(manifest: Manifest): string[] {
  return manifest["Context requirements"].map((entry) => entry.key);
}

function forwardValidatedContext(
  manifest: Manifest,
  suppliedContext: ContextPayload,
  principal: Principal,
): ValidateResult {
  const result = validateContext(manifest, suppliedContext, principal);
  if (result.ok) {
    nextStage(result.filteredContext);
  }
  return result;
}

function runPreflightGate(
  manifest: Manifest,
  serializedInput: string,
): PreflightResult {
  const result = runCostPreflight(manifest, serializedInput);
  if (result.ok) {
    nextStage(serializedInput);
  }
  return result;
}

function firstRequiredStringField(shape: KeyShape): KeyShapeField {
  const field = shape.fields.find(
    (candidate) =>
      candidate.type === "string" && candidate.cardinality === "required",
  );
  if (!field) {
    throw new Error("fixture: no required string field in published shape");
  }
  return field;
}

function fieldWithMaxLength(shape: KeyShape): KeyShapeField | undefined {
  return shape.fields.find(
    (field) =>
      typeof field.cardinality === "object" &&
      field.cardinality !== null &&
      "maxLength" in field.cardinality,
  );
}

function fieldWithUnits(shape: KeyShape): KeyShapeField | undefined {
  return shape.fields.find((field) => field.units !== null);
}

function requiredFields(shape: KeyShape): KeyShapeField[] {
  return shape.fields.filter((field) => field.cardinality === "required");
}

beforeEach(() => {
  nextStage.mockClear();
});

describe("T-C2-01 validator_accepts_complete_valid_context", () => {
  it("passes a complete tenant-consistent context and forwards only declared keys", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext();

    const result = forwardValidatedContext(
      manifest,
      suppliedContext,
      principal,
    );

    expect(result).toEqual({
      ok: true,
      filteredContext: {
        [REQUIRED_KEY_DEMOGRAPHICS]: validDemographicsPayload(),
        [REQUIRED_KEY_VITALS]: validVitalsPayload(),
        [OPTIONAL_KEY_CHIEF_COMPLAINT]: validChiefComplaintPayload(),
      },
    });
    expect(Object.keys((result as { ok: true; filteredContext: ContextPayload }).filteredContext)).toEqual(
      declaredContextKeys(manifest),
    );
    expect(nextStage).toHaveBeenCalledTimes(1);
    expect(nextStage).toHaveBeenCalledWith({
      [REQUIRED_KEY_DEMOGRAPHICS]: validDemographicsPayload(),
      [REQUIRED_KEY_VITALS]: validVitalsPayload(),
      [OPTIONAL_KEY_CHIEF_COMPLAINT]: validChiefComplaintPayload(),
    });
  });
});

describe("T-C2-02 validator_rejects_each_missing_required_key", () => {
  for (const missingKey of [REQUIRED_KEY_DEMOGRAPHICS, REQUIRED_KEY_VITALS] as const) {
    it(`emits context_required listing ${missingKey} when that required key is omitted`, () => {
      const manifest = loadedManifest();
      const principal = buildPrincipal();
      const suppliedContext = validSuppliedContext();
      delete suppliedContext[missingKey];

      const result = validateContext(manifest, suppliedContext, principal);

      expect(result.ok).toBe(false);
      if (result.ok) {
        return;
      }
      expect(result.code).toBe("context_required");
      expect(result.missingKeys).toEqual([missingKey]);
      expect(result.manifestVersion).toBe(FIXTURE_CAPABILITY_VERSION);
      expect(result.manifestCapabilityId).toBe(FIXTURE_CAPABILITY_ID);

      const expectedShape = publishedShapeForKey(missingKey);
      if (expectedShape !== undefined) {
        expect(result.shapes).toEqual({ [missingKey]: expectedShape });
      } else {
        expect(result.shapes[missingKey]).toBeUndefined();
      }

      const wire = buildContextRequiredResponse(
        result,
        FIXTURE_REQUEST_REFERENCE,
        FIXTURE_TRACE_ID,
      );
      expect(wire).toMatchObject({
        code: "context_required",
        request_reference: FIXTURE_REQUEST_REFERENCE,
        trace_id: FIXTURE_TRACE_ID,
        retry_safe: true,
        missing_keys: [missingKey],
        manifest_version: FIXTURE_CAPABILITY_VERSION,
        manifest_capability_id: FIXTURE_CAPABILITY_ID,
      });
      if (expectedShape !== undefined) {
        expect(wire.shapes).toEqual({ [missingKey]: expectedShape });
      }
    });
  }
});

describe("T-C2-03 validator_rejects_multiple_missing_required_keys", () => {
  it("lists the full missing-key set in context_required, not just the first", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext({
      org: FIXTURE_ORG_ID,
      branch: FIXTURE_BRANCH_ID,
    });
    delete suppliedContext[REQUIRED_KEY_DEMOGRAPHICS];
    delete suppliedContext[REQUIRED_KEY_VITALS];

    const result = validateContext(manifest, suppliedContext, principal);

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.code).toBe("context_required");
    expect(result.missingKeys).toEqual([
      REQUIRED_KEY_DEMOGRAPHICS,
      REQUIRED_KEY_VITALS,
    ]);
    expect(result.manifestVersion).toBe(FIXTURE_CAPABILITY_VERSION);
    expect(result.manifestCapabilityId).toBe(FIXTURE_CAPABILITY_ID);

    const wire = buildContextRequiredResponse(
      result,
      FIXTURE_REQUEST_REFERENCE,
      FIXTURE_TRACE_ID,
    );
    expect(wire.missing_keys).toEqual([
      REQUIRED_KEY_DEMOGRAPHICS,
      REQUIRED_KEY_VITALS,
    ]);
    expect(wire.shapes).toEqual(result.shapes);
  });
});

describe("T-C2-04 validator_rejects_each_shape_violation", () => {
  const basePayload = validChiefComplaintPayload();

  const violationCases = [
    {
      kind: "wrong field type",
      mutate: (payload: ContextPayload) => {
        const field = firstRequiredStringField(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
        return { ...payload, [field.name]: 12_345 };
      },
    },
    {
      kind: "wrong cardinality",
      mutate: (payload: ContextPayload) => {
        const field = fieldWithMaxLength(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
        if (
          field &&
          typeof field.cardinality === "object" &&
          field.cardinality !== null
        ) {
          const maxLength = (field.cardinality as { maxLength: number }).maxLength;
          return { ...payload, [field.name]: "x".repeat(maxLength + 1) };
        }
        const fallback = firstRequiredStringField(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
        return { ...payload, [fallback.name]: ["not-a-scalar"] };
      },
    },
    {
      kind: "wrong unit",
      mutate: (payload: ContextPayload) => {
        const field = fieldWithUnits(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
        if (!field) {
          throw new Error("fixture: no field with units in published shape");
        }
        return {
          ...payload,
          [field.name]: "definitely-not-a-valid-unit-bearing-value",
        };
      },
    },
    {
      kind: "missing required field",
      mutate: (payload: ContextPayload) => {
        const field = requiredFields(VISIT_CHIEF_COMPLAINT_V1_SHAPE)[0];
        const copy = { ...payload };
        delete copy[field.name];
        return copy;
      },
    },
  ] as const;

  for (const { kind, mutate } of violationCases) {
    it(`rejects ${kind} on visit.chief_complaint@v1 with context_invalid`, () => {
      const manifest = loadedManifest();
      const principal = buildPrincipal();
      const suppliedContext = validSuppliedContext({
        [OPTIONAL_KEY_CHIEF_COMPLAINT]: mutate(basePayload),
      });

      const result = validateContext(manifest, suppliedContext, principal);

      expect(result).toEqual({ ok: false, code: "context_invalid" });
      expect(nextStage).not.toHaveBeenCalled();
    });
  }
});

describe("T-C2-05 validator_rejects_oversize_key", () => {
  it("rejects a key whose byte length exceeds the manifest per-key maxSize", () => {
    const manifest = loadedManifest({
      "Context requirements": [
        {
          key: REQUIRED_KEY_DEMOGRAPHICS,
          required: true,
          shapeRef: REQUIRED_KEY_DEMOGRAPHICS,
          maxSize: 4_096,
        },
        {
          key: REQUIRED_KEY_VITALS,
          required: true,
          shapeRef: REQUIRED_KEY_VITALS,
          maxSize: 4_096,
        },
        {
          key: OPTIONAL_KEY_CHIEF_COMPLAINT,
          required: false,
          shapeRef: OPTIONAL_KEY_CHIEF_COMPLAINT,
          maxSize: 64,
        },
      ],
    });
    const principal = buildPrincipal();
    const oversizedComplaint = {
      ...validChiefComplaintPayload(),
      complaint: "x".repeat(128),
    };
    const suppliedContext = validSuppliedContext({
      [OPTIONAL_KEY_CHIEF_COMPLAINT]: oversizedComplaint,
    });

    const result = validateContext(manifest, suppliedContext, principal);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
    expect(
      utf8ByteLength(JSON.stringify(oversizedComplaint)),
    ).toBeGreaterThan(64);
    expect(nextStage).not.toHaveBeenCalled();
  });
});

describe("T-C2-06 validator_drops_undeclared_key_spy", () => {
  it("drops an undeclared key before handing context to the composer", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const undeclaredPayload = { medication_id: "med-001", active: true };
    const suppliedContext = validSuppliedContext({
      [UNDECLARED_KEY]: undeclaredPayload,
    });

    const result = forwardValidatedContext(
      manifest,
      suppliedContext,
      principal,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }
    expect(result.filteredContext).not.toHaveProperty(UNDECLARED_KEY);
    expect(Object.keys(result.filteredContext)).toEqual(
      declaredContextKeys(manifest),
    );
    expect(nextStage).toHaveBeenCalledTimes(1);
    expect(nextStage.mock.calls[0]?.[0]).not.toHaveProperty(UNDECLARED_KEY);
    expect(nextStage.mock.calls[0]?.[0]).toEqual(result.filteredContext);
  });
});

describe("T-C2-07 validator_rejects_org_mismatch", () => {
  it("rejects when principal.organizationId does not match the supplied context org", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal({ organizationId: "org-Y" });
    const suppliedContext = validSuppliedContext({ org: "org-X" });

    const result = validateContext(manifest, suppliedContext, principal);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
    expect(nextStage).not.toHaveBeenCalled();
  });
});

describe("T-C2-08 validator_rejects_branch_mismatch", () => {
  it("rejects when principal.branchId does not match the supplied context branch", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal({ branchId: "branch-Y" });
    const suppliedContext = validSuppliedContext({ branch: "branch-X" });

    const result = validateContext(manifest, suppliedContext, principal);

    expect(result).toEqual({ ok: false, code: "context_invalid" });
    expect(nextStage).not.toHaveBeenCalled();
  });
});

describe("T-C2-09 validator_passes_absent_optional_key", () => {
  it("passes when a manifest-declared optional key is omitted", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext();
    delete suppliedContext[OPTIONAL_KEY_CHIEF_COMPLAINT];

    const result = forwardValidatedContext(
      manifest,
      suppliedContext,
      principal,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }
    expect(result.filteredContext).not.toHaveProperty(OPTIONAL_KEY_CHIEF_COMPLAINT);
    expect(Object.keys(result.filteredContext)).toEqual([
      REQUIRED_KEY_DEMOGRAPHICS,
      REQUIRED_KEY_VITALS,
    ]);
    expect(nextStage).toHaveBeenCalledTimes(1);
    expect(nextStage.mock.calls[0]?.[0]).toEqual(result.filteredContext);
  });
});

describe("T-C2-10 preflight_passes_under_ceiling", () => {
  it("returns ok when both pre-flight predicates pass", () => {
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 1_024,
        perRequestTokenCeiling: 9_024,
        quotaWeight: 1,
      },
    });
    const serializedInput = "x".repeat(100);

    const estimate = estimateInputTokens(serializedInput);
    expect(estimate).toBe(expectedEstimate(serializedInput));
    expect(estimate).toBeLessThanOrEqual(manifest.Economics.maxInputTokens);
    expect(estimate + manifest.Economics.maxOutputTokens).toBeLessThanOrEqual(
      manifest.Economics.perRequestTokenCeiling,
    );

    const result = runPreflightGate(manifest, serializedInput);

    expect(result).toEqual({ ok: true });
    expect(nextStage).toHaveBeenCalledTimes(1);
    expect(nextStage).toHaveBeenCalledWith(serializedInput);
  });
});

describe("T-C2-11 preflight_rejects_over_ceiling", () => {
  it("returns request_too_large when estimated input plus max output exceeds the ceiling", () => {
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 500,
        perRequestTokenCeiling: 100,
        quotaWeight: 1,
      },
    });
    const serializedInput = "x".repeat(400);
    const estimate = estimateInputTokens(serializedInput);
    expect(estimate + manifest.Economics.maxOutputTokens).toBeGreaterThan(
      manifest.Economics.perRequestTokenCeiling,
    );

    const result = runPreflightGate(manifest, serializedInput);

    expect(result).toEqual({ ok: false, code: "request_too_large" });
    expect(nextStage).not.toHaveBeenCalled();
  });
});

describe("T-C2-12 preflight_estimate_includes_max_output_tokens", () => {
  it("rejects when input alone would pass the ceiling but input plus maxOutputTokens exceeds it", () => {
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 80,
        perRequestTokenCeiling: 100,
        quotaWeight: 1,
      },
    });
    const serializedInput = "x".repeat(120);
    const estimate = estimateInputTokens(serializedInput);
    expect(estimate).toBeLessThanOrEqual(manifest.Economics.perRequestTokenCeiling);
    expect(estimate + manifest.Economics.maxOutputTokens).toBeGreaterThan(
      manifest.Economics.perRequestTokenCeiling,
    );

    const result = runCostPreflight(manifest, serializedInput);

    expect(result).toEqual({ ok: false, code: "request_too_large" });
  });
});

describe("T-C2-13 preflight_no_egress_on_rejection_spy", () => {
  it("does not call the composer/provider entry spy when pre-flight rejects", () => {
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 500,
        perRequestTokenCeiling: 100,
        quotaWeight: 1,
      },
    });
    const serializedInput = "x".repeat(400);

    const result = runPreflightGate(manifest, serializedInput);

    expect(result).toEqual({ ok: false, code: "request_too_large" });
    expect(nextStage).not.toHaveBeenCalled();
  });
});

describe("T-C2-14 preflight_estimator_is_deterministic_bytes", () => {
  it("matches ceil(utf8Bytes/4)*1.15, is multi-byte-safe, and is stable across calls", () => {
    const asciiPayload = "fixed-ascii-payload-for-estimator";
    const multiBytePayload = "caf\u00e9";

    expect(estimateInputTokens(asciiPayload)).toBe(
      expectedEstimate(asciiPayload),
    );
    expect(estimateInputTokens(asciiPayload)).toBe(
      estimateInputTokens(asciiPayload),
    );

    expect(utf8ByteLength(multiBytePayload)).toBe(5);
    expect(estimateInputTokens(multiBytePayload)).toBe(
      Math.ceil(5 / 4) * 1.15,
    );
    expect(estimateInputTokens(multiBytePayload)).toBe(
      estimateInputTokens(multiBytePayload),
    );
  });
});

describe("T-C2-15 preflight_rejects_over_max_input_tokens", () => {
  it("returns request_too_large when estimated input alone exceeds maxInputTokens", () => {
    const serializedInput = "x".repeat(100);
    const estimate = expectedEstimate(serializedInput);
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: Math.floor(estimate),
        maxOutputTokens: 100,
        perRequestTokenCeiling: 10_000,
        quotaWeight: 1,
      },
    });

    expect(estimate).toBeGreaterThan(manifest.Economics.maxInputTokens);
    expect(estimate + manifest.Economics.maxOutputTokens).toBeLessThanOrEqual(
      manifest.Economics.perRequestTokenCeiling,
    );

    const result = runCostPreflight(manifest, serializedInput);

    expect(result).toEqual({ ok: false, code: "request_too_large" });
  });
});

describe("C2-R review resolution — fail-closed load paths", () => {
  it("load rejects non-numeric Economics.maxOutputTokens", () => {
    expect(() =>
      load(
        validManifest({
          Economics: {
            maxInputTokens: 8_000,
            maxOutputTokens: "1024",
            perRequestTokenCeiling: 9_024,
            quotaWeight: 1,
          },
        }),
      ),
    ).toThrow(/Economics/);
  });

  it("load rejects non-numeric Economics.maxInputTokens", () => {
    expect(() =>
      load(
        validManifest({
          Economics: {
            maxInputTokens: undefined,
            maxOutputTokens: 1_024,
            perRequestTokenCeiling: 9_024,
            quotaWeight: 1,
          },
        }),
      ),
    ).toThrow(/Economics/);
  });

  it("load rejects non-numeric Economics.perRequestTokenCeiling", () => {
    expect(() =>
      load(
        validManifest({
          Economics: {
            maxInputTokens: 8_000,
            maxOutputTokens: 1_024,
            perRequestTokenCeiling: "9024",
            quotaWeight: 1,
          },
        }),
      ),
    ).toThrow(/Economics/);
  });

  it("load rejects non-numeric legacy Economics.perRequestCostCeiling alias", () => {
    expect(() =>
      load(
        validManifest({
          Economics: {
            maxInputTokens: 8_000,
            maxOutputTokens: 1_024,
            perRequestCostCeiling: "9024",
            quotaWeight: 1,
          },
        }),
      ),
    ).toThrow(/Economics/);
  });

  it("load rejects non-boolean Context requirements.required", () => {
    expect(() =>
      load(
        validManifest({
          "Context requirements": [
            {
              key: REQUIRED_KEY_DEMOGRAPHICS,
              required: "yes",
              shapeRef: REQUIRED_KEY_DEMOGRAPHICS,
              maxSize: 4_096,
            },
          ],
        }),
      ),
    ).toThrow(/Context requirements/);
  });

  it("load rejects non-numeric Context requirements.maxSize", () => {
    expect(() =>
      load(
        validManifest({
          "Context requirements": [
            {
              key: REQUIRED_KEY_DEMOGRAPHICS,
              required: true,
              shapeRef: REQUIRED_KEY_DEMOGRAPHICS,
              maxSize: "4096",
            },
          ],
        }),
      ),
    ).toThrow(/Context requirements/);
  });

  it("load rejects a Context requirements key outside the published vocabulary", () => {
    expect(() =>
      load(
        validManifest({
          "Context requirements": [
            {
              key: "visit.vitals@v2",
              required: true,
              shapeRef: "visit.vitals@v2",
              maxSize: 4_096,
            },
          ],
        }),
      ),
    ).toThrow(/Context requirements unknown key/);
  });
});

describe("C2-R review resolution — exact boundaries", () => {
  it("preflight passes when estimate + maxOutputTokens equals the ceiling", () => {
    const serializedInput = "abcd"; // 4 bytes → ceil(4/4)*1.15 = 1.15
    const estimate = estimateInputTokens(serializedInput);
    expect(estimate).toBe(1.15);
    const maxOutputTokens = 10;
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens,
        perRequestTokenCeiling: estimate + maxOutputTokens,
        quotaWeight: 1,
      },
    });

    expect(runCostPreflight(manifest, serializedInput)).toEqual({ ok: true });
  });

  it("preflight passes when estimate equals maxInputTokens", () => {
    const serializedInput = "abcd";
    const estimate = estimateInputTokens(serializedInput);
    expect(estimate).toBe(1.15);
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: estimate,
        maxOutputTokens: 100,
        perRequestTokenCeiling: 10_000,
        quotaWeight: 1,
      },
    });

    expect(runCostPreflight(manifest, serializedInput)).toEqual({ ok: true });
  });

  it("validator passes when key JSON bytes equal maxSize", () => {
    const payload = { note: "exact-bound" };
    const exactBytes = new TextEncoder().encode(JSON.stringify(payload)).byteLength;
    const manifest = loadedManifest({
      "Context requirements": [
        {
          key: REQUIRED_KEY_DEMOGRAPHICS,
          required: true,
          shapeRef: REQUIRED_KEY_DEMOGRAPHICS,
          maxSize: exactBytes,
        },
        {
          key: REQUIRED_KEY_VITALS,
          required: true,
          shapeRef: REQUIRED_KEY_VITALS,
          maxSize: 4_096,
        },
      ],
    });
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext({
      [REQUIRED_KEY_DEMOGRAPHICS]: payload,
    });

    const result = validateContext(manifest, suppliedContext, principal);
    expect(result.ok).toBe(true);
  });
});

describe("C2-R review resolution — evaluation order and tenant edges", () => {
  it("short-circuits to context_required when required key is missing even with tenant and shape defects", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext({
      org: "wrong-org",
      branch: "wrong-branch",
      [OPTIONAL_KEY_CHIEF_COMPLAINT]: { visit_id: 123 },
    });
    delete suppliedContext[REQUIRED_KEY_DEMOGRAPHICS];

    const result = validateContext(manifest, suppliedContext, principal);

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.code).toBe("context_required");
    expect(result.missingKeys).toEqual([REQUIRED_KEY_DEMOGRAPHICS]);
  });

  it("rejects absent org as context_invalid", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext();
    delete suppliedContext.org;

    expect(validateContext(manifest, suppliedContext, principal)).toEqual({
      ok: false,
      code: "context_invalid",
    });
  });

  it("rejects absent branch as context_invalid", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext();
    delete suppliedContext.branch;

    expect(validateContext(manifest, suppliedContext, principal)).toEqual({
      ok: false,
      code: "context_invalid",
    });
  });

  it("drops same-concept different-version key and surfaces required v1 as missing", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext();
    delete suppliedContext[REQUIRED_KEY_VITALS];
    suppliedContext["visit.vitals@v2"] = { systolic: 120 };

    const result = validateContext(manifest, suppliedContext, principal);

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.code).toBe("context_required");
    expect(result.missingKeys).toEqual([REQUIRED_KEY_VITALS]);
  });
});

describe("C2-R review resolution — shape tolerance and immutability", () => {
  it("tolerates unknown_shape for published vocabulary keys without a shape", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    // demographics/vitals have no published shape — unknown_shape must pass.
    const result = validateContext(
      manifest,
      validSuppliedContext(),
      principal,
    );
    expect(result.ok).toBe(true);
  });

  it("rejects client shape violations as context_invalid (not internal_error)", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext({
      [OPTIONAL_KEY_CHIEF_COMPLAINT]: {
        visit_id: "not-a-uuid",
        complaint: "Headache",
      },
    });

    expect(validateContext(manifest, suppliedContext, principal)).toEqual({
      ok: false,
      code: "context_invalid",
    });
  });

  it("freezes filteredContext and does not alias nested caller values", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const nested = { note: "caller-owned" };
    const suppliedContext = validSuppliedContext({
      [REQUIRED_KEY_DEMOGRAPHICS]: nested,
    });

    const result = validateContext(manifest, suppliedContext, principal);
    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }

    expect(Object.isFrozen(result.filteredContext)).toBe(true);
    expect(() => {
      result.filteredContext.extra = true;
    }).toThrow();

    nested.note = "mutated-after-validate";
    expect(result.filteredContext[REQUIRED_KEY_DEMOGRAPHICS]).toEqual({
      note: "caller-owned",
    });
  });

  it("freezes context_required wire body including missing_keys and shapes copies", () => {
    const manifest = loadedManifest();
    const principal = buildPrincipal();
    const suppliedContext = validSuppliedContext();
    delete suppliedContext[REQUIRED_KEY_DEMOGRAPHICS];

    const result = validateContext(manifest, suppliedContext, principal);
    expect(result.ok).toBe(false);
    if (result.ok || result.code !== "context_required") {
      return;
    }

    expect(Object.isFrozen(result)).toBe(true);
    expect(Object.isFrozen(result.missingKeys)).toBe(true);

    const wire = buildContextRequiredResponse(
      result,
      FIXTURE_REQUEST_REFERENCE,
      FIXTURE_TRACE_ID,
    );
    expect(Object.isFrozen(wire)).toBe(true);
    expect(Object.isFrozen(wire.missing_keys)).toBe(true);
    expect(Object.isFrozen(wire.shapes)).toBe(true);

    const missingKeys = wire.missing_keys as string[];
    expect(() => {
      missingKeys.push("injected");
    }).toThrow();
    expect(result.missingKeys).toEqual([REQUIRED_KEY_DEMOGRAPHICS]);
  });
});

describe("C2-R review resolution — estimator literals and artifact bytes", () => {
  it("anchors estimateInputTokens to fixed input→estimate literals", () => {
    // utf8("")=0 → ceil(0/4)*1.15 = 0
    expect(estimateInputTokens("")).toBe(0);
    // utf8("a")=1 → ceil(1/4)*1.15 = 1.15
    expect(estimateInputTokens("a")).toBe(1.15);
    // utf8("abcd")=4 → ceil(4/4)*1.15 = 1.15
    expect(estimateInputTokens("abcd")).toBe(1.15);
    // utf8("abcde")=5 → ceil(5/4)*1.15 = 2.3
    expect(estimateInputTokens("abcde")).toBe(2.3);
    // utf8("café")=5 → 2.3
    expect(estimateInputTokens("caf\u00e9")).toBe(2.3);
    // utf8("日本語")=9 → ceil(9/4)*1.15 (IEEE: 3*1.15)
    expect(estimateInputTokens("日本語")).toBe(Math.ceil(9 / 4) * 1.15);
  });

  it("includes promptArtifactByteLength in the measured input", () => {
    const serializedInput = "abcd"; // 4 bytes → 1.15 alone
    expect(estimateInputTokens(serializedInput)).toBe(1.15);
    // 4 + 4 = 8 bytes → ceil(8/4)*1.15 = 2.3
    expect(estimateInputTokens(serializedInput, 4)).toBe(2.3);

    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 1,
        perRequestTokenCeiling: 2.2,
        quotaWeight: 1,
      },
    });

    expect(runCostPreflight(manifest, serializedInput)).toEqual({ ok: true });
    expect(runCostPreflight(manifest, serializedInput, 4)).toEqual({
      ok: false,
      code: "request_too_large",
    });
  });

  it("rejects non-finite promptArtifactByteLength as request_too_large", () => {
    const manifest = loadedManifest();
    expect(runCostPreflight(manifest, "x", Number.NaN)).toEqual({
      ok: false,
      code: "request_too_large",
    });
    expect(runCostPreflight(manifest, "x", -1)).toEqual({
      ok: false,
      code: "request_too_large",
    });
  });
});

describe("4.7 perRequestTokenCeiling token units, not currency", () => {
  it("rejects when estimated tokens plus maxOutputTokens exceed the token ceiling", () => {
    // 20 would be a tiny dollar budget that would still admit almost any
    // request if the check were money. As tokens, 20 is a hard reject for a
    // short payload plus 500 max output — proving the field name is tokens
    // and the comparison stays estimatedInputTokens + maxOutputTokens.
    const serializedInput = "x".repeat(40);
    const estimate = estimateInputTokens(serializedInput);
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 500,
        perRequestTokenCeiling: 20,
        quotaWeight: 1,
      },
    });

    expect(estimate + manifest.Economics.maxOutputTokens).toBeGreaterThan(
      manifest.Economics.perRequestTokenCeiling,
    );
    expect(runCostPreflight(manifest, serializedInput)).toEqual({
      ok: false,
      code: "request_too_large",
    });
  });

  it("passes the same comparison when estimated tokens plus maxOutputTokens fit the token ceiling", () => {
    const serializedInput = "x".repeat(40);
    const estimate = estimateInputTokens(serializedInput);
    const maxOutputTokens = 10;
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens,
        perRequestTokenCeiling: estimate + maxOutputTokens,
        quotaWeight: 1,
      },
    });

    expect(estimate + maxOutputTokens).toBeLessThanOrEqual(
      manifest.Economics.perRequestTokenCeiling,
    );
    expect(runCostPreflight(manifest, serializedInput)).toEqual({ ok: true });
  });

  it("applies the token comparison after loading the legacy cost-named alias", () => {
    const serializedInput = "x".repeat(40);
    const estimate = estimateInputTokens(serializedInput);
    const wire = validManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 500,
        perRequestCostCeiling: 20,
        quotaWeight: 1,
      },
    });
    const manifest = load(wire);

    expect(manifest.Economics.perRequestTokenCeiling).toBe(20);
    expect(manifest.Economics).not.toHaveProperty("perRequestCostCeiling");
    expect(estimate + 500).toBeGreaterThan(20);
    expect(runCostPreflight(manifest, serializedInput)).toEqual({
      ok: false,
      code: "request_too_large",
    });
  });

  it("logs the ceiling as per_request_token_ceiling, never a currency field", () => {
    const debug = vi.fn();
    const logger: Logger = {
      error: vi.fn(),
      info: vi.fn(),
      debug,
      child: () => logger,
    };
    const serializedInput = "x".repeat(40);
    const estimate = estimateInputTokens(serializedInput);
    const manifest = loadedManifest({
      Economics: {
        maxInputTokens: 8_000,
        maxOutputTokens: 10,
        perRequestTokenCeiling: estimate + 10,
        quotaWeight: 1,
      },
    });

    expect(runCostPreflight(manifest, serializedInput, 0, logger)).toEqual({
      ok: true,
    });
    expect(debug).toHaveBeenCalledWith(
      "preflight_estimate",
      expect.objectContaining({
        estimated_input_tokens: estimate,
        per_request_token_ceiling: estimate + 10,
      }),
    );
    const payload = debug.mock.calls[0]?.[1] as Record<string, unknown>;
    expect(payload).not.toHaveProperty("per_request_cost_ceiling");
    expect(payload).not.toHaveProperty("cost_usd");
    expect(payload).not.toHaveProperty("price");
  });
});
