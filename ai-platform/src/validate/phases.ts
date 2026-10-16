import { validateContextRequest } from "../context/context-request";
import type { InteractionMode } from "../manifest";

export const VALIDATION_PHASES = [
  "transport_parse",
  "schema",
  "business",
  "safety",
] as const;

export type ValidationPhase = (typeof VALIDATION_PHASES)[number];

export type ValidationError = {
  phase: ValidationPhase;
  message: string;
};

export type AssembledOutput = {
  raw: string;
  transportValid?: boolean;
  truncated?: boolean;
};

export type SchemaRunner = (parsed: unknown) => string | null;
export type SchemaRegistry = Map<string | null, SchemaRunner>;

export type BusinessRuleRunner = (
  parsed: unknown,
  context: unknown,
) => string | null;
export type BusinessRuleRegistry = Map<string, BusinessRuleRunner>;

export type SafetyMarkers = {
  leakedInstructionNeedle?: string;
  refusalPrefixes?: string[];
  injectionEchoNeedle?: string;
};

export type RunPhasesInput = {
  output: AssembledOutput;
  mode: "prose" | "structured" | "structured_atomic";
  outputSchemaRef: string | null;
  businessValidationRuleRefs: readonly string[];
  schemaRegistry: SchemaRegistry;
  ruleRegistry: BusinessRuleRegistry;
  context?: unknown;
  safetyMarkers?: SafetyMarkers;
  interactionMode?: InteractionMode;
  permittedKeySet?: readonly string[];
};

export type RunPhasesSuccess = { ok: true; validated: unknown };
export type RunPhasesFailure = { ok: false; failure: ValidationError };
export type RunPhasesResult = RunPhasesSuccess | RunPhasesFailure;

function tryParseContextRequest(
  raw: string,
  permittedKeySet: readonly string[] | undefined,
): { ok: true; validated: unknown } | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }

  // Empty list is not a meaningful context request for dual acceptance —
  // a leg that asks for zero keys is neither prose nor a resolvable request.
  if (Array.isArray(parsed) && parsed.length === 0) {
    return null;
  }

  const validation = validateContextRequest(parsed);
  if (!validation.ok) {
    return null;
  }

  if (!Array.isArray(parsed)) {
    return null;
  }

  if (permittedKeySet !== undefined) {
    const permitted = new Set(permittedKeySet);
    for (const entry of parsed) {
      if (
        typeof entry === "object" &&
        entry !== null &&
        "key" in entry &&
        typeof entry.key === "string" &&
        !permitted.has(entry.key)
      ) {
        return null;
      }
    }
  }

  return { ok: true, validated: parsed };
}

function parseOutput(
  output: AssembledOutput,
  mode: RunPhasesInput["mode"],
  input: RunPhasesInput,
): { ok: true; parsed: unknown } | { ok: false; failure: ValidationError } {
  if (output.transportValid === false) {
    return {
      ok: false,
      failure: { phase: "transport_parse", message: "transport invalid" },
    };
  }

  if (
    input.interactionMode === "conversational" &&
    mode === "prose"
  ) {
    const contextRequest = tryParseContextRequest(
      output.raw,
      input.permittedKeySet,
    );
    if (contextRequest !== null) {
      return { ok: true, parsed: contextRequest.validated };
    }

    if (output.raw.trim() === "") {
      return {
        ok: false,
        failure: {
          phase: "transport_parse",
          message: "neither prose nor context request",
        },
      };
    }

    const trimmed = output.raw.trimStart();
    if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
      // Reject only when the text is parseable JSON that failed as a context
      // request. Prose that happens to open with `[` / `{` (e.g. "[Note] …")
      // is accepted as prose.
      try {
        JSON.parse(output.raw);
      } catch {
        return { ok: true, parsed: output.raw };
      }
      return {
        ok: false,
        failure: {
          phase: "transport_parse",
          message: "neither prose nor context request",
        },
      };
    }

    return { ok: true, parsed: output.raw };
  }

  if (mode === "prose") {
    return { ok: true, parsed: output.raw };
  }

  try {
    const parsed = JSON.parse(output.raw) as unknown;
    return { ok: true, parsed };
  } catch {
    return {
      ok: false,
      failure: { phase: "transport_parse", message: "parse failure" },
    };
  }
}

function checkSafety(
  raw: string,
  parsed: unknown,
  output: AssembledOutput,
  markers: SafetyMarkers | undefined,
): ValidationError | null {
  if (output.truncated === true) {
    return { phase: "safety", message: "truncated output" };
  }

  if (raw.trim() === "") {
    return { phase: "safety", message: "empty output" };
  }

  if (markers?.leakedInstructionNeedle && raw.includes(markers.leakedInstructionNeedle)) {
    return { phase: "safety", message: "leaked system instruction" };
  }

  if (markers?.injectionEchoNeedle && raw.includes(markers.injectionEchoNeedle)) {
    return { phase: "safety", message: "prompt injection echo" };
  }

  if (markers?.refusalPrefixes) {
    const trimmed = raw.trimStart();
    for (const prefix of markers.refusalPrefixes) {
      if (trimmed.startsWith(prefix)) {
        return { phase: "safety", message: "model refusal" };
      }
    }
  }

  if (typeof parsed === "object" && parsed !== null) {
    const doc = parsed as Record<string, unknown>;
    if (doc._truncated === true) {
      return { phase: "safety", message: "truncated output" };
    }
  }

  return null;
}

export function runValidationPhases(input: RunPhasesInput): RunPhasesResult {
  const parsedResult = parseOutput(input.output, input.mode, input);
  if (!parsedResult.ok) {
    return parsedResult;
  }

  const parsed = parsedResult.parsed;

  if (input.outputSchemaRef !== null) {
    const schemaRunner = input.schemaRegistry.get(input.outputSchemaRef);
    if (!schemaRunner) {
      return {
        ok: false,
        failure: {
          phase: "schema",
          message: `unresolved schema ref: ${input.outputSchemaRef}`,
        },
      };
    }
    const schemaError = schemaRunner(parsed);
    if (schemaError !== null) {
      return {
        ok: false,
        failure: { phase: "schema", message: schemaError },
      };
    }
  }

  for (const ruleRef of input.businessValidationRuleRefs) {
    const ruleRunner = input.ruleRegistry.get(ruleRef);
    if (!ruleRunner) {
      return {
        ok: false,
        failure: {
          phase: "business",
          message: `unresolved business rule ref: ${ruleRef}`,
        },
      };
    }
    const ruleError = ruleRunner(parsed, input.context ?? {});
    if (ruleError !== null) {
      return {
        ok: false,
        failure: { phase: "business", message: ruleError },
      };
    }
  }

  const safetyError = checkSafety(
    input.output.raw,
    parsed,
    input.output,
    input.safetyMarkers,
  );
  if (safetyError !== null) {
    return { ok: false, failure: safetyError };
  }

  return { ok: true, validated: parsed };
}
