import type { InspectResponse } from "../quota-do";
import { ok, reject, requireOperator } from "./http";
import type { ControlBindings, OperatorAuth } from "./types";

function capMap<T>(map: Record<string, T>): {
  entries: Record<string, T>;
  truncated: boolean;
} {
  const allEntries = Object.entries(map);
  if (allEntries.length <= 500) {
    return { entries: map, truncated: false };
  }
  return {
    entries: Object.fromEntries(allEntries.slice(0, 500)),
    truncated: true,
  };
}

export async function handleInstallationQuotaGet(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  if (request.method !== "GET") {
    return reject(405, "method_not_allowed");
  }

  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/quota$/,
  );
  const installationId = match?.[1];
  if (!installationId) {
    // Unreachable via HTTP because dispatch pre-filters with identical regexes; reachable via direct handler invocation in tests; kept as a safety net.
    return reject(400, "invalid_route");
  }

  if (!bindings.DO) {
    return reject(503, "quota_do_unavailable");
  }

  const installation = await bindings.DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const entitlement = await bindings.DB.prepare(
    `SELECT plan, status, period_start, period_end, request_quota, token_budget, cost_budget
     FROM entitlement WHERE installation_id = ?`,
  )
    .bind(installationId)
    .first<{
      plan: string;
      status: string;
      period_start: string;
      period_end: string;
      request_quota: number;
      token_budget: number;
      cost_budget: number;
    }>();

  const id = bindings.DO.idFromName(installationId);
  const stub = bindings.DO.get(id);
  let response: Response;
  try {
    response = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind: "inspect" }),
    });
  } catch {
    return reject(503, "quota_do_unavailable");
  }
  if (!response.ok) {
    return reject(503, "quota_do_unavailable");
  }
  const inspect = (await response.json()) as InspectResponse;

  const state = inspect.state;
  const body: Record<string, unknown> = {
    installation_id: installationId,
    bound_installation_id: state.boundInstallationId ?? null,
    period_bounds: state.periodBounds ?? null,
    period_counters: {
      requests_used: state.periodCounters.requestsUsed,
      tokens_used: state.periodCounters.tokensUsed,
      cost_used: state.periodCounters.costUsed,
      in_flight: state.periodCounters.inFlight,
    },
    entitlement: entitlement
      ? {
          plan: entitlement.plan,
          status: entitlement.status,
          period_start: entitlement.period_start,
          period_end: entitlement.period_end,
          request_quota: entitlement.request_quota,
          token_budget: entitlement.token_budget,
          cost_budget: entitlement.cost_budget,
        }
      : null,
    remaining: entitlement
      ? {
          requests:
            entitlement.request_quota - state.periodCounters.requestsUsed,
          tokens: entitlement.token_budget - state.periodCounters.tokensUsed,
          cost: entitlement.cost_budget - state.periodCounters.costUsed,
        }
      : null,
    idempotency_keys: Object.keys(state.idempotency).length,
    jti_replay_entries: Object.keys(state.jtiReplay).length,
    admitted_requests: Object.keys(state.admittedRequests).length,
    credited_requests: Object.keys(state.creditedRequests).length,
  };

  if (new URL(request.url).searchParams.get("verbose") === "true") {
    const idempotency = capMap(state.idempotency);
    const jtiReplay = capMap(state.jtiReplay);
    const admittedRequests = capMap(state.admittedRequests);
    const creditedRequests = capMap(state.creditedRequests);
    body.maps = {
      idempotency: idempotency.entries,
      jti_replay: jtiReplay.entries,
      admitted_requests: admittedRequests.entries,
      credited_requests: creditedRequests.entries,
      truncated:
        idempotency.truncated ||
        jtiReplay.truncated ||
        admittedRequests.truncated ||
        creditedRequests.truncated,
    };
  }

  return ok(body);
}
