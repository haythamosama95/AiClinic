import { writeEntrypointAudit } from "./audit";
import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireNonEmptyString,
  requireOperator,
} from "./http";
import type {
  ControlActionResult,
  ControlBindings,
  OperatorAuth,
  TokenContractRetirePayload,
} from "./types";

const ROTATION_TARGET_VER = "2";

export async function beginTokenContractRotationAction(
  bindings: ControlBindings,
  actor: string,
): Promise<ControlActionResult> {
  const { DB } = bindings;
  const ver = ROTATION_TARGET_VER;

  const current = await DB.prepare(
    "SELECT ver, retired_at FROM token_contract WHERE ver = ?",
  )
    .bind(ver)
    .first<{ ver: string; retired_at: string | null }>();
  if (current && current.retired_at === null) {
    return { ok: true, body: { ver } };
  }

  const addedAt = nowIso();
  const batchResults = await DB.batch([
    DB.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       SELECT ?, ?, NULL, ?
       WHERE (SELECT COUNT(*) FROM token_contract WHERE retired_at IS NULL) < 2
         AND NOT EXISTS (SELECT 1 FROM token_contract WHERE ver = ?)`,
    ).bind(ver, addedAt, actor, ver),
  ]);

  if ((batchResults[0]?.meta.changes ?? 0) === 0) {
    const existing = await DB.prepare("SELECT ver FROM token_contract WHERE ver = ?")
      .bind(ver)
      .first<{ ver: string }>();
    if (existing) {
      return { ok: false, status: 409, error: "ver_already_exists" };
    }
    return { ok: false, status: 409, error: "rotation_already_open" };
  }

  await writeEntrypointAudit(
    DB,
    actor,
    "token_contract_begin_rotation",
    ver,
    null,
  );

  return { ok: true, body: { ver } };
}

export async function retireTokenContractAction(
  bindings: ControlBindings,
  actor: string,
  args: Record<string, unknown>,
): Promise<ControlActionResult> {
  const verRaw = requireNonEmptyString(args.ver);
  if (verRaw === null) {
    return { ok: false, status: 400, error: "invalid_ver" };
  }
  const ver = verRaw.trim();

  const { DB } = bindings;
  const retiredAt = nowIso();
  const auditId = newId();
  const batchResults = await DB.batch([
    DB.prepare(
      `UPDATE token_contract
       SET retired_at = ?, changed_by = ?
       WHERE ver = ?
         AND retired_at IS NULL
         AND (SELECT cnt FROM (
           SELECT COUNT(*) AS cnt FROM token_contract WHERE retired_at IS NULL
         )) >= 2`,
    ).bind(retiredAt, actor, ver),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       SELECT ?, ?, 'token_contract_retire', ?, NULL, NULL, ?
       WHERE EXISTS (
         SELECT 1 FROM token_contract WHERE ver = ? AND retired_at = ?
       )`,
    ).bind(auditId, actor, ver, retiredAt, ver, retiredAt),
  ]);

  if ((batchResults[0]?.meta.changes ?? 0) === 0) {
    const row = await DB.prepare(
      "SELECT ver, retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(ver)
      .first<{ ver: string; retired_at: string | null }>();

    if (!row) {
      return { ok: false, status: 404, error: "ver_not_found" };
    }
    if (row.retired_at != null) {
      return { ok: false, status: 409, error: "ver_already_retired" };
    }
    return { ok: false, status: 409, error: "no_rotation_open" };
  }

  return { ok: true, body: { ver, retired_at: retiredAt } };
}

export async function handleTokenContractBeginRotation(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const body = await parseJsonBody<{ ver: string }>(request);
  if (body instanceof Response) {
    return body;
  }

  const verRaw = requireNonEmptyString(body.ver);
  if (verRaw === null) {
    return reject(400, "invalid_ver");
  }

  const result = await beginTokenContractRotationAction(bindings, auth.operatorId);
  if (!result.ok) {
    return reject(result.status, result.error);
  }
  return ok(result.body);
}

export async function handleTokenContractRetire(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const body = await parseJsonBody<TokenContractRetirePayload>(request);
  if (body instanceof Response) {
    return body;
  }

  const result = await retireTokenContractAction(bindings, auth.operatorId, body);
  if (!result.ok) {
    return reject(result.status, result.error);
  }
  return ok(result.body);
}
