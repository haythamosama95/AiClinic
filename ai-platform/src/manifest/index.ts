/**
 * Field-group manifest for the ten §5.1 capability manifest groups.
 * Types and validation derive from this; contract tests (T-A4-*) exercise it.
 */
import { validateKey } from "../context/index";

export const MANIFEST_FIELD_GROUPS = [
  "Identity",
  "Access",
  "Interaction",
  "Input",
  "Context requirements",
  "Prompt binding",
  "Output",
  "Routing",
  "Economics",
  "Governance",
] as const;

export type ManifestFieldGroup = (typeof MANIFEST_FIELD_GROUPS)[number];

export const MANIFEST_FIELD_MANIFEST = {
  Identity: [
    "capabilityId",
    "version",
    "title",
    "lifecycleState",
    "successorId",
  ],
  Access: [
    "requiredCapabilityScope",
    "minimumPlanTier",
    "allowedStaffRoles",
    "killSwitchFlag",
  ],
  Interaction: ["interactionMode"],
  Input: [
    "userIntentShape",
    "priorTurnShape",
    "sizeLimits",
    "allowedLanguages",
  ],
  "Context requirements": [
    "key",
    "required",
    "shapeRef",
    "maxSize",
    "freshnessHint",
  ],
  "Prompt binding": [
    "systemInstructionArtifactRef",
    "businessRuleFragmentRefs",
    "contextRenderingTemplateRef",
    "outputFormatInstructionDerivationRule",
  ],
  Output: [
    "mode",
    "outputSchemaRef",
    "businessValidationRuleRefs",
    "repairPolicy",
  ],
  Routing: [
    "routingPolicyRef",
    "requiredProviderFeatures",
    "latencyClass",
    "degradedTierPolicy",
  ],
  Economics: [
    "maxInputTokens",
    "maxOutputTokens",
    "perRequestCostCeiling",
    "quotaWeight",
  ],
  Governance: ["acceptanceMode", "retentionClass", "evalSuiteRef"],
} as const;

const CONVERSATIONAL_ONLY_INTERACTION_FIELDS = [
  "maxHistoryTurns",
  "maxContextRoundsPerTurn",
  "transcriptSizeLimit",
] as const;

const ROUTING_FORBIDDEN_TARGET_FIELDS = ["provider", "model"] as const;

export type InteractionMode = "single_shot" | "conversational";

type ManifestGroupRecord<Keys extends readonly string[]> = {
  [K in Keys[number]]: unknown;
};

type IdentityGroup = ManifestGroupRecord<
  typeof MANIFEST_FIELD_MANIFEST.Identity
>;
type AccessGroup = ManifestGroupRecord<typeof MANIFEST_FIELD_MANIFEST.Access>;
type InteractionGroup = Partial<
  ManifestGroupRecord<typeof MANIFEST_FIELD_MANIFEST.Interaction>
> &
  Partial<
    Record<(typeof CONVERSATIONAL_ONLY_INTERACTION_FIELDS)[number], unknown>
  >;
type InputGroup = ManifestGroupRecord<typeof MANIFEST_FIELD_MANIFEST.Input>;
type ContextRequirementEntry = ManifestGroupRecord<
  typeof MANIFEST_FIELD_MANIFEST["Context requirements"]
>;

type ConversationalContextRequirements = {
  readonly permittedKeySet: readonly string[];
};

type ContextRequirementsGroup =
  | ContextRequirementEntry[]
  | ConversationalContextRequirements;
type PromptBindingGroup = ManifestGroupRecord<
  typeof MANIFEST_FIELD_MANIFEST["Prompt binding"]
>;
type OutputGroup = ManifestGroupRecord<typeof MANIFEST_FIELD_MANIFEST.Output>;
type RoutingGroup = ManifestGroupRecord<
  typeof MANIFEST_FIELD_MANIFEST.Routing
>;
type EconomicsGroup = ManifestGroupRecord<
  typeof MANIFEST_FIELD_MANIFEST.Economics
>;
type GovernanceGroup = ManifestGroupRecord<
  typeof MANIFEST_FIELD_MANIFEST.Governance
