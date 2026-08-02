import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { vi } from "vitest";
import {
  CANONICAL_FIELD_MANIFEST,
  type CanonicalRequest,
  type CanonicalResult,
} from "../../src/contracts/canonical";
import type { Principal } from "../../src/identity";
import { VISIT_CHIEF_COMPLAINT_V1 } from "../../src/context";
import { load, type Manifest } from "../../src/manifest";
import {
  DEEPSEEK_API_KEY_BINDING,
  DeepSeekAdapter,
  type DeepSeekTransport,
  type DeepSeekTransportResponse,
  type SecretStorePort,
} from "../../src/provider/deepseek";
import type { ProviderInvokeResult } from "../../src/provider/port";
import {
  deriveOverall,
  writeScoreReport,
  type CaseScore,
  type ScoreReport,
} from "./score-report";

const EVAL_ROOT = path.dirname(fileURLToPath(import.meta.url));
const AI_PLATFORM_ROOT = path.resolve(EVAL_ROOT, "..", "..");
const D5_FIXTURES_ROOT = path.join(AI_PLATFORM_ROOT, "test", "fixtures", "deepseek");
const ROUTING_POLICY_PATH = path.join(
  AI_PLATFORM_ROOT,
  "control",
  "routing-policy",
  "platform-default",
  "1.json",
);

const FIRST_CAPABILITY_ID = "clinic.visit_summary";
export { FIRST_CAPABILITY_ID };
const KNOWN_FIXTURE_SECRET = "deepseek-eval-fixture-secret";

export type PromptBuild = "current" | "deliberately_regressed";
export type RunKind = "golden" | "live_smoke";

type CaseDefinition = {
  case_id: string;
  user_intent: string;
  context: Record<string, unknown>;
};

type FixtureBinding = {
  case_id: string;
  d5_fixture_subdir: string;
  provider_response_file: string;
};

type ExpectationDefinition = {
  case_id: string;
  system_instruction_must_contain?: string[];
  output_must_contain?: string[];
  output_min_length?: number;
  output_mode?: "prose" | "structured";
};

export type GoldenRunOptions = {
  capabilityId?: string;
  promptBuild?: PromptBuild;
  runKind?: RunKind;
  reportsDir?: string;
};

export type GoldenRunResult = {
  passed: boolean;
  reportPath: string;
  report: ScoreReport;
  fixturePathsUsed: string[];
  capabilityIds: string[];
  usedLiveEgress: boolean;
};

type HarnessRuntime = {
  fixturePathsUsed: string[];
  usedLiveEgress: boolean;
};

const harnessRuntime: HarnessRuntime = {
  fixturePathsUsed: [],
  usedLiveEgress: false,
};

function resetHarnessRuntime(): void {
  harnessRuntime.fixturePathsUsed = [];
  harnessRuntime.usedLiveEgress = false;
}

function readJson<T>(filePath: string): T {
  return JSON.parse(readFileSync(filePath, "utf8")) as T;
}

function visitSummaryManifest(): Manifest {
  const wire = {
    Identity: {
      capabilityId: FIRST_CAPABILITY_ID,
      version: "1.0.0",
      title: "Visit summary",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.visit_summary",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: {
      interactionMode: "single_shot",
    },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": [
      {
        key: VISIT_CHIEF_COMPLAINT_V1,
        required: true,
        shapeRef: VISIT_CHIEF_COMPLAINT_V1,
        maxSize: 4_096,
        freshnessHint: "session",
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: "clinic.visit_summary/system@v1",
      businessRuleFragmentRefs: ["clinic.visit_summary/rules-visit-summary@v1"],
      contextRenderingTemplateRef:
        "clinic.visit_summary/template-visit-summary@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: "routing/standard@v1",
      requiredProviderFeatures: {
        structuredOutput: false,
        contextWindow: 32_000,
        language: "en",
      },
      latencyClass: "standard",
      degradedTierPolicy: "fallback_chain",
    },
    Economics: {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      perRequestCostCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/visit-summary@v1",
    },
  };
  return load(wire);
}

function fixturePrincipal(): Principal {
  return Object.freeze({
    installationId: "inst-f1-eval-harness",
    organizationId: "org-f1-001",
    branchId: "branch-f1-001",
    actorId: "actor-f1-001",
    role: "clinician",
    scopes: Object.freeze(["ai.visit_summary"]),
    jti: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
  });
}

function capabilityRoot(capabilityId: string): string {
  return path.join(EVAL_ROOT, capabilityId);
}

export function listCapabilityCases(capabilityId: string): string[] {
  const casesDir = path.join(capabilityRoot(capabilityId), "cases");
  return readdirSync(casesDir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => name.replace(/\.json$/, ""));
}

export function listEvalCapabilities(): string[] {
  return readdirSync(EVAL_ROOT, { withFileTypes: true })
    .filter(
      (entry) =>
        entry.isDirectory() &&
        entry.name.includes(".") &&
        !["prompts", "reports"].includes(entry.name),
    )
    .map((entry) => entry.name);
}

