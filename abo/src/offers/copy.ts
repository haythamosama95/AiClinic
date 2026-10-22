// R8-CONSOLE5 / R8-PUB1: shared offer copy and terms validation.
// Used before a publication consumes approval and when reading stored offer rows, so both
// paths apply one rule. Nothing here invents commercial copy; invalid input is only rejected.

export type LocalizedCopy = {
  name: string;
  summary: string;
};

// `en` is required; other locale keys carry the same shape.
export type OfferCopy = { en: LocalizedCopy; [locale: string]: LocalizedCopy };

export function isRecordValue(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

export function isNonEmptyTerms(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isLocalizedCopy(value: unknown): value is LocalizedCopy {
  return (
    isRecordValue(value) &&
    typeof value.name === "string" &&
    value.name.trim().length > 0 &&
    typeof value.summary === "string"
  );
}

// Returns the validated copy, or null when the copy is malformed. The `en` entry is required;
// every other locale present must have the same shape.
export function validateOfferCopy(value: unknown): OfferCopy | null {
  if (!isRecordValue(value) || !isLocalizedCopy(value.en)) {
    return null;
  }
  for (const entry of Object.values(value)) {
    if (!isLocalizedCopy(entry)) {
      return null;
    }
  }
  return value as OfferCopy;
}

// Validates a stored offer_version row. Returns null when it is usable, otherwise a short
// reason naming the malformed field.
export function storedOfferFault(row: {
  price_minor: unknown;
  copy: unknown;
}): string | null {
  if (!isPositiveSafeInteger(row.price_minor)) {
    return "price_minor";
  }
  if (typeof row.copy !== "string") {
    return "copy";
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(row.copy);
  } catch {
    return "copy";
  }
  return validateOfferCopy(parsed) === null ? "copy" : null;
}
