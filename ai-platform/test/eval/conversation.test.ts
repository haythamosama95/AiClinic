import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  deriveConversationOverall,
  type ConversationScore,
} from "./conversation-score-report";
import {
  FIRST_CAPABILITY_ID,
  listEvalCapabilities,
  runGoldenSuite,
} from "./harness";
import type { CaseScore } from "./score-report";
import {
  CONVERSATION_CAPABILITY_ID,
  getConversationHarnessRuntimeSnapshot,
  listConversationCases,
  listConversationEvalCapabilities,
  loadConversationCapability,
  runConversationSuite,
} from "./conversation-harness";

const EVAL_ROOT = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(EVAL_ROOT, "..", "..", "..");
const CI_WORKFLOW_PATH = path.join(
  REPO_ROOT,
  ".github",
  "workflows",
  "ci.yml",
);

const CONVERSATION_CAPABILITY = "clinic.chat_assistant";

describe("scripted_conversation_converges_within_round_budget", () => {
  it("scores convergence within the fixture capability declared round budget", async () => {
    const capability = loadConversationCapability(CONVERSATION_CAPABILITY);
    const roundBudget =
      capability.manifest.Interaction.maxContextRoundsPerTurn;

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "converges_within_round_budget",
    });

    expect(result.passed).toBe(true);
    expect(result.report.capability_id).toBe(CONVERSATION_CAPABILITY);
    expect(result.report.run_kind).toBe("conversation");

    const caseScore = result.report.conversations.find(
      (entry) => entry.case_id === "converges_within_round_budget",
    );
    expect(caseScore).toBeDefined();
    expect(caseScore!.round_budget).toBe("pass");
    expect(caseScore!.overall).toBe("pass");
    expect(roundBudget).toBeGreaterThan(0);
  });
});

describe("assistant_must_request_correct_key", () => {
  it("requires the correct permitted key, not merely any permitted key", async () => {
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "assistant_must_request_correct_key",
    });

    const caseScore = result.report.conversations.find(
      (entry) => entry.case_id === "assistant_must_request_correct_key",
    );
    expect(caseScore).toBeDefined();
    expect(caseScore!.right_keys).toBe("pass");
    expect(caseScore!.overall).toBe("pass");
    expect(result.passed).toBe(true);
  });
});

describe("cannot_obtain_key_outside_permitted_set", () => {
  it("fails the permitted-set criterion when a forbidden key is obtained", async () => {
    const capability = loadConversationCapability(CONVERSATION_CAPABILITY);
    const permittedKeys =
      capability.manifest["Context requirements"].permittedKeySet;

    expect(permittedKeys).toContain("visit.chief_complaint@v1");
    expect(permittedKeys).not.toContain("medication.active_list@v1");

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "cannot_obtain_key_outside_permitted_set",
    });

    const caseScore = result.report.conversations.find(
      (entry) => entry.case_id === "cannot_obtain_key_outside_permitted_set",
    );
    expect(caseScore).toBeDefined();
    expect(caseScore!.permitted_set).toBe("pass");
    expect(caseScore!.overall).toBe("pass");
    expect(result.passed).toBe(true);
  });
});

describe("scoring_is_per_conversation_not_per_turn", () => {
  it("fails the whole conversation when a criterion fails on one leg", async () => {
    const failingLegScore: ConversationScore = {
      case_id: "synthetic_per_conversation_gate",
      right_keys: "pass",
      permitted_set: "fail",
      round_budget: "pass",
      overall: "fail",
    };

    expect(deriveConversationOverall(failingLegScore)).toBe("fail");
    expect(failingLegScore.overall).toBe("fail");

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "cannot_obtain_key_outside_permitted_set",
    });

    for (const entry of result.report.conversations) {
      expect(entry).toHaveProperty("right_keys");
      expect(entry).toHaveProperty("permitted_set");
      expect(entry).toHaveProperty("round_budget");
      expect(entry).toHaveProperty("overall");
      expect(entry).not.toHaveProperty("legs");
      expect(entry).not.toHaveProperty("turns");
      expect(deriveConversationOverall(entry)).toBe(entry.overall);
    }
  });
});

