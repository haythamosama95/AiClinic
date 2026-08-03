/**
 * Capability registry, resolver stage, and discovery (C1 §4.3.4, §5.5).
 */

import {
  type ConfigCache,
  ConfigCacheMissError,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import type { Principal } from "../identity";
import { hashManifest, type Manifest } from "../manifest";

export type CapabilityRegistry = Map<string, Manifest>;

export type ResolveResult =
  | { ok: true; manifest: Manifest }
  | {
      ok: false;
      code:
        | "capability_unknown"
        | "capability_retired"
        | "capability_disabled"
        | "forbidden_capability";
    };

export type DiscoveryResult = {
  manifests: Manifest[];
  etag: string;
};

const PLAN_TIER_ORDER = ["starter", "standard", "professional", "enterprise"] as const;

/** OD-9 overlap window: two client release cycles, minimum 90 days (not a configuration surface). */
export const OVERLAP_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;

export type LifecycleOverlay = {
  lifecycle_state?: string;
  successor_id?: string | null;
  deprecated_at?: string;
  retire_after?: string;
};

export type EffectiveLifecycle = {
  lifecycleState: string;
  successorId: string | null;
};

let capabilityRegistry: CapabilityRegistry = new Map();
let registryInstalled = false;

export function effectiveLifecycle(
  manifest: Manifest,
  overlay: LifecycleOverlay | null,
): EffectiveLifecycle {
  const publishedState =
    typeof manifest.Identity.lifecycleState === "string"
      ? manifest.Identity.lifecycleState
      : "active";
  const publishedSuccessor =
    typeof manifest.Identity.successorId === "string"
      ? manifest.Identity.successorId
      : null;

  if (!overlay || overlay.lifecycle_state == null) {
    return { lifecycleState: publishedState, successorId: publishedSuccessor };
  }

  return {
    lifecycleState: overlay.lifecycle_state,
    successorId:
      overlay.successor_id != null ? overlay.successor_id : publishedSuccessor,
  };
}

async function loadLifecycleOverlay(
  cache: ConfigCache,
  reader: D1Reader,
  capabilityId: string,
  version: string,
): Promise<LifecycleOverlay | null> {
  try {
    const row = await loadConfig(
      cache,
      reader,
      "grants",
      `global/${capabilityId}/${version}`,
    );
    return {
      lifecycle_state:
        typeof row.lifecycle_state === "string" ? row.lifecycle_state : undefined,
      successor_id:
        typeof row.successor_id === "string" ? row.successor_id : null,
      deprecated_at:
        typeof row.deprecated_at === "string" ? row.deprecated_at : undefined,
      retire_after:
        typeof row.retire_after === "string" ? row.retire_after : undefined,
    };
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return null;
    }
    throw error;
  }
}

function manifestWithEffectiveIdentity(
  manifest: Manifest,
  effective: EffectiveLifecycle,
): Manifest {
  if (
    manifest.Identity.lifecycleState === effective.lifecycleState &&
    manifest.Identity.successorId === effective.successorId
  ) {
    return manifest;
  }

  const derived = {
    ...manifest,
    Identity: {
      ...manifest.Identity,
      lifecycleState: effective.lifecycleState,
      successorId: effective.successorId,
    },
  };
  return freezeManifest(derived as Manifest);
}

function registryKey(capabilityId: string, version: string): string {
  return `${capabilityId}@${version}`;
}

function parseAllowedCapabilities(entitlement: Record<string, unknown>): string[] {
  const raw = entitlement.allowed_capabilities;
  if (Array.isArray(raw)) {
    return raw.every((entry) => typeof entry === "string") ? (raw as string[]) : [];
  }
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (!Array.isArray(parsed) || !parsed.every((entry) => typeof entry === "string")) {
        return [];
      }
      return parsed as string[];
    } catch {
      return [];
    }
  }
  return [];
}

