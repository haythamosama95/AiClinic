/**
 * Entitlement stage — AI-enablement, plan tier, capability grant, kill switches (B3 §4.3.3–4).
 */

import {
  type ConfigCache,
  type ConfigEntityKind,
  ConfigCacheMissError,
  type D1Reader,
  loadConfig,
} from "../config-cache";

export type Principal = {
  readonly installationId: string;
  readonly organizationId: string;
  readonly branchId: string;
  readonly actorId: string;
  readonly role: string;
  readonly scopes: readonly string[];
  readonly jti: string;
  readonly iat: number;
  readonly exp: number;
  readonly ver: string;
};

export type EntitlementContext = {
  capabilityId: string;
  capabilityVersion: string;
  minimumPlanTier: string;
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
    };

/** Plan tier rank — lower index means lower tier (§4.3.4 plan-level allowances). */
const PLAN_TIER_ORDER = ["starter", "standard", "professional", "enterprise"] as const;

function scopeReaderForKind(reader: D1Reader, kind: ConfigEntityKind): D1Reader {
  return {
    read(key: string) {
      return reader.read(`${kind}:${key}`);
    },
  };
}

function parseAllowedCapabilities(entitlement: Record<string, unknown>): string[] {
  const raw = entitlement.allowed_capabilities;
  if (Array.isArray(raw)) {
    return raw as string[];
  }
  if (typeof raw === "string") {
    return JSON.parse(raw) as string[];
  }
  return [];
}

function planTierMeetsMinimum(plan: string, minimum: string): boolean {
  const planRank = PLAN_TIER_ORDER.indexOf(plan as typeof PLAN_TIER_ORDER[number]);
  const minimumRank = PLAN_TIER_ORDER.indexOf(
    minimum as typeof PLAN_TIER_ORDER[number],
  );
  if (planRank === -1 || minimumRank === -1) {
    return false;
  }
  return planRank >= minimumRank;
}

function rejectForbidden(path: EntitlementRejectionPath): EntitlementResult {
  return { ok: false, code: "forbidden_capability", path };
}

function rejectKillSwitch(path: EntitlementRejectionPath): EntitlementResult {
  return { ok: false, code: "capability_disabled", path };
}

async function loadKillSwitch(
  cache: ConfigCache,
  reader: D1Reader,
  key: string,
): Promise<Record<string, unknown>> {
  return loadConfig(cache, scopeReaderForKind(reader, "kill_switches"), "kill_switches", key);
}

function isKillSwitchActive(row: Record<string, unknown>): boolean {
  return row.active === true;
}

export async function evaluateEntitlement(
  principal: Principal,
  ctx: EntitlementContext,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<EntitlementResult> {
  const installationId = principal.installationId;

  const entitlement = await loadConfig(
    cache,
    scopeReaderForKind(reader, "entitlements"),
    "entitlements",
    installationId,
  );

  const entitlementStatus = entitlement.status;
  if (entitlementStatus !== "active") {
    return rejectForbidden("ai_disabled");
  }

  const plan = entitlement.plan;
  if (typeof plan !== "string" || !planTierMeetsMinimum(plan, ctx.minimumPlanTier)) {
    return rejectForbidden("plan_tier");
  }

  const allowedCapabilities = parseAllowedCapabilities(entitlement);
  if (!allowedCapabilities.includes(ctx.capabilityId)) {
    return rejectForbidden("capability_not_granted");
  }

  const grantKey = `${installationId}/${ctx.capabilityId}`;
  try {
    const grant = await loadConfig(
      cache,
      scopeReaderForKind(reader, "grants"),
      "grants",
      grantKey,
    );
    if (grant.revoked_at != null) {
      return rejectForbidden("capability_not_granted");
    }
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return rejectForbidden("capability_not_granted");
    }
    throw error;
  }

  const globalSwitch = await loadKillSwitch(cache, reader, "global");
  if (isKillSwitchActive(globalSwitch)) {
    return rejectKillSwitch("kill_switch_global");
  }

  const capabilitySwitch = await loadKillSwitch(
    cache,
    reader,
    `capability:${ctx.capabilityId}`,
  );
  if (isKillSwitchActive(capabilitySwitch)) {
    return rejectKillSwitch("kill_switch_capability");
  }

  const installationSwitch = await loadKillSwitch(
    cache,
    reader,
    `installation:${installationId}`,
  );
  if (isKillSwitchActive(installationSwitch)) {
    return rejectKillSwitch("kill_switch_installation");
  }

  const providerSwitch = await loadKillSwitch(
    cache,
    reader,
    `provider:${ctx.providerId}`,
  );
  if (isKillSwitchActive(providerSwitch)) {
    return rejectKillSwitch("kill_switch_provider");
  }

  return { ok: true };
}
