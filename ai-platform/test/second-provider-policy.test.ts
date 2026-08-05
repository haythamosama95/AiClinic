import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ConfigCache } from "../src/config-cache";
import {
  createProviderAdapter,
  listWiredProviderIds,
} from "../src/provider/wiring";
import type { GeminiTransport } from "../src/provider/gemini";
import { selectCandidateChain } from "../src/router";

const TEST_ROOT = path.dirname(fileURLToPath(import.meta.url));
const AI_PLATFORM_ROOT = path.join(TEST_ROOT, "..");
const REPO_ROOT = path.join(AI_PLATFORM_ROOT, "..");

const POLICY_FILE = path.join(
  AI_PLATFORM_ROOT,
  "control",
  "routing-policy",
  "platform-default",
  "1.json",
);

const D7_SLICE_ALLOWED_RELATIVE_PATHS = [
  "src/provider/gemini.ts",
  "src/provider/wiring.ts",
  "control/routing-policy/platform-default/1.json",
  "test/gemini-adapter.test.ts",
  "test/second-provider-policy.test.ts",
  "test/fixtures/gemini",
] as const;


const PIPELINE_MODULES_THAT_MUST_NOT_REQUIRE_CHANGES = [
  "src/invocation/index.ts",
  "src/stream/index.ts",
  "src/validate/index.ts",
  "src/journal/index.ts",
] as const;

const FIXTURE_POLICY_KEY = "routing-policy-platform-default";
const FIXTURE_INSTALLATION_ID = "inst-d7-policy-001";
const FIXTURE_CAPABILITY_ID = "clinic.gemini_fallback_fixture";

type RoutingPolicyDocument = {
  schema_version: number;
  policy_id: string;
  policy_version: number;
  defaults: {
    cost_class: string;
    max_parallel_attempts: number;
  };
  rules: Array<{
    rule_id: string;
    match: Record<string, unknown>;
    requires: {
      structured_output: boolean;
      min_context_window: number;
      languages: string[];
    };
    targets: Array<{
      provider_id: string;
      model_id: string;
      features: Record<string, unknown>;
      max_attempts: number;
      timeout_ms: number;
    }>;
    max_parallel_attempts?: number;
  }>;
  overrides: unknown[];
};

type RouterContext = {
  installationId: string;
  capabilityId: string;
  routingTier: "standard" | "degraded";
  requirements: {
    structured_output_required: boolean;
    min_context_window: number;
    languages: readonly string[];
    latency_class: string;
  };
  manifestCostClass: "economy" | "standard" | "premium";
  entitlementMaxCostClass: "economy" | "standard" | "premium";
  killedProviderIds?: readonly string[];
};

function loadPlatformPolicyDocument(): RoutingPolicyDocument {
  const raw = readFileSync(POLICY_FILE, "utf8");
  return JSON.parse(raw) as RoutingPolicyDocument;
}

function preloadPolicyCache(
  document: RoutingPolicyDocument,
  key: string = FIXTURE_POLICY_KEY,
): ConfigCache {
  const cache = new ConfigCache();
  cache.remember("active_routing_policy", key, {
    policy_id: document.policy_id,
    policy_version: document.policy_version,
    content_pointer: `control/routing-policy/${document.policy_id}/${document.policy_version}.json`,
    active_from: "2026-08-01T00:00:00.000Z",
    activated_by: "test-fixture",
    document,
  });
  return cache;
}

function defaultContext(overrides: Partial<RouterContext> = {}): RouterContext {
  return {
    installationId: FIXTURE_INSTALLATION_ID,
    capabilityId: FIXTURE_CAPABILITY_ID,
    routingTier: overrides.routingTier ?? "standard",
    requirements: overrides.requirements ?? {
      structured_output_required: false,
      min_context_window: 0,
      languages: ["en"],
      latency_class: "interactive",
    },
    manifestCostClass: overrides.manifestCostClass ?? "standard",
    entitlementMaxCostClass: overrides.entitlementMaxCostClass ?? "premium",
    killedProviderIds: overrides.killedProviderIds,
  };
}

function route(
  cache: ConfigCache,
  context: RouterContext = defaultContext(),
  policyCacheKey: string = FIXTURE_POLICY_KEY,
) {
  return selectCandidateChain({
    cache,
    policyCacheKey,
    context,
  });
}

function chainProviderIds(outcome: ReturnType<typeof route>): string[] {
  return outcome.routing_decision.chain.map((entry) => entry.provider_id);
}


function changedPathsVersusAiMaster(): string[] {
  try {
    const output = execSync("git diff --name-only origin/ai/master...HEAD", {
      cwd: REPO_ROOT,
      encoding: "utf8",
    });
    return output
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
  } catch {
    return [];
  }
}

