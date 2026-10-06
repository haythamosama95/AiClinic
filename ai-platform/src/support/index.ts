import { subscriptionRef } from "vendor-contracts";
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

export type SupportLookupListEntry = {
  request: SupportLookupRequestTrace;
  attempts: SupportLookupAttemptTrace[];
  envelope: Envelope | null;
};

export type SupportLookupListResult =
  | { found: false }
  | { found: true; requests: SupportLookupListEntry[] };

export type SupportLookupQuery =
  | string
  | {
      reference?: string;
      subscription_ref?: string;
      org_id?: string;
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

const LOOKUP_BY_REFERENCE_SQL = `SELECT
  r.request_id, r.request_reference, r.installation_id, r.actor_id, r.branch_id,
  r.capability_id, r.capability_version, r.prompt_artifact_hash, r.state,
  r.created_at, r.updated_at, r.completed_at, r.terminal_error_code, r.trace_id,
  r.payload_pointer,
  a.attempt_no, a.provider, a.model, a.outcome, a.latency_ms,
  a.tokens_in, a.tokens_out, a.cost, a.provider_request_id, a.error_code
FROM ai_request r
LEFT JOIN ai_attempt a ON a.request_id = r.request_id
WHERE r.request_reference = ?`;

const LOOKUP_BY_INSTALLATION_SQL = `SELECT
  r.request_id, r.request_reference, r.installation_id, r.actor_id, r.branch_id,
  r.capability_id, r.capability_version, r.prompt_artifact_hash, r.state,
  r.created_at, r.updated_at, r.completed_at, r.terminal_error_code, r.trace_id,
  r.payload_pointer,
  a.attempt_no, a.provider, a.model, a.outcome, a.latency_ms,
  a.tokens_in, a.tokens_out, a.cost, a.provider_request_id, a.error_code
FROM ai_request r
LEFT JOIN ai_attempt a ON a.request_id = r.request_id
WHERE r.installation_id = ?
ORDER BY r.created_at DESC, a.attempt_no ASC`;

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

function requestTraceFromRow(first: LookupRow): SupportLookupRequestTrace {
  return {
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
}

function attemptsFromRows(rows: LookupRow[]): SupportLookupAttemptTrace[] {
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
  return attempts;
}

async function loadEnvelopeIfWithinRetention(
  first: LookupRow,
  bindings: SupportLookupBindings,
  now: Date,
  resolveRetentionClass: RetentionClassResolver,
): Promise<Envelope | null> {
  const retentionClass = resolveRetentionClass(
    first.capability_id,
    first.capability_version,
  );
  const refTime = first.completed_at ?? first.created_at;
  if (!isWithinDiagnosticRetention(refTime, retentionClass, now)) {
    return null;
  }
  const pointer = first.payload_pointer ?? envelopeKey(first.request_id);
  const object = await bindings.r2.get(pointer);
  if (!object) {
    return null;
  }
  return JSON.parse(await object.text()) as Envelope;
}

function groupRowsByRequest(rows: LookupRow[]): LookupRow[][] {
  const byRequest = new Map<string, LookupRow[]>();
  for (const row of rows) {
    const group = byRequest.get(row.request_id) ?? [];
    group.push(row);
    byRequest.set(row.request_id, group);
  }
  return [...byRequest.values()];
}

async function buildSingleLookupFromRows(
  rows: LookupRow[],
  bindings: SupportLookupBindings,
): Promise<SupportLookupResult> {
  if (rows.length === 0) {
    return { found: false };
  }

  const now = bindings.now?.() ?? new Date();
  const resolveRetentionClass =
    bindings.resolveRetentionClass ?? defaultRetentionClassResolver();
  const first = rows[0];
  const envelope = await loadEnvelopeIfWithinRetention(
    first,
    bindings,
    now,
    resolveRetentionClass,
  );

  return {
    found: true,
    request: requestTraceFromRow(first),
    attempts: attemptsFromRows(rows),
    envelope,
  };
}

async function resolveInstallationId(
  db: D1Database,
  query: { subscription_ref?: string; org_id?: string },
): Promise<string | null> {
  if (query.org_id) {
    const row = await db
      .prepare(
        `SELECT installation_id FROM tenant_binding
         WHERE org_id = ? AND status = 'active'
         ORDER BY epoch DESC LIMIT 1`,
      )
      .bind(query.org_id)
      .first<{ installation_id: string }>();
    return row?.installation_id ?? null;
  }

  if (query.subscription_ref) {
    const bindings = await db
      .prepare(
        `SELECT org_id, installation_id FROM tenant_binding WHERE status = 'active'`,
      )
      .all<{ org_id: string; installation_id: string }>();
    for (const row of bindings.results ?? []) {
      const ref = await subscriptionRef(row.org_id);
      if (ref === query.subscription_ref) {
        return row.installation_id;
      }
    }
  }

  return null;
}

function normalizeQuery(
  query: SupportLookupQuery,
): { reference?: string; subscription_ref?: string; org_id?: string } {
  if (typeof query === "string") {
    return { reference: query };
  }
  return {
    reference:
      typeof query.reference === "string" ? query.reference : undefined,
    subscription_ref:
      typeof query.subscription_ref === "string"
        ? query.subscription_ref
        : undefined,
    org_id: typeof query.org_id === "string" ? query.org_id : undefined,
  };
}

export async function supportLookup(
  query: SupportLookupQuery,
  bindings: SupportLookupBindings,
): Promise<SupportLookupResult | SupportLookupListResult> {
  const normalized = normalizeQuery(query);
  const hasReference = normalized.reference !== undefined;
  const hasSubscription = normalized.subscription_ref !== undefined;
  const hasOrg = normalized.org_id !== undefined;

  if (!hasReference && !hasSubscription && !hasOrg) {
    return { found: false };
  }
  if (
    (hasReference ? 1 : 0) + (hasSubscription ? 1 : 0) + (hasOrg ? 1 : 0) >
    1
  ) {
    return { found: false };
  }

  if (hasReference) {
    const reference = normalizeRequestReference(normalized.reference!);
    const result = await bindings.db
      .prepare(LOOKUP_BY_REFERENCE_SQL)
      .bind(reference)
      .all<LookupRow>();
    return buildSingleLookupFromRows(result.results ?? [], bindings);
  }

  const installationId = await resolveInstallationId(bindings.db, normalized);
  if (!installationId) {
    return { found: false };
  }

  const result = await bindings.db
    .prepare(LOOKUP_BY_INSTALLATION_SQL)
    .bind(installationId)
    .all<LookupRow>();
  const rows = result.results ?? [];
  if (rows.length === 0) {
    return { found: true, requests: [] };
  }

  const now = bindings.now?.() ?? new Date();
  const resolveRetentionClass =
    bindings.resolveRetentionClass ?? defaultRetentionClassResolver();

  const requests: SupportLookupListEntry[] = [];
  for (const group of groupRowsByRequest(rows)) {
    const first = group[0];
    const envelope = await loadEnvelopeIfWithinRetention(
      first,
      bindings,
      now,
      resolveRetentionClass,
    );
    requests.push({
      request: requestTraceFromRow(first),
      attempts: attemptsFromRows(group),
      envelope,
    });
  }

  return { found: true, requests };
}
