import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { Principal } from "../../src/identity";
import { load, type Manifest } from "../../src/manifest";
import {
  validateContext,
  type TranscriptTurn,
} from "../../src/context/validator";
import {
  deriveConversationOverall,
  deriveRunOverall,
  writeConversationScoreReport,
  type ConversationCriterion,
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
  usedLiveEgress: boolean;
  fixturePathsUsed: string[];
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

function loadCase(capabilityId: string, caseId: string): CaseDefinition {
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

  transcript.push({
    turn_ordinal: turnOrdinal,
    kind: "context_resolved",
    context: turn.context,
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

function scorePermittedSet(
  manifest: Manifest,
  transcript: TranscriptTurn[],
  forbiddenResolvedKeys: readonly string[],
  suppliedContext: Record<string, unknown>,
): ConversationCriterion {
  const legTurnOrdinal = transcript.length + 1;
  const validation = validateContext(
    manifest,
    suppliedContext,
    fixturePrincipal(),
    { transcript, legTurnOrdinal },
  );

  if (!validation.ok) {
    return "fail";
  }

  const obtainedKeys = new Set(Object.keys(validation.filteredContext));
  for (const turn of validation.validatedTranscript ?? []) {
    if (turn.kind === "context_resolved") {
      for (const key of Object.keys(turn.context)) {
        obtainedKeys.add(key);
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

function scoreRoundBudget(
  manifest: Manifest,
  transcript: TranscriptTurn[],
  suppliedContext: Record<string, unknown>,
): ConversationCriterion {
  const legTurnOrdinal = transcript.length + 1;
  const validation = validateContext(
    manifest,
    suppliedContext,
    fixturePrincipal(),
    { transcript, legTurnOrdinal },
  );

  if (!validation.ok) {
    return "fail";
  }

  return "pass";
}

function runCase(
  capabilityId: string,
  caseId: string,
  manifest: Manifest,
): ConversationScore {
  const caseDef = loadCase(capabilityId, caseId);
  const transcript: TranscriptTurn[] = [];
  let suppliedContext: Record<string, unknown> = {};

  for (const leg of caseDef.legs) {
    for (const appendTurn of leg.append_before_fixture) {
      appendTurnToTranscript(transcript, appendTurn);
    }

    const fixtureLeg = loadFixtureLeg(capabilityId, leg.fixture);
    appendAssistantTurn(transcript, fixtureLeg.assistant_turn);
  }

  const legTurnOrdinal = transcript.length + 1;
  const validation = validateContext(
    manifest,
    suppliedContext,
    fixturePrincipal(),
    { transcript, legTurnOrdinal },
  );

  if (validation.ok) {
    suppliedContext = validation.filteredContext;
  }

  const rightKeys = scoreRightKeys(
    transcript,
    caseDef.scoring.required_key_requests,
  );
  const permittedSet = scorePermittedSet(
    manifest,
    transcript,
    caseDef.scoring.forbidden_resolved_keys,
    suppliedContext,
  );
  const roundBudget = scoreRoundBudget(manifest, transcript, suppliedContext);

  const score: ConversationScore = {
    case_id: caseId,
    right_keys: rightKeys,
    permitted_set: permittedSet,
    round_budget: roundBudget,
    overall: "fail",
  };
  score.overall = deriveConversationOverall(score);
  return score;
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

  const conversations: ConversationScore[] = [];
  for (const caseId of caseIds) {
    conversations.push(runCase(capabilityId, caseId, manifest));
  }

  const report: ConversationScoreReport = {
    capability_id: capabilityId,
    run_kind: "conversation",
    recorded_at: new Date().toISOString(),
    conversations,
    overall: deriveRunOverall(conversations),
  };

  const reportPath = writeConversationScoreReport(reportsDir, report);

  return {
    passed: report.overall === "pass",
    reportPath,
    report,
    fixturePathsUsed: [...harnessRuntime.fixturePathsUsed],
    usedLiveEgress: harnessRuntime.usedLiveEgress,
  };
}

export function getConversationHarnessRuntimeSnapshot(): HarnessRuntime {
  return { ...harnessRuntime };
}
