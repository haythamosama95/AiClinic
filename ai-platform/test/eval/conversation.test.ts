import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  deriveConversationOverall,
  matchesExpectedOutcome,
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
  loadCase,
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

const FIXTURES_SEGMENT = path.join(
  "test",
  "eval",
  "clinic.chat_assistant",
  "fixtures",
);
const REPORTS_SEGMENT = path.join("test", "eval", "reports");

function assertPathContainsSegments(
  absolutePath: string,
  segments: string,
): void {
  const normalized = path.normalize(absolutePath);
  expect(normalized.includes(path.normalize(segments))).toBe(true);
}

describe("scripted_conversation_converges_within_round_budget", () => {
  it("scores convergence within the fixture capability declared round budget", async () => {
    const capability = loadConversationCapability(CONVERSATION_CAPABILITY);
    const caseDef = loadCase(
      CONVERSATION_CAPABILITY,
      "converges_within_round_budget",
    );
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
    expect(
      matchesExpectedOutcome(caseScore!, caseDef.expected_outcome),
    ).toBe(true);
    expect(caseScore!.round_budget).toBe("pass");
    expect(caseScore!.overall).toBe("pass");
    expect(caseDef.scoring.expect_convergence).toBe(true);
    expect(roundBudget).toBeGreaterThan(0);
  });
});

describe("assistant_must_request_correct_key", () => {
  it("requires the correct permitted key across a multi-leg negotiation", async () => {
    const caseDef = loadCase(
      CONVERSATION_CAPABILITY,
      "assistant_must_request_correct_key",
    );
    expect(caseDef.legs.length).toBeGreaterThanOrEqual(2);

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "assistant_must_request_correct_key",
    });

    const caseScore = result.report.conversations.find(
      (entry) => entry.case_id === "assistant_must_request_correct_key",
    );
    expect(caseScore).toBeDefined();
    expect(
      matchesExpectedOutcome(caseScore!, caseDef.expected_outcome),
    ).toBe(true);
    expect(caseScore!.right_keys).toBe("pass");
    expect(caseScore!.overall).toBe("pass");
    expect(result.passed).toBe(true);
  });
});

describe("cannot_obtain_key_outside_permitted_set", () => {
  it("fails permitted_set only when a forbidden key is obtained; out-of-set inject is dropped", async () => {
    const capability = loadConversationCapability(CONVERSATION_CAPABILITY);
    const caseDef = loadCase(
      CONVERSATION_CAPABILITY,
      "cannot_obtain_key_outside_permitted_set",
    );
    const permittedKeys =
      capability.manifest["Context requirements"].permittedKeySet;

    expect(permittedKeys).toContain("visit.chief_complaint@v1");
    expect(permittedKeys).not.toContain("medication.active_list@v1");
    expect(caseDef.scoring.forbidden_resolved_keys).toContain(
      "medication.active_list@v1",
    );

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "cannot_obtain_key_outside_permitted_set",
    });

    const caseScore = result.report.conversations.find(
      (entry) => entry.case_id === "cannot_obtain_key_outside_permitted_set",
    );
    expect(caseScore).toBeDefined();
    expect(
      matchesExpectedOutcome(caseScore!, caseDef.expected_outcome),
    ).toBe(true);
    expect(caseScore!.permitted_set).toBe("pass");
    expect(caseScore!.overall).toBe("pass");
    expect(result.passed).toBe(true);
  });
});

