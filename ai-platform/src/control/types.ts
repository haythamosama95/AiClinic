export type ControlActionResult =
  | { ok: true; body: Record<string, unknown> }
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
