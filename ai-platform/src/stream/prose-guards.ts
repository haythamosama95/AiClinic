export interface ProseGuardThresholds {
  maxLength: number;
  stopSequences: string[];
  systemPromptLeakNeedle: string;
}

export type GuardViolationKind =
  | "length_ceiling"
  | "stop_sequence"
  | "system_prompt_leak";

function checkStopSequenceAndLeak(
  text: string,
  thresholds: ProseGuardThresholds,
): GuardViolationKind | null {
  for (const stopSequence of thresholds.stopSequences) {
    if (text.includes(stopSequence)) {
      return "stop_sequence";
    }
  }

  if (text.includes(thresholds.systemPromptLeakNeedle)) {
    return "system_prompt_leak";
  }

  return null;
}

export function checkIncrementalGuards(
  chunk: string,
  assembled: string,
  thresholds: ProseGuardThresholds,
): GuardViolationKind | null {
  if (chunk.length > thresholds.maxLength) {
    return "length_ceiling";
  }

  return checkStopSequenceAndLeak(assembled, thresholds);
}

export function runFullGuardSet(
  text: string,
  thresholds: ProseGuardThresholds,
): void {
  const violation = checkStopSequenceAndLeak(text, thresholds);
  if (violation !== null) {
    throw new Error(`guard_violation:${violation}`);
  }
}
