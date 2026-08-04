import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  FIRST_CAPABILITY_ID,
  listCapabilityCases,
  listEvalCapabilities,
  runGoldenSuite,
} from "./harness";

const FIRST_CAPABILITY = "clinic.visit_summary";

describe("T1 golden_set_passes_on_current_prompt", () => {
  it("golden set passes on the current pinned production prompt", async () => {
    const result = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "current",
    });

    expect(result.passed).toBe(true);
    expect(result.report.overall).toBe("pass");
    expect(result.report.capability_id).toBe(FIRST_CAPABILITY);
    expect(result.report.prompt_build).toBe("current");
    expect(result.report.cases.length).toBeGreaterThan(0);
    for (const entry of result.report.cases) {
      expect(entry.quality).toBe("pass");
      expect(entry.schema).toBe("pass");
    }
  });
});

describe("T2 deliberately_regressed_prompt_fails", () => {
  it("deliberately regressed prompt fails the golden set and blocks the change", async () => {
    const result = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "deliberately_regressed",
    });

    expect(result.passed).toBe(false);
    expect(result.report.overall).toBe("fail");
    expect(result.report.prompt_build).toBe("deliberately_regressed");
  });
});

describe("T3 scores_recorded_per_run", () => {
  it("writes a JSON score report with per-case quality and schema scores", async () => {
    const result = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "current",
    });

    expect(result.reportPath).toContain("/test/eval/reports/");
    const persisted = JSON.parse(readFileSync(result.reportPath, "utf8"));
    expect(persisted.capability_id).toBe(FIRST_CAPABILITY);
    expect(persisted.run_kind).toBe("golden");
    expect(persisted.prompt_build).toBe("current");
    expect(persisted.recorded_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    expect(Array.isArray(persisted.cases)).toBe(true);
    for (const entry of persisted.cases) {
      expect(entry.case_id).toEqual(expect.any(String));
      expect(entry.quality).toMatch(/^(pass|fail)$/);
      expect(entry.schema).toMatch(/^(pass|fail)$/);
    }
    expect(persisted.overall).toMatch(/^(pass|fail)$/);
  });
});

describe("T5 golden_cases_use_recorded_fixtures", () => {
  it("golden execution binds to recorded provider fixtures under the capability tree", async () => {
    const result = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "current",
    });

    expect(result.usedLiveEgress).toBe(false);
    expect(result.fixturePathsUsed.length).toBeGreaterThan(0);
    for (const fixturePath of result.fixturePathsUsed) {
      expect(fixturePath).toContain("/test/eval/clinic.visit_summary/fixtures/");
    }
  });
});

describe("T6 evals_are_per_capability", () => {
  it("scopes golden cases to the first capability without a cross-capability aggregate gate", () => {
    const capabilities = listEvalCapabilities();
    expect(capabilities).toEqual([FIRST_CAPABILITY_ID]);
    expect(listCapabilityCases(FIRST_CAPABILITY)).toEqual([
      "visit_summary.happy_path",
    ]);
  });
});
