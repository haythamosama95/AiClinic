import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  FIRST_CAPABILITY_ID,
  FLOATING_MODEL_ALIASES,
  getLiveSmokeExpectation,
  getLiveSmokeModelTargets,
  getLiveSmokeTargets,
  getLiveSmokeWorkflowPath,
  isPinnedModelId,
  readLiveSmokeWorkflowSchedule,
  runLiveSmokeSuite,
  scoreQuality,
} from "./harness";
import type { CanonicalRequest } from "../../src/contracts/canonical";
import type { DeepSeekTransportResponse } from "../../src/provider/deepseek";

function recordedLiveTransport(): {
  fetch(
    url: string,
    init: {
      url: string;
      method: string;
      headers: Record<string, string>;
      body?: string;
      signal?: AbortSignal;
    },
  ): Promise<DeepSeekTransportResponse>;
} {
  const deepseekBody = JSON.stringify({
    id: "smoke-ds",
    object: "chat.completion",
    model: "deepseek-v4-flash",
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content:
            "Live smoke advisory visit summary mentioning headache for clinician review.",
        },
        finish_reason: "stop",
      },
    ],
    usage: { prompt_tokens: 10, completion_tokens: 12, total_tokens: 22 },
  });
  const geminiBody = JSON.stringify({
    candidates: [
      {
        content: {
          parts: [
            {
              text: "Live smoke advisory visit summary mentioning headache for clinician review.",
            },
          ],
          role: "model",
        },
        finishReason: "STOP",
      },
    ],
    usageMetadata: {
      promptTokenCount: 10,
      candidatesTokenCount: 12,
      totalTokenCount: 22,
    },
    responseId: "smoke-gem",
  });

  return {
    async fetch(url: string): Promise<DeepSeekTransportResponse> {
      return {
        status: 200,
        headers: { "content-type": "application/json" },
        body: url.includes("googleapis.com") ? geminiBody : deepseekBody,
      };
    },
  };
}

describe("T4 scheduled_live_smoke_against_pinned_models", () => {
  it("live smoke targets pinned model_id values from routing policy", () => {
    const targets = getLiveSmokeTargets();
    expect(targets).toEqual([
      { provider_id: "deepseek", model_id: "deepseek-v4-flash" },
      { provider_id: "gemini", model_id: "gemini-3.5-flash" },
    ]);
    expect(getLiveSmokeModelTargets()).toEqual([
      "deepseek-v4-flash",
      "gemini-3.5-flash",
    ]);

    for (const target of targets) {
      expect(isPinnedModelId(target.model_id)).toBe(true);
      expect(FLOATING_MODEL_ALIASES).not.toContain(target.model_id);
    }

    for (const alias of [
      "latest",
      "auto",
      "default",
      "deepseek-chat",
      "gemini-1.5-flash",
    ]) {
      expect(isPinnedModelId(alias)).toBe(false);
    }
  });

  it("scheduled workflow invokes live-smoke with provider secrets wired", () => {
    const workflowPath = getLiveSmokeWorkflowPath();
    expect(existsSync(workflowPath)).toBe(true);
    const workflow = readFileSync(workflowPath, "utf8");
    expect(workflow).toContain("live-smoke.test.ts");
    expect(workflow).toContain("secrets.DEEPSEEK_API_KEY");
    expect(workflow).toContain("secrets.GEMINI_API_KEY");
    expect(workflow).toMatch(/DEEPSEEK_API_KEY:\s*\$\{\{\s*secrets\.DEEPSEEK_API_KEY\s*\}\}/);
    expect(workflow).toMatch(/GEMINI_API_KEY:\s*\$\{\{\s*secrets\.GEMINI_API_KEY\s*\}\}/);
    expect(readLiveSmokeWorkflowSchedule()).toMatch(/^\d/);
  });

  it("live smoke invokes adapters per pinned target and writes run_kind live_smoke report", async () => {
    const result = await runLiveSmokeSuite({
      capabilityId: FIRST_CAPABILITY_ID,
      secretStore: {
        getSecret(name: string): string | undefined {
          if (name === "DEEPSEEK_API_KEY") return "test-deepseek-key";
          if (name === "GEMINI_API_KEY") return "test-gemini-key";
          return undefined;
        },
      },
      transport: recordedLiveTransport(),
    });

    expect(result.skipped).toBe(false);
    if (result.skipped) {
      return;
    }

    expect(result.usedLiveEgress).toBe(true);
    expect(result.report.run_kind).toBe("live_smoke");
    expect(result.report.prompt_build).toBe("current");
    expect(result.report.cases.length).toBe(2);
    expect(result.reportPath).toContain(path.join("test", "eval", "reports"));
    for (const entry of result.report.cases) {
      expect(entry.case_id).toMatch(/^live_smoke\.(deepseek|gemini)\./);
      expect(entry.schema).toBe("pass");
      expect(entry.quality).toBe("pass");
    }
    expect(result.passed).toBe(true);

    const persisted = JSON.parse(readFileSync(result.reportPath, "utf8"));
    expect(persisted.run_kind).toBe("live_smoke");
    expect(persisted.overall).toBe("pass");
  });

  it("live smoke quality floor requires advisory + chief-complaint needles beyond min_length 1", () => {
    const expectation = getLiveSmokeExpectation();
    expect(expectation.output_min_length).toBeGreaterThan(1);
    expect(expectation.output_must_contain).toEqual(
      expect.arrayContaining(["advisory", "headache"]),
    );

    const request = {
      requestReference: "EVAL-REQ-SMOKE-FLOOR",
      parts: [{ role: "system", content: "advisory only" }],
      stream: false,
    } as CanonicalRequest;

    expect(
      scoreQuality(request, "x", expectation),
    ).toBe("fail");
    expect(
      scoreQuality(
        request,
        "Live smoke advisory visit summary mentioning headache for clinician review.",
        expectation,
      ),
    ).toBe("pass");
  });

  it("skips live egress when provider credentials are absent", async () => {
    const result = await runLiveSmokeSuite({
      secretStore: {
        getSecret(): string | undefined {
          return undefined;
        },
      },
    });
    expect(result.skipped).toBe(true);
    if (!result.skipped) {
      return;
    }
    expect(result.reason).toMatch(/No provider API keys/i);
  });
});
