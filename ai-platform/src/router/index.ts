/**
 * Routing policy interpretation — candidate chain selection (D2 §4.3.7).
 * Stateless: policy data + request inputs only; no provider history (FR-011).
 */

import {
  type ConfigCache,
  ConfigCacheMissError,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";

export type RoutingTier = "standard" | "degraded";
export type CostClass = "economy" | "standard" | "premium";
export type CostClassSource =
  | "manifest"
  | "entitlement_cap"
  | "installation_override";

export type CapabilityRequirements = {
  structured_output_required: boolean;
  min_context_window: number;
  languages: readonly string[];
  latency_class: string;
};

export type RouterContext = {
  installationId: string;
  capabilityId: string;
  routingTier: RoutingTier;
  requirements: CapabilityRequirements;
  manifestCostClass: CostClass;
  entitlementMaxCostClass: CostClass;
  /**
   * Optional provider ids excluded by an upstream kill-switch guard (B3).
   * Targets whose provider_id is listed are dropped with reason_code `kill_switch`.
   */
  killedProviderIds?: readonly string[];
  /** Ignored — routing is stateless (FR-011). */
  priorProviderFailure?: { providerId: string; modelId: string };
};

export type ExcludedReasonCode =
  | "feature_unsupported"
  | "context_window_too_small"
  | "language_unsupported"
  | "kill_switch"
  | "installation_excluded"
  | "cost_class_excluded";

export type ChainEntry = {
  ordinal: number;
  provider_id: string;
  model_id: string;
  /** Attempt bounds carried through from the matched rule's target (§4.3.7). */
  max_attempts: number;
  timeout_ms: number;
};

export type ExcludedEntry = {
  provider_id: string;
  model_id: string;
  reason_code: ExcludedReasonCode;
};

export type RoutingDecision = {
  policy_id: string;
  policy_version: number;
  rule_id: string;
  effective_cost_class: CostClass;
  cost_class_source: CostClassSource;
  routing_tier: RoutingTier;
  required_features: CapabilityRequirements;
  chain: ChainEntry[];
  excluded: ExcludedEntry[];
};

export type RouterOutcome = {
  routing_decision: RoutingDecision;
};

export type RoutingPolicyErrorCode =
  | "policy_identity_mismatch"
  | "unsupported_schema_version"
  | "missing_catch_all"
  | "no_matching_rule";

export class RoutingPolicyError extends Error {
  readonly code: RoutingPolicyErrorCode;

  constructor(code: RoutingPolicyErrorCode, message: string) {
    super(message);
    this.name = "RoutingPolicyError";
    this.code = code;
  }
}

type TargetFeatures = {
  structured_output: boolean;
  min_context_window: number;
  languages: string[];
  latency_class: string;
  cost_class: CostClass;
};

type PolicyTarget = {
  provider_id: string;
  model_id: string;
  features: TargetFeatures;
  max_attempts: number;
  timeout_ms: number;
};

type PolicyRuleMatch = {
  capability_ids?: string[];
  installation_ids?: string[];
  cost_classes?: CostClass[];
  tiers?: RoutingTier[];
  languages?: string[];
  latency_classes?: string[];
};

type PolicyRuleRequires = {
  structured_output: boolean;
  min_context_window: number;
  languages: string[];
};

type PolicyRule = {
  rule_id: string;
  match: PolicyRuleMatch;
  requires: PolicyRuleRequires;
  targets: PolicyTarget[];
  /**
   * Schema-retained. Invocation walks the chain sequentially; racing
   * multiplies token spend (§13.6). Not copied onto RoutingDecision.
   */
  max_parallel_attempts?: number;
};

type PolicyOverride = {
  installation_id: string;
  exclude_providers?: string[];
  pin_target?: { provider_id: string; model_id: string };
  force_cost_class?: CostClass;
};

type RoutingPolicyDocument = {
  schema_version: number;
  policy_id: string;
  policy_version: number;
  defaults: {
    /**
     * Schema-retained for §4.3.7 table parity. Does **not** participate in
     * effective cost-class calculation (three-source minimum only).
     */
    cost_class: CostClass;
    /**
     * Schema-retained. Not read: invocation is strictly sequential
     * (no parallel racing). Not copied onto RoutingDecision.
     */
    max_parallel_attempts: number;
  };
  rules: PolicyRule[];
  overrides: PolicyOverride[];
};

type ActiveRoutingPolicyRow = {
  policy_id: string;
  policy_version: number;
  document: RoutingPolicyDocument;
};

/** Cache/D1 rows may expose `version` (§7.3) or `policy_version` (document/test fixtures). */
function normalizePolicyRow(row: unknown): ActiveRoutingPolicyRow {
  const raw = row as Record<string, unknown>;
  const document = raw.document as RoutingPolicyDocument;
  const policyId = String(raw.policy_id ?? "");
  const versionRaw =
    raw.policy_version !== undefined ? raw.policy_version : raw.version;
  const policyVersion =
    typeof versionRaw === "number" ? versionRaw : Number(versionRaw);

  return {
    policy_id: policyId,
    policy_version: policyVersion,
    document,
  };
}

const COST_CLASS_ORDER: Record<CostClass, number> = {
  economy: 0,
  standard: 1,
  premium: 2,
};

function isKnownCostClass(value: unknown): value is CostClass {
  return typeof value === "string" && Object.hasOwn(COST_CLASS_ORDER, value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

const SOURCE_PRIORITY: Record<CostClassSource, number> = {
  installation_override: 0,
  entitlement_cap: 1,
  manifest: 2,
};

const SUPPORTED_SCHEMA_VERSIONS = new Set([1]);

function matchClause<T>(allowed: T[] | undefined, value: T): boolean {
  return !allowed || allowed.length === 0 || allowed.includes(value);
}

function matchAllLanguages(
  allowed: string[] | undefined,
  required: readonly string[],
): boolean {
  if (!allowed || allowed.length === 0) {
    return true;
  }
  return required.every((language) => allowed.includes(language));
}

function isCatchAllMatch(match: PolicyRuleMatch | undefined): boolean {
  if (!match) {
    return true;
  }
  return (
    (!match.capability_ids || match.capability_ids.length === 0) &&
    (!match.installation_ids || match.installation_ids.length === 0) &&
    (!match.cost_classes || match.cost_classes.length === 0) &&
    (!match.tiers || match.tiers.length === 0) &&
    (!match.languages || match.languages.length === 0) &&
    (!match.latency_classes || match.latency_classes.length === 0)
  );
}

function validatePolicyDocument(
  policyRow: ActiveRoutingPolicyRow,
  document: RoutingPolicyDocument,
): void {
  if (
    document.policy_id !== policyRow.policy_id ||
    document.policy_version !== policyRow.policy_version
  ) {
    throw new RoutingPolicyError(
      "policy_identity_mismatch",
      `Document identity ${document.policy_id}@${document.policy_version} does not match row ${policyRow.policy_id}@${policyRow.policy_version}`,
    );
  }

  if (!SUPPORTED_SCHEMA_VERSIONS.has(document.schema_version)) {
    throw new RoutingPolicyError(
      "unsupported_schema_version",
      `Unsupported routing policy schema_version ${document.schema_version}`,
    );
  }

  const lastRule = document.rules[document.rules.length - 1];
  if (!lastRule || !isCatchAllMatch(lastRule.match)) {
    throw new RoutingPolicyError(
      "missing_catch_all",
      "Routing policy document must end with a catch-all rule (empty/absent match)",
    );
  }
}

function ruleMatches(
  rule: PolicyRule,
  context: RouterContext,
  effectiveCostClass: CostClass,
): boolean {
  const { match } = rule;
  const { requirements } = context;

  if (!matchClause(match.capability_ids, context.capabilityId)) {
    return false;
  }
  if (!matchClause(match.installation_ids, context.installationId)) {
    return false;
  }
  if (!matchClause(match.cost_classes, effectiveCostClass)) {
    return false;
  }
  if (!matchClause(match.tiers, context.routingTier)) {
    return false;
  }
  if (!matchAllLanguages(match.languages, requirements.languages)) {
    return false;
  }
  if (!matchClause(match.latency_classes, requirements.latency_class)) {
    return false;
  }

  return true;
}

/**
 * Effective cost class is the lowest of three sources only:
 * manifest, entitlement_cap, and optional installation `force_cost_class`
 * from the matched policy-document override. `defaults.cost_class` is ignored.
 */
function resolveEffectiveCostClass(
  context: RouterContext,
  forceCostClassFromDocument?: CostClass,
): { class: CostClass; source: CostClassSource } {
  const candidates: { class: CostClass; source: CostClassSource }[] = [
    { class: context.manifestCostClass, source: "manifest" },
    { class: context.entitlementMaxCostClass, source: "entitlement_cap" },
  ];

  if (forceCostClassFromDocument !== undefined) {
    candidates.push({
      class: forceCostClassFromDocument,
      source: "installation_override",
    });
  }

  return candidates.reduce((lowest, candidate) => {
    const candidateOrder = COST_CLASS_ORDER[candidate.class];
    const lowestOrder = COST_CLASS_ORDER[lowest.class];

    if (candidateOrder < lowestOrder) {
      return candidate;
    }
    if (
      candidateOrder === lowestOrder &&
      SOURCE_PRIORITY[candidate.source] < SOURCE_PRIORITY[lowest.source]
    ) {
      return candidate;
    }
    return lowest;
  });
}

/**
 * Merge request requirements with the matched rule's `requires` floor.
 * Target features must satisfy the stricter floor on each dimension.
 */
function mergeRequirementFloors(
  requirements: CapabilityRequirements,
  ruleRequires: PolicyRuleRequires,
): CapabilityRequirements {
  const languages = Array.from(
    new Set([...requirements.languages, ...ruleRequires.languages]),
  );

  return {
    structured_output_required:
      requirements.structured_output_required || ruleRequires.structured_output,
    min_context_window: Math.max(
      requirements.min_context_window,
      ruleRequires.min_context_window,
    ),
    languages,
    latency_class: requirements.latency_class,
  };
}

function applyInstallationOverride(
  targets: PolicyTarget[],
  override: PolicyOverride | undefined,
): { targets: PolicyTarget[]; excluded: ExcludedEntry[] } {
  if (!override) {
    return { targets: [...targets], excluded: [] };
  }

  const excluded: ExcludedEntry[] = [];
  let remaining = [...targets];

  if (override.exclude_providers && override.exclude_providers.length > 0) {
    const excludedProviders = new Set(override.exclude_providers);
    const next: PolicyTarget[] = [];

    for (const target of remaining) {
      if (excludedProviders.has(target.provider_id)) {
        excluded.push({
          provider_id: target.provider_id,
          model_id: target.model_id,
          reason_code: "installation_excluded",
        });
      } else {
        next.push(target);
      }
    }
    remaining = next;
  }

  if (override.pin_target) {
    const pin = override.pin_target;
    const pinned = remaining.find(
      (target) =>
        target.provider_id === pin.provider_id &&
        target.model_id === pin.model_id,
    );

    for (const target of remaining) {
      if (
        target.provider_id !== pin.provider_id ||
        target.model_id !== pin.model_id
      ) {
        excluded.push({
          provider_id: target.provider_id,
          model_id: target.model_id,
          reason_code: "installation_excluded",
        });
      }
    }

    remaining = pinned ? [pinned] : [];
  }

  return { targets: remaining, excluded };
}

function isKillSwitchRowActive(
  row: Record<string, unknown> | undefined,
): boolean {
  return row?.active === true;
}

/**
 * Provider ids with an active `kill_switches` cache row (B3 / §3.1.1 producer).
 * Callers may also pass an explicit `RouterContext.killedProviderIds` list;
 * `selectCandidateChain` merges both sources before filtering.
 */
export function collectKilledProviderIds(
  cache: ConfigCache,
  providerIds: readonly string[],
): string[] {
  const killed: string[] = [];
  for (const providerId of providerIds) {
    const row = cache.consult("kill_switches", `provider:${providerId}`);
    if (isKillSwitchRowActive(row)) {
      killed.push(providerId);
    }
  }
  return killed;
}

function mergeKilledProviderIds(
  cache: ConfigCache,
  targets: PolicyTarget[],
  contextKilled?: readonly string[],
): readonly string[] {
  const fromCache = collectKilledProviderIds(
    cache,
    targets.map((target) => target.provider_id),
  );
  if (!contextKilled || contextKilled.length === 0) {
    return fromCache;
  }
  if (fromCache.length === 0) {
    return contextKilled;
  }
  return [...new Set([...contextKilled, ...fromCache])];
}

function filterTargets(
  targets: PolicyTarget[],
  requirements: CapabilityRequirements,
  effectiveCostClass: CostClass,
  killedProviderIds?: readonly string[],
): { chain: ChainEntry[]; excluded: ExcludedEntry[] } {
  const chain: ChainEntry[] = [];
  const excluded: ExcludedEntry[] = [];
  const killed = killedProviderIds ? new Set(killedProviderIds) : undefined;
  let ordinal = 0;

  for (const target of targets) {
    const { features } = target;

    if (killed?.has(target.provider_id)) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "kill_switch",
      });
      continue;
    }

    if (
      requirements.structured_output_required &&
      !features.structured_output
    ) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "feature_unsupported",
      });
      continue;
    }

    // Missing/unknown window fails closed. A declared finite window that is
    // too small keeps the distinct `context_window_too_small` reason.
    if (!isFiniteNumber(features.min_context_window)) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "feature_unsupported",
      });
      continue;
    }
    if (features.min_context_window < requirements.min_context_window) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "context_window_too_small",
      });
      continue;
    }

    // Missing/non-array languages fail closed (`feature_unsupported`) instead
    // of throwing TypeError or treating a string as a language list.
    if (!Array.isArray(features.languages)) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "feature_unsupported",
      });
      continue;
    }
    if (
      !requirements.languages.every((language) =>
        features.languages.includes(language),
      )
    ) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "language_unsupported",
      });
      continue;
    }

    // Latency has no distinct reason_code in the frozen enum; map to feature_unsupported.
    if (features.latency_class !== requirements.latency_class) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "feature_unsupported",
      });
      continue;
    }

    // Missing/unknown cost class fails closed. A known class above the
    // effective ceiling keeps `cost_class_excluded`.
    if (!isKnownCostClass(features.cost_class)) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "feature_unsupported",
      });
      continue;
    }
    if (COST_CLASS_ORDER[features.cost_class] > COST_CLASS_ORDER[effectiveCostClass]) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "cost_class_excluded",
      });
      continue;
    }

    chain.push({
      ordinal,
      provider_id: target.provider_id,
      model_id: target.model_id,
      max_attempts: target.max_attempts,
      timeout_ms: target.timeout_ms,
    });
    ordinal += 1;
  }

  return { chain, excluded };
}

