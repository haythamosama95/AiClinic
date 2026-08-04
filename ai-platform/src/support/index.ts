import type { Envelope } from "../journal";
import { normalizeRequestReference } from "../reference";
import {
  defaultRetentionClassResolver,
  isWithinDiagnosticRetention,
  type RetentionClassResolver,
} from "../retention";

export type SupportLookupRequestTrace = {
  requestId: string;
  requestReference: string;
  installationId: string;
  actorId: string;
  branchId: string | null;
  capabilityId: string;
  capabilityVersion: string;
  promptArtifactHash: string;
  state: string;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
  terminalErrorCode: string | null;
  traceId: string;
  payloadPointer: string | null;
};

export type SupportLookupAttemptTrace = {
  attemptNo: number;
  provider: string;
  model: string;
  outcome: string;
  latencyMs: number;
  tokensIn: number;
  tokensOut: number;
  cost: number;
  providerRequestId: string | null;
  errorCode: string | null;
};

export type SupportLookupResult =
  | { found: false }
  | {
      found: true;
      request: SupportLookupRequestTrace;
      attempts: SupportLookupAttemptTrace[];
      envelope: Envelope | null;
    };

export type SupportLookupBindings = {
  db: D1Database;
  r2: R2Bucket;
  now?: () => Date;
  resolveRetentionClass?: RetentionClassResolver;
};

type LookupRow = {
  request_id: string;
  request_reference: string;
  installation_id: string;
  actor_id: string;
  branch_id: string | null;
  capability_id: string;
  capability_version: string;
  prompt_artifact_hash: string;
  state: string;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
  terminal_error_code: string | null;
  trace_id: string;
  payload_pointer: string | null;
  attempt_no: number | null;
  provider: string | null;
  model: string | null;
  outcome: string | null;
  latency_ms: number | null;
  tokens_in: number | null;
  tokens_out: number | null;
  cost: number | null;
  provider_request_id: string | null;
  error_code: string | null;
};

const LOOKUP_SQL = `SELECT
  r.request_id, r.request_reference, r.installation_id, r.actor_id, r.branch_id,
  r.capability_id, r.capability_version, r.prompt_artifact_hash, r.state,
  r.created_at, r.updated_at, r.completed_at, r.terminal_error_code, r.trace_id,
  r.payload_pointer,
  a.attempt_no, a.provider, a.model, a.outcome, a.latency_ms,
  a.tokens_in, a.tokens_out, a.cost, a.provider_request_id, a.error_code
FROM ai_request r
LEFT JOIN ai_attempt a ON a.request_id = r.request_id
WHERE r.request_reference = ?`;

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

export async function supportLookup(
  reference: string,
  bindings: SupportLookupBindings,
): Promise<SupportLookupResult> {
  const normalized = normalizeRequestReference(reference);
  const now = bindings.now?.() ?? new Date();
  const resolveRetentionClass =
    bindings.resolveRetentionClass ?? defaultRetentionClassResolver();

  const result = await bindings.db.prepare(LOOKUP_SQL).bind(normalized).all<LookupRow>();
  const rows = result.results ?? [];

  if (rows.length === 0) {
    return { found: false };
  }

  const first = rows[0];
  const request: SupportLookupRequestTrace = {
    requestId: first.request_id,
    requestReference: first.request_reference,
    installationId: first.installation_id,
    actorId: first.actor_id,
    branchId: first.branch_id,
    capabilityId: first.capability_id,
    capabilityVersion: first.capability_version,
    promptArtifactHash: first.prompt_artifact_hash,
    state: first.state,
    createdAt: first.created_at,
    updatedAt: first.updated_at,
    completedAt: first.completed_at,
    terminalErrorCode: first.terminal_error_code,
    traceId: first.trace_id,
    payloadPointer: first.payload_pointer,
  };

  const attempts: SupportLookupAttemptTrace[] = [];
  for (const row of rows) {
    if (row.attempt_no === null) {
      continue;
    }
    attempts.push({
      attemptNo: row.attempt_no,
      provider: row.provider!,
      model: row.model!,
      outcome: row.outcome!,
      latencyMs: row.latency_ms!,
      tokensIn: row.tokens_in!,
      tokensOut: row.tokens_out!,
      cost: row.cost!,
      providerRequestId: row.provider_request_id,
      errorCode: row.error_code,
    });
  }

  const retentionClass = resolveRetentionClass(
    first.capability_id,
    first.capability_version,
  );
  const refTime = first.completed_at ?? first.created_at;
  const withinRetention = isWithinDiagnosticRetention(
    refTime,
    retentionClass,
    now,
  );

  let envelope: Envelope | null = null;
  if (withinRetention) {
    const pointer = first.payload_pointer ?? envelopeKey(first.request_id);
    const object = await bindings.r2.get(pointer);
    if (object) {
      envelope = JSON.parse(await object.text()) as Envelope;
    }
  }

  return { found: true, request, attempts, envelope };
}