function planTierMeetsMinimum(plan: string, minimum: string): boolean {
  const planRank = PLAN_TIER_ORDER.indexOf(plan as (typeof PLAN_TIER_ORDER)[number]);
  const minimumRank = PLAN_TIER_ORDER.indexOf(
    minimum as (typeof PLAN_TIER_ORDER)[number],
  );
  if (planRank === -1 || minimumRank === -1) {
    return false;
  }
  return planRank >= minimumRank;
}

function isKillSwitchActive(row: Record<string, unknown>): boolean {
  return row.active === true;
}

/** Absent kill-switch row ⇒ inactive (miss returns `{ active: false }`). */
async function loadKillSwitch(
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

async function assertPlanAllowance(
  principal: Principal,
  capabilityId: string,
  version: string,
  manifest: Manifest,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<{ ok: true } | { ok: false; code: "forbidden_capability" }> {
  const installationId = principal.installationId;
  const forbidden = {
    ok: false as const,
    code: "forbidden_capability" as const,
  };

  let entitlement: Record<string, unknown>;
  try {
    entitlement = await loadConfig(cache, reader, "entitlements", installationId);
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return forbidden;
    }
    throw error;
  }

  if (entitlement.status !== "active") {
    return forbidden;
  }

  const plan = entitlement.plan;
  if (typeof plan !== "string") {
    return forbidden;
  }

  const allowedCapabilities = parseAllowedCapabilities(entitlement);
  if (allowedCapabilities.length === 0 || !allowedCapabilities.includes(capabilityId)) {
    return forbidden;
  }

  const minimumPlanTier = manifest.Access.minimumPlanTier;
  if (
    typeof minimumPlanTier !== "string" ||
    !planTierMeetsMinimum(plan, minimumPlanTier)
  ) {
    return forbidden;
  }

  const installationGrant = await loadMatchingGrant(
    cache,
    reader,
    `${installationId}/${capabilityId}`,
    version,
  );
  if (installationGrant === "revoked" || installationGrant === "version_mismatch") {
    return forbidden;
  }
  if (installationGrant === "missing") {
    const planGrant = await loadMatchingGrant(
      cache,
      reader,
      `plan:${plan}/${capabilityId}`,
      version,
    );
    if (planGrant !== "granted") {
      return forbidden;
    }
  }

  return { ok: true };
}

async function resolveProviderId(
  manifest: Manifest,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<string | undefined> {
  const policyRef = manifest.Routing.routingPolicyRef;
  if (typeof policyRef !== "string") {
    return undefined;
  }

  try {
    const policy = await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      policyRef,
    );
    const providerId = policy.provider_id ?? policy.providerId;
    return typeof providerId === "string" ? providerId : undefined;
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return undefined;
    }
    throw error;
  }
}

