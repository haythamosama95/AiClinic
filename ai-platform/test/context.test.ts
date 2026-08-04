import { describe, expect, it } from "vitest";
import {
  validateKey,
  validatePayload,
  VISIT_CHIEF_COMPLAINT_V1,
  VISIT_CHIEF_COMPLAINT_V1_SHAPE,
  type KeyShape,
  type KeyShapeField,
  type ValidationResult,
} from "../src/context";

const SECTION_5_2_EXAMPLE_KEYS = [
  "patient.demographics@v1",
  "visit.vitals@v1",
  "visit.chief_complaint@v1",
  "medication.active_list@v1",
  "lab.recent_results@v1",
  "clinic.branch_profile@v1",
] as const;

const FIRST_CONTEXT_KEY = VISIT_CHIEF_COMPLAINT_V1;

type PayloadRecord = Record<string, unknown>;

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

function requiredFields(shape: KeyShape): KeyShapeField[] {
  return shape.fields.filter((field) => field.cardinality === "required");
}

function fieldWithUnits(shape: KeyShape): KeyShapeField | undefined {
  return shape.fields.find(
    (field) => field.units !== null && field.units !== undefined,
  );
}

function fieldWithMaxLength(shape: KeyShape): KeyShapeField | undefined {
  return shape.fields.find(
    (field) =>
      typeof field.cardinality === "object" &&
      field.cardinality !== null &&
      "maxLength" in field.cardinality,
  );
}

function firstRequiredStringField(shape: KeyShape): KeyShapeField {
  const field = shape.fields.find(
    (f) => f.type === "string" && f.cardinality === "required",
  );
  if (!field) {
    throw new Error("fixture: no required string field in published shape");
  }
  return field;
}

