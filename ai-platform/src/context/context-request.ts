/**
 * Platform-owned context-request schema (§6.7.2).
 * Shared by every conversational capability — not a per-capability shape.
 */

export type ContextRequestEntry = {
  readonly key: string;
  readonly arguments: Record<string, unknown>;
};

export type ContextRequest = readonly ContextRequestEntry[];

export const CONTEXT_REQUEST_SCHEMA_ID = "platform.context_request@v1" as const;

export type ContextRequestValidationResult =
  | { readonly ok: true }
  | { readonly ok: false; readonly reason: string };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateContextRequest(
  value: unknown,
): ContextRequestValidationResult {
  if (!Array.isArray(value)) {
    return { ok: false, reason: "root_not_list" };
  }

  for (const element of value) {
    if (!isPlainObject(element)) {
      return { ok: false, reason: "element_not_object" };
    }

    if (!("key" in element)) {
      return { ok: false, reason: "missing_key" };
    }

    if (!("arguments" in element)) {
      return { ok: false, reason: "missing_arguments" };
    }

    if (typeof element.key !== "string") {
      return { ok: false, reason: "invalid_key_type" };
    }

    if (!isPlainObject(element.arguments)) {
      return { ok: false, reason: "invalid_arguments_type" };
    }
  }

  return { ok: true };
}
