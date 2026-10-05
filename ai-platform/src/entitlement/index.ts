/**
 * Entitlement stage — plan snapshot capability membership and kill switches (B3 §4.3.3–4).
 */

import { loadPlanSnapshotFromMirror } from "../capability";
import {
  type ConfigCache,
  ConfigCacheMissError,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import type { Principal } from "../identity";
import { noopLogger, type Logger } from "../logger";
import { recordGuardRejection } from "../rate-limit";

export type { Principal };

export type EntitlementContext = {
  capabilityId: string;
  capabilityVersion: string;
  minimumPlanTier?: string;
  providerId: string;
};

export type EntitlementRejectionPath =
  | "ai_disabled"
  | "plan_tier"
  | "capability_not_granted"
  | "kill_switch_global"
  | "kill_switch_capability"
  | "kill_switch_installation"
  | "kill_switch_provider";

export type EntitlementResult =
  | { ok: true }
  | {
    ok: false;
    code: "forbidden_capability" | "capability_disabled";
    path: EntitlementRejectionPath;
  }
  | {
    ok: false;
    code: "internal_error";
  };

function parseAllowedCapabilities(entitlement: Record<string, unknown>): string[] | null {
  const raw = entitlement.allowed_capabilities;
  if (Array.isArray(raw)) {
    return raw.every((entry) => typeof entry === "string") ? (raw as string[]) : null;
  }
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (!Array.isArray(parsed) || !parsed.every((entry) => typeof entry === "string")) {
        return null;
      }
      return parsed as string[];
    } catch {
      return null;
    }
  }
  return [];
}

function rejectForbidden(
  path: EntitlementRejectionPath,
  installationId: string,
  logger: Logger,
): EntitlementResult {
  logger.debug("entitlement_rejected", {
    path,
    installation_id: installationId,
    code: "forbidden_capability",
  });
  recordGuardRejection({
    error_code: "forbidden_capability",
    installation_id: installationId,
  });
  return { ok: false, code: "forbidden_capability", path };
}

function rejectKillSwitch(
  path: EntitlementRejectionPath,
  installationId: string,
  logger: Logger,
): EntitlementResult {
  logger.debug("entitlement_rejected", {
    path,
    installation_id: installationId,
    code: "capability_disabled",
  });
  recordGuardRejection({
    error_code: "capability_disabled",
    installation_id: installationId,
  });
  return { ok: false, code: "capability_disabled", path };
}

/**
 * Miss = inactive (fail-open for absence). An explicit `{ active: true }` row fails closed.
 * Production persistence of kill-switch rows is a control-plane/A5 concern; B3 only
 * evaluates the config-cache shape.
 */
async function loadKillSwitchOrInactive(
  cache: ConfigCache,
  reader: D1Reader,
  key: string,
): Promise<Record<string, unknown>> {
  try {
    return await loadConfig(cache, reader, "kill_switches", key);
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return { active: false };
    }
    throw error;
  }
}

function isKillSwitchActive(row: Record<string, unknown>): boolean {
  return row.active === true;
}

async function loadMatchingGrant(
  cache: ConfigCache,
  reader: D1Reader,
  grantKey: string,
  capabilityVersion: string,
): Promise<"granted" | "missing" | "revoked" | "version_mismatch"> {
  try {
    const grant = await loadConfig(cache, reader, "grants", grantKey);
    if (grant.revoked_at != null) {
      return "revoked";
    }
    if (
      typeof grant.capability_version === "string" &&
      grant.capability_version !== capabilityVersion
    ) {
      return "version_mismatch";
    }
    return "granted";
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return "missing";
    }
    throw error;
  }
}

export async function evaluateEntitlement(
  principal: Principal,
  ctx: EntitlementContext,
  cache: ConfigCache,
  reader: D1Reader,
  db: D1Database,
  logger: Logger = noopLogger,
): Promise<EntitlementResult> {
  const installationId = principal.installationId;

  const planSnapshot = await loadPlanSnapshotFromMirror(db, installationId);
  if (
    planSnapshot === null ||
    !planSnapshot.capabilities.includes(ctx.capabilityId)
  ) {
    return rejectForbidden("capability_not_granted", installationId, logger);
  }

  const globalSwitch = await loadKillSwitchOrInactive(cache, reader, "global");
  if (isKillSwitchActive(globalSwitch)) {
    return rejectKillSwitch("kill_switch_global", installationId, logger);
  }

  const capabilitySwitch = await loadKillSwitchOrInactive(
    cache,
    reader,
    `capability:${ctx.capabilityId}`,
  );
  if (isKillSwitchActive(capabilitySwitch)) {
    return rejectKillSwitch("kill_switch_capability", installationId, logger);
  }

  const installationSwitch = await loadKillSwitchOrInactive(
    cache,
    reader,
    `installation:${installationId}`,
  );
  if (isKillSwitchActive(installationSwitch)) {
    return rejectKillSwitch("kill_switch_installation", installationId, logger);
  }

  const providerSwitch = await loadKillSwitchOrInactive(
    cache,
    reader,
    `provider:${ctx.providerId}`,
  );
  if (isKillSwitchActive(providerSwitch)) {
    return rejectKillSwitch("kill_switch_provider", installationId, logger);
  }

  return { ok: true };
}

export type CoveragePrecheckContext = {
  providerId: string;
};

export type CoveragePrecheckResult =
  | { ok: true }
  | {
    ok: false;
    code: "suspended" | "coverage_lapsed" | "capability_disabled" | "internal_error";
    coverageReason?: "none";
  };

/**
 * Stage 3 — read `coverage_mirror` for suspension and evaluate kill switches only.
 */
export async function evaluateCoveragePrecheck(
  principal: Principal,
  ctx: CoveragePrecheckContext,
  db: D1Database,
  cache: ConfigCache,
  reader: D1Reader,
  logger: Logger = noopLogger,
): Promise<CoveragePrecheckResult> {
  const installationId = principal.installationId;

  const mirror = await db
    .prepare(
      `SELECT suspended FROM coverage_mirror WHERE installation_id = ?`,
    )
    .bind(installationId)
    .first<{ suspended: number }>();
  if (mirror === null) {
    recordGuardRejection({
      error_code: "coverage_lapsed",
      installation_id: installationId,
    });
    return { ok: false, code: "coverage_lapsed", coverageReason: "none" };
  }
  if (mirror.suspended !== 0) {
    recordGuardRejection({
      error_code: "suspended",
      installation_id: installationId,
    });
    return { ok: false, code: "suspended" };
  }

  const globalSwitch = await loadKillSwitchOrInactive(cache, reader, "global");
  if (isKillSwitchActive(globalSwitch)) {
    rejectKillSwitch("kill_switch_global", installationId, logger);
    return { ok: false, code: "capability_disabled" };
  }

  const installationSwitch = await loadKillSwitchOrInactive(
    cache,
    reader,
    `installation:${installationId}`,
  );
  if (isKillSwitchActive(installationSwitch)) {
    rejectKillSwitch("kill_switch_installation", installationId, logger);
    return { ok: false, code: "capability_disabled" };
  }

  const providerSwitch = await loadKillSwitchOrInactive(
    cache,
    reader,
    `provider:${ctx.providerId}`,
  );
  if (isKillSwitchActive(providerSwitch)) {
    rejectKillSwitch("kill_switch_provider", installationId, logger);
    return { ok: false, code: "capability_disabled" };
  }

  return { ok: true };
}
