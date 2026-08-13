import type { BuiltRequest } from "@/catalog";
import type { ConnectionConfig } from "@/lib/connection";

export type OpsRunResult = {
  status: number;
  contentType: string;
  bodyText: string;
  headers: Record<string, string>;
  durationMs: number;
};

export type BootstrapCredentialsResult = {
  operatorBearer?: string;
  aat?: string;
  notes: string[];
  errors: string[];
};

export async function bootstrapDevCredentials(): Promise<BootstrapCredentialsResult> {
  const res = await fetch("/ops/bootstrap", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({}),
  });
  const payload = (await res.json()) as BootstrapCredentialsResult & {
    error?: string;
  };
  if (!res.ok && payload.error) {
    throw new Error(payload.error);
  }
  return payload;
}

export async function runBuiltRequest(
  built: BuiltRequest,
  connection: ConnectionConfig,
): Promise<OpsRunResult> {
  const started = performance.now();
  const res = await fetch("/ops/run", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      request: built,
      connection: {
        platformBaseUrl: connection.platformBaseUrl,
        operatorBearer: connection.operatorBearer,
        aat: connection.aat,
      },
    }),
  });
  const contentType = res.headers.get("content-type") ?? "";
  const bodyText = await res.text();
  const durationMs = Math.round(performance.now() - started);

  if (!res.ok && contentType.includes("application/json") === false) {
    return {
      status: res.status,
      contentType,
      bodyText,
      headers: Object.fromEntries(res.headers.entries()),
      durationMs,
    };
  }

  try {
    const parsed = JSON.parse(bodyText) as OpsRunResult;
    if (
      typeof parsed.status === "number" &&
      typeof parsed.bodyText === "string"
    ) {
      return { ...parsed, durationMs: parsed.durationMs ?? durationMs };
    }
  } catch {
    // fall through
  }

  return {
    status: res.status,
    contentType,
    bodyText,
    headers: Object.fromEntries(res.headers.entries()),
    durationMs,
  };
}
