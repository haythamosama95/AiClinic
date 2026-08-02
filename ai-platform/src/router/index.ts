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
  installationForceCostClass?: CostClass;
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
  max_parallel_attempts: number;
};

export type RouterOutcome = {
  routing_decision: RoutingDecision;
};

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

type PolicyRule = {
  rule_id: string;
  match: PolicyRuleMatch;
  requires: {
    structured_output: boolean;
    min_context_window: number;
    languages: string[];
  };
  targets: PolicyTarget[];
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
    cost_class: CostClass;
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

const COST_CLASS_ORDER: Record<CostClass, number> = {
  economy: 0,
  standard: 1,
  premium: 2,
};

const SOURCE_PRIORITY: Record<CostClassSource, number> = {
  installation_override: 0,
  entitlement_cap: 1,
  manifest: 2,
};

const OUTGOING_CONNECTION_CAP = 6;

function clampParallelAttempts(value: number): number {
  return Math.min(OUTGOING_CONNECTION_CAP, Math.max(1, value));
}

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

function resolveEffectiveCostClass(
  context: RouterContext,
): { class: CostClass; source: CostClassSource } {
  const candidates: { class: CostClass; source: CostClassSource }[] = [
    { class: context.manifestCostClass, source: "manifest" },
    { class: context.entitlementMaxCostClass, source: "entitlement_cap" },
  ];

  if (context.installationForceCostClass !== undefined) {
    candidates.push({
      class: context.installationForceCostClass,
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

function filterTargets(
  targets: PolicyTarget[],
  requirements: CapabilityRequirements,
  effectiveCostClass: CostClass,
): { chain: ChainEntry[]; excluded: ExcludedEntry[] } {
  const chain: ChainEntry[] = [];
  const excluded: ExcludedEntry[] = [];
  let ordinal = 0;

  for (const target of targets) {
    const { features } = target;

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

    if (features.min_context_window < requirements.min_context_window) {
      excluded.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
        reason_code: "context_window_too_small",
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

    if (features.latency_class !== requirements.latency_class) {
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
}: {
  cache: ConfigCache;
  policyCacheKey: string;
  context: RouterContext;
}): RouterOutcome {
  const installationPolicyKey = `${policyCacheKey}/${context.installationId}`;
  let row = cache.consult("active_routing_policy", installationPolicyKey);
  if (row === undefined) {
    row = cache.consult("active_routing_policy", policyCacheKey);
  }
  if (row === undefined) {
    throw new ConfigCacheMissError("active_routing_policy", policyCacheKey);
  }

  const policyRow = row as ActiveRoutingPolicyRow;
  const document = policyRow.document;

  const installationOverride = document.overrides.find(
    (override) => override.installation_id === context.installationId,
  );

  const { class: effectiveCostClass, source: costClassSource } =
    resolveEffectiveCostClass(context);

  const matchedRule = document.rules.find((rule) =>
    ruleMatches(rule, context, effectiveCostClass),
  );

  if (!matchedRule) {
    throw new Error(
      `No routing policy rule matched for installation ${context.installationId}`,
    );
  }

  const { targets: narrowedTargets, excluded: overrideExcluded } =
    applyInstallationOverride(matchedRule.targets, installationOverride);

  const { chain, excluded: filterExcluded } = filterTargets(
    narrowedTargets,
    context.requirements,
    effectiveCostClass,
  );

  const rawParallelAttempts =
    matchedRule.max_parallel_attempts ??
    document.defaults.max_parallel_attempts;

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
      excluded: [...overrideExcluded, ...filterExcluded],
      max_parallel_attempts: clampParallelAttempts(rawParallelAttempts),
    },
  };
}

function scopeReaderForKind(reader: D1Reader, kind: string): D1Reader {
  return {
    read(key: string) {
      return reader.read(`${kind}:${key}`);
    },
  };
}

/** Preload installation-specific active routing policy into the config cache (J3). */
export async function preloadRoutingPolicyForInstallation(
  cache: ConfigCache,
  reader: D1Reader,
  policyCacheKey: string,
  installationId: string,
): Promise<void> {
  await loadConfig(
    cache,
    scopeReaderForKind(reader, "active_routing_policy"),
    "active_routing_policy",
    `${policyCacheKey}/${installationId}`,
  );
}
