import {
  isValidRequestReference,
  normalizeRequestReference,
} from "../reference";
import {
  createManifestRetentionClassResolver,
  purgeByInstallationId,
} from "../retention";
import { supportLookup } from "../support";
import { writeAudit } from "./audit";
import { ok, reject, requireOperator } from "./http";
import type { ControlBindings, OperatorAuth } from "./types";

const INSTALLATION_DELETED_STATUS = "deleted";

async function runPurge(
  installationId: string,
  operatorId: string,
  bindings: { db: D1Database; r2: R2Bucket },
): Promise<Response | null> {
  try {
    await purgeByInstallationId(installationId, operatorId, bindings);
    return null;
  } catch {
    return reject(500, "storage_error");
  }
}

export async function handleSupportLookup(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  if (!bindings.R2) {
    return reject(500, "missing_r2_binding");
  }

  const url = new URL(request.url);
  const raw = url.searchParams.get("reference");
  if (!raw || raw.trim() === "") {
    return reject(400, "missing_reference");
  }

  const normalized = normalizeRequestReference(raw.trim());
  if (!isValidRequestReference(normalized)) {
    return reject(400, "invalid_reference");
  }

  const result = await supportLookup(normalized, {
    db: bindings.DB,
    r2: bindings.R2,
    resolveRetentionClass: createManifestRetentionClassResolver(),
  });

  if (!result.found) {
    return reject(404, "not_found");
  }

  return ok({
    request: result.request,
    attempts: result.attempts,
    envelope: result.envelope,
  });
}

export async function handleInstallationPurge(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  if (!bindings.R2) {
    return reject(500, "missing_r2_binding");
  }

  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/purge$/,
  );
  const targetId = match?.[1];
  if (!targetId) {
    // Unreachable via HTTP because dispatch pre-filters with identical regexes; reachable via direct handler invocation in tests; kept as a safety net.
    return reject(400, "invalid_route");
  }

  const installation = await bindings.DB.prepare(
    "SELECT status FROM installation WHERE installation_id = ?",
  )
    .bind(targetId)
    .first<{ status: string }>();

  if (
    installation &&
    installation.status !== INSTALLATION_DELETED_STATUS
  ) {
    return reject(409, "illegal_lifecycle_transition");
  }

  // Intent-to-purge audit before retention deletes: retention/index.ts still
  // journals completion after its D1 batch (owned elsewhere). Writing first
  // ensures an operator-identity row exists even if the completion audit fails.
  await writeAudit(
    bindings.DB,
    auth.operatorId,
    "purge_installation",
    targetId,
  );

  const purgeError = await runPurge(targetId, auth.operatorId, {
    db: bindings.DB,
    r2: bindings.R2,
  });
  if (purgeError) {
    return purgeError;
  }

  return ok();
}
