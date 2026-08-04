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

export type ReaskPort = (errors: ValidationError[]) => Promise<AssembledOutput>;

export type RepairJournalSink = (record: {
  attempt: number;
  errors: ValidationError[];
}) => void;

export type RepairCostSink = (usage: { tokens: number; cost: number }) => void;

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
  repairCostPerAttempt?: { tokens: number; cost: number };
};

export type ValidateAndRepairSuccess = { ok: true; validated: unknown };
export type ValidateAndRepairFailure = {
  ok: false;
  code: "validation_failed";
  phase: ValidationPhase;
};
export type ValidateAndRepairResult =
  | ValidateAndRepairSuccess
  | ValidateAndRepairFailure;

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
      return {
        ok: false,
        code: "validation_failed",
        phase: result.failure.phase,
      };
    }

    if (!input.reask) {
      return {
        ok: false,
        code: "validation_failed",
        phase: result.failure.phase,
      };
    }

    attempt += 1;
    input.repairJournalSink?.({
      attempt,
      errors: [result.failure],
    });
    input.repairCostSink?.(
      input.repairCostPerAttempt ?? { tokens: 0, cost: 0 },
    );

    currentOutput = await input.reask([result.failure]);
  }
}
