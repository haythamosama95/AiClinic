import { supportLookup } from "../support";
import { createManifestRetentionClassResolver } from "../retention";
import { isValidRequestReference, normalizeRequestReference } from "../reference";

export type SupportLookupOperatorAuth = {
  resolve(request: Request): { operatorId: string } | null;
};

export type SupportLookupControlBindings = {
  DB: D1Database;
  R2: R2Bucket;
};

/** Handle the operator-only request-reference lookup endpoint. */
export async function handleSupportLookup(
  request: Request,
  bindings: SupportLookupControlBindings,
  operatorAuth: SupportLookupOperatorAuth,
): Promise<Response> {
  if (operatorAuth.resolve(request) === null) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const rawReference = new URL(request.url).searchParams.get("reference");
  if (rawReference === null || rawReference.trim().length === 0) {
    return Response.json({ error: "missing_reference" }, { status: 400 });
  }

  const reference = normalizeRequestReference(rawReference.trim());
  if (!isValidRequestReference(reference)) {
    return Response.json({ error: "invalid_reference" }, { status: 400 });
  }

  const result = await supportLookup(reference, {
    db: bindings.DB,
    r2: bindings.R2,
    resolveRetentionClass: createManifestRetentionClassResolver(),
  });
  if (!result.found) {
    return Response.json({ error: "not_found" }, { status: 404 });
  }

  return Response.json({
    request: result.request,
    attempts: result.attempts,
    envelope: result.envelope,
  });
}
