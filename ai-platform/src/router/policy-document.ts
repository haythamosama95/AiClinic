/**
 * Shared pure parser for routing policy documents (R8-ROUTE1).
 *
 * Used before publication writes and at runtime so that identity-only or
 * otherwise incomplete documents never become serving state. Stateless and
 * dependency-free: no imports from router/index.ts or config-cache.
 */

export type PolicyCostClass = "economy" | "standard" | "premium";
export type PolicyRoutingTier = "standard" | "degraded";

export type PolicyTargetFeatures = {
  structured_output: boolean;
  min_context_window: number;
  languages: string[];
  latency_class: string;
  cost_class: PolicyCostClass;
};

export type PolicyTarget = {
  provider_id: string;
  model_id: string;
  features: PolicyTargetFeatures;
  max_attempts: number;
  timeout_ms: number;
};

export type PolicyRuleMatch = {
  capability_ids?: string[];
  installation_ids?: string[];
  cost_classes?: PolicyCostClass[];
  tiers?: PolicyRoutingTier[];
  languages?: string[];
  latency_classes?: string[];
};

export type PolicyRuleRequires = {
  structured_output: boolean;
  min_context_window: number;
  languages: string[];
};

export type PolicyRule = {
  rule_id: string;
  match?: PolicyRuleMatch;
  requires: PolicyRuleRequires;
  targets: PolicyTarget[];
  max_parallel_attempts?: number;
};

export type PolicyOverride = {
  installation_id: string;
  exclude_providers?: string[];
  pin_target?: { provider_id: string; model_id: string };
  force_cost_class?: PolicyCostClass;
};

export type RoutingPolicyDocument = {
  schema_version: 1;
  policy_id: string;
  policy_version: number;
  defaults: {
    cost_class: PolicyCostClass;
    max_parallel_attempts: number;
  };
  rules: PolicyRule[];
  overrides: PolicyOverride[];
};

export type ParseRoutingPolicyDocumentResult =
  | { ok: true; document: RoutingPolicyDocument }
  | { ok: false; code: "invalid_policy_document"; reason: string };

class PolicyShapeError extends Error {}

const COST_CLASSES: readonly PolicyCostClass[] = ["economy", "standard", "premium"];
const ROUTING_TIERS: readonly PolicyRoutingTier[] = ["standard", "degraded"];

function fail(path: string, expectation: string): never {
  throw new PolicyShapeError(`${path} must be ${expectation}`);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireRecord(value: unknown, path: string): Record<string, unknown> {
  if (!isRecord(value)) fail(path, "an object");
  return value;
}

function requireArray(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) fail(path, "an array");
  return value;
}

function requireNonEmptyString(value: unknown, path: string): string {
  if (typeof value !== "string" || value.length === 0) fail(path, "a nonempty string");
  return value;
}

function requireBoolean(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") fail(path, "a boolean");
  return value;
}

function requirePositiveSafeInteger(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    fail(path, "a positive safe integer");
  }
  return value;
}

function requireContextSize(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    fail(path, "a finite number >= 0");
  }
  return value;
}

function requireStringArray(value: unknown, path: string): string[] {
  const items = requireArray(value, path);
  items.forEach((item, index) => requireNonEmptyString(item, `${path}[${index}]`));
  return items as string[];
}

function requireEnum<T extends string>(
  value: unknown,
  allowed: readonly T[],
  path: string,
): T {
  if (typeof value !== "string" || !(allowed as readonly string[]).includes(value)) {
    fail(path, `one of ${allowed.join(", ")}`);
  }
  return value as T;
}

function parseFeatures(value: unknown, path: string): PolicyTargetFeatures {
  const record = requireRecord(value, path);
  return {
    structured_output: requireBoolean(record.structured_output, `${path}.structured_output`),
    min_context_window: requireContextSize(record.min_context_window, `${path}.min_context_window`),
    languages: requireStringArray(record.languages, `${path}.languages`),
    latency_class: requireNonEmptyString(record.latency_class, `${path}.latency_class`),
    cost_class: requireEnum(record.cost_class, COST_CLASSES, `${path}.cost_class`),
  };
}

function parseTarget(value: unknown, path: string): PolicyTarget {
  const record = requireRecord(value, path);
  return {
    provider_id: requireNonEmptyString(record.provider_id, `${path}.provider_id`),
    model_id: requireNonEmptyString(record.model_id, `${path}.model_id`),
    features: parseFeatures(record.features, `${path}.features`),
    max_attempts: requirePositiveSafeInteger(record.max_attempts, `${path}.max_attempts`),
    timeout_ms: requirePositiveSafeInteger(record.timeout_ms, `${path}.timeout_ms`),
  };
}

