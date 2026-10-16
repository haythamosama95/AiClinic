import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  estimateUsageFromStreamedChars,
  ledgerUsageFromProvider,
  PLATFORM_PRICING_TABLE,
  priceUsage,
  ratesForModel,
} from "../src/pricing";

const TEST_ROOT = path.dirname(fileURLToPath(import.meta.url));
const AI_PLATFORM_ROOT = path.join(TEST_ROOT, "..");

function readSrc(relativePath: string): string {
  return readFileSync(path.join(AI_PLATFORM_ROOT, relativePath), "utf8");
}

describe("platform pricing artifact", () => {
  it("is a versioned control artifact sitting alongside the routing-policy fixture", () => {
    expect(
      existsSync(
        path.join(
          AI_PLATFORM_ROOT,
          "control",
          "pricing",
          "platform-default",
          "1.json",
        ),
      ),
    ).toBe(true);
    expect(
      existsSync(
        path.join(
          AI_PLATFORM_ROOT,
          "control",
          "routing-policy",
          "platform-default",
          "1.json",
        ),
      ),
    ).toBe(true);
    expect(PLATFORM_PRICING_TABLE.pricing_id).toBe("platform-default");
    expect(PLATFORM_PRICING_TABLE.pricing_version).toBe(1);
    expect(PLATFORM_PRICING_TABLE.unit).toBe("per_1k_tokens");
  });

  it("prices DeepSeek, Gemini, and fake models from distinct input/output rates", () => {
    expect(ratesForModel("deepseek-v4-flash")).toEqual({
      input_per_1k: 0.14,
      output_per_1k: 0.28,
    });
    expect(ratesForModel("gemini-3.5-flash")).toEqual({
      input_per_1k: 0.075,
      output_per_1k: 0.3,
    });
    expect(priceUsage({
      modelId: "deepseek-v4-flash",
      inputTokens: 1000,
      outputTokens: 1000,
    })).toBe(0.42);
    expect(priceUsage({
      modelId: "gemini-3.5-flash",
      inputTokens: 1000,
      outputTokens: 1000,
    })).toBe(0.375);
    expect(
      priceUsage({
        modelId: "fake-v1",
        inputTokens: 10,
        outputTokens: 20,
      }),
    ).toBe(0.005);
  });

  it("uses the default rates for unknown models rather than a silent zero", () => {
    expect(ratesForModel("unknown-model")).toEqual(
      PLATFORM_PRICING_TABLE.default,
    );
    expect(
      priceUsage({
        modelId: "unknown-model",
        inputTokens: 10,
        outputTokens: 20,
      }),
    ).toBe(
      priceUsage({
        modelId: "fake-v1",
        inputTokens: 10,
        outputTokens: 20,
      }),
    );
  });
});

describe("ledgerUsageFromProvider", () => {
  it("sums input+output tokens and prices them with the shared helper", () => {
    const usage = ledgerUsageFromProvider({
      usage: { input: 10, output: 20, cached: 99 },
      providerModel: { provider: "fake", model: "fake-v1" },
    });
    expect(usage).toEqual({
      tokens: 30,
      cost: priceUsage({
        modelId: "fake-v1",
        inputTokens: 10,
        outputTokens: 20,
      }),
    });
    expect(usage.cost).not.toBe(0);
    expect(usage.cost).not.toBe(0.001);
  });
});

describe("estimateUsageFromStreamedChars", () => {
  it("treats chars as output tokens and prices them through priceUsage", () => {
    const streamedChars = 21;
    const estimated = estimateUsageFromStreamedChars(streamedChars, "fake-v1");
    expect(estimated).toEqual({
      tokens: streamedChars,
      cost: priceUsage({
        modelId: "fake-v1",
        inputTokens: 0,
        outputTokens: streamedChars,
      }),
    });
    expect(estimated.cost).not.toBe(streamedChars * 0.001);
  });
});

describe("post-response pricing is the only cost formula", () => {
  it("does not hardcode 0 / 0.001 cost formulas in invocation, worker, or pipeline", () => {
    const invocation = readSrc("src/invocation/index.ts");
    expect(invocation).not.toMatch(/cost:\s*0,/);
    expect(invocation).not.toMatch(/accruedCost \+= 0/);
    expect(invocation).not.toMatch(/streamedChars \*\s*0\.001/);

    const worker = readSrc("src/worker.ts");
    expect(worker).not.toMatch(/cost:\s*0\.001/);

    const pipeline = readSrc("src/pipeline/index.ts");
    expect(pipeline).not.toMatch(/cost:\s*0\.001/);
  });

  it("keeps preflight token-only — pricing is not imported there", () => {
    const preflight = readSrc("src/context/preflight.ts");
    expect(preflight).not.toMatch(/from ["']\.\.\/pricing["']/);
    expect(preflight).not.toMatch(/priceUsage|ledgerUsageFromProvider/);
  });
});