describe("T-D7-13 added_by_routing_policy_edit_no_pipeline_diff", () => {
  it("requires only allowlisted second-adapter + routing-policy + wiring paths — not pipeline modules", () => {
    for (const relativePath of D7_SLICE_ALLOWED_RELATIVE_PATHS) {
      const absolute = path.join(AI_PLATFORM_ROOT, relativePath);
      expect(existsSync(absolute), `${relativePath} must exist`).toBe(true);
    }

    const wiringSource = readFileSync(
      path.join(AI_PLATFORM_ROOT, "src/provider/wiring.ts"),
      "utf8",
    );
    for (const pipelineModule of PIPELINE_MODULES_THAT_MUST_NOT_REQUIRE_CHANGES) {
      const importPath = pipelineModule
        .replace("src/", "../")
        .replace("/index.ts", "");
      expect(
        wiringSource.includes(`from "${importPath}"`) ||
          wiringSource.includes(`from '${importPath}'`),
        `wiring must not import pipeline module ${pipelineModule}`,
      ).toBe(false);
    }

    for (const pipelineModule of PIPELINE_MODULES_THAT_MUST_NOT_REQUIRE_CHANGES) {
      const source = readFileSync(
        path.join(AI_PLATFORM_ROOT, pipelineModule),
        "utf8",
      );
      expect(
        source.includes("gemini") || source.includes("Gemini"),
        `pipeline module ${pipelineModule} must not reference Gemini`,
      ).toBe(false);
    }

    // D7 freeze vs later slices: only fail when listed pre-existing stage
    // modules change. New modules (F5 `src/pipeline`, load harness, etc.) are
    // outside T-D7-13's "second adapter by policy alone" claim.
    const changed = changedPathsVersusAiMaster();
    for (const filePath of changed) {
      for (const pipelineModule of PIPELINE_MODULES_THAT_MUST_NOT_REQUIRE_CHANGES) {
        const forbidden = `ai-platform/${pipelineModule}`;
        expect(
          filePath === forbidden,
          `D7 freeze broken: stage module changed (${filePath})`,
        ).toBe(false);
      }
    }
  });

  it("createProviderAdapter constructs a Gemini port from the wiring map", () => {
    expect(listWiredProviderIds()).toContain("gemini");
    expect(listWiredProviderIds()).toContain("deepseek");

    const transport: GeminiTransport = {
      fetch() {
        return {
          status: 200,
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            candidates: [
              {
                content: { parts: [{ text: "wired" }], role: "model" },
                finishReason: "STOP",
              },
            ],
            usageMetadata: {
              promptTokenCount: 1,
              candidatesTokenCount: 1,
            },
          }),
        };
      },
    };

    const port = createProviderAdapter("gemini", {
      transport,
      secretStore: {
        getSecret(name: string) {
          return name === "GEMINI_API_KEY" ? "wiring-smoke-key" : undefined;
        },
      },
    });
    expect(typeof port.invoke).toBe("function");
  });
});

describe("T-D7-14 fallback_ordering_honoured", () => {
  it("places gemini after higher-priority targets with selection reason recorded and identical chains", () => {
    const document = loadPlatformPolicyDocument();
    const cache = preloadPolicyCache(document);
    const context = defaultContext();

    const firstOutcome = route(cache, context);
    const secondOutcome = route(cache, context);

    const providerIds = chainProviderIds(firstOutcome);
    const geminiIndex = providerIds.indexOf("gemini");
    expect(geminiIndex).toBeGreaterThan(0);
    expect(providerIds.slice(0, geminiIndex).length).toBeGreaterThan(0);
    expect(providerIds).toContain("deepseek");
    expect(providerIds.indexOf("deepseek")).toBeLessThan(geminiIndex);

    const geminiTarget = firstOutcome.routing_decision.chain.find(
      (entry) => entry.provider_id === "gemini",
    );
    expect(geminiTarget?.model_id).toBe("gemini-3.5-flash");

    const decision = firstOutcome.routing_decision;
    expect(decision.policy_id).toBe(document.policy_id);
    expect(decision.policy_version).toBe(document.policy_version);
    expect(decision.rule_id).toBeTruthy();
    expect(decision.chain.length).toBeGreaterThan(1);

    expect(secondOutcome.routing_decision.chain).toEqual(
      firstOutcome.routing_decision.chain,
    );
    expect(secondOutcome.routing_decision.excluded).toEqual(
      firstOutcome.routing_decision.excluded,
    );
  });
});
