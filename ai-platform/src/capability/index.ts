/**
 * Capability registry, resolver stage, and discovery (C1 §4.3.4, §5.5).
 * Discovery serves a public manifest projection; invoke resolution returns full manifests.
 */

import {
  type ConfigCache,
  ConfigCacheMissError,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import type { Principal } from "../identity";
import { noopLogger, type Logger } from "../logger";
import { hashManifest, type Manifest } from "../manifest";

export type CapabilityRegistry = Map<string, Manifest>;

export type ResolveResult =
  | { ok: true; manifest: Manifest; killedProviderIds?: readonly string[] }
  | {
    ok: false;
    code:
    | "capability_unknown"
    | "capability_retired"
    | "capability_disabled"
    | "forbidden_capability";
  };

export type PublicManifest = {
  readonly Identity: Manifest["Identity"];
  readonly Interaction: Manifest["Interaction"];
  readonly Input: Manifest["Input"];
  readonly "Context requirements": Manifest["Context requirements"];
  readonly Output: Readonly<Pick<Manifest["Output"], "mode" | "outputSchemaRef">>;
  readonly Governance: Readonly<Pick<Manifest["Governance"], "acceptanceMode">>;
};

export type DiscoveryResult = {
  manifests: PublicManifest[];
  etag: string;
};

import { planTierMeetsMinimum } from "../platform-vocabulary";

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

  const requiredScope = manifest.Access.requiredCapabilityScope;
  if (
    typeof requiredScope === "string" &&
    requiredScope.length > 0 &&
    !principal.scopes.includes(requiredScope)
  ) {
    return forbidden;
  }

  const allowedStaffRoles = manifest.Access.allowedStaffRoles;
  if (
    Array.isArray(allowedStaffRoles) &&
    allowedStaffRoles.length > 0 &&
    !allowedStaffRoles.includes(principal.role)
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

/**
 * Providers live only in `RoutingPolicyDocument.rules[].targets[]` — never as a
 * top-level `provider_id` on the active_routing_policy row (§3.1.1).
 */
function providerIdsFromPolicyRow(policy: Record<string, unknown>): string[] {
  const document =
    policy.document !== null &&
      typeof policy.document === "object" &&
      !Array.isArray(policy.document)
      ? (policy.document as Record<string, unknown>)
      : policy;
  const rules = document.rules;
  if (!Array.isArray(rules)) {
    return [];
  }

  const ids = new Set<string>();
  for (const rule of rules) {
    if (rule === null || typeof rule !== "object" || Array.isArray(rule)) {
      continue;
    }
    const targets = (rule as Record<string, unknown>).targets;
    if (!Array.isArray(targets)) {
      continue;
    }
    for (const target of targets) {
      if (target === null || typeof target !== "object" || Array.isArray(target)) {
        continue;
      }
      const providerId = (target as Record<string, unknown>).provider_id;
      if (typeof providerId === "string") {
        ids.add(providerId);
      }
    }
  }
  return [...ids];
}

async function resolveProviderIds(
  manifest: Manifest,
  cache: ConfigCache,
  reader: D1Reader,
  installationId: string,
): Promise<string[]> {
  const policyRef = manifest.Routing.routingPolicyRef;
  if (typeof policyRef !== "string") {
    return [];
  }

  try {
    let policy: Record<string, unknown>;
    try {
      policy = await loadConfig(
        cache,
        reader,
        "active_routing_policy",
        `${policyRef}/${installationId}`,
      );
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        policy = await loadConfig(
          cache,
          reader,
          "active_routing_policy",
          policyRef,
        );
      } else {
        throw error;
      }
    }
    return providerIdsFromPolicyRow(policy);
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return [];
    }
    throw error;
  }
}

/**
 * Active `provider:<id>` kill switches for providers named in the routing
 * policy. Policy miss → empty list (do not invent provider ids). These ids
 * are for the router to exclude; they do not disable the capability.
 */
async function collectActiveProviderKillSwitches(
  manifest: Manifest,
  cache: ConfigCache,
  reader: D1Reader,
  installationId: string,
): Promise<readonly string[]> {
  const providerIds = await resolveProviderIds(
    manifest,
    cache,
    reader,
    installationId,
  );
  const killed: string[] = [];
  for (const providerId of providerIds) {
    const row = await loadKillSwitch(cache, reader, `provider:${providerId}`);
    if (isKillSwitchActive(row)) {
      killed.push(providerId);
    }
  }
  return killed;
}

async function evaluateCapabilityKillSwitches(
  principal: Principal,
  capabilityId: string,
  manifest: Manifest,
  cache: ConfigCache,
  reader: D1Reader,
): Promise<{
  capabilityDisabled: boolean;
  killedProviderIds: readonly string[];
}> {
  if (manifest.Access.killSwitchFlag === true) {
    return { capabilityDisabled: true, killedProviderIds: [] };
  }

  const installationId = principal.installationId;
  const capabilityKeys = [
    "global",
    `capability:${capabilityId}`,
    `installation:${installationId}`,
  ];

  for (const key of capabilityKeys) {
    const row = await loadKillSwitch(cache, reader, key);
    if (isKillSwitchActive(row)) {
      return { capabilityDisabled: true, killedProviderIds: [] };
    }
  }

  const killedProviderIds = await collectActiveProviderKillSwitches(
    manifest,
    cache,
    reader,
    installationId,
  );
  return { capabilityDisabled: false, killedProviderIds };
}

