import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { Principal } from "../../src/identity";
import { load, type Manifest } from "../../src/manifest";
import {
  validateContext,
  type TranscriptTurn,
  type ValidateResult,
} from "../../src/context/validator";
import {
  deriveConversationOverall,
  deriveRunOverallFromExpectations,
  matchesExpectedOutcome,
  writeConversationScoreReport,
  type ConversationCriterion,
  type ConversationExpectedOutcome,
  type ConversationScore,
  type ConversationScoreReport,
} from "./conversation-score-report";

export const CONVERSATION_CAPABILITY_ID = "clinic.chat_assistant";

const EVAL_ROOT = path.dirname(fileURLToPath(import.meta.url));

type AppendTurn =
  | { kind: "user"; text: string }
  | { kind: "context_resolved"; context: Record<string, unknown> };

type FixtureAssistantTurn =
  | {
      kind: "context_requested";
      requests: Array<{ key: string; arguments: Record<string, unknown> }>;
    }
  | { kind: "model"; text: string };

type LegDefinition = {
  fixture: string;
  append_before_fixture: AppendTurn[];
};

type CaseDefinition = {
  case_id: string;
  legs: LegDefinition[];
  scoring: {
    required_key_requests: string[];
    forbidden_resolved_keys: string[];
    expect_convergence: boolean;
  };
  expected_outcome: ConversationExpectedOutcome;
};

type FixtureLeg = {
  leg_id: string;
  assistant_turn: FixtureAssistantTurn;
};

type CapabilityFile = {
  capability_id: string;
  manifest: Record<string, unknown>;
};

export type LoadedConversationCapability = {
  capability_id: string;
  manifest: Manifest;
};

export type ConversationRunOptions = {
  capabilityId?: string;
  caseId?: string;
  reportsDir?: string;
};

export type ConversationRunResult = {
  passed: boolean;
  report: ConversationScoreReport;
  reportPath: string;
  fixturePathsUsed: string[];
};

type HarnessRuntime = {
  fixturePathsUsed: string[];
};

const harnessRuntime: HarnessRuntime = {
  fixturePathsUsed: [],
};

function resetHarnessRuntime(): void {
  harnessRuntime.fixturePathsUsed = [];
}

function readJson<T>(filePath: string): T {
  return JSON.parse(readFileSync(filePath, "utf8")) as T;
}

function capabilityRoot(capabilityId: string): string {
  return path.join(EVAL_ROOT, capabilityId);
}

function fixturePrincipal(): Principal {
  return Object.freeze({
    installationId: "inst-h4-eval-harness",
    organizationId: "org-h4-001",
    branchId: "branch-h4-001",
    actorId: "actor-h4-001",
    role: "clinician",
    scopes: Object.freeze(["ai.chat_assistant"]),
    jti: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
  });
}

export function loadConversationCapability(
  capabilityId: string,
): LoadedConversationCapability {
  const capabilityFile = readJson<CapabilityFile>(
    path.join(capabilityRoot(capabilityId), "capability.json"),
  );
  return {
    capability_id: capabilityFile.capability_id,
    manifest: load(capabilityFile.manifest),
  };
}

export function listConversationEvalCapabilities(): string[] {
  return readdirSync(EVAL_ROOT, { withFileTypes: true })
    .filter(
      (entry) =>
        entry.isDirectory() &&
        entry.name.includes(".") &&
        existsSync(path.join(EVAL_ROOT, entry.name, "capability.json")),
    )
    .map((entry) => entry.name)
    .sort();
}

export function listConversationCases(capabilityId: string): string[] {
  const casesDir = path.join(capabilityRoot(capabilityId), "cases");
  return readdirSync(casesDir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => name.replace(/\.json$/, ""))
    .sort();
}

export function loadCase(
  capabilityId: string,
  caseId: string,
): CaseDefinition {
  return readJson<CaseDefinition>(
    path.join(capabilityRoot(capabilityId), "cases", `${caseId}.json`),
  );
}

