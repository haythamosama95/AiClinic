import type { InteractionMode } from "../manifest";
import { noopLogger, type Logger } from "../logger";
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
  logger?: Logger;
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
  const logger = input.logger ?? noopLogger;
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
      logger.error("validation_terminal_failure", {
        phase: result.failure.phase,
        message: result.failure.message,
        attempt,
      });
      return terminalFailure(result.failure);
    }

    if (!input.reask) {
      logger.error("validation_terminal_failure", {
        phase: result.failure.phase,
        message: result.failure.message,
        attempt,
        reason: "no_reask_port",
      });
      return terminalFailure(result.failure);
    }

    attempt += 1;
    logger.info("validation_repair_attempt", {
      attempt,
      phase: result.failure.phase,
      message: result.failure.message,
    });
    input.repairJournalSink?.({
      attempt,
      errors: [result.failure],
    });

    let reaskResult: ReaskResult;
    try {
      reaskResult = await input.reask([result.failure]);
    } catch (error) {
      logger.error("validation_reask_failed", {
        attempt,
        phase: result.failure.phase,
        error: error instanceof Error ? error.message : String(error),
      });
      return terminalFailure({
        phase: result.failure.phase,
        message: `reask failed: ${result.failure.message}`,
      });
    }

    input.repairCostSink?.(reaskResult.usage);
    currentOutput = reaskResult.output;
  }
}
