import type { Manifest } from "../manifest";
import artifactRegistry from "../../prompts/clinic.visit_summary/registry.json";
import rulesVisitSummary from "../../prompts/clinic.visit_summary/rules-visit-summary.md?raw";
import systemInstructionBundled from "../../prompts/clinic.visit_summary/system.md?raw";
import templateVisitSummary from "../../prompts/clinic.visit_summary/template-visit-summary.md?raw";

const SYSTEM_INSTRUCTION_REF = "clinic.visit_summary/system@v1";
const RULES_FRAGMENT_REF = "clinic.visit_summary/rules-visit-summary@v1";
const TEMPLATE_REF = "clinic.visit_summary/template-visit-summary@v1";

async function loadSystemInstruction(): Promise<string | undefined> {
  try {
    const mockable = await import(
      /* @vite-ignore */
      "../../prompts/clinic.visit_summary/system.md"
    );
    if (Object.hasOwn(mockable, "default")) {
      return mockable.default as string | undefined;
    }
  } catch {
    // Vitest build-pin tests mock the non-?raw module id; keep the bundled import.
  }
  return systemInstructionBundled;
}

const systemInstruction = await loadSystemInstruction();

const ARTIFACT_MAP: Readonly<Record<string, string | undefined>> = Object.freeze({
  [SYSTEM_INSTRUCTION_REF]: systemInstruction,
  [RULES_FRAGMENT_REF]: rulesVisitSummary,
  [TEMPLATE_REF]: templateVisitSummary,
});

function stableContentHash(content: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < content.length; index += 1) {
    hash ^= content.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

export function resolveArtifact(
  ref: string,
  manifest: Manifest,
): string | undefined {
  void manifest;
  return ARTIFACT_MAP[ref];
}

export function resolvePromptVersion(manifest: Manifest): string {
  return String(manifest["Prompt binding"].systemInstructionArtifactRef);
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
    const content = ARTIFACT_MAP[refKey];
    if (content === undefined) {
      throw new Error(`Missing pinned artifact: ${refKey}`);
    }

    const expectedHash = artifactRegistry[refKey as keyof typeof artifactRegistry];
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
