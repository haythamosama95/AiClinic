import {
  assertNoProviderShapedFieldNames,
  type CanonicalRequest,
} from "../contracts/canonical";
import type { Principal } from "../identity";
import type { Manifest } from "../manifest";
import { generateRequestReference } from "../reference";
import { resolveArtifact, resolvePromptVersion } from "./registry";

export type ComposeRequestInput = {
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  userIntent: string;
  principal: Principal;
  requestReference?: string;
  streamFlag?: boolean;
  deadline?: number | null;
};

export type ComposeRequestResult =
  | { ok: true; request: CanonicalRequest; promptVersion: string }
  | { ok: false; code: "internal_error" };

function deriveOutputFormatInstruction(
  manifest: Manifest,
): string | undefined {
  const derivationRule =
    manifest["Prompt binding"].outputFormatInstructionDerivationRule;

  if (derivationRule !== "derive_from_output_mode") {
    return undefined;
  }

  const { mode, outputSchemaRef } = manifest.Output;

  if (mode === "prose" && outputSchemaRef === null) {
    return "Output format: respond in clear professional prose suitable for clinical advisory review. Do not wrap the response in JSON, markdown code fences, or other structured envelopes.";
  }

  if (outputSchemaRef !== null) {
    return `Output format: respond with JSON values conforming to the published output schema ${String(outputSchemaRef)}. Emit only valid JSON with no surrounding prose.`;
  }

  return undefined;
}

function renderDelimitedContext(
  manifest: Manifest,
  filteredContext: Record<string, unknown>,
): string {
  const blocks: string[] = [];

  for (const requirement of manifest["Context requirements"]) {
    const key = String(requirement.key);
    const shape = String(requirement.shapeRef);
    const value = filteredContext[key];

    if (value === undefined) {
      continue;
    }

    const serialized = JSON.stringify(value).replaceAll("</", "\\u003c/");
    blocks.push(`<key name="${key}" shape="${shape}">\n${serialized}\n</key>`);
  }

  return blocks.join("\n");
}

function resolveRequestReference(input: ComposeRequestInput): string {
  return input.requestReference ?? generateRequestReference();
}

export function composeRequest(
  input: ComposeRequestInput,
): ComposeRequestResult {
  try {
    const { manifest, filteredContext, userIntent, principal } = input;
    const promptBinding = manifest["Prompt binding"];

    const systemInstruction = resolveArtifact(
      String(promptBinding.systemInstructionArtifactRef),
      manifest,
    );
    if (systemInstruction === undefined) {
      return { ok: false, code: "internal_error" };
    }

    const businessRuleFragments: string[] = [];
    for (const ref of promptBinding.businessRuleFragmentRefs as string[]) {
      const fragment = resolveArtifact(String(ref), manifest);
      if (fragment === undefined) {
        return { ok: false, code: "internal_error" };
      }
      businessRuleFragments.push(fragment);
    }

    const contextTemplate = resolveArtifact(
      String(promptBinding.contextRenderingTemplateRef),
      manifest,
    );
    if (contextTemplate === undefined) {
      return { ok: false, code: "internal_error" };
    }

    const outputFormatInstruction = deriveOutputFormatInstruction(manifest);
    if (outputFormatInstruction === undefined) {
      return { ok: false, code: "internal_error" };
    }

    const messageParts: Array<{ role: string; content: string }> = [
      { role: "system", content: systemInstruction },
      ...businessRuleFragments.map((content) => ({
        role: "system",
        content,
      })),
      { role: "system", content: outputFormatInstruction },
      {
        role: "data",
        content: renderDelimitedContext(manifest, filteredContext),
      },
      { role: "user", content: userIntent },
    ];

    const request: CanonicalRequest = {
      "ordered role-tagged message parts": messageParts,
      "output format directive": {
        mode: manifest.Output.mode,
        outputSchemaRef: manifest.Output.outputSchemaRef,
      },
      "sampling constraints": {
        allowedLanguages: manifest.Input.allowedLanguages,
      },
      "max output tokens": manifest.Economics.maxOutputTokens,
      "stop conditions": [],
      "tool/function declarations (reserved for future)": [],
      "stream flag": input.streamFlag ?? false,
      deadline: input.deadline ?? null,
      "correlation ids": {
        request_reference: resolveRequestReference(input),
        trace_id: principal.jti,
      },
    };

    assertNoProviderShapedFieldNames(Object.keys(request));

    return {
      ok: true,
      request,
      promptVersion: resolvePromptVersion(manifest),
    };
  } catch {
    return { ok: false, code: "internal_error" };
  }
}
