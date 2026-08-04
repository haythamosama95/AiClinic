import {
  assertNoProviderShapedFieldNames,
  type CanonicalMessagePart,
  type CanonicalRequest,
} from "../contracts/canonical";
import type { Principal } from "../identity";
import type { Manifest } from "../manifest";
import { CONTEXT_REQUEST_SCHEMA_ID } from "../context/context-request";
import type { Transcript } from "../context/validator";
import { resolveArtifact, resolvePromptVersion } from "./registry";

export type ComposeRequestInput = {
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  userIntent: string;
  principal: Principal;
  requestReference: string;
  streamFlag?: boolean;
  deadline?: number | null;
  transcript?: Transcript;
};

export type ComposeRequestResult =
  | { ok: true; request: CanonicalRequest; promptVersion: string }
  | { ok: false; code: "internal_error" };

/**
 * Forward stop conditions from the manifest. A4 §5.1 declares no stop-sequences
 * field on Output/Input, so this returns the empty list — forwarding absence,
 * not inventing a threshold.
 */
export function stopConditionsFromManifest(
  _manifest: Manifest,
): readonly string[] {
  return [];
}

function neutralizeJson(value: unknown): string {
  return JSON.stringify(value).replaceAll("</", "\\u003c/");
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function stripKeyBlock(template: string, key: string): string {
  const pattern = new RegExp(
    `<key\\b[^>]*\\bname="${escapeRegExp(key)}"[^>]*>[\\s\\S]*?<\\/key>\\n?`,
    "g",
  );
  return template.replace(pattern, "");
}

/**
 * Render filtered context by substituting `{{key}}` placeholders in the
 * capability's context-rendering template. Absent single_shot keys have their
 * `<key …>…</key>` blocks stripped. Unresolved placeholders throw.
 */
export function renderThroughTemplate(
  template: string,
  manifest: Manifest,
  filteredContext: Record<string, unknown>,
): string {
  let rendered = template;

  const requirements = manifest["Context requirements"] as Array<{
    key: unknown;
    shapeRef: unknown;
  }>;

  for (const requirement of requirements) {
    const key = String(requirement.key);
    const value = filteredContext[key];

    if (value === undefined) {
      rendered = stripKeyBlock(rendered, key);
      continue;
    }

    rendered = rendered.replaceAll(`{{${key}}}`, neutralizeJson(value));
  }

  if (/\{\{[^}]+\}\}/.test(rendered)) {
    throw new Error("Context rendering template has unresolved placeholders");
  }

  return rendered.trimEnd();
}

function renderConversationalFilteredContext(
  manifest: Manifest,
  filteredContext: Record<string, unknown>,
): string {
  const contextRequirements = manifest["Context requirements"] as {
    permittedKeySet: readonly string[];
  };
  const blocks: string[] = [];

  for (const key of contextRequirements.permittedKeySet) {
    const value = filteredContext[key];
    if (value === undefined) {
      continue;
    }
    // Platform convention: published context-key shape ref equals the key id.
    blocks.push(
      `<key name="${key}" shape="${key}">\n${neutralizeJson(value)}\n</key>`,
    );
  }

  return blocks.join("\n");
}

function renderDelimitedContextObject(
  context: Record<string, unknown>,
  orderedKeys?: readonly string[],
): string {
  const keys = orderedKeys ?? Object.keys(context).sort();
  const blocks: string[] = [];

  for (const key of keys) {
    if (!(key in context)) {
      continue;
    }
    const value = context[key];
    // Platform convention: context key id is the published shape ref.
    blocks.push(
      `<key name="${key}" shape="${key}">\n${neutralizeJson(value)}\n</key>`,
    );
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

export function composeRequest(
  input: ComposeRequestInput,
): ComposeRequestResult {
  try {
    if (
      typeof input.requestReference !== "string" ||
      input.requestReference.length === 0
    ) {
      return { ok: false, code: "internal_error" };
    }

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

    const contextPart =
      manifest.interactionMode === "conversational"
        ? renderConversationalFilteredContext(manifest, filteredContext)
        : renderThroughTemplate(contextTemplate, manifest, filteredContext);

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
      stopConditions: [...stopConditionsFromManifest(manifest)],
      toolDeclarations: [],
      stream: input.streamFlag ?? false,
      deadline: input.deadline ?? null,
      correlationIds: {
        request_reference: input.requestReference,
        trace_id: principal.jti,
      },
    };

    assertNoProviderShapedFieldNames(Object.keys(request));

    return {
      ok: true,
      request,
      promptVersion: resolvePromptVersion(manifest),
    };
  } catch (error) {
    console.error(
      "composeRequest failed",
      { trace_id: input.principal.jti },
      error,
    );
    return { ok: false, code: "internal_error" };
  }
}
