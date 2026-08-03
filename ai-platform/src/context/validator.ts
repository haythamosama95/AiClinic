/**
 * Context validator — manifest-driven key presence, shape, size, and tenant checks (§5.2 / B2 C2).
 * H2 extends conversational transcript validation, budgets, and permitted-key allowlist.
 */

import {
  VISIT_CHIEF_COMPLAINT_V1,
  VISIT_CHIEF_COMPLAINT_V1_SHAPE,
  type KeyShape,
  validatePayload,
} from "./index";
import { buildErrorBody } from "../errors";
import type { Principal } from "../identity";
import type { Manifest } from "../manifest";
import type { ContextRequest } from "./context-request";

export type TranscriptTurn =
  | { turn_ordinal: number; kind: "user"; text: string }
  | { turn_ordinal: number; kind: "model"; text: string }
  | {
      turn_ordinal: number;
      kind: "context_requested";
      requests: ContextRequest;
    }
  | {
      turn_ordinal: number;
      kind: "context_resolved";
      context: Record<string, unknown>;
    };

export type Transcript = readonly TranscriptTurn[];

export type ValidateResult =
  | {
      ok: true;
      filteredContext: Record<string, unknown>;
      validatedTranscript?: Transcript;
    }
  | {
      ok: false;
      code: "context_required";
      missingKeys: string[];
      shapes: Record<string, KeyShape>;
      manifestVersion: string;
      manifestCapabilityId: string;
    }
  | { ok: false; code: "context_invalid" }
  | { ok: false; code: "conversation_budget_exhausted" };

export type ConversationalValidateOptions = {
  transcript: unknown;
  legTurnOrdinal: number;
};

const TRANSCRIPT_KINDS = new Set([
  "user",
  "model",
  "context_requested",
  "context_resolved",
]);

const PUBLISHED_SHAPES: ReadonlyMap<string, KeyShape> = new Map([
  [VISIT_CHIEF_COMPLAINT_V1, VISIT_CHIEF_COMPLAINT_V1_SHAPE],
]);

function publishedShapeForKey(key: string): KeyShape | undefined {
  return PUBLISHED_SHAPES.get(key);
}

function jsonByteLength(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function buildShapesForMissingKeys(
  missingKeys: readonly string[],
): Record<string, KeyShape> {
  const shapes: Record<string, KeyShape> = {};
  for (const key of missingKeys) {
    const shape = publishedShapeForKey(key);
    if (shape !== undefined) {
      shapes[key] = shape;
    }
  }
  return shapes;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value);
}

function parseTranscriptTurn(turn: unknown): TranscriptTurn | null {
  if (!isPlainObject(turn)) {
    return null;
  }

  if (!("turn_ordinal" in turn) || !isInteger(turn.turn_ordinal)) {
    return null;
  }

  if (typeof turn.kind !== "string" || !TRANSCRIPT_KINDS.has(turn.kind)) {
    return null;
  }

  const turnOrdinal = turn.turn_ordinal;

  switch (turn.kind) {
    case "user":
      if (!("text" in turn) || typeof turn.text !== "string") {
        return null;
      }
      return { turn_ordinal: turnOrdinal, kind: "user", text: turn.text };
    case "model":
      if (!("text" in turn) || typeof turn.text !== "string") {
        return null;
      }
      return { turn_ordinal: turnOrdinal, kind: "model", text: turn.text };
    case "context_requested":
      if (!("requests" in turn) || !Array.isArray(turn.requests)) {
        return null;
      }
      return {
        turn_ordinal: turnOrdinal,
        kind: "context_requested",
        requests: turn.requests as ContextRequest,
      };
    case "context_resolved":
      if (!("context" in turn) || !isPlainObject(turn.context)) {
        return null;
      }
      return {
        turn_ordinal: turnOrdinal,
        kind: "context_resolved",
        context: turn.context,
      };
    default:
      return null;
  }
}

function parseTranscript(transcript: unknown): Transcript | null {
  if (!Array.isArray(transcript)) {
    return null;
  }

  const parsed: TranscriptTurn[] = [];
  for (const turn of transcript) {
    const parsedTurn = parseTranscriptTurn(turn);
    if (parsedTurn === null) {
      return null;
    }
    parsed.push(parsedTurn);
  }

  return parsed;
}

function validateTranscriptOrdering(
  transcript: Transcript,
  legTurnOrdinal: number,
): boolean {
  let previousOrdinal = Number.NEGATIVE_INFINITY;

  for (const turn of transcript) {
    if (turn.turn_ordinal <= previousOrdinal) {
      return false;
    }
    if (turn.turn_ordinal >= legTurnOrdinal) {
      return false;
    }
    previousOrdinal = turn.turn_ordinal;
  }

  return true;
}

function countTailContextRounds(transcript: Transcript): number {
  let count = 0;
  for (let index = transcript.length - 1; index >= 0; index -= 1) {
    if (transcript[index]?.kind === "context_requested") {
      count += 1;
    } else {
      break;
    }
  }
  return count;
}

function filterToPermittedKeys(
  context: Record<string, unknown>,
  permittedKeySet: ReadonlySet<string>,
): Record<string, unknown> {
  const filtered: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(context)) {
    if (permittedKeySet.has(key)) {
      filtered[key] = value;
    }
  }
  return filtered;
}

