import { buildEntrypointAuditStatement } from "./audit";
import type { ControlActionResult, ControlBindings } from "./types";

export async function setInstallationSuspendedAction(
  bindings: ControlBindings,
  actor: string,
  installationId: string,
  suspended: boolean,
): Promise<ControlActionResult> {
  const { DB } = bindings;
  const status = suspended ? "suspended" : "active";
  const action = suspended ? "suspend" : "resume";

  const existing = await DB.prepare(
    "SELECT status FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ status: string }>();
  if (!existing) {
    return { ok: false, status: 404, error: "installation_not_found" };
  }
  if (existing.status === status) {
    return { ok: true, body: { installation_id: installationId, status } };
  }

  const results = await DB.batch([
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ? AND status = ?",
    ).bind(status, installationId, existing.status),
    buildEntrypointAuditStatement(
      DB,
      actor,
      action,
      installationId,
      null,
      existing.status,
      status,
      true,
    ),
  ]);

  if ((results[0]?.meta.changes ?? 0) === 0) {
    const current = await DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(installationId)
      .first<{ status: string }>();
    if (!current) {
      return { ok: false, status: 404, error: "installation_not_found" };
    }
    if (current.status !== status) {
      return { ok: false, status: 409, error: "illegal_installation_transition" };
    }
  }

  return { ok: true, body: { installation_id: installationId, status } };
}
