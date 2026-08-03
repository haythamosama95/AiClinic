import {
  assertNoProviderShapedFieldNames,
  type CanonicalMessagePart,
  type CanonicalRequest,
} from "../contracts/canonical";
import type { Principal } from "../identity";
import type { Manifest } from "../manifest";
import { generateRequestReference } from "../reference";
import { CONTEXT_REQUEST_SCHEMA_ID } from "../context/context-request";
import type { Transcript } from "../context/validator";
import { resolveArtifact, resolvePromptVersion } from "./registry";

export type ComposeRequestInput = {
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  userIntent: string;
  principal: Principal;
  requestReference?: string;
  streamFlag?: boolean;
  deadline?: number | null;
  transcript?: Transcript;
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

  if (manifest.interactionMode === "conversational" && mode === "prose") {
    return (
      "Output format: respond in clear professional prose suitable for clinical advisory review, " +
      `or respond with a JSON array conforming to the platform context-request schema ` +
      `${CONTEXT_REQUEST_SCHEMA_ID} using keys from the permitted set. ` +
      "Do not wrap prose in JSON, markdown code fences, or other structured envelopes."
    );
  }

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

  if (manifest.interactionMode === "conversational") {
    for (const [key, value] of Object.entries(filteredContext)) {
      const serialized = JSON.stringify(value).replaceAll("</", "\\u003c/");
      blocks.push(`<key name="${key}" shape="${key}">\n${serialized}\n</key>`);
    }
    return blocks.join("\n");
  }

  for (const requirement of manifest["Context requirements"] as Array<{
    key: unknown;
    shapeRef: unknown;
  }>) {
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

function renderDelimitedContextObject(
  context: Record<string, unknown>,
): string {
  const blocks: string[] = [];
  for (const [key, value] of Object.entries(context)) {
    const serialized = JSON.stringify(value).replaceAll("</", "\\u003c/");
    blocks.push(`<key name="${key}" shape="${key}">\n${serialized}\n</key>`);
  }
  return blocks.join("\n");
}

function renderTranscriptPriorTurns(
  transcript: Transcript,
): CanonicalMessagePart[] {
  const parts: CanonicalMessagePart[] = [];

  for (const turn of transcript) {
    switch (turn.kind) {
      case "user":
        parts.push({ role: "user", content: turn.text });
        break;
      case "model":
        parts.push({ role: "assistant", content: turn.text });
        break;
      case "context_requested":
        parts.push({
          role: "assistant",
          content: JSON.stringify(turn.requests),
        });
        break;
      case "context_resolved":
        parts.push({
          role: "data",
          content: renderDelimitedContextObject(turn.context),
        });
        break;
      default:
        break;
    }
  }

  return parts;
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

    const transcriptParts =
      manifest.interactionMode === "conversational" && input.transcript
        ? renderTranscriptPriorTurns(input.transcript)
        : [];

    const contextPart = renderDelimitedContext(manifest, filteredContext);
    const messageParts: CanonicalMessagePart[] = [
      { role: "system", content: systemInstruction },
      ...businessRuleFragments.map((content) => ({
        role: "system" as const,
        content,
      })),
      { role: "system", content: outputFormatInstruction },
      ...transcriptParts,
    ];

    if (contextPart.length > 0) {
      messageParts.push({ role: "data", content: contextPart });
    }

    messageParts.push({ role: "user", content: userIntent });

    const request: CanonicalRequest = {
      parts: messageParts,
      formatDirective: {
        mode: String(manifest.Output.mode),
        outputSchemaRef:
          manifest.Output.outputSchemaRef == null
            ? null
            : String(manifest.Output.outputSchemaRef),
      },
      samplingConstraints: {
        allowedLanguages: Array.isArray(manifest.Input.allowedLanguages)
          ? manifest.Input.allowedLanguages.map(String)
          : [],
      },
      maxOutputTokens: Number(manifest.Economics.maxOutputTokens),
      stopConditions: [],
      toolDeclarations: [],
      stream: input.streamFlag ?? false,
      deadline: input.deadline ?? null,
      correlationIds: {
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
