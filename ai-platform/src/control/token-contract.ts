import { writeAudit } from "./audit";
import {
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
  const accepted = await DB.prepare(
    "SELECT COUNT(*) AS count FROM token_contract WHERE retired_at IS NULL",
  ).first<{ count: number }>();

  if ((accepted?.count ?? 0) >= 2) {
    return reject(409, "rotation_already_open");
  }

  const existing = await DB.prepare("SELECT ver FROM token_contract WHERE ver = ?")
    .bind(ver)
    .first<{ ver: string }>();

  if (existing) {
    return reject(409, "ver_already_exists");
  }

  const addedAt = nowIso();
  await DB.prepare(
    `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
     VALUES (?, ?, NULL, ?)`,
  )
    .bind(ver, addedAt, auth.operatorId)
    .run();

  await writeAudit(DB, auth.operatorId, "token_contract_begin_rotation", ver);

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

  const accepted = await DB.prepare(
    "SELECT COUNT(*) AS count FROM token_contract WHERE retired_at IS NULL",
  ).first<{ count: number }>();

  if ((accepted?.count ?? 0) < 2) {
    return reject(409, "no_rotation_open");
  }

  const retiredAt = nowIso();
  await DB.prepare(
    "UPDATE token_contract SET retired_at = ?, changed_by = ? WHERE ver = ?",
  )
    .bind(retiredAt, auth.operatorId, ver)
    .run();

  await writeAudit(DB, auth.operatorId, "token_contract_retire", ver);

  return ok({ ver, retired_at: retiredAt });
}
