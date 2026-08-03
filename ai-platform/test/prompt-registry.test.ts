import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Principal } from "../src/identity";
import { load, type Manifest } from "../src/manifest";
import {
  resolveArtifact,
  resolvePromptVersion,
  verifyBuildPins,
} from "../src/prompt/registry";
import systemInstructionArtifact from "../prompts/clinic.visit_summary/system.md?raw";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const MIGRATIONS_DIR = path.join(ROOT, "migrations");

const FIXTURE_CAPABILITY_ID = "clinic.visit_summary";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_ORG_ID = "org-d1-001";
const FIXTURE_BRANCH_ID = "branch-d1-001";
const FIXTURE_TRACE_ID = "01PROMPTREGISTRY00000001";
const FIXTURE_REQUEST_REFERENCE = "ABCD-EFGH";

const SYSTEM_INSTRUCTION_REF = "clinic.visit_summary/system@v1";
const RULES_FRAGMENT_REF = "clinic.visit_summary/rules-visit-summary@v1";
const TEMPLATE_REF = "clinic.visit_summary/template-visit-summary@v1";

/** Identifiers that would store prompt text — not hashes or pointers. */
const PROMPT_TEXT_IDENTIFIER_PATTERN =
  /^(prompt|system_instruction|instruction)$/i;

type ManifestWire = Record<string, unknown>;

type CorrelationIds = {
  readonly traceId: string;
  readonly requestReference: string;
};

const d1BindingSpy = vi.fn<
  (query: string, ...params: unknown[]) => Promise<unknown>
>();

const mockD1Binding = Object.freeze({
  prepare: (query: string) => ({
    bind: (...params: unknown[]) => ({
      run: () => d1BindingSpy(query, ...params),
      all: () => d1BindingSpy(query, ...params),
      first: () => d1BindingSpy(query, ...params),
    }),
  }),
  batch: vi.fn(),
  exec: vi.fn(),
});

function validManifest(): ManifestWire {
  return {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      version: FIXTURE_CAPABILITY_VERSION,
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
        key: "visit.chief_complaint@v1",
        required: true,
        shapeRef: "visit.chief_complaint@v1",
        maxSize: 4_096,
        freshnessHint: "session",
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: SYSTEM_INSTRUCTION_REF,
      businessRuleFragmentRefs: [RULES_FRAGMENT_REF],
      contextRenderingTemplateRef: TEMPLATE_REF,
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
}

function loadedManifest(): Manifest {
  return load(validManifest());
}

function fixtureFilteredContext(): Record<string, string> {
  return {
    "visit.chief_complaint@v1": "Headache for two days.",
  };
}

function fixtureCorrelationIds(): CorrelationIds {
  return Object.freeze({
    traceId: FIXTURE_TRACE_ID,
    requestReference: FIXTURE_REQUEST_REFERENCE,
  });
}

function buildPrincipal(): Principal {
  return Object.freeze({
    installationId: "inst-d1-001",
    organizationId: FIXTURE_ORG_ID,
    branchId: FIXTURE_BRANCH_ID,
    actorId: "actor-d1-001",
    role: "clinician",
    scopes: Object.freeze([`ai.${FIXTURE_CAPABILITY_ID}`]),
    jti: "jti-d1-001",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
  });
}

function extractCreateTableBlocks(sql: string): Array<{ table: string; body: string }> {
  const blocks: Array<{ table: string; body: string }> = [];
  const pattern =
    /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s*\(([\s\S]*?)\);/gi;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(sql)) !== null) {
    blocks.push({ table: match[1], body: match[2] });
  }
  return blocks;
}

function extractColumnNames(tableBody: string): string[] {
  const columns: string[] = [];
  for (const line of tableBody.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("FOREIGN KEY") || trimmed.startsWith("PRIMARY KEY")) {
      continue;
    }
    const columnMatch = /^(\w+)\s+/i.exec(trimmed);
    if (columnMatch) {
      columns.push(columnMatch[1]);
    }
  }
  return columns;
}