function loadCase(capabilityId: string, caseId: string): CaseDefinition {
  return readJson<CaseDefinition>(
    path.join(capabilityRoot(capabilityId), "cases", `${caseId}.json`),
  );
}

function loadFixtureBinding(
  capabilityId: string,
  caseId: string,
): FixtureBinding {
  return readJson<FixtureBinding>(
    path.join(capabilityRoot(capabilityId), "fixtures", `${caseId}.json`),
  );
}

function loadExpectation(
  capabilityId: string,
  caseId: string,
): ExpectationDefinition {
  return readJson<ExpectationDefinition>(
    path.join(
      capabilityRoot(capabilityId),
      "expectations",
      `${caseId}.json`,
    ),
  );
}

function resolveProviderResponsePath(binding: FixtureBinding): string {
  const capabilityScoped = path.join(
    capabilityRoot(FIRST_CAPABILITY_ID),
    "fixtures",
    binding.provider_response_file,
  );
  harnessRuntime.fixturePathsUsed.push(capabilityScoped);
  return capabilityScoped;
}

function createFixtureTransport(providerResponsePath: string): DeepSeekTransport {
  const body = readFileSync(providerResponsePath, "utf8");
  return {
    fetch(): DeepSeekTransportResponse {
      return {
        status: 200,
        headers: { "content-type": "application/json" },
        body,
      };
    },
  };
}

function createFixtureSecretStore(): SecretStorePort {
  return {
    getSecret(name: string): string | undefined {
      return name === DEEPSEEK_API_KEY_BINDING ? KNOWN_FIXTURE_SECRET : undefined;
    },
  };
}

async function composeWithPromptBuild(
  manifest: Manifest,
  caseDef: CaseDefinition,
  promptBuild: PromptBuild,
): Promise<CanonicalRequest> {
  const principal = fixturePrincipal();

  if (promptBuild === "deliberately_regressed") {
    const worseRoot = path.join(
      EVAL_ROOT,
      "prompts",
      "clinic.visit_summary.worse",
    );
    const worseSystem = readFileSync(
      path.join(worseRoot, "system.md"),
      "utf8",
    );
    const productionRules = readFileSync(
      path.join(
        AI_PLATFORM_ROOT,
        "prompts",
        "clinic.visit_summary",
        "rules-visit-summary.md",
      ),
      "utf8",
    );
    const productionTemplate = readFileSync(
      path.join(
        AI_PLATFORM_ROOT,
        "prompts",
        "clinic.visit_summary",
        "template-visit-summary.md",
      ),
      "utf8",
    );

    vi.resetModules();
    vi.doMock("../../src/prompt/registry", () => ({
      resolveArtifact(ref: string): string | undefined {
        if (ref === "clinic.visit_summary/system@v1") {
          return worseSystem;
        }
        if (ref === "clinic.visit_summary/rules-visit-summary@v1") {
          return productionRules;
        }
        if (ref === "clinic.visit_summary/template-visit-summary@v1") {
          return productionTemplate;
        }
        return undefined;
      },
      resolvePromptVersion(): string {
        return "clinic.visit_summary/system@v1";
      },
      verifyBuildPins(): void {},
    }));

    const { composeRequest } = await import("../../src/prompt/composer");
    const composed = composeRequest({
      manifest,
      filteredContext: caseDef.context,
      userIntent: caseDef.user_intent,
      principal,
      streamFlag: false,
    });
    if (!composed.ok) {
      throw new Error("Failed to compose request with worse prompt build");
    }
    return composed.request;
  }

  vi.resetModules();
  vi.unmock("../../src/prompt/registry");
  const { composeRequest } = await import("../../src/prompt/composer");
  const composed = composeRequest({
    manifest,
    filteredContext: caseDef.context,
    userIntent: caseDef.user_intent,
    principal,
    streamFlag: false,
  });
  if (!composed.ok) {
    throw new Error("Failed to compose request with current prompt build");
  }
  return composed.request;
}

function extractFinalContent(outcome: ProviderInvokeResult): string {
  if (outcome.kind !== "success") {
    return "";
  }
  const content = outcome.result["final content"];
  if (typeof content === "string") {
    return content;
  }
  if (content && typeof content === "object" && "text" in content) {
    return String((content as { text: unknown }).text);
  }
  return String(content);
}

function assertCanonicalResultShape(result: CanonicalResult): boolean {
  for (const key of CANONICAL_FIELD_MANIFEST.result) {
    if (!Object.hasOwn(result, key)) {
      return false;
    }
  }
  return true;
}

