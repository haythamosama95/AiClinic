import {
  REQUEST_REFERENCE_PATTERN,
  TAXONOMY_BODY_KEYS,
  ULID_PATTERN,
} from "./env";

export type TaxonomyBody = {
  code: string;
  request_reference: string;
  trace_id: string;
  retry_safe: boolean;
  [key: string]: unknown;
};

/**
 * Assert the clinic taxonomy envelope (`errors.ts` `buildErrorBody`).
 * Supplementary keys (`retry_after`, `period_reset`, …) are allowed.
 */
export function assertTaxonomyBody(
  body: unknown,
  expected: { code: string; retry_safe?: boolean },
): asserts body is TaxonomyBody {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw new Error(
      `expected taxonomy object, got ${JSON.stringify(body)}`,
    );
  }
  const record = body as Record<string, unknown>;
  for (const key of TAXONOMY_BODY_KEYS) {
    if (!(key in record)) {
      throw new Error(
        `taxonomy body missing ${key}: ${JSON.stringify(record)}`,
      );
    }
  }
  if (record.code !== expected.code) {
    throw new Error(
      `taxonomy code: expected ${expected.code}, got ${String(record.code)}`,
    );
  }
  if (typeof record.request_reference !== "string") {
    throw new Error("taxonomy request_reference is not a string");
  }
  if (typeof record.trace_id !== "string") {
    throw new Error("taxonomy trace_id is not a string");
  }
  if (typeof record.retry_safe !== "boolean") {
    throw new Error("taxonomy retry_safe is not a boolean");
  }
  if (
    expected.retry_safe !== undefined &&
    record.retry_safe !== expected.retry_safe
  ) {
    throw new Error(
      `taxonomy retry_safe: expected ${expected.retry_safe}, got ${String(record.retry_safe)}`,
    );
  }
}

export function assertRequestReferenceShape(value: string): void {
  if (!REQUEST_REFERENCE_PATTERN.test(value)) {
    throw new Error(`request_reference shape: ${value}`);
  }
}

export function assertUlidShape(value: string): void {
  if (!ULID_PATTERN.test(value)) {
    throw new Error(`trace_id ULID shape: ${value}`);
  }
}

export { REQUEST_REFERENCE_PATTERN, TAXONOMY_BODY_KEYS, ULID_PATTERN };