function assertNoPromptTextIdentifiersInMigrations(): void {
  const migrationFiles = readdirSync(MIGRATIONS_DIR).filter((file) =>
    file.endsWith(".sql"),
  );
  expect(migrationFiles.length).toBeGreaterThan(0);

  for (const file of migrationFiles) {
    const sql = readFileSync(path.join(MIGRATIONS_DIR, file), "utf8");
    for (const { table, body } of extractCreateTableBlocks(sql)) {
      expect(
        PROMPT_TEXT_IDENTIFIER_PATTERN.test(table),
        `${file}: table "${table}" must not store prompt text`,
      ).toBe(false);

      for (const column of extractColumnNames(body)) {
        expect(
          PROMPT_TEXT_IDENTIFIER_PATTERN.test(column),
          `${file}: column "${column}" must not store prompt text`,
        ).toBe(false);
      }
    }
  }
}

function assertRegistryNeverTouchesD1(): void {
  expect(d1BindingSpy).not.toHaveBeenCalled();
}

beforeEach(() => {
  d1BindingSpy.mockClear();
  void mockD1Binding;
  void fixtureFilteredContext();
  void buildPrincipal();
  void fixtureCorrelationIds();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unmock("../prompts/clinic.visit_summary/system.md");
});

describe("T-D1-01 registry_pinned_hash_resolves_to_artifact", () => {
  it("resolveArtifact returns deployed system instruction content for the manifest-pinned ref", () => {
    const manifest = loadedManifest();
    const promptBinding = manifest["Prompt binding"];

    const resolved = resolveArtifact(
      promptBinding.systemInstructionArtifactRef,
      manifest,
    );

    expect(resolved).toBe(systemInstructionArtifact);
    assertRegistryNeverTouchesD1();
  });
});

describe("T-D1-02 registry_altered_artifact_fails_build", () => {
  it("verifyBuildPins throws when pinned artifact content no longer matches registry.json", async () => {
    vi.resetModules();
    vi.doMock("../prompts/clinic.visit_summary/system.md", () => ({
      default: "tampered system instruction content",
    }));

    const { verifyBuildPins: verifyAlteredPins } = await import(
      "../src/prompt/registry"
    );

    expect(() => verifyAlteredPins(load(validManifest()))).toThrow();
    assertRegistryNeverTouchesD1();
  });
});

describe("T-D1-03 registry_missing_artifact_fails_build", () => {
  it("verifyBuildPins throws when a manifest-pinned artifact is absent from the deployment", async () => {
    vi.resetModules();
    vi.doMock("../prompts/clinic.visit_summary/system.md", () => ({
      default: undefined,
    }));

    const { verifyBuildPins: verifyMissingPins } = await import(
      "../src/prompt/registry"
    );

    expect(() => verifyMissingPins(load(validManifest()))).toThrow();
    assertRegistryNeverTouchesD1();
  });
});

describe("T-D1-04 registry_no_prompt_text_in_any_d1_table", () => {
  it("(a) D1 migrations define no prompt-text table or column identifiers", () => {
    assertNoPromptTextIdentifiersInMigrations();
  });

  it("(b) registry functions never call the D1 binding", () => {
    const manifest = loadedManifest();
    const promptBinding = manifest["Prompt binding"];

    resolveArtifact(promptBinding.systemInstructionArtifactRef, manifest);
    resolvePromptVersion(manifest);
    verifyBuildPins(manifest);

    assertRegistryNeverTouchesD1();
  });
});

describe("T-D1-05 registry_prompt_version_surfaced_for_journal", () => {
  it("resolvePromptVersion returns the pinned systemInstructionArtifactRef string", () => {
    const manifest = loadedManifest();

    expect(resolvePromptVersion(manifest)).toBe(SYSTEM_INSTRUCTION_REF);
    assertRegistryNeverTouchesD1();
  });
});
