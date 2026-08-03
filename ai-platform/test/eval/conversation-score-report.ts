import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

export type ConversationCriterion = "pass" | "fail";

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