function manifestToHashInput(manifest: Manifest): PublicManifest {
  return toPublicManifest(manifest);
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

export function toPublicManifest(manifest: Manifest): PublicManifest {
  return deepFreeze({
    Identity: manifest.Identity,
    Interaction: manifest.Interaction,
    Input: manifest.Input,
    "Context requirements": manifest["Context requirements"],
    Output: {
      mode: manifest.Output.mode,
      outputSchemaRef: manifest.Output.outputSchemaRef,
    },
    Governance: {
      acceptanceMode: manifest.Governance.acceptanceMode,
    },
  });
}

function unmodifiableRegistry(registry: Map<string, Manifest>): CapabilityRegistry {
  return new Proxy(registry, {
    get(target, prop, receiver) {
      if (prop === "set" || prop === "delete" || prop === "clear") {
        return () => {
          throw new TypeError("CapabilityRegistry is immutable");
        };
      }
      if (prop === "size") {
        return target.size;
      }
      const value = Reflect.get(target, prop, target);
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
  options?: { replace?: boolean; logger?: Logger },
): void {
  if (registryInstalled && options?.replace !== true) {
    throw new Error(
      "CapabilityRegistry is already installed; pass { replace: true } to replace",
    );
  }
  capabilityRegistry = registry;
  registryInstalled = true;
  const logger = options?.logger ?? noopLogger;
  logger.info("capability_registry_installed", {
    capability_count: registry.size,
    replace: options?.replace === true,
  });
}

/** True when the in-memory registry contains this exact capability id + version. */
export function isCapabilityVersionRegistered(
  capabilityId: string,
  version: string,
): boolean {
  return capabilityRegistry.has(registryKey(capabilityId, version));
}

/**
 * True when successor identity is known to the registry.
 * Accepts either `capabilityId` (any version) or `capabilityId@version`.
 */
export function isSuccessorRegistered(successorId: string): boolean {
  if (successorId.includes("@")) {
    return capabilityRegistry.has(successorId);
  }
  for (const key of capabilityRegistry.keys()) {
    if (key.startsWith(`${successorId}@`)) {
      return true;
    }
  }
  return false;
}

export async function resolve(
  principal: Principal,
  capabilityId: string,
  version: string,
  cache: ConfigCache,
  reader: D1Reader,
  logger: Logger = noopLogger,
): Promise<ResolveResult> {
  const manifest = capabilityRegistry.get(registryKey(capabilityId, version));
  if (manifest === undefined) {
    logger.debug("capability_resolve_rejected", {
      capability_id: capabilityId,
      version,
      code: "capability_unknown",
    });
    return { ok: false, code: "capability_unknown" };
  }

  const overlay = await loadLifecycleOverlay(cache, reader, capabilityId, version);
  const effective = effectiveLifecycle(manifest, overlay);

  if (effective.lifecycleState === "retired") {
    logger.debug("capability_resolve_rejected", {
      capability_id: capabilityId,
      version,
      code: "capability_retired",
    });
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
    logger.debug("capability_resolve_rejected", {
      capability_id: capabilityId,
      version,
      code: allowance.code,
      installation_id: principal.installationId,
    });
    return allowance;
  }

  const killSwitches = await evaluateCapabilityKillSwitches(
    principal,
    capabilityId,
    manifest,
    cache,
    reader,
  );
  if (killSwitches.capabilityDisabled) {
    logger.debug("capability_resolve_rejected", {
      capability_id: capabilityId,
      version,
      code: "capability_disabled",
      installation_id: principal.installationId,
    });
    return { ok: false, code: "capability_disabled" };
  }

  return {
    ok: true,
    manifest: manifestWithEffectiveIdentity(manifest, effective),
    killedProviderIds: killSwitches.killedProviderIds,
  };
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
  logger: Logger = noopLogger,
): Promise<DiscoveryResult> {
  const installationId = principal.installationId;

  let entitlement: Record<string, unknown>;
  try {
    entitlement = await loadConfig(
      cache,
      reader,
      "entitlements",
      installationId,
      logger,
    );
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      const result = { manifests: [], etag: await computeDiscoveryEtag([]) };
      logger.info("discover_complete", {
        installation_id: installationId,
        manifest_count: 0,
        reason: "entitlement_miss",
      });
      return result;
    }
    throw error;
  }

  if (entitlement.status !== "active") {
    const result = { manifests: [], etag: await computeDiscoveryEtag([]) };
    logger.info("discover_complete", {
      installation_id: installationId,
      manifest_count: 0,
      reason: "entitlement_inactive",
    });
    return result;
  }

  const plan = entitlement.plan;
  if (typeof plan !== "string") {
    const result = { manifests: [], etag: await computeDiscoveryEtag([]) };
    logger.info("discover_complete", {
      installation_id: installationId,
      manifest_count: 0,
      reason: "invalid_plan",
    });
    return result;
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
              const planGrant = await loadMatchingGrant(
                cache,
                reader,
                `plan:${plan}/${capabilityId}`,
                version,
              );
              return planGrant === "granted" ? "ok" : "skip";
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
  const result = {
    manifests: sorted.map(toPublicManifest),
    etag: await computeDiscoveryEtag(sorted),
  };
  logger.info("discover_complete", {
    installation_id: installationId,
    manifest_count: sorted.length,
    etag: result.etag,
  });
  return result;
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
    if (!(error instanceof ConfigCacheMissError)) {
      throw error;
    }
  }

  try {
    const entitlement = await loadConfig(
      cache,
      reader,
      "entitlements",
      installationId,
    );
    const plan = entitlement.plan;
    if (typeof plan !== "string") {
      return null;
    }
    const planGrant = await loadConfig(
      cache,
      reader,
      "grants",
      `plan:${plan}/${capabilityId}`,
    );
    if (planGrant.revoked_at != null) {
      return null;
    }
    return typeof planGrant.capability_version === "string"
      ? planGrant.capability_version
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
  manifestList: readonly PublicManifest[],
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
