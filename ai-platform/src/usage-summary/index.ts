/**
 * Installation-facing usage-summary read (G3 §7.6).
 * Live current period from Quota DO; prior periods from usage_rollup.quota_weight.
 */

import {
  isolateConfigCache,
  createD1ConfigReader,
  type ConfigCache,
} from "../config-cache";
import { buildErrorBody, liveHttpStatusForCode } from "../errors";
import type { AlertEnv } from "../alert";
import { clockNowMs, clockNowSeconds } from "../clock";
import { IssuerTokenVerifier } from "../identity";
import { noopLogger, type Logger } from "../logger";
import type { InspectResponse } from "../quota-do";
import { generateRequestReference } from "../reference";
import { generateUlid } from "../trace";
import { CHANNEL_VERSIONS } from "vendor-contracts";

const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

export interface UsageSummaryEnv extends AlertEnv {
  DB: D1Database;
  DO: DurableObjectNamespace;
  R2?: R2Bucket;
  ISSUER_ID: string;
  TEST_CLOCK?: string;
}

type UsageSummarySuccessBody = {
  current_period: {
    period: string;
    credits_used: number;
    credit_budget: number;
  };
  prior_periods: Array<{
    period: string;
    credits_used: number;
  }>;
};

function periodFromIso(iso: string): string {
  return iso.slice(0, 7);
}

function unauthenticatedResponse(): Response {
  const status = liveHttpStatusForCode("unauthenticated") ?? 401;
  return Response.json(
    buildErrorBody({
      code: "unauthenticated",
      requestReference: generateRequestReference(),
      traceId: generateUlid(),
    }),
    { status },
  );
}

async function inspectQuotaDo(
  doNamespace: DurableObjectNamespace,
  installationId: string,
): Promise<InspectResponse | undefined> {
  const stub = doNamespace.get(doNamespace.idFromName(installationId));
  try {
    const response = await stub.fetch(QUOTA_DO_RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "inspect",
      }),
    });
    if (!response.ok) {
      return undefined;
    }
    return (await response.json()) as InspectResponse;
  } catch {
    return undefined;
  }
}

export async function handleUsageSummaryRequest(
  request: Request,
  env: UsageSummaryEnv,
  logger: Logger = noopLogger,
  cache: ConfigCache = isolateConfigCache,
): Promise<Response> {
  const header = request.headers.get("Authorization");
  if (header === null) {
    logger.debug("usage_summary_auth_rejected", {
      code: "unauthenticated",
      reason: "missing_authorization_header",
    });
    return unauthenticatedResponse();
  }

  if (!header.startsWith("Bearer ")) {
    logger.debug("usage_summary_auth_rejected", {
      code: "unauthenticated",
      reason: "invalid_authorization_scheme",
      authorization_scheme: header.split(/\s+/)[0] ?? "unknown",
    });
    return unauthenticatedResponse();
  }

  const token = header.slice("Bearer ".length).trim();
  if (token.length === 0) {
    logger.debug("usage_summary_auth_rejected", {
      code: "unauthenticated",
      reason: "empty_bearer_token",
    });
    return unauthenticatedResponse();
  }

  const reader = createD1ConfigReader(env.DB, env.R2);
  const verifier = new IssuerTokenVerifier();
  const now = await clockNowSeconds(env);
  const nowMs = await clockNowMs(env);
  const verifyResult = await verifier.verify(token, {
    audience: "ai-platform",
    clockSkewSeconds: 60,
    now,
    nowMs,
    cache,
    reader,
    issuerId: env.ISSUER_ID,
    db: env.DB,
    alertEnv: env,
  });

  if (!verifyResult.ok) {
    logger.debug("usage_summary_auth_rejected", {
      code: verifyResult.code,
      reason:
        verifyResult.code === "suspended"
          ? "suspended"
          : "token_verification_failed",
    });
    const status = liveHttpStatusForCode(verifyResult.code) ?? 401;
    return Response.json(
      buildErrorBody({
        code: verifyResult.code,
        requestReference: generateRequestReference(),
        traceId: generateUlid(),
      }),
      { status },
    );
  }

  const installationId = verifyResult.principal.installationId;

  const entitlement = await env.DB.prepare(
    `SELECT period_start, credit_budget
     FROM entitlement
     WHERE installation_id = ?`,
  )
    .bind(installationId)
    .first<{ period_start: string; credit_budget: number }>();

  if (!entitlement?.period_start) {
    logger.error("usage_summary_entitlement_missing", { installation_id: installationId });
    const status = liveHttpStatusForCode("internal_error") ?? 500;
    return Response.json(
      buildErrorBody({
        code: "internal_error",
        requestReference: generateRequestReference(),
        traceId: generateUlid(),
      }),
      { status },
    );
  }

  const currentPeriod = periodFromIso(entitlement.period_start);
  const creditBudget = entitlement.credit_budget;

  const inspect = await inspectQuotaDo(env.DO, installationId);
  if (!inspect) {
    logger.error("usage_summary_quota_do_unavailable", { installation_id: installationId });
    const status = liveHttpStatusForCode("internal_error") ?? 500;
    return Response.json(
      buildErrorBody({
        code: "internal_error",
        requestReference: generateRequestReference(),
        traceId: generateUlid(),
      }),
      { status },
    );
  }

  const creditsUsed = inspect.state.periodCounters.creditsUsed;

  const priorRows = await env.DB.prepare(
    `SELECT json_extract(dimensions, '$.period') AS period, quota_weight
     FROM usage_rollup
     WHERE json_extract(dimensions, '$.installation_id') = ?
       AND json_extract(dimensions, '$.period') != ?
     ORDER BY period ASC`,
  )
    .bind(installationId, currentPeriod)
    .all<{ period: string; quota_weight: number }>();

  const priorPeriods = (priorRows.results ?? []).map((row) => ({
    period: row.period,
    credits_used: row.quota_weight,
  }));

  const body: UsageSummarySuccessBody = {
    current_period: {
      period: currentPeriod,
      credits_used: creditsUsed,
      credit_budget: creditBudget,
    },
    prior_periods: priorPeriods,
  };

  logger.info("usage_summary_succeeded", {
    installation_id: installationId,
    current_period: currentPeriod,
    prior_period_count: priorPeriods.length,
  });

  return Response.json(body);
}
