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

/** Key name itself is requirements vocabulary (§5.1); nested provider/model keys still fail. */
const PROVIDER_SHAPED_KEY_ALLOWLIST = new Set(["requiredProviderFeatures"]);

const LIFECYCLE_STATES = new Set(["active", "deprecated", "retired"]);
const OUTPUT_MODES = new Set(["prose", "structured", "structured_atomic"]);
const ACCEPTANCE_MODES = new Set([
  "advisory_display",
  "human_accept_required",
  "auto_apply",
]);

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
  readonly Identity: IdentityGroup;
  readonly Access: AccessGroup;
  readonly Interaction: InteractionGroup;
  readonly Input: InputGroup;
  readonly "Context requirements": ContextRequirementsGroup;
  readonly "Prompt binding": PromptBindingGroup;
  readonly Output: OutputGroup;
  readonly Routing: RoutingGroup;
  readonly Economics: EconomicsGroup;
  readonly Governance: GovernanceGroup;
};

export type PublishedRegistryEntry = {
  capabilityId: string;
  version: string;
  hash: string;
};

export type ManifestTreeIo = {
  manifestsDir: string;
  registryPath: string;
  readFile: (path: string) => Promise<string>;
  readdir: (path: string) => Promise<string[]>;
  join: (...parts: string[]) => string;
};

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function deepFreeze<T>(value: T): T {
  if (value === null || typeof value !== "object") {
    return value;
  }
  Object.freeze(value);
  if (Array.isArray(value)) {
    for (const entry of value) {
      deepFreeze(entry);
    }
    return value;
  }
  for (const child of Object.values(value as Record<string, unknown>)) {
    deepFreeze(child);
  }
  return value;
}

function assertExactKeys(
  group: Record<string, unknown>,
  keys: readonly string[],
  groupName: string,
): void {
  const expected = new Set(keys);
  const actual = Object.keys(group);
  for (const key of keys) {
    if (!(key in group)) {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }
  }
  for (const key of actual) {
    if (!expected.has(key)) {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }
  }
}

function isForbiddenProviderOrModelKey(key: string): boolean {
  if (PROVIDER_SHAPED_KEY_ALLOWLIST.has(key)) {
    return false;
  }
  const lower = key.toLowerCase();
  if (lower === "provider" || lower === "model") {
    return true;
  }
  return /provider|model/i.test(key);
}

function assertNeverNamesProviderOrModel(
  value: unknown,
  path: string,
): void {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => {
      assertNeverNamesProviderOrModel(entry, `${path}[${index}]`);
    });
    return;
  }
  if (!isPlainObject(value)) {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    if (isForbiddenProviderOrModelKey(key)) {
      throw new Error(
        `Manifest must not name provider or model at ${path}.${key}`,
      );
    }
    assertNeverNamesProviderOrModel(child, `${path}.${key}`);
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
  assertExactKeys(value, keys, groupName);
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
    assertExactKeys(entry, entryKeys, groupName);

    if (typeof entry.key !== "string") {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }
    if (typeof entry.required !== "boolean") {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }
    if (!isFiniteNumber(entry.maxSize)) {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }

    // Same A5 vocabulary gate as conversational permittedKeySet (H1): a
    // manifest-declared key outside the published set is a platform defect.
    const keyResult = validateKey(entry.key);
    if (!keyResult.ok) {
      throw new Error(`Context requirements unknown key: ${entry.key}`);
    }
  }

  return value as ContextRequirementEntry[];
}

function assertEconomicsTypes(economics: Record<string, unknown>): void {
  for (const field of MANIFEST_FIELD_MANIFEST.Economics) {
    if (!isFiniteNumber(economics[field])) {
      throw new Error("Malformed manifest group: Economics");
    }
  }
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

  assertExactKeys(value, ["permittedKeySet"], groupName);

  if (!Array.isArray(value.permittedKeySet)) {
    throw new Error(`Malformed manifest group: ${groupName}`);
  }

  const seen = new Set<string>();
  for (const key of value.permittedKeySet) {
    if (typeof key !== "string") {
      throw new Error(`Malformed manifest group: ${groupName}`);
    }

    // H1 content rule (specs/044): permitted keys must be in the A5 vocabulary.
    // A4 owns presence/absence of permittedKeySet; this vocabulary check is the
    // H1 extension co-located in the A4 loader (H1 Consumes A4).
    const keyResult = validateKey(key);
    if (!keyResult.ok) {
      throw new Error(`Permitted key set unknown key: ${key}`);
    }

    if (seen.has(key)) {
      throw new Error(`Permitted key set duplicate key: ${key}`);
    }
    seen.add(key);
  }

  // Empty permittedKeySet is legal: the capability may never request context
  // keys (allowlist of zero). H2 still enforces the allowlist at validation.
  return {
    permittedKeySet: value.permittedKeySet as readonly string[],
  };
}

function isPositiveInteger(value: unknown): value is number {
  return isFiniteNumber(value) && Number.isInteger(value) && value > 0;
}

