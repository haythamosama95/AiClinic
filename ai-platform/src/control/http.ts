import type { OperatorAuth, OperatorPrincipal } from "./types";

function unauthorized(): Response {
  return new Response(JSON.stringify({ error: "unauthorized" }), {
    status: 401,
    headers: { "content-type": "application/json" },
  });
}

export function reject(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function ok(body: Record<string, unknown> = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function newId(): string {
  return crypto.randomUUID();
}

export function requireOperator(
  request: Request,
  operatorAuth: OperatorAuth,
): OperatorPrincipal | Response {
  const principal = operatorAuth.resolve(request);
  if (!principal) {
    return unauthorized();
  }
  return principal;
}

export async function parseJsonBody<T>(request: Request): Promise<T | Response> {
  try {
    return (await request.json()) as T;
  } catch {
    return reject(400, "invalid_json");
  }
}

export function requireNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string" || value.trim() === "") {
    return null;
  }
  return value;
}