/** Conforming payload for the first published context key (visit.chief_complaint@v1). */
function validPayload(): PayloadRecord {
  const payload: PayloadRecord = {};
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

function withTypeViolation(payload: PayloadRecord): PayloadRecord {
  const field = firstRequiredStringField(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
  return { ...payload, [field.name]: 12345 };
}

function withCardinalityViolation(payload: PayloadRecord): PayloadRecord {
  const field = fieldWithMaxLength(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
  if (field && typeof field.cardinality === "object" && field.cardinality !== null) {
    const maxLength = (field.cardinality as { maxLength: number }).maxLength;
    return { ...payload, [field.name]: "x".repeat(maxLength + 1) };
  }
  const stringField = firstRequiredStringField(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
  return { ...payload, [stringField.name]: ["not-a-scalar"] };
}

function withUnitsViolation(payload: PayloadRecord): PayloadRecord {
  const field = fieldWithUnits(VISIT_CHIEF_COMPLAINT_V1_SHAPE);
  if (!field) {
    throw new Error("fixture: no field with units in published shape");
  }
  return { ...payload, [field.name]: "definitely-not-a-valid-unit-bearing-value" };
}

function withMissingField(payload: PayloadRecord): PayloadRecord {
  const field = requiredFields(VISIT_CHIEF_COMPLAINT_V1_SHAPE)[0];
  const copy = { ...payload };
  delete copy[field.name];
  return copy;
}

function assertAccepted(result: ValidationResult): void {
  expect(result).toEqual({ ok: true });
}

function assertRejected(
  result: ValidationResult,
  expectedCode?: string,
): void {
  expect(result.ok).toBe(false);
  if (expectedCode !== undefined) {
    expect(result).toMatchObject({ ok: false, code: expectedCode });
  }
}

describe("T-A5-01 context_key_valid_accepted", () => {
  it("accepts every §5.2 example domain.concept@vN key", () => {
    for (const key of SECTION_5_2_EXAMPLE_KEYS) {
      assertAccepted(validateKey(key));
    }
  });
});

describe("T-A5-02 context_key_malformed_format_rejected", () => {
  const malformedKeys = [
    "visit.vitals",
    "visit_vitals@v1",
    "visit@v1",
    "visit..vitals@v1",
    "visit.vitals@1",
    "visit.vitals@version1",
  ] as const;

  for (const key of malformedKeys) {
    it(`rejects malformed key ${key}`, () => {
      assertRejected(validateKey(key));
    });
  }
});

describe("T-A5-03 context_key_storage_named_rejected", () => {
  it("rejects visits_vitals_table@v1 as storage_named_key", () => {
    assertRejected(validateKey("visits_vitals_table@v1"), "storage_named_key");
  });

  it("rejects get_visit_vitals_rpc@v1 as storage_named_key", () => {
    assertRejected(validateKey("get_visit_vitals_rpc@v1"), "storage_named_key");
  });

  it("rejects visits.vitals_table@v1 (well-formed, concept ends with _table)", () => {
    assertRejected(validateKey("visits.vitals_table@v1"), "storage_named_key");
  });

  it("rejects visits.vitals_view@v1 (well-formed, concept ends with _view)", () => {
    assertRejected(validateKey("visits.vitals_view@v1"), "storage_named_key");
  });

  it("rejects clinic.get_visit_vitals_rpc@v1 (well-formed get_*_rpc concept)", () => {
    assertRejected(
      validateKey("clinic.get_visit_vitals_rpc@v1"),
      "storage_named_key",
    );
  });
});

describe("T-A5-04 context_key_unknown_version_rejected", () => {
  it("rejects visit.vitals@v9 for a known concept with unpublished version", () => {
    assertRejected(validateKey("visit.vitals@v9"), "unknown_version");
  });

  it("rejects patient.demographics@v2 for a known concept with unpublished version", () => {
    assertRejected(validateKey("patient.demographics@v2"), "unknown_version");
  });
});

describe("T-A5-04b context_key_unknown_key_rejected", () => {
  it("rejects a well-formed key whose domain.concept is outside the vocabulary as unknown_key", () => {
    assertRejected(validateKey("patient.allergies@v1"), "unknown_key");
  });
});

describe("T-A5-05 context_key_payload_validates", () => {
  it("accepts a payload conforming to the first key's published shape", () => {
    assertAccepted(validatePayload(FIRST_CONTEXT_KEY, validPayload()));
  });
});

describe("T-A5-06 context_key_shape_violation_type", () => {
  it("rejects a payload with a type violation", () => {
    assertRejected(
      validatePayload(
        FIRST_CONTEXT_KEY,
        withTypeViolation(validPayload()),
      ),
      "type",
    );
  });
});

describe("T-A5-07 context_key_shape_violation_cardinality", () => {
  it("rejects a payload with a cardinality violation", () => {
    assertRejected(
      validatePayload(
        FIRST_CONTEXT_KEY,
        withCardinalityViolation(validPayload()),
      ),
      "cardinality",
    );
  });
});

describe("T-A5-08 context_key_shape_violation_units", () => {
  it("rejects a payload with a units violation", () => {
    assertRejected(
      validatePayload(
        FIRST_CONTEXT_KEY,
        withUnitsViolation(validPayload()),
      ),
      "units",
    );
  });
});

describe("T-A5-09 context_key_shape_violation_missing_field", () => {
  it("rejects a payload missing a required field and names the field", () => {
    const missingField = requiredFields(VISIT_CHIEF_COMPLAINT_V1_SHAPE)[0];
    const result = validatePayload(
      FIRST_CONTEXT_KEY,
      withMissingField(validPayload()),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("missing_field");
      expect(result.field).toBe(missingField.name);
    }
  });
});

describe("T-A5-10 first_context_key_shape_published", () => {
  it("exports the first key constant as visit.chief_complaint@v1", () => {
    expect(FIRST_CONTEXT_KEY).toBe("visit.chief_complaint@v1");
  });

  it("declares field names, types, cardinality, and units on the published KeyShape", () => {
    expect(VISIT_CHIEF_COMPLAINT_V1_SHAPE.key).toBe("visit.chief_complaint@v1");
    expect(VISIT_CHIEF_COMPLAINT_V1_SHAPE.fields.length).toBeGreaterThan(0);

    for (const field of VISIT_CHIEF_COMPLAINT_V1_SHAPE.fields) {
      expect(field.name).toEqual(expect.any(String));
      expect(field.name.length).toBeGreaterThan(0);
      expect(field.type).toEqual(expect.any(String));
      expect(field.cardinality).toBeDefined();
      expect(field).toHaveProperty("units");
    }
  });
});
