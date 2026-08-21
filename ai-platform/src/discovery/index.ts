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
import { EnrolledKeyVerifier } from "../identity";
import { noopLogger, type Logger } from "../logger";
import { generateRequestReference } from "../reference";
import { generateUlid } from "../trace";

export interface DiscoveryEnv {
  DB: D1Database;
  R2?: R2Bucket;
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
  const verifier = new EnrolledKeyVerifier();
  const verifyResult = await verifier.verify(token, {
    audience: "ai-platform",
    clockSkewSeconds: 60,
    now: Math.floor(Date.now() / 1000),
    cache,
    reader,
  });

  if (!verifyResult.ok) {
    logger.debug("discovery_auth_rejected", {
      code: verifyResult.code,
      reason:
        verifyResult.code === "installation_suspended"
          ? "installation_suspended"
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
