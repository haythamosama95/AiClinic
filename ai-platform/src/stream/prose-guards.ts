export interface ProseGuardThresholds {
  maxLength: number;
  stopSequences: string[];
  /** Port of structured `SafetyMarkers.leakedInstructionNeedle`. */
  systemPromptLeakNeedle: string;
  /**
   * Additional distinctive slices (interior / ending) of the composed system
   * instruction. When present, any slice match trips `system_prompt_leak`.
   */
  systemPromptLeakNeedles?: readonly string[];
  /** Port of structured `SafetyMarkers.refusalPrefixes`. Matched at start. */
  refusalPrefixes?: string[];
  /** Port of structured `SafetyMarkers.injectionEchoNeedle`. Substring match. */
  injectionEchoNeedle?: string;
}

export type GuardViolationKind =
  | "length_ceiling"
  | "stop_sequence"
  | "system_prompt_leak"
  | "empty_output"
  | "refusal"
  | "injection_echo";

function leakNeedlesFromThresholds(
  thresholds: ProseGuardThresholds,
): readonly string[] {
  const extra = thresholds.systemPromptLeakNeedles;
  if (extra !== undefined && extra.length > 0) {
    return extra.filter((needle) => needle.length > 0);
  }
  return thresholds.systemPromptLeakNeedle.length > 0
    ? [thresholds.systemPromptLeakNeedle]
    : [];
}

function checkStopSequenceAndLeak(
  text: string,
  thresholds: ProseGuardThresholds,
): GuardViolationKind | null {
  for (const stopSequence of thresholds.stopSequences) {
    if (text.includes(stopSequence)) {
      return "stop_sequence";
    }
  }

  for (const needle of leakNeedlesFromThresholds(thresholds)) {
    if (text.includes(needle)) {
      return "system_prompt_leak";
    }
  }

  if (
    thresholds.injectionEchoNeedle &&
    text.includes(thresholds.injectionEchoNeedle)
  ) {
    return "injection_echo";
  }

  if (thresholds.refusalPrefixes) {
    const trimmed = text.trimStart();
    for (const prefix of thresholds.refusalPrefixes) {
      if (prefix.length > 0 && trimmed.startsWith(prefix)) {
        return "refusal";
      }
    }
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
