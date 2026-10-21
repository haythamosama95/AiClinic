export type ControlActionResult =
  | {
      ok: true;
      body: Record<string, unknown>;
      // R9-PAL1: identity of a committed kill-switch transition (changed_at is
      // the value the mutation wrote). Not part of the HTTP response body.
      transition?: { action: "arm" | "disarm"; changed_at: string };
    }
  | { ok: false; status: number; error: string };

export type ControlBindings = {
  DB: D1Database;
  R2?: R2Bucket;
  DO?: DurableObjectNamespace;
};

export function requireNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string" || value.trim() === "") {
    return null;
  }
  return value;
}