function loadFixtureLeg(
  capabilityId: string,
  fixtureRelativePath: string,
): FixtureLeg {
  const fixturePath = path.join(
    capabilityRoot(capabilityId),
    "fixtures",
    fixtureRelativePath,
  );
  harnessRuntime.fixturePathsUsed.push(fixturePath);
  return readJson<FixtureLeg>(fixturePath);
}

function appendTurnToTranscript(
  transcript: TranscriptTurn[],
  turn: AppendTurn,
): void {
  const turnOrdinal = transcript.length + 1;
  if (turn.kind === "user") {
    transcript.push({
      turn_ordinal: turnOrdinal,
      kind: "user",
      text: turn.text,
    });
    return;
  }

  const principal = fixturePrincipal();
  transcript.push({
    turn_ordinal: turnOrdinal,
    kind: "context_resolved",
    context: {
      org: principal.organizationId,
      branch: principal.branchId,
      ...turn.context,
    },
  });
}

function appendAssistantTurn(
  transcript: TranscriptTurn[],
  assistantTurn: FixtureAssistantTurn,
): void {
  const turnOrdinal = transcript.length + 1;
  if (assistantTurn.kind === "model") {
    transcript.push({
      turn_ordinal: turnOrdinal,
      kind: "model",
      text: assistantTurn.text,
    });
    return;
  }

  transcript.push({
    turn_ordinal: turnOrdinal,
    kind: "context_requested",
    requests: assistantTurn.requests,
  });
}

function collectRequestedKeys(transcript: TranscriptTurn[]): Set<string> {
  const requested = new Set<string>();
  for (const turn of transcript) {
    if (turn.kind !== "context_requested") {
      continue;
    }
    for (const request of turn.requests) {
      requested.add(request.key);
    }
  }
  return requested;
}

function lastAssistantTurn(
  transcript: TranscriptTurn[],
): TranscriptTurn | undefined {
  for (let index = transcript.length - 1; index >= 0; index -= 1) {
    const turn = transcript[index];
    if (turn?.kind === "model" || turn?.kind === "context_requested") {
      return turn;
    }
  }
  return undefined;
}

function scoreRightKeys(
  transcript: TranscriptTurn[],
  requiredKeyRequests: readonly string[],
): ConversationCriterion {
  const requested = collectRequestedKeys(transcript);
  for (const key of requiredKeyRequests) {
    if (!requested.has(key)) {
      return "fail";
    }
  }
  return "pass";
}

/**
 * permitted_set (§13.5 stay inside the permitted set):
 * fail when a context_requested key is outside permittedKeySet, or when a
 * forbidden key remains obtainable after H2's allowlist drop.
 * Independent of validation ok/fail (no criterion conflation).
 */
function scorePermittedSet(
  manifest: Manifest,
  transcript: TranscriptTurn[],
  forbiddenResolvedKeys: readonly string[],
  validation: ValidateResult,
): ConversationCriterion {
  const permittedKeySet = new Set(
    manifest["Context requirements"].permittedKeySet,
  );

  for (const turn of transcript) {
    if (turn.kind !== "context_requested") {
      continue;
    }
    for (const request of turn.requests) {
      if (!permittedKeySet.has(request.key)) {
        return "fail";
      }
    }
  }

  const obtainedKeys = new Set<string>();
  if (validation.ok) {
    for (const turn of validation.validatedTranscript ?? []) {
      if (turn.kind === "context_resolved") {
        for (const key of Object.keys(turn.context)) {
          obtainedKeys.add(key);
        }
      }
    }
  } else {
    // Validation failed (e.g. budget): still inspect the raw transcript's
    // resolved keys that would survive the allowlist filter, without treating
    // the validation failure itself as a permitted_set fail.
    for (const turn of transcript) {
      if (turn.kind !== "context_resolved") {
        continue;
      }
      for (const key of Object.keys(turn.context)) {
        if (permittedKeySet.has(key)) {
          obtainedKeys.add(key);
        }
      }
    }
  }

  for (const forbiddenKey of forbiddenResolvedKeys) {
    if (obtainedKeys.has(forbiddenKey)) {
      return "fail";
    }
  }

  return "pass";
}

