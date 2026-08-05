import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  D5_FIXTURES_ROOT,
  FIRST_CAPABILITY_ID,
  listCapabilityCases,
  listEvalCapabilities,
  runGoldenSuite,
} from "./harness";

const FIRST_CAPABILITY = "clinic.visit_summary";
const EVAL_ROOT = path.dirname(fileURLToPath(import.meta.url));

function pathContainsParts(actual: string, ...parts: string[]): boolean {
  const normalized = path.normalize(actual);
  const expected = path.normalize(path.join(...parts));
  return normalized.includes(expected);
}

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
  it("deliberately regressed prompt fails quality on the happy-path case", async () => {
    const result = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "deliberately_regressed",
    });

    expect(result.passed).toBe(false);
    expect(result.report.overall).toBe("fail");
    expect(result.report.prompt_build).toBe("deliberately_regressed");

    const happyPath = result.report.cases.find(
      (entry) => entry.case_id === "visit_summary.happy_path",
    );
    expect(happyPath).toBeDefined();
    expect(happyPath?.quality).toBe("fail");
    expect(happyPath?.schema).toBe("pass");
  });
});

describe("T3 scores_recorded_per_run", () => {
  it("writes a JSON score report with per-case quality and schema scores", async () => {
    const result = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "current",
    });

    expect(
      pathContainsParts(result.reportPath, "test", "eval", "reports"),
    ).toBe(true);
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
  it("golden execution binds to D5 recorded fixtures with no live egress", async () => {
    const fetchSpy = viFetchSpy();
    try {
      const result = await runGoldenSuite({
        capabilityId: FIRST_CAPABILITY,
        promptBuild: "current",
      });

      expect(result.usedLiveEgress).toBe(false);
      expect(fetchSpy.calls).toBe(0);
      expect(result.fixturePathsUsed.length).toBeGreaterThan(0);
      expect(
        result.fixturePathsUsed.some((fixturePath) =>
          pathContainsParts(
            fixturePath,
            "test",
            "fixtures",
            "deepseek",
            "visit-summary",
          ),
        ),
      ).toBe(true);
      expect(existsSync(D5_FIXTURES_ROOT)).toBe(true);
      for (const fixturePath of result.fixturePathsUsed) {
        const underD5 = pathContainsParts(
          fixturePath,
          "test",
          "fixtures",
          "deepseek",
        );
        const underEvalBinding = pathContainsParts(
          fixturePath,
          "test",
          "eval",
          "clinic.visit_summary",
          "fixtures",
        );
        expect(underD5 || underEvalBinding).toBe(true);
      }
    } finally {
      fetchSpy.restore();
    }
  });
});

describe("T6 evals_are_per_capability", () => {
  it("scopes golden cases structurally per capability without a brittle singleton gate", () => {
    const capabilities = listEvalCapabilities();
    expect(capabilities).toContain(FIRST_CAPABILITY_ID);

    for (const capabilityId of capabilities) {
      const caseIds = listCapabilityCases(capabilityId);
      expect(caseIds.length).toBeGreaterThan(0);

      const root = path.join(EVAL_ROOT, capabilityId);
      for (const caseId of caseIds) {
        expect(
          existsSync(path.join(root, "cases", `${caseId}.json`)),
        ).toBe(true);
        expect(
          existsSync(path.join(root, "fixtures", `${caseId}.json`)),
        ).toBe(true);
        expect(
          existsSync(path.join(root, "expectations", `${caseId}.json`)),
        ).toBe(true);
      }
    }
  });

  it("runGoldenSuite capabilityIds reports only the evaluated capability", async () => {
    const result = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "current",
    });
    expect(result.capabilityIds).toEqual([FIRST_CAPABILITY]);
  });
});

describe("composeWithPromptBuild_mock_isolation", () => {
  it("current prompt build still resolves production system text after a regressed run", async () => {
    const regressed = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "deliberately_regressed",
    });
    expect(regressed.passed).toBe(false);

    const current = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY,
      promptBuild: "current",
    });
    expect(current.passed).toBe(true);
    expect(current.report.cases.every((entry) => entry.quality === "pass")).toBe(
      true,
    );
  });
});

function viFetchSpy(): { calls: number; restore: () => void } {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = ((...args: Parameters<typeof fetch>) => {
    calls += 1;
    return original(...args);
  }) as typeof fetch;
  return {
    get calls() {
      return calls;
    },
    restore() {
      globalThis.fetch = original;
    },
  };
}