function assertConversationalInteractionFields(
  interaction: InteractionGroup,
): void {
  for (const field of CONVERSATIONAL_ONLY_INTERACTION_FIELDS) {
    if (!(field in interaction)) {
      throw new Error(`Conversational manifest omits required field: ${field}`);
    }
    if (!isPositiveInteger(interaction[field])) {
      throw new Error(
        `Malformed conversational Interaction field: ${field}`,
      );
    }
  }
}

function assertInteractionExactKeys(
  interaction: InteractionGroup,
  interactionMode: InteractionMode,
): void {
  const allowed = new Set<string>(["interactionMode"]);
  if (interactionMode === "conversational") {
    for (const field of CONVERSATIONAL_ONLY_INTERACTION_FIELDS) {
      allowed.add(field);
    }
  }
  for (const key of Object.keys(interaction)) {
    if (!allowed.has(key)) {
      throw new Error("Malformed manifest group: Interaction");
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

/** §7.7 diagnostic band: days to weeks, capped at the journal horizon. */
const DIAGNOSTIC_HORIZON_MIN_DAYS = 1;
const DIAGNOSTIC_HORIZON_MAX_DAYS = 90;
const DIAGNOSTIC_RETENTION_CLASS =
  /^diagnostic_(\d+)d$/i;

function assertRetentionClassBand(retentionClass: unknown): void {
  if (typeof retentionClass !== "string") {
    throw new Error("Malformed manifest group: Governance");
  }
  const match = DIAGNOSTIC_RETENTION_CLASS.exec(retentionClass.trim());
  if (!match) {
    throw new Error(
      "Malformed manifest Governance.retentionClass: expected diagnostic_Nd",
    );
  }
  const days = Number.parseInt(match[1], 10);
  if (
    !Number.isFinite(days) ||
    days < DIAGNOSTIC_HORIZON_MIN_DAYS ||
    days > DIAGNOSTIC_HORIZON_MAX_DAYS
  ) {
    throw new Error(
      `Malformed manifest Governance.retentionClass: diagnostic horizon must be ${DIAGNOSTIC_HORIZON_MIN_DAYS}–${DIAGNOSTIC_HORIZON_MAX_DAYS} days`,
    );
  }
}

function assertContentEnums(manifest: {
  Identity: Record<string, unknown>;
  Output: Record<string, unknown>;
  Governance: Record<string, unknown>;
}): void {
  if (!LIFECYCLE_STATES.has(String(manifest.Identity.lifecycleState))) {
    throw new Error("Malformed manifest group: Identity");
  }
  if (!OUTPUT_MODES.has(String(manifest.Output.mode))) {
    throw new Error("Malformed manifest group: Output");
  }
  if (!ACCEPTANCE_MODES.has(String(manifest.Governance.acceptanceMode))) {
    throw new Error("Malformed manifest group: Governance");
  }
  assertRetentionClassBand(manifest.Governance.retentionClass);
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
  if (!isPlainObject(json.Interaction)) {
    throw new Error("Malformed manifest group: Interaction");
  }
  const interaction = json.Interaction as InteractionGroup;
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
  assertInteractionExactKeys(interaction, interactionMode);

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
  assertEconomicsTypes(economics);
  const governance = validateObjectGroup(
    json.Governance,
    "Governance",
    MANIFEST_FIELD_MANIFEST.Governance,
  );

  assertContentEnums({ Identity: identity, Output: output, Governance: governance });
  assertNeverNamesProviderOrModel(json, "manifest");

  const manifest: Manifest = {
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

  return deepFreeze(manifest);
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

function bufferToHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function load(json: Record<string, unknown>): Manifest {
  return validate(json);
}

export async function hashManifest(
  json: Record<string, unknown>,
): Promise<string> {
  const encoded = new TextEncoder().encode(canonicalStringify(json));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return bufferToHex(digest);
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

/**
 * Build gate: load every checked-in published manifest, hash it, and assert
 * the append-only registry mapping `(capability_id, version)` → hash.
 */
export async function verifyManifestTree(io: ManifestTreeIo): Promise<void> {
  const registryRaw = await io.readFile(io.registryPath);
  const registry = JSON.parse(registryRaw) as Record<string, string>;
  if (!isPlainObject(registry)) {
    throw new Error("Published registry must be a JSON object");
  }

  const names = (await io.readdir(io.manifestsDir)).filter((name) =>
    name.endsWith(".json"),
  );
  if (names.length === 0) {
    throw new Error(`No published manifests in ${io.manifestsDir}`);
  }

  const entries: PublishedRegistryEntry[] = [];
  for (const name of names) {
    const filePath = io.join(io.manifestsDir, name);
    const json = JSON.parse(await io.readFile(filePath)) as Record<
      string,
      unknown
    >;
    load(json);
    if (!isPlainObject(json.Identity)) {
      throw new Error(`Published manifest ${name} missing Identity`);
    }
    const capabilityId = json.Identity.capabilityId;
    const version = json.Identity.version;
    if (typeof capabilityId !== "string" || typeof version !== "string") {
      throw new Error(`Published manifest ${name} missing capabilityId/version`);
    }
    entries.push({
      capabilityId,
      version,
      hash: await hashManifest(json),
    });
  }

  verifyPublishedRegistry(entries, registry);
}
