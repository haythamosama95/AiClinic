import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

export type ConversationCriterion = "pass" | "fail";

export type ConversationExpectedOutcome = {
  right_keys: ConversationCriterion;
  permitted_set: ConversationCriterion;
  round_budget: ConversationCriterion;
};

export type ConversationScore = {
  case_id: string;
  right_keys: ConversationCriterion;
  permitted_set: ConversationCriterion;
  round_budget: ConversationCriterion;
  overall: ConversationCriterion;
};

export type ConversationScoreReport = {
  capability_id: string;
  run_kind: "conversation";
  recorded_at: string;
  conversations: ConversationScore[];
  overall: ConversationCriterion;
};

export function deriveConversationOverall(
  score: Pick<
    ConversationScore,
    "right_keys" | "permitted_set" | "round_budget"
  >,
): ConversationCriterion {
  if (
    score.right_keys === "fail" ||
    score.permitted_set === "fail" ||
    score.round_budget === "fail"
  ) {
    return "fail";
  }
  return "pass";
}

/** Suite gate: every case must match its declared expected_outcome. */
export function matchesExpectedOutcome(
  score: Pick<
    ConversationScore,
    "right_keys" | "permitted_set" | "round_budget"
  >,
  expected: ConversationExpectedOutcome,
): boolean {
  return (
    score.right_keys === expected.right_keys &&
    score.permitted_set === expected.permitted_set &&
    score.round_budget === expected.round_budget
  );
}

export function deriveRunOverall(
  conversations: ConversationScore[],
): ConversationCriterion {
  for (const entry of conversations) {
    if (entry.overall === "fail") {
      return "fail";
    }
  }
  return "pass";
}

/**
 * Suite overall for conversation evals: pass when every case matches its
 * declared expected_outcome (positive and negative-control cases alike).
 */
export function deriveRunOverallFromExpectations(
  results: ReadonlyArray<{
    score: Pick<
      ConversationScore,
      "right_keys" | "permitted_set" | "round_budget"
    >;
    expected: ConversationExpectedOutcome;
  }>,
): ConversationCriterion {
  for (const { score, expected } of results) {
    if (!matchesExpectedOutcome(score, expected)) {
      return "fail";
    }
  }
  return "pass";
}

export function writeConversationScoreReport(
  reportsDir: string,
  report: ConversationScoreReport,
): string {
  mkdirSync(reportsDir, { recursive: true });
  const filename = `${report.run_kind}-${report.recorded_at.replace(/[:.]/g, "-")}.json`;
  const reportPath = path.join(reportsDir, filename);
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return reportPath;
}
