/**
 * Live capability-discovery HTTP surface (I2 §5.5).
 * Composes C1 discover/buildDiscoveryResponse with B3 enrolled-key verification.
 */

import { buildDiscoveryResponse, discover } from "../capability";
import {
  isolateConfigCache,
  createD1ConfigReader,
  type ConfigCache,
} from "../config-cache";
import { buildErrorBody, liveHttpStatusForCode } from "../errors";
import { clockNowMs, clockNowSeconds } from "../clock";
import { IssuerTokenVerifier } from "../identity";
import type { AlertEnv } from "../alert";
import { noopLogger, type Logger } from "../logger";
import { generateRequestReference } from "../reference";
import { generateUlid } from "../trace";

export interface DiscoveryEnv extends AlertEnv {
  DB: D1Database;
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

export async function handleDiscoveryRequest(
  request: Request,
  env: DiscoveryEnv,
  logger: Logger = noopLogger,
  cache: ConfigCache = isolateConfigCache,
): Promise<Response> {
  const header = request.headers.get("Authorization");
  if (header === null) {
    logger.debug("discovery_auth_rejected", {
      code: "unauthenticated",
      reason: "missing_authorization_header",
    });
    return unauthenticatedResponse();
  }

  if (!header.startsWith("Bearer ")) {
    logger.debug("discovery_auth_rejected", {
      code: "unauthenticated",
      reason: "invalid_authorization_scheme",
      authorization_scheme: header.split(/\s+/)[0] ?? "unknown",
    });
    return unauthenticatedResponse();
  }

  const token = header.slice("Bearer ".length).trim();
  if (token.length === 0) {
    logger.debug("discovery_auth_rejected", {
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
    logger.debug("discovery_auth_rejected", {
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

  const discoveryResult = await discover(
    verifyResult.principal,
    cache,
    reader,
    logger,
  );
  // discover() defensive guards (revoked-grant skip, non-string plan, non-string
  // registry identity) are unreachable via production paths; kept against malformed
  // D1/registry rows — do not invent test chapters for them.
  const ifNoneMatch = request.headers.get("If-None-Match");
  logger.info("discovery_succeeded", {
    installation_id: verifyResult.principal.installationId,
    organization_id: verifyResult.principal.organizationId,
    branch_id: verifyResult.principal.branchId,
    manifest_count: discoveryResult.manifests.length,
    etag: discoveryResult.etag,
    ...(ifNoneMatch !== null ? { if_none_match: ifNoneMatch } : {}),
  });
  return buildDiscoveryResponse(
    request,
    discoveryResult.manifests,
    discoveryResult.etag,
  );
}