function scoreQuality(
  composedRequest: CanonicalRequest,
  finalContent: string,
  expectation: ExpectationDefinition,
): "pass" | "fail" {
  const systemParts = composedRequest["ordered role-tagged message parts"]
    .filter((part) => part.role === "system")
    .map((part) => part.content)
    .join("\n");

  for (const needle of expectation.system_instruction_must_contain ?? []) {
    if (!systemParts.toLowerCase().includes(needle.toLowerCase())) {
      return "fail";
    }
  }

  const normalizedOutput = finalContent.toLowerCase();
  for (const needle of expectation.output_must_contain ?? []) {
    if (!normalizedOutput.includes(needle.toLowerCase())) {
      return "fail";
    }
  }

  if (
    expectation.output_min_length !== undefined &&
    finalContent.length < expectation.output_min_length
  ) {
    return "fail";
  }

  return "pass";
}

function scoreSchema(
  outcome: ProviderInvokeResult,
  expectation: ExpectationDefinition,
): "pass" | "fail" {
  if (outcome.kind !== "success") {
    return "fail";
  }

  if (!assertCanonicalResultShape(outcome.result)) {
    return "fail";
  }

  const mode = expectation.output_mode ?? "prose";
  const content = extractFinalContent(outcome);
  if (mode === "prose") {
    if (content.trim().length === 0) {
      return "fail";
    }
    if (content.trim().startsWith("{") && content.trim().endsWith("}")) {
      return "fail";
    }
  }

  return "pass";
}

function runCase(
  capabilityId: string,
  caseId: string,
  promptBuild: PromptBuild,
): Promise<CaseScore> {
  const manifest = visitSummaryManifest();
  const caseDef = loadCase(capabilityId, caseId);
  const binding = loadFixtureBinding(capabilityId, caseId);
  const expectation = loadExpectation(capabilityId, caseId);

  const providerResponsePath = resolveProviderResponsePath(binding);
  harnessRuntime.fixturePathsUsed.push(
    path.join(
      capabilityRoot(capabilityId),
      "fixtures",
      `${caseId}.json`,
    ),
  );

  const transport = createFixtureTransport(providerResponsePath);
  const adapter = new DeepSeekAdapter({
    transport,
    secretStore: createFixtureSecretStore(),
  });

  return composeWithPromptBuild(manifest, caseDef, promptBuild).then(
    (request) => {
      const outcome = adapter.invoke(request);
      const finalContent = extractFinalContent(outcome);
      const quality = scoreQuality(request, finalContent, expectation);
      const schema = scoreSchema(outcome, expectation);
      return {
        case_id: caseId,
        quality,
        schema,
      };
    },
  );
}

export async function runGoldenSuite(
  options: GoldenRunOptions = {},
): Promise<GoldenRunResult> {
  resetHarnessRuntime();

  const capabilityId = options.capabilityId ?? FIRST_CAPABILITY_ID;
  const promptBuild = options.promptBuild ?? "current";
  const runKind = options.runKind ?? "golden";
  const reportsDir =
    options.reportsDir ?? path.join(EVAL_ROOT, "reports");

  const caseIds = listCapabilityCases(capabilityId);
  const caseScores: CaseScore[] = [];

  for (const caseId of caseIds) {
    caseScores.push(await runCase(capabilityId, caseId, promptBuild));
  }

  const report: ScoreReport = {
    capability_id: capabilityId,
    run_kind: runKind,
    prompt_build: promptBuild,
    recorded_at: new Date().toISOString(),
    cases: caseScores,
    overall: deriveOverall(caseScores),
  };

  const reportPath = writeScoreReport(reportsDir, report);

  return {
    passed: report.overall === "pass",
    reportPath,
    report,
    fixturePathsUsed: [...harnessRuntime.fixturePathsUsed],
    capabilityIds: listEvalCapabilities(),
    usedLiveEgress: harnessRuntime.usedLiveEgress,
  };
}

export function getPinnedModelIdsFromRoutingPolicy(): string[] {
  const policy = readJson<{
    rules: Array<{ targets: Array<{ model_id: string }> }>;
  }>(ROUTING_POLICY_PATH);

  const modelIds = new Set<string>();
  for (const rule of policy.rules) {
    for (const target of rule.targets) {
      modelIds.add(target.model_id);
    }
  }
  return [...modelIds].sort();
}

export function getLiveSmokeModelTargets(): string[] {
  return getPinnedModelIdsFromRoutingPolicy();
}

export function getLiveSmokeWorkflowPath(): string {
  return path.resolve(
    AI_PLATFORM_ROOT,
    "..",
    ".github",
    "workflows",
    "ai-platform-eval-live-smoke.yml",
  );
}

export function readLiveSmokeWorkflowSchedule(): string | undefined {
  const workflowPath = getLiveSmokeWorkflowPath();
  const content = readFileSync(workflowPath, "utf8");
  const match = content.match(/schedule:\s*\n\s*-\s*cron:\s*['"]([^'"]+)['"]/);
  return match?.[1];
}

export function getHarnessRuntimeSnapshot(): HarnessRuntime {
  return { ...harnessRuntime };
}
