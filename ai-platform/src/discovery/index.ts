/**
 * Live capability-discovery HTTP surface (I2 §5.5).
 * Composes C1 discover/buildDiscoveryResponse with B3 enrolled-key verification.
 */

import { buildDiscoveryResponse, discover } from "../capability";
import { ConfigCache, createD1ConfigReader } from "../config-cache";
import { buildErrorBody, liveHttpStatusForCode } from "../errors";
import { EnrolledKeyVerifier } from "../identity";
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
): Promise<Response> {
  const header = request.headers.get("Authorization");
  if (header === null || !header.startsWith("Bearer ")) {
    return unauthenticatedResponse();
  }

  const token = header.slice("Bearer ".length).trim();
  if (token.length === 0) {
    return unauthenticatedResponse();
  }

  const cache = new ConfigCache();
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

  const discoveryResult = await discover(verifyResult.principal, cache, reader);
  return buildDiscoveryResponse(
    request,
    discoveryResult.manifests,
    discoveryResult.etag,
  );
}
