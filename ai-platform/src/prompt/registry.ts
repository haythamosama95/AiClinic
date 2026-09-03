import type { Manifest } from "../manifest";
import clinicVisitSummaryRules from "../../prompts/clinic.visit_summary/rules-visit-summary.md";
import clinicVisitSummarySystem from "../../prompts/clinic.visit_summary/system.md";
import clinicVisitSummaryTemplate from "../../prompts/clinic.visit_summary/template-visit-summary.md";
import clinicVisitSummaryRegistry from "../../prompts/clinic.visit_summary/registry.json";

/**
 * Build-time index over prompts/ (Clarification Q1): every `.md` under
 * `prompts/<cap>/` maps to ref `<cap>/<name>@v1`. Eager static imports only —
 * Workers runtime has no `import.meta.glob`. Add each new prompt artifact and
 * its `registry.json` here when shipping a capability.
 */
const BUNDLED_ARTIFACTS: ReadonlyArray<{
  ref: string;
  content: string;
}> = [
    {
      ref: "clinic.visit_summary/system@v1",
      content: clinicVisitSummarySystem,
    },
    {
      ref: "clinic.visit_summary/rules-visit-summary@v1",
      content: clinicVisitSummaryRules,
    },
    {
      ref: "clinic.visit_summary/template-visit-summary@v1",
      content: clinicVisitSummaryTemplate,
    },
  ];

const BUNDLED_REGISTRIES: ReadonlyArray<Record<string, string>> = [
  clinicVisitSummaryRegistry,
];

function buildBaseArtifactMap(): Record<string, string> {
  const map: Record<string, string> = {};
  for (const { ref, content } of BUNDLED_ARTIFACTS) {
    if (Object.hasOwn(map, ref)) {
      throw new Error(`Duplicate artifact ref: ${ref}`);
    }
    map[ref] = content;
  }
  return map;
}

function buildPinRegistry(): Record<string, string> {
  const pins: Record<string, string> = {};
  for (const registry of BUNDLED_REGISTRIES) {
    for (const [ref, hash] of Object.entries(registry)) {
      if (Object.hasOwn(pins, ref) && pins[ref] !== hash) {
        throw new Error(`Duplicate conflicting registry pin for ${ref}`);
      }
      pins[ref] = hash;
    }
  }
  return pins;
}

const BASE_ARTIFACT_MAP: Readonly<Record<string, string>> = Object.freeze(
  buildBaseArtifactMap(),
);
const PIN_REGISTRY: Readonly<Record<string, string>> = Object.freeze(
  buildPinRegistry(),
);

/** Test-only overlay; production always reads BASE_ARTIFACT_MAP. */
const testOverlay = new Map<string, string | undefined>();

export function __setArtifactContentForTest(
  ref: string,
  content: string | undefined,
): void {
  testOverlay.set(ref, content);
}

export function __resetArtifactContentForTest(): void {
  testOverlay.clear();
}

function resolveContent(ref: string): string | undefined {
  if (testOverlay.has(ref)) {
    return testOverlay.get(ref);
  }
  return BASE_ARTIFACT_MAP[ref];
}

export function stableContentHash(content: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < content.length; index += 1) {
    hash ^= content.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

/** Base indexed content (ignores the test overlay). */
export function indexedArtifactContent(ref: string): string | undefined {
  return BASE_ARTIFACT_MAP[ref];
}

/** Every pin key across all prompts registry.json files. */
export function allRegistryPins(): Readonly<Record<string, string>> {
  return PIN_REGISTRY;
}

export function resolveArtifact(
  ref: string,
  manifest: Manifest,
): string | undefined {
  void manifest;
  return resolveContent(ref);
}

export function resolvePromptVersion(manifest: Manifest): string {
  const promptBinding = manifest["Prompt binding"];
  const parts: string[] = [];

  const system = resolveContent(
    String(promptBinding.systemInstructionArtifactRef),
  );
  if (system !== undefined) {
    parts.push(system);
  }

  const fragments = promptBinding.businessRuleFragmentRefs;
  if (Array.isArray(fragments)) {
    for (const ref of fragments) {
      const fragment = resolveContent(String(ref));
      if (fragment !== undefined) {
        parts.push(fragment);
      }
    }
  }

  const templateRef = promptBinding.contextRenderingTemplateRef;
  if (templateRef != null && String(templateRef).length > 0) {
    const template = resolveContent(String(templateRef));
    if (template !== undefined) {
      parts.push(template);
    }
  }

  return stableContentHash(parts.join("\0"));
}

export function verifyBuildPins(manifest: Manifest): void {
  const promptBinding = manifest["Prompt binding"];
  const pinnedRefs = [
    promptBinding.systemInstructionArtifactRef,
    ...(promptBinding.businessRuleFragmentRefs as string[]),
    promptBinding.contextRenderingTemplateRef,
  ];

  for (const ref of pinnedRefs) {
    const refKey = String(ref);
    const content = resolveContent(refKey);
    if (content === undefined) {
      throw new Error(`Missing pinned artifact: ${refKey}`);
    }

    const expectedHash = PIN_REGISTRY[refKey];
    if (expectedHash === undefined) {
      throw new Error(`Missing registry pin for artifact: ${refKey}`);
    }

    const actualHash = stableContentHash(content);
    if (actualHash !== expectedHash) {
      throw new Error(
        `Pinned artifact hash mismatch for ${refKey}: expected ${expectedHash}, got ${actualHash}`,
      );
    }
  }
}

/**
 * Verifies every pin in every per-capability registry.json against the
 * build-time indexed artifact content (hash mismatch / missing throws).
 */
export function verifyAllRegistryPins(): void {
  for (const [ref, expectedHash] of Object.entries(PIN_REGISTRY)) {
    const content = BASE_ARTIFACT_MAP[ref];
    if (content === undefined) {
      throw new Error(`Missing pinned artifact: ${ref}`);
    }
    const actualHash = stableContentHash(content);
    if (actualHash !== expectedHash) {
      throw new Error(
        `Pinned artifact hash mismatch for ${ref}: expected ${expectedHash}, got ${actualHash}`,
      );
    }
  }
}
