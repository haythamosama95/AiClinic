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
  const addedAt = nowIso();
  // Atomic FR-002 guard: count check and insert share one statement so two
  // concurrent begin-rotation requests cannot both observe count=1 and insert.
  const insertResult = await DB.prepare(
    `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
     SELECT ?, ?, NULL, ?
     WHERE (SELECT COUNT(*) FROM token_contract WHERE retired_at IS NULL) < 2
       AND NOT EXISTS (SELECT 1 FROM token_contract WHERE ver = ?)`,
  )
    .bind(ver, addedAt, auth.operatorId, ver)
    .run();

  if ((insertResult.meta.changes ?? 0) === 0) {
    const existing = await DB.prepare("SELECT ver FROM token_contract WHERE ver = ?")
      .bind(ver)
      .first<{ ver: string }>();
    if (existing) {
      return reject(409, "ver_already_exists");
    }
    return reject(409, "rotation_already_open");
  }

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
  const retiredAt = nowIso();
  // Atomic retire: stamp only when the named ver is still accepted and the
  // accepted set has at least two members (forbids emptying to zero).
  const updateResult = await DB.prepare(
    `UPDATE token_contract
     SET retired_at = ?, changed_by = ?
     WHERE ver = ?
       AND retired_at IS NULL
       AND (SELECT cnt FROM (
         SELECT COUNT(*) AS cnt FROM token_contract WHERE retired_at IS NULL
       )) >= 2`,
  )
    .bind(retiredAt, auth.operatorId, ver)
    .run();

  if ((updateResult.meta.changes ?? 0) === 0) {
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

  await writeAudit(DB, auth.operatorId, "token_contract_retire", ver);

  return ok({ ver, retired_at: retiredAt });
}