export function selectCandidateChain({
  cache,
  policyCacheKey,
  context,
  logger = noopLogger,
  preloadedPolicy,
}: {
  cache: ConfigCache;
  policyCacheKey: string;
  context: RouterContext;
  logger?: Logger;
  /**
   * Row just returned by `preloadRoutingPolicyForInstallation`. Same-request
   * consumers must not re-consult: TTL 0 stamps `expiresAt === remember-now`,
   * and an async D1 read can tick the clock before this call.
   */
  preloadedPolicy?: Record<string, unknown>;
}): RouterOutcome {
  const installationPolicyKey = `${policyCacheKey}/${context.installationId}`;
  let row =
    preloadedPolicy ?? cache.consult("active_routing_policy", installationPolicyKey);
  if (row === undefined) {
    row = cache.consult("active_routing_policy", policyCacheKey);
  }
  if (row === undefined) {
    throw new ConfigCacheMissError("active_routing_policy", policyCacheKey);
  }

  const policyRow = normalizePolicyRow(row);
  const document = policyRow.document;

  validatePolicyDocument(policyRow, document);

  const installationOverride = document.overrides.find(
    (override) => override.installation_id === context.installationId,
  );

  const { class: effectiveCostClass, source: costClassSource } =
    resolveEffectiveCostClass(context, installationOverride?.force_cost_class);

  const matchedRule = document.rules.find((rule) =>
    ruleMatches(rule, context, effectiveCostClass),
  );

  // Catch-all validation runs before matching, so `rules.find` cannot miss; kept as a defensive safety net.
  if (!matchedRule) {
    throw new RoutingPolicyError(
      "no_matching_rule",
      `No routing policy rule matched for installation ${context.installationId}`,
    );
  }

  const { targets: narrowedTargets, excluded: overrideExcluded } =
    applyInstallationOverride(matchedRule.targets, installationOverride);

  const effectiveRequirements = mergeRequirementFloors(
    context.requirements,
    matchedRule.requires,
  );

  const killedProviderIds = mergeKilledProviderIds(
    cache,
    narrowedTargets,
    context.killedProviderIds,
  );

  const { chain, excluded: filterExcluded } = filterTargets(
    narrowedTargets,
    effectiveRequirements,
    effectiveCostClass,
    killedProviderIds,
  );

  const excluded = [...overrideExcluded, ...filterExcluded];

  logger.info("Routing decision resolved", {
    installation_id: context.installationId,
    capability_id: context.capabilityId,
    policy_id: document.policy_id,
    rule_id: matchedRule.rule_id,
    routing_tier: context.routingTier,
    effective_cost_class: effectiveCostClass,
    chain_length: chain.length,
  });

  if (excluded.length > 0) {
    logger.debug("Routing exclusions applied", {
      installation_id: context.installationId,
      excluded_count: excluded.length,
      excluded,
    });
  }

  return {
    routing_decision: {
      policy_id: document.policy_id,
      policy_version: document.policy_version,
      rule_id: matchedRule.rule_id,
      effective_cost_class: effectiveCostClass,
      cost_class_source: costClassSource,
      routing_tier: context.routingTier,
      required_features: context.requirements,
      chain,
      excluded,
    },
  };
}

/**
 * Preload installation-specific active routing policy into the config cache (J3).
 * Cache key is `${policyCacheKey}/${installationId}` — an allowed extension of
 * the single-document cache contract (delivery plan §2.3). `selectCandidateChain`
 * consults that key first, then falls back to the global `policyCacheKey`.
 */
export async function preloadRoutingPolicyForInstallation(
  cache: ConfigCache,
  reader: D1Reader,
  policyCacheKey: string,
  installationId: string,
): Promise<Record<string, unknown>> {
  return loadConfig(
    cache,
    reader,
    "active_routing_policy",
    `${policyCacheKey}/${installationId}`,
  );
}
