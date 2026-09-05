import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
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
import {
  GEMINI_API_KEY_BINDING,
  GeminiAdapter,
  type GeminiTransport,
} from "../../src/provider/gemini";
import {
  createProviderAdapter,
  type WiredProviderId,
} from "../../src/provider/wiring";
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
export { FIRST_CAPABILITY_ID, D5_FIXTURES_ROOT };
const KNOWN_FIXTURE_SECRET = "deepseek-eval-fixture-secret";

/** Known floating aliases that MUST NOT appear as routing-policy pins. */
export const FLOATING_MODEL_ALIASES = Object.freeze([
  "latest",
  "auto",
  "default",
  "deepseek-chat",
  "deepseek-reasoner",
  "gemini-1.5-flash",
  "gemini-1.5-pro",
]);

export type PromptBuild = "current" | "deliberately_regressed";
/** Fixture-response build: current recording vs deliberately-regressed body. */
export type FixtureBuild = "current" | "deliberately_regressed";
export type RunKind = "golden" | "live_smoke";

export type LiveSmokeTarget = {
  provider_id: WiredProviderId;
  model_id: string;
};

type CaseDefinition = {
  case_id: string;
  user_intent: string;
  context: Record<string, unknown>;
};

type FixtureBinding = {
  case_id: string;
  /**
   * D5 fixture subdirectory under `test/fixtures/deepseek/`.
   * Required when `eval_provider_response_file` is unset.
   */
  d5_fixture_subdir?: string;
  /** Filename under the D5 subdirectory (when using the D5 tree). */
  provider_response_file?: string;
  /**
   * Eval-owned recorded body relative to the capability `fixtures/` directory.
   * Used for negative / control cases that must not mutate the D5 tree.
   */
  eval_provider_response_file?: string;
  /**
   * Eval-owned deliberately-regressed body relative to capability `fixtures/`.
   * Selected when `fixtureBuild === "deliberately_regressed"`.
   */
  deliberately_regressed_response_file?: string;
};

export type ExpectationDefinition = {
  case_id: string;
  system_instruction_must_contain?: string[];
  output_must_contain?: string[];
  output_min_length?: number;
  output_mode?: "prose" | "structured";
  /** Optional path relative to the case capability root for composed-system golden. */
  request_system_golden_file?: string;
};

