import { writeEntrypointAudit } from "./audit";
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

  await DB.prepare(
    "UPDATE installation SET status = ? WHERE installation_id = ?",
  )
    .bind(status, installationId)
    .run();

  await writeEntrypointAudit(DB, actor, action, installationId, null);

  return { ok: true, body: { installation_id: installationId, status } };
}