>;

/** §5.1 capability manifest — ten field groups plus a read-only interaction mode. */
export type Manifest = {
  readonly interactionMode: InteractionMode;
  Identity: IdentityGroup;
  Access: AccessGroup;
  Interaction: InteractionGroup;
  Input: InputGroup;
  "Context requirements": ContextRequirementsGroup;
  "Prompt binding": PromptBindingGroup;
  Output: OutputGroup;
  Routing: RoutingGroup;
  Economics: EconomicsGroup;
  Governance: GovernanceGroup;
};

export type PublishedRegistryEntry = {
  capabilityId: string;
  version: string;
  hash: string;
};

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertManifestKeys(
  group: Record<string, unknown>,
  keys: readonly string[],
  groupName: ManifestFieldGroup,
): void {
  for (const key of keys) {
    if (!(key in group)) {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }
  }
}

function validateObjectGroup(
  value: unknown,
  groupName: ManifestFieldGroup,
  keys: readonly string[],
): Record<string, unknown> {
  if (!isPlainObject(value)) {
    throw new Error(`Malformed manifest group: ${groupName}`);
  }
  assertManifestKeys(value, keys, groupName);
  return value;
}

function validateSingleShotContextRequirements(
  value: unknown,
  groupName: ManifestFieldGroup,
): ContextRequirementEntry[] {
  if (!Array.isArray(value)) {
    throw new Error(`Malformed manifest group: ${groupName}`);
  }

  const entryKeys = MANIFEST_FIELD_MANIFEST["Context requirements"];
  for (const entry of value) {
    if (!isPlainObject(entry)) {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }
    assertManifestKeys(entry, entryKeys, groupName);
  }

  return value as ContextRequirementEntry[];
}

function validateConversationalContextRequirements(
  value: unknown,
  groupName: ManifestFieldGroup,
): ConversationalContextRequirements {
  if (!isPlainObject(value)) {
    throw new Error(`Malformed manifest group: ${groupName}`);
  }

  if (!("permittedKeySet" in value)) {
    throw new Error("Conversational manifest omits required field: permittedKeySet");
  }

  if (!Array.isArray(value.permittedKeySet)) {
    throw new Error(`Malformed manifest group: ${groupName}`);
  }

  for (const key of value.permittedKeySet) {
    if (typeof key !== "string") {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }

    const keyResult = validateKey(key);
    if (!keyResult.ok) {
      throw new Error(`Permitted key set unknown key: ${key}`);
    }
  }

  return {
    permittedKeySet: value.permittedKeySet as readonly string[],
  };
}

function assertConversationalInteractionFields(
  interaction: InteractionGroup,
): void {
  for (const field of CONVERSATIONAL_ONLY_INTERACTION_FIELDS) {
    if (!(field in interaction)) {
      throw new Error(`Conversational manifest omits required field: ${field}`);
    }
  }
}

function resolveInteractionMode(
  interaction: InteractionGroup,
): InteractionMode {
  const mode = interaction.interactionMode;
  if (mode === undefined) {
    return "single_shot";
  }
  if (mode !== "single_shot" && mode !== "conversational") {
    throw new Error("Malformed manifest group: Interaction");
  }
  return mode;
}

function assertNoConversationalFieldsOnSingleShot(
  interaction: InteractionGroup,
  interactionMode: InteractionMode,
  contextRequirements: unknown,
): void {
  if (interactionMode !== "single_shot") {
    return;
  }

  for (const field of CONVERSATIONAL_ONLY_INTERACTION_FIELDS) {
    if (field in interaction) {
      throw new Error(
        `Conversational-only field rejected on single_shot: ${field}`,
      );
    }
  }

  if (
    isPlainObject(contextRequirements) &&
    "permittedKeySet" in contextRequirements
  ) {
    throw new Error(
      "Conversational-only field rejected on single_shot: permittedKeySet",
    );
  }
}

function assertRoutingNeverNamesProviderOrModel(
  routing: Record<string, unknown>,
): void {
  for (const field of ROUTING_FORBIDDEN_TARGET_FIELDS) {
    if (field in routing) {
      throw new Error(
        `Manifest must not name provider or model in Routing: ${field}`,
      );
    }
  }
}