describe("scoring_is_per_conversation_not_per_turn", () => {
  it("fails the whole conversation when a criterion fails on a later leg", async () => {
    const failingLegScore: ConversationScore = {
      case_id: "synthetic_per_conversation_gate",
      right_keys: "pass",
      permitted_set: "fail",
      round_budget: "pass",
      overall: "fail",
    };

    expect(deriveConversationOverall(failingLegScore)).toBe("fail");
    expect(failingLegScore.overall).toBe("fail");

    const caseDef = loadCase(
      CONVERSATION_CAPABILITY,
      "criterion_fails_mid_conversation",
    );
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "criterion_fails_mid_conversation",
    });

    const caseScore = result.report.conversations.find(
      (entry) => entry.case_id === "criterion_fails_mid_conversation",
    );
    expect(caseScore).toBeDefined();
    expect(caseDef.legs.length).toBeGreaterThanOrEqual(2);
    expect(
      matchesExpectedOutcome(caseScore!, caseDef.expected_outcome),
    ).toBe(true);
    expect(caseScore!.permitted_set).toBe("fail");
    expect(caseScore!.overall).toBe("fail");
    expect(caseScore).not.toHaveProperty("legs");
    expect(caseScore).not.toHaveProperty("turns");
    expect(deriveConversationOverall(caseScore!)).toBe(caseScore!.overall);
    expect(result.passed).toBe(true);
  });
});

describe("scripted_multi_leg_against_fixtures", () => {
  it("advances scripted legs against recorded fixtures without a provider path", async () => {
    const caseIds = listConversationCases(CONVERSATION_CAPABILITY);
    expect(caseIds).toEqual(
      expect.arrayContaining([
        "converges_within_round_budget",
        "assistant_must_request_correct_key",
        "cannot_obtain_key_outside_permitted_set",
        "fails_to_converge_within_budget",
        "exceeds_round_budget",
        "requests_wrong_permitted_key",
        "requests_key_outside_permitted_set",
        "criterion_fails_mid_conversation",
      ]),
    );

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
    });

    expect(result.passed).toBe(true);
    expect(result.fixturePathsUsed.length).toBeGreaterThan(0);
    for (const fixturePath of result.fixturePathsUsed) {
      assertPathContainsSegments(fixturePath, FIXTURES_SEGMENT);
    }

    const runtime = getConversationHarnessRuntimeSnapshot();
    expect(runtime.fixturePathsUsed.length).toBeGreaterThan(0);

    const harnessSource = readFileSync(
      path.join(EVAL_ROOT, "conversation-harness.ts"),
      "utf8",
    );
    // Structural no-provider guard: conversation harness must not import adapters
    // or open HTTP. Avoid spelling provider product names (R-12 scan targets).
    expect(harnessSource).not.toMatch(/from ["'].*provider\//);
    expect(harnessSource).not.toMatch(/\bAdapter\b/);
    expect(harnessSource).not.toMatch(/\bfetch\s*\(/);
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

    const ciWorkflow = readFileSync(CI_WORKFLOW_PATH, "utf8");
    expect(ciWorkflow).toMatch(/ai-platform-eval-golden/);
    const goldenJobMatch = ciWorkflow.match(
      /ai-platform-eval-golden:[\s\S]*?(?=\n  [a-z]|\n\S|$)/,
    );
    expect(goldenJobMatch?.[0]).toContain("test/eval/conversation.test.ts");
    expect(goldenJobMatch?.[0]).toContain("test/eval/golden.test.ts");
  });
});

describe("conversation_eval_scores_recorded_per_conversation", () => {
  it("writes a JSON score report with per-conversation criteria scores", async () => {
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
    });

    assertPathContainsSegments(result.reportPath, REPORTS_SEGMENT);
    const persisted = JSON.parse(readFileSync(result.reportPath, "utf8"));

    expect(persisted.capability_id).toBe(CONVERSATION_CAPABILITY);
    expect(persisted.run_kind).toBe("conversation");
    expect(persisted.recorded_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    expect(Array.isArray(persisted.conversations)).toBe(true);
    expect(persisted.conversations.length).toBeGreaterThanOrEqual(8);
    expect(persisted.overall).toBe("pass");

    for (const entry of persisted.conversations) {
      expect(entry.case_id).toEqual(expect.any(String));
      expect(entry.right_keys).toMatch(/^(pass|fail)$/);
      expect(entry.permitted_set).toMatch(/^(pass|fail)$/);
      expect(entry.round_budget).toMatch(/^(pass|fail)$/);
      expect(entry.overall).toMatch(/^(pass|fail)$/);
      expect(entry).not.toHaveProperty("quality");
      expect(entry).not.toHaveProperty("schema");
    }

    expect(persisted).not.toHaveProperty("cases");
    expect(persisted).not.toHaveProperty("prompt_build");
  });
});