/**
 * round_budget: H2 conversation_budget_exhausted fails the criterion; when
 * expect_convergence is true, the last assistant turn must be kind "model".
 */
function scoreRoundBudget(
  transcript: TranscriptTurn[],
  validation: ValidateResult,
  expectConvergence: boolean,
): ConversationCriterion {
  if (
    !validation.ok &&
    validation.code === "conversation_budget_exhausted"
  ) {
    return "fail";
  }

  if (expectConvergence) {
    const last = lastAssistantTurn(transcript);
    if (last?.kind !== "model") {
      return "fail";
    }
  }

  return "pass";
}

function runCase(
  capabilityId: string,
  caseId: string,
  manifest: Manifest,
): { score: ConversationScore; expected: ConversationExpectedOutcome } {
  const caseDef = loadCase(capabilityId, caseId);
  const transcript: TranscriptTurn[] = [];

  for (const leg of caseDef.legs) {
    for (const appendTurn of leg.append_before_fixture) {
      appendTurnToTranscript(transcript, appendTurn);
    }

    const fixtureLeg = loadFixtureLeg(capabilityId, leg.fixture);
    appendAssistantTurn(transcript, fixtureLeg.assistant_turn);
  }

  const principal = fixturePrincipal();
  const legTurnOrdinal = transcript.length + 1;
  const validation = validateContext(
    manifest,
    {
      org: principal.organizationId,
      branch: principal.branchId,
    },
    principal,
    { transcript, legTurnOrdinal },
  );

  const rightKeys = scoreRightKeys(
    transcript,
    caseDef.scoring.required_key_requests,
  );
  const permittedSet = scorePermittedSet(
    manifest,
    transcript,
    caseDef.scoring.forbidden_resolved_keys,
    validation,
  );
  const roundBudget = scoreRoundBudget(
    transcript,
    validation,
    caseDef.scoring.expect_convergence,
  );

  const score: ConversationScore = {
    case_id: caseId,
    right_keys: rightKeys,
    permitted_set: permittedSet,
    round_budget: roundBudget,
    overall: "fail",
  };
  score.overall = deriveConversationOverall(score);
  return { score, expected: caseDef.expected_outcome };
}

export async function runConversationSuite(
  options: ConversationRunOptions = {},
): Promise<ConversationRunResult> {
  resetHarnessRuntime();

  const capabilityId = options.capabilityId ?? CONVERSATION_CAPABILITY_ID;
  const reportsDir =
    options.reportsDir ?? path.join(EVAL_ROOT, "reports");
  const { manifest } = loadConversationCapability(capabilityId);

  const caseIds = options.caseId
    ? [options.caseId]
    : listConversationCases(capabilityId);

  const results: Array<{
    score: ConversationScore;
    expected: ConversationExpectedOutcome;
  }> = [];
  for (const caseId of caseIds) {
    results.push(runCase(capabilityId, caseId, manifest));
  }

  const conversations = results.map((entry) => entry.score);
  const report: ConversationScoreReport = {
    capability_id: capabilityId,
    run_kind: "conversation",
    recorded_at: new Date().toISOString(),
    conversations,
    overall: deriveRunOverallFromExpectations(results),
  };

  const reportPath = writeConversationScoreReport(reportsDir, report);

  return {
    passed: report.overall === "pass",
    reportPath,
    report,
    fixturePathsUsed: [...harnessRuntime.fixturePathsUsed],
  };
}

export function getConversationHarnessRuntimeSnapshot(): HarnessRuntime {
  return { ...harnessRuntime };
}

export {
  matchesExpectedOutcome,
  deriveRunOverallFromExpectations,
};