function applyPermittedKeyAllowlist(
  transcript: Transcript,
  permittedKeySet: readonly string[],
): Transcript {
  const permitted = new Set(permittedKeySet);

  return transcript.map((turn) => {
    if (turn.kind !== "context_resolved") {
      return turn;
    }

    return {
      ...turn,
      context: filterToPermittedKeys(turn.context, permitted),
    };
  });
}

function permittedKeySetFromManifest(
  manifest: Manifest,
): readonly string[] | null {
  const contextRequirements = manifest["Context requirements"];
  if (!isPlainObject(contextRequirements)) {
    return null;
  }

  if (!Array.isArray(contextRequirements.permittedKeySet)) {
    return null;
  }

  return contextRequirements.permittedKeySet as readonly string[];
}

function validateConversationalContext(
  manifest: Manifest,
  suppliedContext: Record<string, unknown>,
  options: ConversationalValidateOptions,
): ValidateResult {
  const permittedKeySet = permittedKeySetFromManifest(manifest);
  if (permittedKeySet === null) {
    return { ok: false, code: "context_invalid" };
  }

  const parsedTranscript = parseTranscript(options.transcript ?? []);
  if (parsedTranscript === null) {
    return { ok: false, code: "context_invalid" };
  }

  if (!validateTranscriptOrdering(parsedTranscript, options.legTurnOrdinal)) {
    return { ok: false, code: "context_invalid" };
  }

  const maxHistoryTurns = Number(manifest.Interaction.maxHistoryTurns);
  if (parsedTranscript.length > maxHistoryTurns) {
    return { ok: false, code: "conversation_budget_exhausted" };
  }

  const maxContextRounds = Number(manifest.Interaction.maxContextRoundsPerTurn);
  if (countTailContextRounds(parsedTranscript) > maxContextRounds) {
    return { ok: false, code: "conversation_budget_exhausted" };
  }

  const permitted = new Set(permittedKeySet);
  const filteredContext = filterToPermittedKeys(suppliedContext, permitted);
  const validatedTranscript = applyPermittedKeyAllowlist(
    parsedTranscript,
    permittedKeySet,
  );

  return {
    ok: true,
    filteredContext,
    validatedTranscript,
  };
}

export function validateContext(
  manifest: Manifest,
  suppliedContext: Record<string, unknown>,
  principal: Principal,
  conversational?: ConversationalValidateOptions,
): ValidateResult {
  if (manifest.interactionMode === "conversational") {
    if (conversational === undefined) {
      return { ok: false, code: "context_invalid" };
    }
    return validateConversationalContext(
      manifest,
      suppliedContext,
      conversational,
    );
  }

  const contextRequirements = manifest["Context requirements"];
  if (!Array.isArray(contextRequirements)) {
    return { ok: false, code: "context_invalid" };
  }

  const maxSizeByKey = new Map<string, number>();

  for (const entry of contextRequirements) {
    maxSizeByKey.set(String(entry.key), Number(entry.maxSize));
  }

  const missingKeys: string[] = [];
  for (const entry of contextRequirements) {
    const key = String(entry.key);
    if (
      entry.required === true &&
      !Object.prototype.hasOwnProperty.call(suppliedContext, key)
    ) {
      missingKeys.push(key);
    }
  }

  if (missingKeys.length > 0) {
    return {
      ok: false,
      code: "context_required",
      missingKeys,
      shapes: buildShapesForMissingKeys(missingKeys),
      manifestVersion: String(manifest.Identity.version),
      manifestCapabilityId: String(manifest.Identity.capabilityId),
    };
  }

  if (
    suppliedContext.org !== principal.organizationId ||
    suppliedContext.branch !== principal.branchId
  ) {
    return { ok: false, code: "context_invalid" };
  }

  for (const entry of contextRequirements) {
    const key = String(entry.key);
    if (!Object.prototype.hasOwnProperty.call(suppliedContext, key)) {
      continue;
    }

    const value = suppliedContext[key];
    const payloadResult = validatePayload(key, value);
    if (!payloadResult.ok && payloadResult.code !== "unknown_shape") {
      return { ok: false, code: "context_invalid" };
    }

    const maxSize = maxSizeByKey.get(key);
    if (maxSize !== undefined && jsonByteLength(value) > maxSize) {
      return { ok: false, code: "context_invalid" };
    }
  }

  const filteredContext: Record<string, unknown> = {};
  for (const entry of contextRequirements) {
    const key = String(entry.key);
    if (Object.prototype.hasOwnProperty.call(suppliedContext, key)) {
      filteredContext[key] = suppliedContext[key];
    }
  }

  return { ok: true, filteredContext };
}

export function buildContextRequiredResponse(
  result: Extract<ValidateResult, { ok: false; code: "context_required" }>,
  requestReference: string,
  traceId: string,
): Record<string, unknown> {
  const body = buildErrorBody({
    code: "context_required",
    requestReference,
    traceId,
  });

  return {
    ...body,
    missing_keys: result.missingKeys,
    shapes: result.shapes,
    manifest_version: result.manifestVersion,
    manifest_capability_id: result.manifestCapabilityId,
  };
}