function parseMatch(value: unknown, path: string): PolicyRuleMatch {
  const record = requireRecord(value, path);
  const match: PolicyRuleMatch = {};
  if (record.capability_ids !== undefined) {
    match.capability_ids = requireStringArray(record.capability_ids, `${path}.capability_ids`);
  }
  if (record.installation_ids !== undefined) {
    match.installation_ids = requireStringArray(record.installation_ids, `${path}.installation_ids`);
  }
  if (record.cost_classes !== undefined) {
    match.cost_classes = requireArray(record.cost_classes, `${path}.cost_classes`).map(
      (item, index) => requireEnum(item, COST_CLASSES, `${path}.cost_classes[${index}]`),
    );
  }
  if (record.tiers !== undefined) {
    match.tiers = requireArray(record.tiers, `${path}.tiers`).map((item, index) =>
      requireEnum(item, ROUTING_TIERS, `${path}.tiers[${index}]`),
    );
  }
  if (record.languages !== undefined) {
    match.languages = requireStringArray(record.languages, `${path}.languages`);
  }
  if (record.latency_classes !== undefined) {
    match.latency_classes = requireStringArray(record.latency_classes, `${path}.latency_classes`);
  }
  return match;
}

function isCatchAllMatch(match: PolicyRuleMatch | undefined): boolean {
  if (!match) return true;
  return [
    match.capability_ids,
    match.installation_ids,
    match.cost_classes,
    match.tiers,
    match.languages,
    match.latency_classes,
  ].every((clause) => clause === undefined || clause.length === 0);
}

function parseRule(value: unknown, path: string): PolicyRule {
  const record = requireRecord(value, path);
  const rule: PolicyRule = {
    rule_id: requireNonEmptyString(record.rule_id, `${path}.rule_id`),
    requires: parseRequires(record.requires, `${path}.requires`),
    targets: requireArray(record.targets, `${path}.targets`).map((target, index) =>
      parseTarget(target, `${path}.targets[${index}]`),
    ),
  };
  if (record.match !== undefined) {
    rule.match = parseMatch(record.match, `${path}.match`);
  }
  if (record.max_parallel_attempts !== undefined) {
    rule.max_parallel_attempts = requirePositiveSafeInteger(
      record.max_parallel_attempts,
      `${path}.max_parallel_attempts`,
    );
  }
  return rule;
}

function parseRequires(value: unknown, path: string): PolicyRuleRequires {
  const record = requireRecord(value, path);
  return {
    structured_output: requireBoolean(record.structured_output, `${path}.structured_output`),
    min_context_window: requireContextSize(record.min_context_window, `${path}.min_context_window`),
    languages: requireStringArray(record.languages, `${path}.languages`),
  };
}

function parseOverride(value: unknown, path: string): PolicyOverride {
  const record = requireRecord(value, path);
  const override: PolicyOverride = {
    installation_id: requireNonEmptyString(record.installation_id, `${path}.installation_id`),
  };
  if (record.exclude_providers !== undefined) {
    override.exclude_providers = requireStringArray(
      record.exclude_providers,
      `${path}.exclude_providers`,
    );
  }
  if (record.pin_target !== undefined) {
    const pin = requireRecord(record.pin_target, `${path}.pin_target`);
    override.pin_target = {
      provider_id: requireNonEmptyString(pin.provider_id, `${path}.pin_target.provider_id`),
      model_id: requireNonEmptyString(pin.model_id, `${path}.pin_target.model_id`),
    };
  }
  if (record.force_cost_class !== undefined) {
    override.force_cost_class = requireEnum(
      record.force_cost_class,
      COST_CLASSES,
      `${path}.force_cost_class`,
    );
  }
  return override;
}

/**
 * Validates the full shape of a routing policy document (schema_version 1).
 * Returns the typed document on success, or invalid_policy_document with a
 * human-readable reason. Pure: performs no I/O and never throws.
 */
export function parseRoutingPolicyDocument(
  value: unknown,
): ParseRoutingPolicyDocumentResult {
  try {
    const record = requireRecord(value, "document");
    if (record.schema_version !== 1) {
      fail("schema_version", "1");
    }
    const policyId = requireNonEmptyString(record.policy_id, "policy_id");
    const policyVersion = requirePositiveSafeInteger(record.policy_version, "policy_version");

    const defaults = requireRecord(record.defaults, "defaults");
    const parsedDefaults = {
      cost_class: requireEnum(defaults.cost_class, COST_CLASSES, "defaults.cost_class"),
      max_parallel_attempts: requirePositiveSafeInteger(
        defaults.max_parallel_attempts,
        "defaults.max_parallel_attempts",
      ),
    };

    const rulesValue = requireArray(record.rules, "rules");
    if (rulesValue.length === 0) fail("rules", "a nonempty array");
    const rules = rulesValue.map((rule, index) => parseRule(rule, `rules[${index}]`));
    if (!isCatchAllMatch(rules[rules.length - 1].match)) {
      fail("rules", "ending with a catch-all rule (absent or empty match)");
    }

    const overrides = requireArray(record.overrides, "overrides").map((override, index) =>
      parseOverride(override, `overrides[${index}]`),
    );

    return {
      ok: true,
      document: {
        schema_version: 1,
        policy_id: policyId,
        policy_version: policyVersion,
        defaults: parsedDefaults,
        rules,
        overrides,
      },
    };
  } catch (err) {
    if (err instanceof PolicyShapeError) {
      return { ok: false, code: "invalid_policy_document", reason: err.message };
    }
    throw err;
  }
}

/**
 * Lowercase hex SHA-256 digest of raw bytes (R8-PUB1). Used to name immutable
 * content objects and to verify stored bytes against routing_policy.content_sha256.
 */
export async function sha256HexOfBytes(bytes: ArrayBuffer | Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