function validate(json: Record<string, unknown>): Manifest {
  for (const groupName of MANIFEST_FIELD_GROUPS) {
    if (!(groupName in json)) {
      throw new Error(`Missing manifest group: ${groupName}`);
    }
  }

  const identity = validateObjectGroup(
    json.Identity,
    "Identity",
    MANIFEST_FIELD_MANIFEST.Identity,
  );
  const access = validateObjectGroup(
    json.Access,
    "Access",
    MANIFEST_FIELD_MANIFEST.Access,
  );
  const interaction = validateObjectGroup(
    json.Interaction,
    "Interaction",
    [],
  ) as InteractionGroup;
  const input = validateObjectGroup(
    json.Input,
    "Input",
    MANIFEST_FIELD_MANIFEST.Input,
  );
  const interactionMode = resolveInteractionMode(interaction);
  assertNoConversationalFieldsOnSingleShot(
    interaction,
    interactionMode,
    json["Context requirements"],
  );

  const contextRequirements =
    interactionMode === "conversational"
      ? validateConversationalContextRequirements(
          json["Context requirements"],
          "Context requirements",
        )
      : validateSingleShotContextRequirements(
          json["Context requirements"],
          "Context requirements",
        );

  if (interactionMode === "conversational") {
    assertConversationalInteractionFields(interaction);
  }
  const promptBinding = validateObjectGroup(
    json["Prompt binding"],
    "Prompt binding",
    MANIFEST_FIELD_MANIFEST["Prompt binding"],
  );
  const output = validateObjectGroup(
    json.Output,
    "Output",
    MANIFEST_FIELD_MANIFEST.Output,
  );
  const routing = validateObjectGroup(
    json.Routing,
    "Routing",
    MANIFEST_FIELD_MANIFEST.Routing,
  );
  const economics = validateObjectGroup(
    json.Economics,
    "Economics",
    MANIFEST_FIELD_MANIFEST.Economics,
  );
  const governance = validateObjectGroup(
    json.Governance,
    "Governance",
    MANIFEST_FIELD_MANIFEST.Governance,
  );

  assertRoutingNeverNamesProviderOrModel(routing);

  const manifest = {
    interactionMode,
    Identity: identity as IdentityGroup,
    Access: access as AccessGroup,
    Interaction: interaction,
    Input: input as InputGroup,
    "Context requirements": contextRequirements,
    "Prompt binding": promptBinding as PromptBindingGroup,
    Output: output as OutputGroup,
    Routing: routing as RoutingGroup,
    Economics: economics as EconomicsGroup,
    Governance: governance as GovernanceGroup,
  };

  return new Proxy(manifest, {
    set(target, prop, value) {
      if (prop === "interactionMode") {
        return true;
      }
      return Reflect.set(target, prop, value);
    },
  }) as Manifest;
}

function canonicalStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalStringify(entry)).join(",")}]`;
  }

  const object = value as Record<string, unknown>;
  const keys = Object.keys(object).sort();
  return `{${keys
    .map((key) => `${JSON.stringify(key)}:${canonicalStringify(object[key])}`)
    .join(",")}}`;
}

function stableContentHash(content: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < content.length; index += 1) {
    hash ^= content.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

export function load(json: Record<string, unknown>): Manifest {
  return validate(json);
}

export function hashManifest(json: Record<string, unknown>): string {
  return stableContentHash(canonicalStringify(json));
}

export function verifyPublishedRegistry(
  entries: PublishedRegistryEntry[],
  registry: Record<string, string>,
): void {
  for (const entry of entries) {
    const registryKey = `${entry.capabilityId}@${entry.version}`;
    const publishedHash = registry[registryKey];

    if (publishedHash === undefined) {
      throw new Error(`No published registry entry for ${registryKey}`);
    }

    if (entry.hash !== publishedHash) {
      throw new Error(
        `Published manifest hash mismatch for ${registryKey}: on-disk ${entry.hash}, registry ${publishedHash}`,
      );
    }
  }
}