export type GoldenRunOptions = {
  capabilityId?: string;
  promptBuild?: PromptBuild;
  /** Defaults to `"current"`. Use `"deliberately_regressed"` for output-containment control. */
  fixtureBuild?: FixtureBuild;
  /** Optional case-id filter; defaults to every case under the capability. */
  caseIds?: string[];
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

export type LiveSmokeRunOptions = {
  capabilityId?: string;
  reportsDir?: string;
  /** Injected for tests; defaults to env-backed store. */
  secretStore?: SecretStorePort;
  /** Injected for tests; defaults to real HTTP transport. */
  transport?: SharedHttpTransport;
  /** When true (default), skip providers whose API key is missing. */
  skipMissingCredentials?: boolean;
};

export type LiveSmokeRunResult =
  | (GoldenRunResult & { skipped: false })
  | {
      skipped: true;
      reason: string;
      targets: LiveSmokeTarget[];
    };

type SharedHttpTransport = DeepSeekTransport & GeminiTransport;

type HarnessRuntime = {
  fixturePathsUsed: string[];
  usedLiveEgress: boolean;
  fixtureTransportUsed: boolean;
};

const harnessRuntime: HarnessRuntime = {
  fixturePathsUsed: [],
  usedLiveEgress: false,
  fixtureTransportUsed: false,
};

function resetHarnessRuntime(): void {
  harnessRuntime.fixturePathsUsed = [];
  harnessRuntime.usedLiveEgress = false;
  harnessRuntime.fixtureTransportUsed = false;
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
      routingPolicyRef: "routing/standard",
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
      perRequestTokenCeiling: 9_024,
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

function manifestForCapability(capabilityId: string): Manifest {
  if (capabilityId === FIRST_CAPABILITY_ID) {
    return visitSummaryManifest();
  }
  throw new Error(
    `No golden-suite manifest registered for capability "${capabilityId}"`,
  );
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
  if (!existsSync(casesDir)) {
    return [];
  }
  return readdirSync(casesDir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => name.replace(/\.json$/, ""))
    .sort();
}

export function listEvalCapabilities(): string[] {
  return readdirSync(EVAL_ROOT, { withFileTypes: true })
    .filter(
      (entry) =>
        entry.isDirectory() &&
        entry.name.includes(".") &&
        !["prompts", "reports"].includes(entry.name) &&
        // Golden-layout capabilities own an `expectations/` directory; sibling
        // eval capabilities under `test/eval/` that lack one are not runnable
        // by the golden runner and stay outside golden gating.
        existsSync(path.join(EVAL_ROOT, entry.name, "expectations")),
    )
    .map((entry) => entry.name)
    .sort();
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

function resolveEvalFixturePath(
  capabilityId: string,
  relativePath: string,
): string {
  return path.join(capabilityRoot(capabilityId), "fixtures", relativePath);
}

function resolveProviderResponsePath(
  capabilityId: string,
  binding: FixtureBinding,
  fixtureBuild: FixtureBuild = "current",
): string {
  if (fixtureBuild === "deliberately_regressed") {
    if (!binding.deliberately_regressed_response_file) {
      throw new Error(
        `No deliberately_regressed_response_file for ${capabilityId}/${binding.case_id}`,
      );
    }
    const regressedPath = resolveEvalFixturePath(
      capabilityId,
      binding.deliberately_regressed_response_file,
    );
    if (!existsSync(regressedPath)) {
      throw new Error(
        `Regressed fixture missing for ${capabilityId}/${binding.case_id}: ${regressedPath}`,
      );
    }
    harnessRuntime.fixturePathsUsed.push(regressedPath);
    return regressedPath;
  }

  if (binding.eval_provider_response_file) {
    const evalPath = resolveEvalFixturePath(
      capabilityId,
      binding.eval_provider_response_file,
    );
    if (!existsSync(evalPath)) {
      throw new Error(
        `Eval fixture missing for ${capabilityId}/${binding.case_id}: ${evalPath}`,
      );
    }
    harnessRuntime.fixturePathsUsed.push(evalPath);
    return evalPath;
  }

  if (!binding.d5_fixture_subdir || !binding.provider_response_file) {
    throw new Error(
      `Fixture binding for ${capabilityId}/${binding.case_id} needs d5_fixture_subdir + provider_response_file or eval_provider_response_file`,
    );
  }

  const d5Path = path.join(
    D5_FIXTURES_ROOT,
    binding.d5_fixture_subdir,
    binding.provider_response_file,
  );
  if (!existsSync(d5Path)) {
    throw new Error(
      `D5 fixture missing for ${capabilityId}/${binding.case_id}: ${d5Path}`,
    );
  }
  harnessRuntime.fixturePathsUsed.push(d5Path);
  return d5Path;
}

function createFixtureTransport(providerResponsePath: string): DeepSeekTransport {
  const body = readFileSync(providerResponsePath, "utf8");
  return {
    fetch(): DeepSeekTransportResponse {
      harnessRuntime.fixtureTransportUsed = true;
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

export function createEnvSecretStore(): SecretStorePort {
  return {
    getSecret(name: string): string | undefined {
      const value = process.env[name];
      return value && value.length > 0 ? value : undefined;
    },
  };
}

export function createHttpTransport(): SharedHttpTransport {
  return {
    async fetch(url, init): Promise<DeepSeekTransportResponse> {
      harnessRuntime.usedLiveEgress = true;
      const headers = new Headers();
      for (const [key, value] of Object.entries(init.headers ?? {})) {
        headers.set(key, value);
      }
      const response = await globalThis.fetch(url, {
        method: init.method,
        headers,
        body: init.body,
        signal: init.signal,
      });
      const responseHeaders: Record<string, string> = {};
      response.headers.forEach((value, key) => {
        responseHeaders[key] = value;
      });
      return {
        status: response.status,
        headers: responseHeaders,
        body: await response.text(),
      };
    },
  };
}

async function composeWithPromptBuild(
  manifest: Manifest,
  caseDef: CaseDefinition,
  promptBuild: PromptBuild,
): Promise<CanonicalRequest> {
  const principal = fixturePrincipal();

  // Always compose against the real production registry — never module-mock it.
  // A deliberately-regressed build swaps only the system-instruction artifact
  // text after composition so later "current" runs cannot leak a mock.
  const { composeRequest } = await import("../../src/prompt/composer");
  const composed = composeRequest({
    manifest,
    filteredContext: caseDef.context,
    userIntent: caseDef.user_intent,
    principal,
    requestReference: "EVAL-REQ-01",
    streamFlag: false,
  });
  if (!composed.ok) {
    throw new Error(
      `Failed to compose request with ${promptBuild} prompt build`,
    );
  }

  if (promptBuild === "current") {
    return composed.request;
  }

  const worseSystem = readFileSync(
    path.join(
      EVAL_ROOT,
      "prompts",
      "clinic.visit_summary.worse",
      "system.md",
    ),
    "utf8",
  );

  const parts = composed.request.parts.map((part, index) => {
    // First system part is the system-instruction artifact (composer order).
    if (index === 0 && part.role === "system") {
      return { ...part, content: worseSystem };
    }
    return part;
  });

  return {
    ...composed.request,
    parts,
  };
}

function extractFinalContent(outcome: ProviderInvokeResult): string {
  if (outcome.kind !== "success") {
    return "";
  }
  const content = outcome.result.finalContent;
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

function systemPartsText(composedRequest: CanonicalRequest): string {
  return composedRequest.parts
    .filter((part) => part.role === "system")
    .map((part) => part.content)
    .join("\n");
}

export function scoreQuality(
  composedRequest: CanonicalRequest,
  finalContent: string,
  expectation: ExpectationDefinition,
  capabilityId?: string,
): "pass" | "fail" {
  const systemParts = systemPartsText(composedRequest);

  for (const needle of expectation.system_instruction_must_contain ?? []) {
    if (!systemParts.toLowerCase().includes(needle.toLowerCase())) {
      return "fail";
    }
  }

  if (expectation.request_system_golden_file && capabilityId) {
    const goldenPath = path.join(
      capabilityRoot(capabilityId),
      expectation.request_system_golden_file,
    );
    const golden = readFileSync(goldenPath, "utf8").trim();
    if (systemParts.trim() !== golden) {
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

export function scoreSchema(
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
  fixtureBuild: FixtureBuild = "current",
): Promise<CaseScore> {
  const manifest = manifestForCapability(capabilityId);
  const caseDef = loadCase(capabilityId, caseId);
  const binding = loadFixtureBinding(capabilityId, caseId);
  const expectation = loadExpectation(capabilityId, caseId);

  const providerResponsePath = resolveProviderResponsePath(
    capabilityId,
    binding,
    fixtureBuild,
  );
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
    async (request) => {
      const outcome = await adapter.invoke(request);
      const finalContent = extractFinalContent(outcome);
      const quality = scoreQuality(
        request,
        finalContent,
        expectation,
        capabilityId,
      );
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
  const fixtureBuild = options.fixtureBuild ?? "current";
  const runKind = options.runKind ?? "golden";
  const reportsDir =
    options.reportsDir ?? path.join(EVAL_ROOT, "reports");

  const availableCaseIds = listCapabilityCases(capabilityId);
  const caseIds = options.caseIds
    ? options.caseIds.filter((caseId) => availableCaseIds.includes(caseId))
    : availableCaseIds;
  if (options.caseIds) {
    const missing = options.caseIds.filter(
      (caseId) => !availableCaseIds.includes(caseId),
    );
    if (missing.length > 0) {
      throw new Error(
        `Unknown golden case id(s) for ${capabilityId}: ${missing.join(", ")}`,
      );
    }
  }

  const caseScores: CaseScore[] = [];

  for (const caseId of caseIds) {
    caseScores.push(
      await runCase(capabilityId, caseId, promptBuild, fixtureBuild),
    );
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
    capabilityIds: [capabilityId],
    usedLiveEgress: harnessRuntime.usedLiveEgress,
  };
}

function secretBindingForProvider(providerId: WiredProviderId): string {
  return providerId === "deepseek"
    ? DEEPSEEK_API_KEY_BINDING
    : GEMINI_API_KEY_BINDING;
}

/**
 * Live-smoke quality floor: substantive prose that still reflects the visit-
 * summary capability (advisory framing + chief-complaint signal), not a
 * vacuous `min_length: 1` pass.
 */
function smokeExpectation(): ExpectationDefinition {
  return {
    case_id: "live_smoke",
    output_must_contain: ["advisory", "headache"],
    output_min_length: 40,
    output_mode: "prose",
  };
}

/** Exported for live-smoke / scorer tests that assert the smoke quality floor. */
export function getLiveSmokeExpectation(): ExpectationDefinition {
  return smokeExpectation();
}

async function runLiveSmokeCase(
  target: LiveSmokeTarget,
  capabilityId: string,
  secretStore: SecretStorePort,
  transport: SharedHttpTransport,
): Promise<CaseScore> {
  const caseIds = listCapabilityCases(capabilityId);
  if (caseIds.length === 0) {
    throw new Error(`Live smoke requires at least one case under ${capabilityId}`);
  }
  const caseId = caseIds[0]!;
  const manifest = manifestForCapability(capabilityId);
  const caseDef = loadCase(capabilityId, caseId);
  const request = await composeWithPromptBuild(manifest, caseDef, "current");

  const adapter = createProviderAdapter(target.provider_id, {
    transport,
    secretStore,
    modelId: target.model_id,
  } as ConstructorParameters<typeof DeepSeekAdapter>[0] &
    ConstructorParameters<typeof GeminiAdapter>[0]);

  const outcome = await adapter.invoke(request);
  if (
    outcome.kind === "success" &&
    outcome.result.providerModel.model !== target.model_id
  ) {
    return {
      case_id: `live_smoke.${target.provider_id}.${target.model_id}`,
      quality: "fail",
      schema: "fail",
    };
  }

  const finalContent = extractFinalContent(outcome);
  const expectation = smokeExpectation();
  return {
    case_id: `live_smoke.${target.provider_id}.${target.model_id}`,
    quality: scoreQuality(request, finalContent, expectation, capabilityId),
    schema: scoreSchema(outcome, expectation),
  };
}

export async function runLiveSmokeSuite(
  options: LiveSmokeRunOptions = {},
): Promise<LiveSmokeRunResult> {
  resetHarnessRuntime();

  const capabilityId = options.capabilityId ?? FIRST_CAPABILITY_ID;
  const reportsDir =
    options.reportsDir ?? path.join(EVAL_ROOT, "reports");
  const secretStore = options.secretStore ?? createEnvSecretStore();
  const transport = options.transport ?? createHttpTransport();
  const skipMissing = options.skipMissingCredentials ?? true;
  const targets = getLiveSmokeTargets();

  const runnable = targets.filter((target) => {
    const binding = secretBindingForProvider(target.provider_id);
    return Boolean(secretStore.getSecret(binding));
  });

  if (runnable.length === 0) {
    return {
      skipped: true,
      reason:
        "No provider API keys available for live smoke (DEEPSEEK_API_KEY / GEMINI_API_KEY)",
      targets,
    };
  }

  if (!skipMissing && runnable.length !== targets.length) {
    const missing = targets
      .filter((t) => !runnable.includes(t))
      .map((t) => t.provider_id);
    return {
      skipped: true,
      reason: `Missing credentials for providers: ${missing.join(", ")}`,
      targets,
    };
  }

  // Live-smoke is definitionally an egress path (real HTTP or injected test double).
  harnessRuntime.usedLiveEgress = true;

  const caseScores: CaseScore[] = [];
  for (const target of runnable) {
    caseScores.push(
      await runLiveSmokeCase(target, capabilityId, secretStore, transport),
    );
  }

  const report: ScoreReport = {
    capability_id: capabilityId,
    run_kind: "live_smoke",
    prompt_build: "current",
    recorded_at: new Date().toISOString(),
    cases: caseScores,
    overall: deriveOverall(caseScores),
  };
  const reportPath = writeScoreReport(reportsDir, report);

  return {
    skipped: false,
    passed: report.overall === "pass",
    reportPath,
    report,
    fixturePathsUsed: [...harnessRuntime.fixturePathsUsed],
    capabilityIds: [capabilityId],
    usedLiveEgress: harnessRuntime.usedLiveEgress,
  };
}

export function isPinnedModelId(modelId: string): boolean {
  const normalized = modelId.trim().toLowerCase();
  if (!normalized || normalized.includes(":")) {
    return false;
  }
  if (FLOATING_MODEL_ALIASES.some((alias) => alias.toLowerCase() === normalized)) {
    return false;
  }
  return true;
}

export function getLiveSmokeTargets(): LiveSmokeTarget[] {
  const policy = readJson<{
    rules: Array<{
      targets: Array<{ provider_id: string; model_id: string }>;
    }>;
  }>(ROUTING_POLICY_PATH);

  const seen = new Set<string>();
  const targets: LiveSmokeTarget[] = [];
  for (const rule of policy.rules) {
    for (const target of rule.targets) {
      const key = `${target.provider_id}:${target.model_id}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      if (target.provider_id !== "deepseek" && target.provider_id !== "gemini") {
        continue;
      }
      targets.push({
        provider_id: target.provider_id,
        model_id: target.model_id,
      });
    }
  }
  return targets.sort((a, b) =>
    `${a.provider_id}/${a.model_id}`.localeCompare(
      `${b.provider_id}/${b.model_id}`,
    ),
  );
}

/** @deprecated Prefer {@link getLiveSmokeTargets}; kept for callers that only need model ids. */
export function getPinnedModelIdsFromRoutingPolicy(): string[] {
  return [...new Set(getLiveSmokeTargets().map((t) => t.model_id))].sort();
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
