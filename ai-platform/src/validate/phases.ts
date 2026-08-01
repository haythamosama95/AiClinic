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
};

export type RunPhasesSuccess = { ok: true; validated: unknown };
export type RunPhasesFailure = { ok: false; failure: ValidationError };
export type RunPhasesResult = RunPhasesSuccess | RunPhasesFailure;

function parseOutput(
  output: AssembledOutput,
  mode: RunPhasesInput["mode"],
): { ok: true; parsed: unknown } | { ok: false; failure: ValidationError } {
  if (output.transportValid === false) {
    return {
      ok: false,
      failure: { phase: "transport_parse", message: "transport invalid" },
    };
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
    for (const prefix of markers.refusalPrefixes) {
      if (raw.includes(prefix)) {
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
  const parsedResult = parseOutput(input.output, input.mode);
  if (!parsedResult.ok) {
    return parsedResult;
  }

  const parsed = parsedResult.parsed;

  if (input.outputSchemaRef !== null) {
    const schemaRunner = input.schemaRegistry.get(input.outputSchemaRef);
    if (schemaRunner) {
      const schemaError = schemaRunner(parsed);
      if (schemaError !== null) {
        return {
          ok: false,
          failure: { phase: "schema", message: schemaError },
        };
      }
    }
  }

  for (const ruleRef of input.businessValidationRuleRefs) {
    const ruleRunner = input.ruleRegistry.get(ruleRef);
    if (ruleRunner) {
      const ruleError = ruleRunner(parsed, input.context ?? {});
      if (ruleError !== null) {
        return {
          ok: false,
          failure: { phase: "business", message: ruleError },
        };
      }
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
