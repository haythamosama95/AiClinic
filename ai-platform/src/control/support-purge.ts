import { purgeByInstallationId } from "../retention";
import { supportLookup } from "../support";
import { ok, reject, requireOperator } from "./http";
import type { ControlBindings, OperatorAuth } from "./types";

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
  const reference = url.searchParams.get("reference");
  if (!reference) {
    return reject(400, "missing_reference");
  }

  const result = await supportLookup(reference, {
    db: bindings.DB,
    r2: bindings.R2,
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
    return reject(400, "invalid_route");
  }

  await purgeByInstallationId(targetId, auth.operatorId, {
    db: bindings.DB,
    r2: bindings.R2,
  });

  return ok();
}
