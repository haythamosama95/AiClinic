/**
 * Capability registry, resolver stage, and discovery (C1 §4.3.4, §5.5).
 */

import {
  type ConfigCache,
  type ConfigEntityKind,
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
      code: "capability_unknown" | "capability_retired" | "capability_disabled";
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
      scopeReaderForKind(reader, "grants"),
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

async function loadKillSwitch(
  cache: ConfigCache,
  reader: D1Reader,
  key: string,
): Promise<Record<string, unknown>> {
  return loadConfig(
    cache,
    scopeReaderForKind(reader, "kill_switches"),
    "kill_switches",
    key,
  );
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
      scopeReaderForKind(reader, "active_routing_policy"),
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
  for (const entry of manifest["Context requirements"]) {
    deepFreeze(entry);
  }
  deepFreeze(manifest.Identity);
  deepFreeze(manifest.Access);
  deepFreeze(manifest.Interaction);
  deepFreeze(manifest.Input);
  deepFreeze(manifest["Context requirements"]);
  deepFreeze(manifest["Prompt binding"]);
  deepFreeze(manifest.Output);
  deepFreeze(manifest.Routing);
  deepFreeze(manifest.Economics);
  deepFreeze(manifest.Governance);
  return deepFreeze(manifest);
}

export function createCapabilityRegistry(manifests: Manifest[]): CapabilityRegistry {
  const registry: CapabilityRegistry = new Map();
  for (const manifest of manifests) {
    const capabilityId = manifest.Identity.capabilityId;
    const version = manifest.Identity.version;
    if (typeof capabilityId !== "string" || typeof version !== "string") {
      continue;
    }
    registry.set(registryKey(capabilityId, version), freezeManifest(manifest));
  }
  return registry;
}

export function setCapabilityRegistry(registry: CapabilityRegistry): void {
  capabilityRegistry = registry;
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

  if (await isCapabilityDisabled(principal, capabilityId, manifest, cache, reader)) {
    return { ok: false, code: "capability_disabled" };
  }

  return { ok: true, manifest: manifestWithEffectiveIdentity(manifest, effective) };
}

export function computeDiscoveryEtag(manifestList: Manifest[]): string {
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
      scopeReaderForKind(reader, "entitlements"),
      "entitlements",
      installationId,
    );
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      const manifests: Manifest[] = [];
      return { manifests, etag: computeDiscoveryEtag(manifests) };
    }
    throw error;
  }

  if (entitlement.status !== "active") {
    const manifests: Manifest[] = [];
    return { manifests, etag: computeDiscoveryEtag(manifests) };
  }

  const plan = entitlement.plan;
  if (typeof plan !== "string") {
    const manifests: Manifest[] = [];
    return { manifests, etag: computeDiscoveryEtag(manifests) };
  }

  const allowedCapabilities = parseAllowedCapabilities(entitlement);
  const manifests: Manifest[] = [];

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

    const grantKey = `${installationId}/${capabilityId}`;
    let grantedVersion: string | null = null;
    try {
      const grant = await loadConfig(
        cache,
        scopeReaderForKind(reader, "grants"),
        "grants",
        grantKey,
      );
      if (grant.revoked_at != null) {
        continue;
      }
      if (typeof grant.capability_version === "string") {
        grantedVersion = grant.capability_version;
      }
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        continue;
      }
      throw error;
    }

    if (grantedVersion !== null && manifest.Identity.version !== grantedVersion) {
      continue;
    }

    const overlay = await loadLifecycleOverlay(cache, reader, capabilityId, version);
    const effective = effectiveLifecycle(manifest, overlay);

    if (effective.lifecycleState === "retired") {
      continue;
    }

    const overlayAnnounced = overlay?.lifecycle_state != null;
    const publishedActive = manifest.Identity.lifecycleState === "active";
    if (!overlayAnnounced && !publishedActive) {
      continue;
    }

    if (
      effective.lifecycleState !== "active" &&
      effective.lifecycleState !== "deprecated"
    ) {
      continue;
    }

    manifests.push(manifestWithEffectiveIdentity(manifest, effective));
  }

  const sorted = sortManifests(manifests);
  return { manifests: sorted, etag: computeDiscoveryEtag(sorted) };
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
      scopeReaderForKind(reader, "grants"),
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

export function buildDiscoveryResponse(
  request: Request,
  manifestList: Manifest[],
  etag: string,
): Response {
  const ifNoneMatch = request.headers.get("If-None-Match");
  if (ifNoneMatch === etag) {
    return new Response(null, {
      status: 304,
      headers: { ETag: etag },
    });
  }

  return new Response(JSON.stringify({ manifests: manifestList }), {
    status: 200,
    headers: {
      ETag: etag,
      "Content-Type": "application/json",
    },
  });
}
