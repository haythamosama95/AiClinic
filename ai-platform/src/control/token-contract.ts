import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireOperator,
} from "./http";
import type {
  ControlBindings,
  OperatorAuth,
  TokenContractBeginPayload,
  TokenContractRetirePayload,
} from "./types";

export async function handleTokenContractBeginRotation(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const body = await parseJsonBody<TokenContractBeginPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  const ver = body.ver?.trim();
  if (!ver) {
    return reject(400, "invalid_ver");
  }

  const { DB } = bindings;
  const addedAt = nowIso();
  const auditId = newId();
  // Atomic FR-002 guard + audit: count check, insert, and control_audit share
  // one D1 batch. Audit INSERT is conditioned on the new row fingerprint so a
  // failed guard (0 changes) does not leave a spurious audit row.
  const batchResults = await DB.batch([
    DB.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       SELECT ?, ?, NULL, ?
       WHERE (SELECT COUNT(*) FROM token_contract WHERE retired_at IS NULL) < 2
         AND NOT EXISTS (SELECT 1 FROM token_contract WHERE ver = ?)`,
    ).bind(ver, addedAt, auth.operatorId, ver),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       SELECT ?, ?, 'token_contract_begin_rotation', ?, NULL, NULL, ?
       WHERE EXISTS (
         SELECT 1 FROM token_contract WHERE ver = ? AND added_at = ?
       )`,
    ).bind(auditId, auth.operatorId, ver, addedAt, ver, addedAt),
  ]);

  if ((batchResults[0]?.meta.changes ?? 0) === 0) {
    const existing = await DB.prepare("SELECT ver FROM token_contract WHERE ver = ?")
      .bind(ver)
      .first<{ ver: string }>();
    if (existing) {
      return reject(409, "ver_already_exists");
    }
    return reject(409, "rotation_already_open");
  }

  return ok({ ver });
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

  const ver = body.ver?.trim();
  if (!ver) {
    return reject(400, "invalid_ver");
  }

  const { DB } = bindings;
  const retiredAt = nowIso();
  const auditId = newId();
  // Atomic retire + audit: stamp and journal share one D1 batch. Audit is
  // conditioned on the retired_at fingerprint so failed guards write nothing.
  const batchResults = await DB.batch([
    DB.prepare(
      `UPDATE token_contract
       SET retired_at = ?, changed_by = ?
       WHERE ver = ?
         AND retired_at IS NULL
         AND (SELECT cnt FROM (
           SELECT COUNT(*) AS cnt FROM token_contract WHERE retired_at IS NULL
         )) >= 2`,
    ).bind(retiredAt, auth.operatorId, ver),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       SELECT ?, ?, 'token_contract_retire', ?, NULL, NULL, ?
       WHERE EXISTS (
         SELECT 1 FROM token_contract WHERE ver = ? AND retired_at = ?
       )`,
    ).bind(auditId, auth.operatorId, ver, retiredAt, ver, retiredAt),
  ]);

  if ((batchResults[0]?.meta.changes ?? 0) === 0) {
    const row = await DB.prepare(
      "SELECT ver, retired_at FROM token_contract WHERE ver = ?",
    )
      .bind(ver)
      .first<{ ver: string; retired_at: string | null }>();

    if (!row) {
      return reject(404, "ver_not_found");
    }
    if (row.retired_at != null) {
      return reject(409, "ver_already_retired");
    }
    return reject(409, "no_rotation_open");
  }

  return ok({ ver, retired_at: retiredAt });
}
