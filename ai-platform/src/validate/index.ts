import type { InteractionMode } from "../manifest";
import {
  runValidationPhases,
  type AssembledOutput,
  type BusinessRuleRegistry,
  type RunPhasesInput,
  type SafetyMarkers,
  type SchemaRegistry,
  type ValidationError,
  type ValidationPhase,
} from "./phases";

export {
  runValidationPhases,
  VALIDATION_PHASES,
  type AssembledOutput,
  type BusinessRuleRegistry,
  type BusinessRuleRunner,
  type RunPhasesInput,
  type RunPhasesResult,
  type SafetyMarkers,
  type SchemaRegistry,
  type SchemaRunner,
  type ValidationError,
  type ValidationPhase,
} from "./phases";

export type RepairPolicy = { allowed: boolean; maxAttempts: number };

export type ReaskUsage = { tokens: number; cost: number };

export type ReaskResult = {
  output: AssembledOutput;
  usage: ReaskUsage;
};

export type ReaskPort = (errors: ValidationError[]) => Promise<ReaskResult>;

export type RepairJournalSink = (record: {
  attempt: number;
  errors: ValidationError[];
}) => void;

export type RepairCostSink = (usage: ReaskUsage) => void;

export type ValidateAndRepairInput = {
  output: AssembledOutput;
  mode: RunPhasesInput["mode"];
  outputSchemaRef: string | null;
  businessValidationRuleRefs: readonly string[];
  repairPolicy: RepairPolicy;
  schemaRegistry: SchemaRegistry;
  ruleRegistry: BusinessRuleRegistry;
  context?: unknown;
  safetyMarkers?: SafetyMarkers;
  interactionMode?: InteractionMode;
  permittedKeySet?: readonly string[];
  reask?: ReaskPort;
  repairJournalSink?: RepairJournalSink;
  repairCostSink?: RepairCostSink;
};

export type ValidateAndRepairSuccess = { ok: true; validated: unknown };
export type ValidateAndRepairFailure = {
  ok: false;
  code: "validation_failed";
  phase: ValidationPhase;
  message: string;
};
export type ValidateAndRepairResult =
  | ValidateAndRepairSuccess
  | ValidateAndRepairFailure;

function terminalFailure(
  failure: ValidationError,
): ValidateAndRepairFailure {
  return {
    ok: false,
    code: "validation_failed",
    phase: failure.phase,
    message: failure.message,
  };
}

export async function validateAndRepair(
  input: ValidateAndRepairInput,
): Promise<ValidateAndRepairResult> {
  let currentOutput = input.output;
  let attempt = 0;

  while (true) {
    const result = runValidationPhases({
      output: currentOutput,
      mode: input.mode,
      outputSchemaRef: input.outputSchemaRef,
      businessValidationRuleRefs: input.businessValidationRuleRefs,
      schemaRegistry: input.schemaRegistry,
      ruleRegistry: input.ruleRegistry,
      context: input.context,
      safetyMarkers: input.safetyMarkers,
      interactionMode: input.interactionMode,
      permittedKeySet: input.permittedKeySet,
    });

    if (result.ok) {
      return { ok: true, validated: result.validated };
    }

    if (!input.repairPolicy.allowed || attempt >= input.repairPolicy.maxAttempts) {
      return terminalFailure(result.failure);
    }

    if (!input.reask) {
      return terminalFailure(result.failure);
    }

    attempt += 1;
    input.repairJournalSink?.({
      attempt,
      errors: [result.failure],
    });

    let reaskResult: ReaskResult;
    try {
      reaskResult = await input.reask([result.failure]);
    } catch {
      return terminalFailure({
        phase: result.failure.phase,
        message: `reask failed: ${result.failure.message}`,
      });
    }

    input.repairCostSink?.(reaskResult.usage);
    currentOutput = reaskResult.output;
  }
}