async function isCapabilityDisabled(
  principal: Principal,
  capabilityId: string,
  manifest: Manifest,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<boolean> {
  const installationId = principal.installationId;
  const killSwitchKeys = [
    "global",
    `capability:${capabilityId}`,
    `installation:${installationId}`,
  ];

  const providerId = await resolveProviderId(manifest, cache, reader);
  if (providerId !== undefined) {
    killSwitchKeys.push(`provider:${providerId}`);
  }

  for (const key of killSwitchKeys) {
    const row = await loadKillSwitch(cache, reader, key);
    if (isKillSwitchActive(row)) {
      return true;
    }
  }

  return false;
}

function manifestToHashInput(manifest: Manifest): Record<string, unknown> {
  return {
    Identity: manifest.Identity,
    Access: manifest.Access,
    Interaction: manifest.Interaction,
    Input: manifest.Input,
    "Context requirements": manifest["Context requirements"],
    "Prompt binding": manifest["Prompt binding"],
    Output: manifest.Output,
    Routing: manifest.Routing,
    Economics: manifest.Economics,
    Governance: manifest.Governance,
  };
}

function sortManifests(manifests: Manifest[]): Manifest[] {
  return [...manifests].sort((left, right) =>
    registryKey(left.Identity.capabilityId as string, left.Identity.version as string).localeCompare(
      registryKey(right.Identity.capabilityId as string, right.Identity.version as string),
    ),
  );
}

function deepFreeze<T extends object>(value: T): T {
  Object.freeze(value);
  for (const key of Object.keys(value)) {
    const entry = (value as Record<string, unknown>)[key];
    if (entry !== null && typeof entry === "object" && !Object.isFrozen(entry)) {
      deepFreeze(entry as object);
    }
  }
  return value;
}

function freezeManifest(manifest: Manifest): Manifest {
  return deepFreeze(manifest);
}

function unmodifiableRegistry(registry: Map<string, Manifest>): CapabilityRegistry {
  return new Proxy(registry, {
    get(target, prop, receiver) {
      if (prop === "set" || prop === "delete" || prop === "clear") {
        return () => {
          throw new TypeError("CapabilityRegistry is immutable");
        };
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? (value as Function).bind(target) : value;
    },
  });
}

export function createCapabilityRegistry(manifests: Manifest[]): CapabilityRegistry {
  const registry: CapabilityRegistry = new Map();
  for (const manifest of manifests) {
    const capabilityId = manifest.Identity.capabilityId;
    const version = manifest.Identity.version;
    if (typeof capabilityId !== "string" || typeof version !== "string") {
      throw new TypeError(
        "createCapabilityRegistry: Identity.capabilityId and Identity.version must be strings",
      );
    }
    registry.set(registryKey(capabilityId, version), freezeManifest(manifest));
  }
  return unmodifiableRegistry(registry);
}

export function setCapabilityRegistry(
  registry: CapabilityRegistry,
  options?: { replace?: boolean },
): void {
  if (registryInstalled && options?.replace !== true) {
    throw new Error(
      "CapabilityRegistry is already installed; pass { replace: true } to replace",
    );
  }
  capabilityRegistry = registry;
  registryInstalled = true;
}

export async function resolve(
  principal: Principal,
  capabilityId: string,
  version: string,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<ResolveResult> {
  const manifest = capabilityRegistry.get(registryKey(capabilityId, version));
  if (manifest === undefined) {
    return { ok: false, code: "capability_unknown" };
  }

  const overlay = await loadLifecycleOverlay(cache, reader, capabilityId, version);
  const effective = effectiveLifecycle(manifest, overlay);

  if (effective.lifecycleState === "retired") {
    return { ok: false, code: "capability_retired" };
  }

  const allowance = await assertPlanAllowance(
    principal,
    capabilityId,
    version,
    manifest,
    cache,
    reader,
  );
  if (!allowance.ok) {
    return allowance;
  }

  if (await isCapabilityDisabled(principal, capabilityId, manifest, cache, reader)) {
    return { ok: false, code: "capability_disabled" };
  }

  return { ok: true, manifest: manifestWithEffectiveIdentity(manifest, effective) };
}

export async function computeDiscoveryEtag(
  manifestList: Manifest[],
): Promise<string> {
  const sorted = sortManifests(manifestList);
  return hashManifest({
    manifests: sorted.map(manifestToHashInput),
  });
}

export async function discover(
  principal: Principal,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<DiscoveryResult> {
  const installationId = principal.installationId;

  let entitlement: Record<string, unknown>;
  try {
    entitlement = await loadConfig(
      cache,
      reader,
      "entitlements",
      installationId,
    );
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      const manifests: Manifest[] = [];
      return { manifests, etag: await computeDiscoveryEtag(manifests) };
    }
    throw error;
  }

  if (entitlement.status !== "active") {
    const manifests: Manifest[] = [];
    return { manifests, etag: await computeDiscoveryEtag(manifests) };
  }

  const plan = entitlement.plan;
  if (typeof plan !== "string") {
    const manifests: Manifest[] = [];
    return { manifests, etag: await computeDiscoveryEtag(manifests) };
  }

  const allowedCapabilities = parseAllowedCapabilities(entitlement);

  // Kill switches are intentionally not applied in discovery — advertising killed caps is intentional.
  const candidates: Manifest[] = [];
  for (const manifest of capabilityRegistry.values()) {
    const capabilityId = manifest.Identity.capabilityId;
    const version = manifest.Identity.version;
    if (typeof capabilityId !== "string" || typeof version !== "string") {
      continue;
    }

    if (!allowedCapabilities.includes(capabilityId)) {
      continue;
    }

    const minimumPlanTier = manifest.Access.minimumPlanTier;
    if (
      typeof minimumPlanTier !== "string" ||
      !planTierMeetsMinimum(plan, minimumPlanTier)
    ) {
      continue;
    }

    candidates.push(manifest);
  }

  const evaluated = await Promise.all(
    candidates.map(async (manifest) => {
      const capabilityId = manifest.Identity.capabilityId as string;
      const version = manifest.Identity.version as string;
      const grantKey = `${installationId}/${capabilityId}`;

      const [grantOutcome, overlay] = await Promise.all([
        (async (): Promise<"skip" | "ok"> => {
          try {
            const grant = await loadConfig(cache, reader, "grants", grantKey);
            if (grant.revoked_at != null) {
              return "skip";
            }
            if (
              typeof grant.capability_version === "string" &&
              manifest.Identity.version !== grant.capability_version
            ) {
              return "skip";
            }
            return "ok";
          } catch (error) {
            if (error instanceof ConfigCacheMissError) {
              return "skip";
            }
            throw error;
          }
        })(),
        loadLifecycleOverlay(cache, reader, capabilityId, version),
      ]);

      if (grantOutcome === "skip") {
        return null;
      }

      const effective = effectiveLifecycle(manifest, overlay);
      if (effective.lifecycleState === "retired") {
        return null;
      }

      if (
        effective.lifecycleState !== "active" &&
        effective.lifecycleState !== "deprecated"
      ) {
        return null;
      }

      return manifestWithEffectiveIdentity(manifest, effective);
    }),
  );

  const manifests = evaluated.filter((entry): entry is Manifest => entry !== null);
  const sorted = sortManifests(manifests);
  return { manifests: sorted, etag: await computeDiscoveryEtag(sorted) };
}

export async function getGrantedCapabilityVersion(
  installationId: string,
  capabilityId: string,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<string | null> {
  try {
    const grant = await loadConfig(
      cache,
      reader,
      "grants",
      `${installationId}/${capabilityId}`,
    );
    if (grant.revoked_at != null) {
      return null;
    }
    return typeof grant.capability_version === "string"
      ? grant.capability_version
      : null;
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return null;
    }
    throw error;
  }
}

/** RFC 7232 weak comparison: strip optional `W/` and surrounding quotes. */
function opaqueTagEquals(candidate: string, rawEtag: string): boolean {
  let tag = candidate.trim();
  if (tag.startsWith("W/")) {
    tag = tag.slice(2).trim();
  }
  if (tag.length >= 2 && tag.startsWith('"') && tag.endsWith('"')) {
    tag = tag.slice(1, -1);
  }
  return tag === rawEtag;
}

function ifNoneMatchMatches(ifNoneMatch: string | null, rawEtag: string): boolean {
  if (ifNoneMatch === null) {
    return false;
  }
  const header = ifNoneMatch.trim();
  if (header === "*") {
    return true;
  }
  for (const part of header.split(",")) {
    if (opaqueTagEquals(part, rawEtag)) {
      return true;
    }
  }
  return false;
}

export function buildDiscoveryResponse(
  request: Request,
  manifestList: Manifest[],
  etag: string,
): Response {
  const quotedEtag = `"${etag}"`;
  const cacheControl = "private, must-revalidate";
  const ifNoneMatch = request.headers.get("If-None-Match");

  if (ifNoneMatchMatches(ifNoneMatch, etag)) {
    return new Response(null, {
      status: 304,
      headers: {
        ETag: quotedEtag,
        "Cache-Control": cacheControl,
      },
    });
  }

  return new Response(JSON.stringify({ manifests: manifestList }), {
    status: 200,
    headers: {
      ETag: quotedEtag,
      "Cache-Control": cacheControl,
      "Content-Type": "application/json",
    },
  });
}
