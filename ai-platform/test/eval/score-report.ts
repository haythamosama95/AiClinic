import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

export type CaseScore = {
  case_id: string;
  quality: "pass" | "fail";
  schema: "pass" | "fail";
};

export type ScoreReport = {
  capability_id: string;
  run_kind: "golden" | "live_smoke";
  prompt_build: "current" | "deliberately_regressed";
  recorded_at: string;
  cases: CaseScore[];
  overall: "pass" | "fail";
};

export function deriveOverall(cases: CaseScore[]): "pass" | "fail" {
  if (cases.length === 0) {
    return "fail";
  }
  for (const entry of cases) {
    if (entry.quality === "fail" || entry.schema === "fail") {
      return "fail";
    }
  }
  return "pass";
}

export function writeScoreReport(
  reportsDir: string,
  report: ScoreReport,
): string {
  mkdirSync(reportsDir, { recursive: true });
  const filename = `${report.run_kind}-${report.prompt_build}-${report.recorded_at.replace(/[:.]/g, "-")}.json`;
  const reportPath = path.join(reportsDir, filename);
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return reportPath;
}