describe("negative_control_right_keys", () => {
  it("fails right_keys when the assistant requests the wrong permitted key", async () => {
    const caseDef = loadCase(
      CONVERSATION_CAPABILITY,
      "requests_wrong_permitted_key",
    );
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "requests_wrong_permitted_key",
    });
    const caseScore = result.report.conversations[0]!;
    expect(matchesExpectedOutcome(caseScore, caseDef.expected_outcome)).toBe(
      true,
    );
    expect(caseScore.right_keys).toBe("fail");
    expect(caseScore.overall).toBe("fail");
    expect(result.passed).toBe(true);
  });
});

describe("negative_control_permitted_set", () => {
  it("fails permitted_set when the assistant requests a key outside the set", async () => {
    const caseDef = loadCase(
      CONVERSATION_CAPABILITY,
      "requests_key_outside_permitted_set",
    );
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "requests_key_outside_permitted_set",
    });
    const caseScore = result.report.conversations[0]!;
    expect(matchesExpectedOutcome(caseScore, caseDef.expected_outcome)).toBe(
      true,
    );
    expect(caseScore.permitted_set).toBe("fail");
    expect(caseScore.round_budget).toBe("pass");
    expect(caseScore.overall).toBe("fail");
    expect(result.passed).toBe(true);
  });
});

describe("negative_control_round_budget_non_convergence", () => {
  it("fails round_budget when expect_convergence and the last assistant turn is not model", async () => {
    const caseDef = loadCase(
      CONVERSATION_CAPABILITY,
      "fails_to_converge_within_budget",
    );
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "fails_to_converge_within_budget",
    });
    const caseScore = result.report.conversations[0]!;
    expect(matchesExpectedOutcome(caseScore, caseDef.expected_outcome)).toBe(
      true,
    );
    expect(caseScore.round_budget).toBe("fail");
    expect(caseScore.permitted_set).toBe("pass");
    expect(caseScore.overall).toBe("fail");
    expect(result.passed).toBe(true);
  });
});

describe("negative_control_round_budget_exceeded", () => {
  it("fails round_budget when consecutive context rounds exceed the declared budget", async () => {
    const caseDef = loadCase(CONVERSATION_CAPABILITY, "exceeds_round_budget");
    const capability = loadConversationCapability(CONVERSATION_CAPABILITY);
    expect(capability.manifest.Interaction.maxContextRoundsPerTurn).toBe(3);
    expect(caseDef.legs.length).toBe(4);

    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "exceeds_round_budget",
    });
    const caseScore = result.report.conversations[0]!;
    expect(matchesExpectedOutcome(caseScore, caseDef.expected_outcome)).toBe(
      true,
    );
    expect(caseScore.round_budget).toBe("fail");
    expect(caseScore.permitted_set).toBe("pass");
    expect(caseScore.overall).toBe("fail");
    expect(result.passed).toBe(true);
  });
});

describe("criteria_are_independent_on_budget_breach", () => {
  it("does not mark permitted_set fail merely because round budget was exhausted", async () => {
    const result = await runConversationSuite({
      capabilityId: CONVERSATION_CAPABILITY,
      caseId: "exceeds_round_budget",
    });
    const caseScore = result.report.conversations[0]!;
    expect(caseScore.round_budget).toBe("fail");
    expect(caseScore.permitted_set).toBe("pass");
    expect(caseScore.right_keys).toBe("pass");
  });
});
