/**
 * Administrator coverage read (P3.9 GET /v1/coverage).
 */

import {
  CHANNEL_VERSIONS,
  projectCoverageSnapshot,
  subscriptionRef,
} from "vendor-contracts";
import {
  isolateConfigCache,
  createD1ConfigReader,
  type ConfigCache,
} from "../config-cache";
import type { AlertEnv } from "../alert";
import { clockNowMs, clockNowSeconds } from "../clock";
import { buildErrorBody, liveHttpStatusForCode } from "../errors";
import { IssuerTokenVerifier } from "../identity";
import { noopLogger, type Logger } from "../logger";
import type { ReadCoverageResponse } from "../quota-do";
import { generateRequestReference } from "../reference";
import { generateUlid } from "../trace";
import { decodeDoResponse } from "../quota-do/response-decoder";

const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

export interface CoverageReadEnv extends AlertEnv {
  DB: D1Database;
  DO: DurableObjectNamespace;
  R2?: R2Bucket;
  ISSUER_ID: string;
  TEST_CLOCK?: string;
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

async function callReadCoverage(
  doNamespace: DurableObjectNamespace,
  installationId: string,
  orgId: string,
): Promise<
  | { ok: true; body: ReadCoverageResponse }
  | { ok: false; reason: "unavailable" | "contract_rejected" }
> {
  const stub = doNamespace.get(doNamespace.idFromName(installationId));
  try {
    const response = await stub.fetch(QUOTA_DO_RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        installationId,
        kind: "read_coverage",
        orgId,
        vendorContractVersion: CHANNEL_VERSIONS.platformDo,
      }),
    });
    if (!response.ok) {
      return { ok: false, reason: "unavailable" };
    }
    let body: ReadCoverageResponse | undefined;
    try {
      body = decodeDoResponse<ReadCoverageResponse>(
        await response.json(),
        CHANNEL_VERSIONS.platformDo,
      );
    } catch {
      return { ok: false, reason: "contract_rejected" };
    }
    if (body === undefined) {
      return { ok: false, reason: "contract_rejected" };
    }
    return { ok: true, body };
  } catch {
    return { ok: false, reason: "unavailable" };
  }
}

export async function handleCoverageReadRequest(
  request: Request,
  env: CoverageReadEnv,
  logger: Logger = noopLogger,
  cache: ConfigCache = isolateConfigCache,
): Promise<Response> {
  const header = request.headers.get("Authorization");
  if (header === null) {
    return unauthenticatedResponse();
  }

  if (!header.startsWith("Bearer ")) {
    return unauthenticatedResponse();
  }

  const token = header.slice("Bearer ".length).trim();
  if (token.length === 0) {
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
    // R7-PS4: the administrator's diagnostic read is served while the installation is suspended.
    // The suspended flag in the returned snapshot is authoritative; admission routes never set this.
    allowSuspended: true,
  });

  if (!verifyResult.ok) {
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

  if (verifyResult.principal.role !== "administrator") {
    return new Response(null, { status: 403 });
  }

  const orgId = verifyResult.principal.organizationId;
  const installationId = verifyResult.principal.installationId;

  const doResponse = await callReadCoverage(env.DO, installationId, orgId);
  if (!doResponse.ok) {
    if (doResponse.reason === "contract_rejected") {
      const status = liveHttpStatusForCode("coverage_unknown") ?? 503;
      return Response.json(
        buildErrorBody({
          code: "coverage_unknown",
          requestReference: generateRequestReference(),
          traceId: generateUlid(),
        }),
        { status },
      );
    }
    logger.error("coverage_read_do_unavailable", { installation_id: installationId });
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

  const subRef = await subscriptionRef(orgId);
  return Response.json({
    subscription_ref: subRef,
    snapshot: projectCoverageSnapshot(doResponse.body.snapshot),
    queued_terms: doResponse.body.queued_terms,
    recent_terms: doResponse.body.recent_terms,
  });
}
