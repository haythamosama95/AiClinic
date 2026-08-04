export interface ProseGuardThresholds {
  maxLength: number;
  stopSequences: string[];
  systemPromptLeakNeedle: string;
}

export type GuardViolationKind =
  | "length_ceiling"
  | "stop_sequence"
  | "system_prompt_leak"
  | "empty_output";

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

/**
 * Cheap incremental guards. Length is evaluated against assembled text
 * (cumulative), not the individual chunk.
 */
export function checkIncrementalGuards(
  _chunk: string,
  assembled: string,
  thresholds: ProseGuardThresholds,
): GuardViolationKind | null {
  if (assembled.length > thresholds.maxLength) {
    return "length_ceiling";
  }

  return checkStopSequenceAndLeak(assembled, thresholds);
}

/**
 * Full guard set on assembled text at completion.
 * Includes assembled length plus a deferred empty-output check that is not
 * part of the incremental set (empty streams never trip incremental guards).
 * Returns a violation kind instead of throwing.
 */
export function runFullGuardSet(
  text: string,
  thresholds: ProseGuardThresholds,
): GuardViolationKind | null {
  if (text.length === 0) {
    return "empty_output";
  }

  if (text.length > thresholds.maxLength) {
    return "length_ceiling";
  }

  return checkStopSequenceAndLeak(text, thresholds);
}
