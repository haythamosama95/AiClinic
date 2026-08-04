import { describe, expect, it, vi } from "vitest";
import { ConfigCache } from "../src/config-cache";
import {
  RoutingPolicyError,
  selectCandidateChain,
} from "../src/router";

/** §4.3.7 routing-policy document interpretation shape (routing-decision.md §2). */
type RoutingTier = "standard" | "degraded";
type CostClass = "economy" | "standard" | "premium";
type CostClassSource = "manifest" | "entitlement_cap" | "installation_override";

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

type PolicyRule = {
  rule_id: string;
  match: {
    capability_ids?: string[];
    installation_ids?: string[];
    cost_classes?: CostClass[];
    tiers?: RoutingTier[];
    languages?: string[];
    latency_classes?: string[];
  };
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

type CapabilityRequirements = {
  structured_output_required: boolean;
  min_context_window: number;
  languages: readonly string[];
  latency_class: string;
};

/** Request-side router inputs — D2 does not load manifests (plan Consumes Binding). */
type RouterContext = {
  installationId: string;
  capabilityId: string;
  routingTier: RoutingTier;
  requirements: CapabilityRequirements;
  manifestCostClass: CostClass;
  entitlementMaxCostClass: CostClass;
  killedProviderIds?: readonly string[];
  /** Simulated prior provider failure — router must ignore (FR-011). */
  priorProviderFailure?: { providerId: string; modelId: string };
};

type ExcludedReasonCode =
  | "feature_unsupported"
  | "context_window_too_small"
  | "language_unsupported"
  | "kill_switch"
  | "installation_excluded"
  | "cost_class_excluded";

type ChainEntry = {
  ordinal: number;
  provider_id: string;
  model_id: string;
  max_attempts: number;
  timeout_ms: number;
};

type ExcludedEntry = {
  provider_id: string;
  model_id: string;
  reason_code: ExcludedReasonCode;
};

type RoutingDecision = {
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

type RouterOutcome = {
  routing_decision: RoutingDecision;
};

const FIXTURE_POLICY_KEY = "routing-policy-default";
const FIXTURE_INSTALLATION_ID = "inst-router-001";
const FIXTURE_CAPABILITY_ID = "clinic.router_fixture";

function defaultTargetFeatures(
  overrides: Partial<TargetFeatures> = {},
): TargetFeatures {
  return {
    structured_output: overrides.structured_output ?? true,
    min_context_window: overrides.min_context_window ?? 128_000,
    languages: overrides.languages ?? ["en"],
    latency_class: overrides.latency_class ?? "interactive",
    cost_class: overrides.cost_class ?? "standard",
  };
}

function policyTarget(
  providerId: string,
  modelId: string,
  features: Partial<TargetFeatures> = {},
  attemptBounds: { max_attempts?: number; timeout_ms?: number } = {},
): PolicyTarget {
  return {
    provider_id: providerId,
    model_id: modelId,
    features: defaultTargetFeatures(features),
    max_attempts: attemptBounds.max_attempts ?? 2,
    timeout_ms: attemptBounds.timeout_ms ?? 30_000,
  };
}

function catchAllRule(
  ruleId: string,
  targets: PolicyTarget[],
  match: PolicyRule["match"] = {},
  maxParallelAttempts?: number,
  requires?: PolicyRule["requires"],
): PolicyRule {
  return {
    rule_id: ruleId,
    match,
    requires: requires ?? {
      structured_output: false,
      min_context_window: 0,
      languages: [],
    },
    targets,
    ...(maxParallelAttempts !== undefined
      ? { max_parallel_attempts: maxParallelAttempts }
      : {}),
  };
}

function buildPolicyDocument(
  overrides: Partial<RoutingPolicyDocument> & {
    rules?: PolicyRule[];
    overrides?: PolicyOverride[];
  } = {},
): RoutingPolicyDocument {
  const policyId = overrides.policy_id ?? "policy-router-fixture";
  const policyVersion = overrides.policy_version ?? 1;

  return {
    schema_version: overrides.schema_version ?? 1,
    policy_id: policyId,
    policy_version: policyVersion,
    defaults: overrides.defaults ?? {
      cost_class: "standard",
      max_parallel_attempts: 1,
    },
    rules: overrides.rules ?? [
      catchAllRule("catch-all", [
        policyTarget("deepseek", "deepseek-chat"),
      ]),
    ],
    overrides: overrides.overrides ?? [],
  };
}

/** Preload parsed policy document under `active_routing_policy` (Clarification Q3; A5 remember). */
function preloadPolicyCache(
  document: RoutingPolicyDocument,
  key: string = FIXTURE_POLICY_KEY,
  rowIdentity?: { policy_id: string; policy_version: number },
): ConfigCache {
  const cache = new ConfigCache();
  cache.remember("active_routing_policy", key, {
    policy_id: rowIdentity?.policy_id ?? document.policy_id,
    policy_version: rowIdentity?.policy_version ?? document.policy_version,
    content_pointer: `control/routing-policy/${document.policy_id}/${document.policy_version}.json`,
    active_from: "2026-08-01T00:00:00.000Z",
    activated_by: "test-fixture",
    document,
  });
  return cache;
}

function defaultRequirements(
  overrides: Partial<CapabilityRequirements> = {},
): CapabilityRequirements {
  return {
    structured_output_required: overrides.structured_output_required ?? false,
    min_context_window: overrides.min_context_window ?? 0,
    languages: overrides.languages ?? ["en"],
    latency_class: overrides.latency_class ?? "interactive",
  };
}

function defaultContext(overrides: Partial<RouterContext> = {}): RouterContext {
  return {
    installationId: overrides.installationId ?? FIXTURE_INSTALLATION_ID,
    capabilityId: FIXTURE_CAPABILITY_ID,
    routingTier: overrides.routingTier ?? "standard",
    requirements: overrides.requirements ?? defaultRequirements(),
    manifestCostClass: overrides.manifestCostClass ?? "standard",
    entitlementMaxCostClass: overrides.entitlementMaxCostClass ?? "premium",
    killedProviderIds: overrides.killedProviderIds,
    priorProviderFailure: overrides.priorProviderFailure,
  };
}

function route(
  cache: ConfigCache,
  context: RouterContext = defaultContext(),
  policyCacheKey: string = FIXTURE_POLICY_KEY,
): RouterOutcome {
  return selectCandidateChain({
    cache,
    policyCacheKey,
    context,
  });
}

function chainKeys(outcome: RouterOutcome): string[] {
  return outcome.routing_decision.chain.map(
    (entry) => `${entry.provider_id}/${entry.model_id}`,
  );
}

function excludedReasons(
  outcome: RouterOutcome,
  providerId: string,
  modelId: string,
): ExcludedReasonCode[] {
  return outcome.routing_decision.excluded
    .filter(
      (entry) =>
        entry.provider_id === providerId && entry.model_id === modelId,
    )
    .map((entry) => entry.reason_code);
}

describe("T-D2-07 router_chain_ordered_by_policy", () => {
  it("orders the candidate chain by rules[].targets[] order", () => {
    const targets = [
      policyTarget("deepseek", "deepseek-chat"),
      policyTarget("google", "gemini-1.5-pro"),
      policyTarget("openai", "gpt-4o"),
    ];
    const document = buildPolicyDocument({
      rules: [catchAllRule("multi-target", targets)],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(cache);

    expect(chainKeys(outcome)).toEqual([
      "deepseek/deepseek-chat",
      "google/gemini-1.5-pro",
      "openai/gpt-4o",
    ]);
    expect(outcome.routing_decision.chain.map((entry) => entry.ordinal)).toEqual([
      0,
      1,
      2,
    ]);
  });
});

describe("T-D2-08 router_filter_structured_support", () => {
  it("excludes targets lacking structured output with feature_unsupported", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("structured-filter", [
          policyTarget("deepseek", "no-structured", {
            structured_output: false,
          }),
          policyTarget("google", "with-structured", {
            structured_output: true,
          }),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(
      cache,
      defaultContext({
        requirements: defaultRequirements({
          structured_output_required: true,
        }),
      }),
    );

    expect(chainKeys(outcome)).toEqual(["google/with-structured"]);
    expect(excludedReasons(outcome, "deepseek", "no-structured")).toContain(
      "feature_unsupported",
    );
  });
});

describe("T-D2-09 router_filter_context_window", () => {
  it("excludes targets below the required context window with context_window_too_small", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("context-window-filter", [
          policyTarget("deepseek", "small-window", {
            min_context_window: 8_000,
          }),
          policyTarget("google", "large-window", {
            min_context_window: 128_000,
          }),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(
      cache,
      defaultContext({
        requirements: defaultRequirements({
          min_context_window: 32_000,
        }),
      }),
    );

    expect(chainKeys(outcome)).toEqual(["google/large-window"]);
    expect(excludedReasons(outcome, "deepseek", "small-window")).toContain(
      "context_window_too_small",
    );
  });
});

describe("T-D2-10 router_filter_language", () => {
  it("excludes non-matching language targets with language_unsupported", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("language-filter", [
          policyTarget("deepseek", "english-only", {
            languages: ["en"],
          }),
          policyTarget("google", "arabic-capable", {
            languages: ["en", "ar"],
          }),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(
      cache,
      defaultContext({
        requirements: defaultRequirements({
          languages: ["ar"],
        }),
      }),
    );

    expect(chainKeys(outcome)).toEqual(["google/arabic-capable"]);
    expect(excludedReasons(outcome, "deepseek", "english-only")).toContain(
      "language_unsupported",
    );
  });
});

describe("T-D2-11 router_filter_latency_class", () => {
  it("excludes latency mismatches with reason_code feature_unsupported", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("latency-filter", [
          policyTarget("deepseek", "batch-class", {
            latency_class: "batch",
          }),
          policyTarget("google", "interactive-class", {
            latency_class: "interactive",
          }),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(
      cache,
      defaultContext({
        requirements: defaultRequirements({
          latency_class: "interactive",
        }),
      }),
    );

    expect(chainKeys(outcome)).toEqual(["google/interactive-class"]);
    expect(excludedReasons(outcome, "deepseek", "batch-class")).toEqual([
      "feature_unsupported",
    ]);
  });
});

describe("T-D2-12 router_installation_override_applied", () => {
  it("narrows or pins the chain and never widens beyond matched rule targets", () => {
    const ruleTargets = [
      policyTarget("deepseek", "deepseek-chat"),
      policyTarget("google", "gemini-1.5-pro"),
      policyTarget("openai", "gpt-4o"),
    ];
    const document = buildPolicyDocument({
      rules: [catchAllRule("override-rule", ruleTargets)],
      overrides: [
        {
          installation_id: FIXTURE_INSTALLATION_ID,
          exclude_providers: ["openai"],
          pin_target: {
            provider_id: "google",
            model_id: "gemini-1.5-pro",
          },
        },
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(cache);
    const allowedKeys = new Set(
      ruleTargets.map((target) => `${target.provider_id}/${target.model_id}`),
    );

    expect(chainKeys(outcome).every((key) => allowedKeys.has(key))).toBe(true);
    expect(chainKeys(outcome)).not.toContain("openai/gpt-4o");
    expect(chainKeys(outcome)).toEqual(["google/gemini-1.5-pro"]);
    expect(chainKeys(outcome).length).toBeLessThanOrEqual(ruleTargets.length);
  });
});

describe("T-D2-13 router_identical_inputs_identical_chain", () => {
  it("returns identical candidate chains for identical capability, policy, and request inputs", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("determinism", [
          policyTarget("deepseek", "deepseek-chat"),
          policyTarget("google", "gemini-1.5-pro"),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);
    const context = defaultContext();

    const first = route(cache, context);
    const second = route(cache, context);

    expect(second.routing_decision.chain).toEqual(first.routing_decision.chain);
    expect(second.routing_decision.excluded).toEqual(
      first.routing_decision.excluded,
    );
    expect(second.routing_decision.max_parallel_attempts).toBe(
      first.routing_decision.max_parallel_attempts,
    );
  });
});

describe("T-D2-14 router_selection_reason_recorded", () => {
  it("records routing_decision including max_attempts and timeout_ms carry-through", () => {
    const document = buildPolicyDocument({
      policy_id: "policy-selection-reason",
      policy_version: 3,
      rules: [
        catchAllRule(
          "selection-reason-rule",
          [
            policyTarget(
              "deepseek",
              "deepseek-chat",
              {},
              { max_attempts: 3, timeout_ms: 45_000 },
            ),
          ],
          {},
          2,
        ),
      ],
    });
    const cache = preloadPolicyCache(document);
    const requirements = defaultRequirements({
      structured_output_required: true,
      min_context_window: 16_000,
      languages: ["en"],
      latency_class: "interactive",
    });
    const outcome = route(
      cache,
      defaultContext({
        routingTier: "standard",
        requirements,
        manifestCostClass: "standard",
        entitlementMaxCostClass: "premium",
      }),
    );
    const decision = outcome.routing_decision;

    expect(decision.policy_id).toBe("policy-selection-reason");
    expect(decision.policy_version).toBe(3);
    expect(decision.rule_id).toBe("selection-reason-rule");
    expect(decision.effective_cost_class).toBe("standard");
    expect(decision.cost_class_source).toBe("manifest");
    expect(decision.routing_tier).toBe("standard");
    expect(decision.required_features).toEqual(requirements);
    expect(decision.chain).toEqual([
      {
        ordinal: 0,
        provider_id: "deepseek",
        model_id: "deepseek-chat",
        max_attempts: 3,
        timeout_ms: 45_000,
      },
    ]);
    expect(decision.excluded).toEqual(expect.any(Array));
    expect(decision.max_parallel_attempts).toBe(2);
  });
});

describe("T-D2-15 router_prior_failure_does_not_change_chain", () => {
  it("ignores a simulated prior provider failure for identical subsequent routing", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("stateless", [
          policyTarget("deepseek", "deepseek-chat"),
          policyTarget("google", "gemini-1.5-pro"),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);
    const baseContext = defaultContext();

    const withoutFailure = route(cache, baseContext);
    const withFailure = route(
      cache,
      defaultContext({
        priorProviderFailure: {
          providerId: "deepseek",
          modelId: "deepseek-chat",
        },
      }),
    );

    expect(withFailure.routing_decision.chain).toEqual(
      withoutFailure.routing_decision.chain,
    );
    expect(withFailure.routing_decision.excluded).toEqual(
      withoutFailure.routing_decision.excluded,
    );
  });
});

describe("T-D2-16 router_cost_class_applied", () => {
  it("reads force_cost_class only from the document override (no context field)", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("cost-class", [
          policyTarget("deepseek", "economy-model", {
            cost_class: "economy",
          }),
          policyTarget("google", "premium-model", {
            cost_class: "premium",
          }),
        ]),
      ],
      overrides: [
        {
          installation_id: FIXTURE_INSTALLATION_ID,
          force_cost_class: "economy",
        },
      ],
    });
    const cache = preloadPolicyCache(document);

    const boundByInstallation = route(
      cache,
      defaultContext({
        manifestCostClass: "standard",
        entitlementMaxCostClass: "premium",
      }),
    );
    expect(boundByInstallation.routing_decision.effective_cost_class).toBe(
      "economy",
    );
    expect(boundByInstallation.routing_decision.cost_class_source).toBe(
      "installation_override",
    );
    expect(chainKeys(boundByInstallation)).toEqual(["deepseek/economy-model"]);
  });

  it("uses entitlement_cap and manifest when no document force_cost_class is present", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("cost-class", [
          policyTarget("deepseek", "economy-model", {
            cost_class: "economy",
          }),
          policyTarget("google", "premium-model", {
            cost_class: "premium",
          }),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);

    const boundByEntitlement = route(
      cache,
      defaultContext({
        manifestCostClass: "premium",
        entitlementMaxCostClass: "economy",
      }),
    );
    expect(boundByEntitlement.routing_decision.effective_cost_class).toBe(
      "economy",
    );
    expect(boundByEntitlement.routing_decision.cost_class_source).toBe(
      "entitlement_cap",
    );

    const boundByManifest = route(
      cache,
      defaultContext({
        manifestCostClass: "standard",
        entitlementMaxCostClass: "premium",
      }),
    );
    expect(boundByManifest.routing_decision.effective_cost_class).toBe(
      "standard",
    );
    expect(boundByManifest.routing_decision.cost_class_source).toBe("manifest");
    expect(chainKeys(boundByManifest)).toEqual(["deepseek/economy-model"]);
  });

  it("does not let defaults.cost_class change effective_cost_class or cost_class_source", () => {
    const baseDocument = buildPolicyDocument({
      defaults: {
        cost_class: "economy",
        max_parallel_attempts: 1,
      },
      rules: [
        catchAllRule("defaults-ignored", [
          policyTarget("deepseek", "deepseek-chat", { cost_class: "premium" }),
        ]),
      ],
    });
    const premiumDefaults = buildPolicyDocument({
      defaults: {
        cost_class: "premium",
        max_parallel_attempts: 1,
      },
      rules: baseDocument.rules,
    });

    const withEconomyDefault = route(
      preloadPolicyCache(baseDocument),
      defaultContext({
        manifestCostClass: "standard",
        entitlementMaxCostClass: "premium",
      }),
    );
    const withPremiumDefault = route(
      preloadPolicyCache(premiumDefaults),
      defaultContext({
        manifestCostClass: "standard",
        entitlementMaxCostClass: "premium",
      }),
    );

    expect(withEconomyDefault.routing_decision.effective_cost_class).toBe(
      "standard",
    );
    expect(withEconomyDefault.routing_decision.cost_class_source).toBe(
      "manifest",
    );
    expect(withPremiumDefault.routing_decision.effective_cost_class).toBe(
      withEconomyDefault.routing_decision.effective_cost_class,
    );
    expect(withPremiumDefault.routing_decision.cost_class_source).toBe(
      withEconomyDefault.routing_decision.cost_class_source,
    );
  });

  it("breaks equal-class ties using SOURCE_PRIORITY (installation_override < entitlement_cap < manifest)", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("tie-break", [
          policyTarget("deepseek", "economy-model", { cost_class: "economy" }),
        ]),
      ],
      overrides: [
        {
          installation_id: FIXTURE_INSTALLATION_ID,
          force_cost_class: "economy",
        },
      ],
    });
    const cache = preloadPolicyCache(document);

    const withOverride = route(
      cache,
      defaultContext({
        manifestCostClass: "economy",
        entitlementMaxCostClass: "economy",
      }),
    );
    expect(withOverride.routing_decision.effective_cost_class).toBe("economy");
    expect(withOverride.routing_decision.cost_class_source).toBe(
      "installation_override",
    );

    const withoutOverrideDocument = buildPolicyDocument({
      rules: document.rules,
    });
    const withoutOverride = route(
      preloadPolicyCache(withoutOverrideDocument),
      defaultContext({
        manifestCostClass: "economy",
        entitlementMaxCostClass: "economy",
      }),
    );
    expect(withoutOverride.routing_decision.effective_cost_class).toBe(
      "economy",
    );
    expect(withoutOverride.routing_decision.cost_class_source).toBe(
      "entitlement_cap",
    );
  });
});

describe("T-D2-17 router_degraded_tier_when_soft_threshold", () => {
  it("matches degraded tier rules when routing_tier is degraded", () => {
    // Specific tier rules first; document must end with a true catch-all.
    const withCatchAll = buildPolicyDocument({
      rules: [
        catchAllRule(
          "standard-tier",
          [policyTarget("openai", "gpt-4o")],
          { tiers: ["standard"] },
        ),
        catchAllRule(
          "degraded-tier",
          [policyTarget("deepseek", "deepseek-chat")],
          { tiers: ["degraded"] },
        ),
        catchAllRule("catch-all", [
          policyTarget("fallback", "fallback-model"),
        ]),
      ],
    });
    const cache = preloadPolicyCache(withCatchAll);

    const standardOutcome = route(
      cache,
      defaultContext({ routingTier: "standard" }),
    );
    expect(standardOutcome.routing_decision.rule_id).toBe("standard-tier");
    expect(chainKeys(standardOutcome)).toEqual(["openai/gpt-4o"]);

    const degradedOutcome = route(
      cache,
      defaultContext({ routingTier: "degraded" }),
    );
    expect(degradedOutcome.routing_decision.rule_id).toBe("degraded-tier");
    expect(degradedOutcome.routing_decision.routing_tier).toBe("degraded");
    expect(chainKeys(degradedOutcome)).toEqual(["deepseek/deepseek-chat"]);
  });
});

describe("T-D2-19 routing_policy_is_versioned_data", () => {
  it("consults per-installation key first, then global active_routing_policy key", () => {
    const firstDocument = buildPolicyDocument({
      policy_id: "policy-versioned-a",
      policy_version: 1,
      rules: [
        catchAllRule("version-a", [policyTarget("deepseek", "model-a")]),
      ],
    });
    const secondDocument = buildPolicyDocument({
      policy_id: "policy-versioned-b",
      policy_version: 2,
      rules: [
        catchAllRule("version-b", [policyTarget("google", "model-b")]),
      ],
    });

    const cache = preloadPolicyCache(firstDocument);
    const consultSpy = vi.spyOn(cache, "consult");

    const firstOutcome = route(cache);
    expect(consultSpy.mock.calls[0]).toEqual([
      "active_routing_policy",
      `${FIXTURE_POLICY_KEY}/${FIXTURE_INSTALLATION_ID}`,
    ]);
    expect(consultSpy.mock.calls[1]).toEqual([
      "active_routing_policy",
      FIXTURE_POLICY_KEY,
    ]);
    expect(firstOutcome.routing_decision.policy_id).toBe("policy-versioned-a");
    expect(firstOutcome.routing_decision.policy_version).toBe(1);
    expect(chainKeys(firstOutcome)).toEqual(["deepseek/model-a"]);

    cache.remember("active_routing_policy", FIXTURE_POLICY_KEY, {
      policy_id: secondDocument.policy_id,
      policy_version: secondDocument.policy_version,
      content_pointer: `control/routing-policy/${secondDocument.policy_id}/${secondDocument.policy_version}.json`,
      active_from: "2026-08-02T00:00:00.000Z",
      activated_by: "test-fixture",
      document: secondDocument,
    });

    const secondOutcome = route(cache);
    expect(secondOutcome.routing_decision.policy_id).toBe("policy-versioned-b");
    expect(secondOutcome.routing_decision.policy_version).toBe(2);
    expect(chainKeys(secondOutcome)).toEqual(["google/model-b"]);
    expect(secondOutcome.routing_decision.policy_id).not.toBe(
      firstOutcome.routing_decision.policy_id,
    );
  });
});

describe("T-D2-20 outgoing_connection_cap_bounds_parallelism", () => {
  it("clamps policy-requested parallelism of 10 over default 12 to exactly 6", () => {
    const document = buildPolicyDocument({
      defaults: {
        cost_class: "standard",
        max_parallel_attempts: 12,
      },
      rules: [
        catchAllRule(
          "parallel-cap",
          [policyTarget("deepseek", "deepseek-chat")],
          {},
          10,
        ),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(cache);

    expect(outcome.routing_decision.max_parallel_attempts).toBe(6);
  });

  it("prefers rule max_parallel_attempts over defaults (rule=2, default=12 → 2)", () => {
    const document = buildPolicyDocument({
      defaults: {
        cost_class: "standard",
        max_parallel_attempts: 12,
      },
      rules: [
        catchAllRule(
          "rule-wins",
          [policyTarget("deepseek", "deepseek-chat")],
          {},
          2,
        ),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(cache);

    expect(outcome.routing_decision.max_parallel_attempts).toBe(2);
  });
});

describe("router_rule_requires_floor", () => {
  it("excludes targets that fail the matched rule requires floor", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule(
          "requires-floor",
          [
            policyTarget("deepseek", "small-window", {
              min_context_window: 8_000,
            }),
            policyTarget("google", "large-window", {
              min_context_window: 128_000,
            }),
          ],
          {},
          undefined,
          {
            structured_output: false,
            min_context_window: 64_000,
            languages: [],
          },
        ),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(
      cache,
      defaultContext({
        requirements: defaultRequirements({
          min_context_window: 0,
        }),
      }),
    );

    expect(chainKeys(outcome)).toEqual(["google/large-window"]);
    expect(excludedReasons(outcome, "deepseek", "small-window")).toContain(
      "context_window_too_small",
    );
  });
});

describe("router_empty_chain_after_filtering", () => {
  it("returns chain: [] with every target listed in excluded", () => {
    const targets = [
      policyTarget("deepseek", "batch-only", { latency_class: "batch" }),
      policyTarget("google", "also-batch", { latency_class: "batch" }),
    ];
    const document = buildPolicyDocument({
      rules: [catchAllRule("empty-chain", targets)],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(
      cache,
      defaultContext({
        requirements: defaultRequirements({
          latency_class: "interactive",
        }),
      }),
    );

    expect(outcome.routing_decision.chain).toEqual([]);
    expect(outcome.routing_decision.excluded).toHaveLength(targets.length);
    for (const target of targets) {
      expect(outcome.routing_decision.excluded).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            provider_id: target.provider_id,
            model_id: target.model_id,
            reason_code: "feature_unsupported",
          }),
        ]),
      );
    }
  });
});

describe("router_kill_switch_excludes_providers", () => {
  it("excludes killed provider ids with reason_code kill_switch", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule("kill-switch", [
          policyTarget("deepseek", "deepseek-chat"),
          policyTarget("google", "gemini-1.5-pro"),
        ]),
      ],
    });
    const cache = preloadPolicyCache(document);
    const outcome = route(
      cache,
      defaultContext({
        killedProviderIds: ["deepseek"],
      }),
    );

    expect(chainKeys(outcome)).toEqual(["google/gemini-1.5-pro"]);
    expect(excludedReasons(outcome, "deepseek", "deepseek-chat")).toEqual([
      "kill_switch",
    ]);
  });
});

describe("router_document_validation", () => {
  it("throws policy_identity_mismatch when row and document disagree", () => {
    const document = buildPolicyDocument({
      policy_id: "policy-doc",
      policy_version: 2,
    });
    const cache = preloadPolicyCache(document, FIXTURE_POLICY_KEY, {
      policy_id: "policy-row",
      policy_version: 1,
    });

    expect(() => route(cache)).toThrow(RoutingPolicyError);
    try {
      route(cache);
    } catch (error) {
      expect(error).toBeInstanceOf(RoutingPolicyError);
      expect((error as RoutingPolicyError).code).toBe(
        "policy_identity_mismatch",
      );
    }
  });

  it("throws unsupported_schema_version for unknown schema_version", () => {
    const document = buildPolicyDocument({
      schema_version: 99,
    });
    const cache = preloadPolicyCache(document);

    try {
      route(cache);
      expect.unreachable("expected RoutingPolicyError");
    } catch (error) {
      expect(error).toBeInstanceOf(RoutingPolicyError);
      expect((error as RoutingPolicyError).code).toBe(
        "unsupported_schema_version",
      );
    }
  });

  it("throws missing_catch_all when the last rule is not a catch-all", () => {
    const document = buildPolicyDocument({
      rules: [
        catchAllRule(
          "narrow-only",
          [policyTarget("deepseek", "deepseek-chat")],
          { capability_ids: [FIXTURE_CAPABILITY_ID] },
        ),
      ],
    });
    const cache = preloadPolicyCache(document);

    try {
      route(cache);
      expect.unreachable("expected RoutingPolicyError");
    } catch (error) {
      expect(error).toBeInstanceOf(RoutingPolicyError);
      expect((error as RoutingPolicyError).code).toBe("missing_catch_all");
    }
  });
});
