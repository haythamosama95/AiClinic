import { VISIT_CHIEF_COMPLAINT_V1 } from "../../../src/context";
import {
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  readHttpResult,
  SELF,
  type HttpResult,
} from "./env";
import { mintAat } from "./aat";
import type { Scenario } from "./types";
import { parseSseEvents, type SseEvent } from "./sse";

export { VISIT_CHIEF_COMPLAINT_V1 };

export function visitSummaryInvokeBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org: scenario.orgId,
      branch: scenario.branchId,
      [VISIT_CHIEF_COMPLAINT_V1]: {
        visit_id: crypto.randomUUID(),
        complaint: "Headache for three days.",
        recorded_at: new Date().toISOString(),
      },
    },
    ...overrides,
  };
}

export type ClinicFetchOptions = {
  method?: string;
  token?: string | null;
  headers?: Record<string, string>;
  body?: unknown;
  signal?: AbortSignal;
};

export async function clinicFetch(
  path: string,
  options: ClinicFetchOptions = {},
): Promise<Response> {
  const method = options.method ?? "GET";
  const headers: Record<string, string> = { ...options.headers };
  if (options.token) {
    headers.authorization = `Bearer ${options.token}`;
  }
  let serialized: string | undefined;
  if (options.body !== undefined) {
    serialized =
      typeof options.body === "string"
        ? options.body
        : JSON.stringify(options.body);
    if (!headers["content-type"]) {
      headers["content-type"] = "application/json";
    }
  }
  return SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}${path}`, {
      method,
      headers,
      body: serialized,
      signal: options.signal,
    }),
  );
}

export type InvokeResult = {
  status: number;
  headers: Headers;
  body: Record<string, unknown> | null;
  events: SseEvent[];
  text: string;
};

export async function postRequest(
  scenario: Scenario,
  opts: {
    token?: string | null;
    idempotencyKey?: string;
    traceId?: string;
    capabilityVersion?: string;
    body?: Record<string, unknown> | string;
    signal?: AbortSignal;
    extraHeaders?: Record<string, string>;
    omitIdempotencyKey?: boolean;
    omitCapabilityVersion?: boolean;
  } = {},
): Promise<InvokeResult> {
  const token =
    opts.token === null
      ? undefined
      : opts.token ?? (await mintAat(scenario));
  const headers: Record<string, string> = {
    "content-type": "application/json",
    ...opts.extraHeaders,
  };
  if (token) {
    headers.authorization = `Bearer ${token}`;
  }
  if (!opts.omitIdempotencyKey && !headers["x-idempotency-key"]) {
    headers["x-idempotency-key"] = opts.idempotencyKey ?? crypto.randomUUID();
  }
  if (!opts.omitCapabilityVersion && !headers["x-capability-version"]) {
    headers["x-capability-version"] =
      opts.capabilityVersion ?? CAPABILITY_VERSION;
  }
  if (opts.traceId) {
    headers["x-trace-id"] = opts.traceId;
  }

  const body =
    opts.body === undefined
      ? JSON.stringify(visitSummaryInvokeBody(scenario))
      : typeof opts.body === "string"
        ? opts.body
        : JSON.stringify(opts.body);

  const response = await clinicFetch("/v1/requests", {
    method: "POST",
    headers,
    body,
    signal: opts.signal,
  });

  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    const events = await parseSseEvents(response);
    await flushBackgroundWork();
    return {
      status: response.status,
      headers: response.headers,
      body: null,
      events,
      text: "",
    };
  }

  const result = await readHttpResult(response);
  await flushBackgroundWork();
  return {
    status: result.status,
    headers: result.headers,
    body:
      result.json !== null && typeof result.json === "object"
        ? (result.json as Record<string, unknown>)
        : null,
    events: [],
    text: result.text,
  };
}

export async function getCapabilities(
  token: string,
  ifNoneMatch?: string,
): Promise<{
  status: number;
  etag: string | null;
  body: Record<string, unknown> | null;
}> {
  const headers: Record<string, string> = {};
  if (ifNoneMatch) {
    headers["if-none-match"] = ifNoneMatch;
  }
  const response = await clinicFetch("/v1/capabilities", { token, headers });
  const etag = response.headers.get("ETag");
  if (response.status === 304) {
    return { status: response.status, etag, body: null };
  }
  const result = await readHttpResult(response);
  return {
    status: result.status,
    etag,
    body:
      result.json !== null && typeof result.json === "object"
        ? (result.json as Record<string, unknown>)
        : null,
  };
}

export async function getRequestByRef(
  token: string,
  ref: string,
): Promise<HttpResult> {
  const response = await clinicFetch(`/v1/requests/${ref}`, { token });
  return readHttpResult(response);
}

export async function getHealth(): Promise<HttpResult> {
  const response = await SELF.fetch(new Request(`${GATEWAY_ORIGIN}/health`));
  return readHttpResult(response);
}