describe("scripted_multi_leg_against_fixtures", () => {
  it("advances scripted legs against recorded fixtures without live egress", async () => {
    const caseIds = listConversationCases(CONVERSATION_CAPABILITY);
    expect(caseIds).toEqual(
      expect.arrayContaining([
        "converges_within_round_budget",
        "assistant_must_request_correct_key",
        "cannot_obtain_key_outside_permitted_set",
      ]),
    );

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
    });

    expect(result.usedLiveEgress).toBe(false);
    expect(result.fixturePathsUsed.length).toBeGreaterThan(0);
    for (const fixturePath of result.fixturePathsUsed) {
      expect(fixturePath).toContain(
        "/test/eval/clinic.chat_assistant/fixtures/",
      );
    }

    const runtime = getConversationHarnessRuntimeSnapshot();
    expect(runtime.usedLiveEgress).toBe(false);
    expect(runtime.fixturePathsUsed.length).toBeGreaterThan(0);
  });
});

describe("extends_f1_harness_without_redefining_capability_evals", () => {
  it("keeps F1 capability evals unchanged as a sibling under the same CI gate", async () => {
    const sampleCase: CaseScore = {
      case_id: "visit_summary.happy_path",
      quality: "pass",
      schema: "pass",
    };
    expect(Object.keys(sampleCase).sort()).toEqual([
      "case_id",
      "quality",
      "schema",
    ]);
    expect(sampleCase).not.toHaveProperty("right_keys");
    expect(sampleCase).not.toHaveProperty("permitted_set");
    expect(sampleCase).not.toHaveProperty("round_budget");

    const golden = await runGoldenSuite({
      capabilityId: FIRST_CAPABILITY_ID,
      promptBuild: "current",
    });
    expect(golden.passed).toBe(true);
    expect(golden.report.cases[0]).toHaveProperty("quality");
    expect(golden.report.cases[0]).toHaveProperty("schema");
    expect(golden.report.cases[0]).not.toHaveProperty("right_keys");

    const goldenCapabilities = listEvalCapabilities();
    expect(goldenCapabilities).toEqual([FIRST_CAPABILITY_ID]);
    expect(listConversationEvalCapabilities()).toContain(
      CONVERSATION_CAPABILITY_ID,
    );

    expect(existsSync(path.join(EVAL_ROOT, "conversation-harness.ts"))).toBe(
      true,
    );
    expect(existsSync(path.join(EVAL_ROOT, "conversation.test.ts"))).toBe(
      true,
    );
    expect(existsSync(path.join(EVAL_ROOT, "harness.ts"))).toBe(true);

    const ciWorkflow = readFileSync(CI_WORKFLOW_PATH, "utf8");
    expect(ciWorkflow).toContain("ai-platform-eval-golden");
    expect(ciWorkflow).toContain("test/eval/conversation.test.ts");
    expect(ciWorkflow).toContain("test/eval/golden.test.ts");
  });
});

describe("conversation_eval_scores_recorded_per_conversation", () => {
  it("writes a JSON score report with per-conversation criteria scores", async () => {
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
    });

    expect(result.reportPath).toContain("/test/eval/reports/");
    const persisted = JSON.parse(readFileSync(result.reportPath, "utf8"));

    expect(persisted.capability_id).toBe(CONVERSATION_CAPABILITY);
    expect(persisted.run_kind).toBe("conversation");
    expect(persisted.recorded_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    expect(Array.isArray(persisted.conversations)).toBe(true);
    expect(persisted.conversations.length).toBeGreaterThanOrEqual(3);

    for (const entry of persisted.conversations) {
      expect(entry.case_id).toEqual(expect.any(String));
      expect(entry.right_keys).toMatch(/^(pass|fail)$/);
      expect(entry.permitted_set).toMatch(/^(pass|fail)$/);
      expect(entry.round_budget).toMatch(/^(pass|fail)$/);
      expect(entry.overall).toMatch(/^(pass|fail)$/);
      expect(entry).not.toHaveProperty("quality");
      expect(entry).not.toHaveProperty("schema");
    }

    expect(persisted.overall).toMatch(/^(pass|fail)$/);
    expect(persisted).not.toHaveProperty("cases");
    expect(persisted).not.toHaveProperty("prompt_build");
  });
});
