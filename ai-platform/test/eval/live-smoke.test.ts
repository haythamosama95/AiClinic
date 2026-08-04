import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  getLiveSmokeModelTargets,
  getLiveSmokeWorkflowPath,
  readLiveSmokeWorkflowSchedule,
} from "./harness";

describe("T4 scheduled_live_smoke_against_pinned_models", () => {
  it("live smoke targets pinned model_id values from routing policy", () => {
    const targets = getLiveSmokeModelTargets();
    expect(targets).toEqual(["deepseek-chat", "gemini-1.5-flash"]);
    for (const modelId of targets) {
      expect(modelId).not.toMatch(/^(latest|auto|default)$/i);
      expect(modelId.includes(":")).toBe(false);
    }
  });

  it("scheduled workflow invokes the live-smoke Vitest entry", () => {
    const workflowPath = getLiveSmokeWorkflowPath();
    expect(existsSync(workflowPath)).toBe(true);
    const workflow = readFileSync(workflowPath, "utf8");
    expect(workflow).toContain("live-smoke.test.ts");
    expect(readLiveSmokeWorkflowSchedule()).toMatch(/^\d/);
  });
});
