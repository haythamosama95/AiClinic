/**
 * Context-key vocabulary and published shapes (§5.2).
 * Types and validation derive from the published shape manifest; contract tests (T-A5-*) exercise it.
 */

export type FieldType = "string" | "number" | "boolean";

export type FieldCardinality =
  | "required"
  | "optional"
  | { maxLength: number };

export type KeyShapeField = {
  readonly name: string;
  readonly type: FieldType;
  readonly cardinality: FieldCardinality;
  readonly units: string | null;
};

export type KeyShape = {
  readonly key: string;
  readonly fields: readonly KeyShapeField[];
};

export type ValidationResult =
  | { readonly ok: true }
  | {
      readonly ok: false;
      readonly code: string;
      readonly field?: string;
    };

/** First published context key — OD-1 visit-summary capability (manifest fixture). */
export const VISIT_CHIEF_COMPLAINT_V1 = "visit.chief_complaint@v1" as const;

export const VISIT_CHIEF_COMPLAINT_V1_SHAPE: KeyShape = {
  key: VISIT_CHIEF_COMPLAINT_V1,
  fields: [
    {
      name: "visit_id",
      type: "string",
      cardinality: "required",
      units: "uuid",
    },
    {
      name: "complaint",
      type: "string",
      cardinality: { maxLength: 10_000 },
      units: null,
    },
    {
      name: "recorded_at",
      type: "string",
      cardinality: "optional",
      units: "iso8601",
    },
  ],
};

const SECTION_5_2_EXAMPLE_KEYS = [
  "patient.demographics@v1",
  "visit.vitals@v1",
  VISIT_CHIEF_COMPLAINT_V1,
  "medication.active_list@v1",
  "lab.recent_results@v1",
  "clinic.branch_profile@v1",
] as const;

const PUBLISHED_KEY_SHAPES: ReadonlyMap<string, KeyShape> = new Map([
  [VISIT_CHIEF_COMPLAINT_V1, VISIT_CHIEF_COMPLAINT_V1_SHAPE],
]);

/** Lookup a platform-published shape by key (single source for A5 + C2). */
export function publishedShapeForKey(key: string): KeyShape | undefined {
  return PUBLISHED_KEY_SHAPES.get(key);
}

const PUBLISHED_CONTEXT_KEYS = new Set<string>(SECTION_5_2_EXAMPLE_KEYS);

const CONTEXT_KEY_FORMAT =
  /^([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+)@v([1-9]\d*)$/;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ISO8601_RE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;

function reject(code: string, field?: string): ValidationResult {
  return field === undefined ? { ok: false, code } : { ok: false, code, field };
}

function conceptSegments(key: string): string[] {
  const beforeAt = key.split("@")[0] ?? "";
  const lastSegment = beforeAt.includes(".")
    ? (beforeAt.split(".").at(-1) ?? beforeAt)
    : beforeAt;
  return lastSegment === beforeAt ? [beforeAt] : [beforeAt, lastSegment];
}

function isStorageNamedKey(key: string): boolean {
  for (const part of conceptSegments(key)) {
    if (part.endsWith("_table") || part.endsWith("_view")) {
      return true;
    }
    if (/^get_.+_rpc$/.test(part)) {
      return true;
    }
  }
  return false;
}

function publishedConceptBases(): Set<string> {
  const bases = new Set<string>();
  for (const published of PUBLISHED_CONTEXT_KEYS) {
    const match = CONTEXT_KEY_FORMAT.exec(published);
    if (match?.[1]) {
      bases.add(match[1]);
    }
  }
  return bases;
}

function isFieldRequired(cardinality: FieldCardinality): boolean {
  return cardinality === "required";
}

function validateUnits(
  value: unknown,
  units: string | null,
): ValidationResult | null {
  if (units === null) {
    return null;
  }

  if (typeof value !== "string") {
    return reject("units");
  }

  switch (units) {
    case "uuid":
      if (!UUID_RE.test(value)) {
        return reject("units");
      }
      return null;
    case "iso8601":
      if (!ISO8601_RE.test(value)) {
        return reject("units");
      }
      return null;
    default:
      return null;
  }
}

function validateFieldType(
  value: unknown,
  type: FieldType,
): ValidationResult | null {
  switch (type) {
    case "string":
      if (typeof value !== "string") {
        return reject("type");
      }
      return null;
    case "number":
      if (typeof value !== "number" || Number.isNaN(value)) {
        return reject("type");
      }
      return null;
    case "boolean":
      if (typeof value !== "boolean") {
        return reject("type");
      }
      return null;
    default:
      return reject("type");
  }
}

function validateFieldCardinality(
  value: unknown,
  cardinality: FieldCardinality,
): ValidationResult | null {
  if (
    typeof cardinality === "object" &&
    cardinality !== null &&
    "maxLength" in cardinality &&
    typeof value === "string" &&
    value.length > cardinality.maxLength
  ) {
    return reject("cardinality");
  }

  return null;
}

function validateFieldValue(
  field: KeyShapeField,
  value: unknown,
): ValidationResult | null {
  const typeError = validateFieldType(value, field.type);
  if (typeError !== null) {
    return typeError;
  }

  const cardinalityError = validateFieldCardinality(value, field.cardinality);
  if (cardinalityError !== null) {
    return cardinalityError;
  }

  const unitsError = validateUnits(value, field.units);
  if (unitsError !== null) {
    return unitsError;
  }

  return null;
}

export function validateKey(key: string): ValidationResult {
  // Storage-named rejection precedes format so contract examples without a
  // domain.concept dot (e.g. visits_vitals_table@v1) still get storage_named_key.
  if (isStorageNamedKey(key)) {
    return reject("storage_named_key");
  }

  const match = CONTEXT_KEY_FORMAT.exec(key);
  if (!match) {
    return reject("malformed_key");
  }

  const conceptBase = match[1];
  if (!publishedConceptBases().has(conceptBase)) {
    return reject("unknown_key");
  }

  if (!PUBLISHED_CONTEXT_KEYS.has(key)) {
    return reject("unknown_version");
  }

  return { ok: true };
}

export function validatePayload(
  key: string,
  payload: unknown,
): ValidationResult {
  const keyResult = validateKey(key);
  if (!keyResult.ok) {
    return keyResult;
  }

  const shape = PUBLISHED_KEY_SHAPES.get(key);
  if (shape === undefined) {
    return reject("unknown_shape");
  }

  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    return reject("type");
  }

  const record = payload as Record<string, unknown>;

  for (const field of shape.fields) {
    const value = record[field.name];
    const present = Object.prototype.hasOwnProperty.call(record, field.name);

    if (!present) {
      if (isFieldRequired(field.cardinality)) {
        return reject("missing_field", field.name);
      }
      continue;
    }

    if (value === undefined) {
      if (isFieldRequired(field.cardinality)) {
        return reject("missing_field", field.name);
      }
      continue;
    }

    const fieldError = validateFieldValue(field, value);
    if (fieldError !== null) {
      return fieldError.field === undefined && fieldError.code === "type"
        ? { ok: false, code: "type", field: field.name }
        : fieldError;
    }
  }

  return { ok: true };
}
