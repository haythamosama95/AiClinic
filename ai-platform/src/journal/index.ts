import type { CanonicalResult } from "../contracts/canonical";
import type { TaxonomyCode } from "../errors";
import type { Principal } from "../identity";
import type { Manifest } from "../manifest";
import { normalizeRequestReference } from "../reference";
import { generateUlid } from "../trace";

export type TransitionState =
  | "Accepted"
  | "Composing"
  | "Invoking"
  | "Streaming"
  | "Validating"
  | "Repairing"
  | "AwaitingContext"
  | "Completed"
  | "Failed"
  | "Cancelled";

export type RequestRowInput = {
  requestId: string;
  requestReference: string;
  principal: Principal;
  manifest: Manifest;
  idempotencyKey: string;
  traceId: string;
  conversationId?: string | null;
  turnOrdinal?: number | null;
  routingTier?: "standard" | "degraded";
};

export type AttemptInput = {
  attemptNo: number;
  provider: string;
  model: string;
  outcome: string;
  latencyMs: number;
  tokensIn: number;
  tokensOut: number;
  cost: number;
  providerRequestId?: string;
  errorCode?: TaxonomyCode;
  rawBody: unknown;
};

export type PostResponseInput = {
  requestId: string;
  installationId: string;
  period: string;
  quotaWeight: number;
  totalTokens: number;
  totalCost: number;
  filteredContext: Record<string, unknown>;
  composedPrompt: unknown;
  attempts: AttemptInput[];
  validatedResult: CanonicalResult;
  recordedAt: string;
};

export type Envelope = {
  context: Record<string, unknown>;
  prompt: unknown;
  attempts: unknown[];
  result: CanonicalResult;
};

export type GetRequestResult =
  | { found: true; state: "Completed"; result: CanonicalResult }
  | { found: true; state: "Failed"; terminalErrorCode: TaxonomyCode }
  | { found: true; state: "Cancelled" }
  | { found: false };

type CreateRequestRowResult =
  | { ok: true }
  | { ok: false; code: "internal_error" };

type WritePostResponseBindings = {
  db: D1Database;
  r2: R2Bucket;
  ctx: { waitUntil(promise: Promise<unknown>): void };
};

type GetRequestBindings = {
  db: D1Database;
  r2: R2Bucket;
};

const TERMINAL_TRANSITION_STATES = new Set<TransitionState>([
  "Completed",
  "Failed",
  "Cancelled",
  "AwaitingContext",
]);

/** In-isolate guard-rejection tally keyed by time bucket + dimension set (§4.3.12). */
const guardRejectionTally = new Map<string, number>();

function currentTimeBucket(now = new Date()): string {
  const iso = now.toISOString();
  return `${iso.slice(0, 16)}:00`;
}

function dimensionSetFor(errorCode: string, installationId: string): string {
  return JSON.stringify({
    error_code: errorCode,
    installation_id: installationId,
  });
}

function tallyMapKey(timeBucket: string, dimensionSet: string): string {
  return `${timeBucket}\0${dimensionSet}`;
}

async function counterIdFor(
  dimensionSet: string,
  timeBucket: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${timeBucket}:${dimensionSet}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

function buildEnvelope(input: PostResponseInput): string {
  const envelope: Envelope = {
    context: input.filteredContext,
    prompt: input.composedPrompt,
    attempts: input.attempts.map((attempt) => attempt.rawBody),
    result: input.validatedResult,
  };
  return JSON.stringify(envelope);
}

export async function createRequestRow(
  input: RequestRowInput,
  db: D1Database,
): Promise<CreateRequestRowResult> {
  const now = new Date().toISOString();
  const isSingleShot =
    input.manifest.Interaction.interactionMode === "single_shot";
  const conversationId = isSingleShot
    ? null
    : (input.conversationId ?? null);
  const turnOrdinal = isSingleShot ? null : (input.turnOrdinal ?? null);

  try {
    await db
      .prepare(
        `INSERT INTO ai_request (
          request_id, request_reference, installation_id, actor_id, branch_id,
          capability_id, capability_version, prompt_artifact_hash, idempotency_key,
          trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
          payload_pointer, conversation_id, turn_ordinal, routing_tier
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, ?, ?)`,
      )
      .bind(
        input.requestId,
        input.requestReference,
        input.principal.installationId,
        input.principal.actorId,
        input.principal.branchId,
        input.manifest.Identity.capabilityId,
        input.manifest.Identity.version,
        input.manifest["Prompt binding"].systemInstructionArtifactRef,
        input.idempotencyKey,
        input.traceId,
        "Accepted",
        now,
        now,
        conversationId,
        turnOrdinal,
        input.routingTier ?? null,
      )
      .run();
    return { ok: true };
  } catch {
    return { ok: false, code: "internal_error" };
  }
}

export async function journalTransition(
  requestId: string,
  state: TransitionState,
  now: string,
  db: D1Database,
): Promise<void> {
  if (TERMINAL_TRANSITION_STATES.has(state)) {
    await db
      .prepare(
        `UPDATE ai_request
         SET state = ?, updated_at = ?, completed_at = ?
         WHERE request_id = ?`,
      )
      .bind(state, now, now, requestId)
      .run();
    return;
  }

  await db
    .prepare(
      `UPDATE ai_request SET state = ?, updated_at = ? WHERE request_id = ?`,
    )
    .bind(state, now, requestId)
    .run();
}

export async function recordTerminalState(
  requestId: string,
  state: TransitionState,
  terminalErrorCode: TaxonomyCode | undefined,
  now: string,
  db: D1Database,
): Promise<void> {
  if (state === "Failed") {
    await db
      .prepare(
        `UPDATE ai_request
         SET state = ?, updated_at = ?, completed_at = ?, terminal_error_code = ?
         WHERE request_id = ?`,
      )
      .bind(state, now, now, terminalErrorCode ?? null, requestId)
      .run();
    return;
  }

  await db
    .prepare(
      `UPDATE ai_request
       SET state = ?, updated_at = ?, completed_at = ?
       WHERE request_id = ?`,
    )
    .bind(state, now, now, requestId)
    .run();
}

async function persistPostResponseDetail(
  input: PostResponseInput,
  db: D1Database,
  r2: R2Bucket,
): Promise<void> {
  for (const attempt of input.attempts) {
    await db
      .prepare(
        `INSERT INTO ai_attempt (
          attempt_id, request_id, attempt_no, provider, model, outcome,
          latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        generateUlid(),
        input.requestId,
        attempt.attemptNo,
        attempt.provider,
        attempt.model,
        attempt.outcome,
        attempt.latencyMs,
        attempt.tokensIn,
        attempt.tokensOut,
        attempt.cost,
        attempt.providerRequestId ?? null,
        attempt.errorCode ?? null,
      )
      .run();
  }

  await db
    .prepare(
      `INSERT INTO usage_event (
        usage_event_id, installation_id, period, request_id,
        quota_weight, tokens, cost, recorded_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      generateUlid(),
      input.installationId,
      input.period,
      input.requestId,
      input.quotaWeight,
      input.totalTokens,
      input.totalCost,
      input.recordedAt,
    )
    .run();

  const key = envelopeKey(input.requestId);
  await r2.put(key, buildEnvelope(input));

  await db
    .prepare(`UPDATE ai_request SET payload_pointer = ? WHERE request_id = ?`)
    .bind(key, input.requestId)
    .run();
}

export function writePostResponseDetail(
  input: PostResponseInput,
  bindings: WritePostResponseBindings,
): void {
  bindings.ctx.waitUntil(
    persistPostResponseDetail(input, bindings.db, bindings.r2).catch(
      () => undefined,
    ),
  );
}

type AiRequestLookupRow = {
  request_id: string;
  state: string;
  terminal_error_code: string | null;
  payload_pointer: string | null;
};

export async function getRequest(
  reference: string,
  bindings: GetRequestBindings,
): Promise<GetRequestResult> {
  const normalized = normalizeRequestReference(reference);
  const row = await bindings.db
    .prepare(
      `SELECT request_id, state, terminal_error_code, payload_pointer
       FROM ai_request WHERE request_reference = ?`,
    )
    .bind(normalized)
    .first<AiRequestLookupRow>();

  if (!row) {
    return { found: false };
  }

  if (row.state === "Completed") {
    const pointer = row.payload_pointer ?? envelopeKey(row.request_id);
    const object = await bindings.r2.get(pointer);
    if (!object) {
      return { found: false };
    }
    const envelope = JSON.parse(await object.text()) as Envelope;
    return {
      found: true,
      state: "Completed",
      result: envelope.result,
    };
  }

  if (row.state === "Failed") {
    return {
      found: true,
      state: "Failed",
      terminalErrorCode: row.terminal_error_code as TaxonomyCode,
    };
  }

  if (row.state === "Cancelled") {
    return { found: true, state: "Cancelled" };
  }

  return { found: false };
}

export function recordGuardRejection(input: {
  installationId: string;
  errorCode: string;
  traceId: string;
}): void {
  void input.traceId;
  const timeBucket = currentTimeBucket();
  const dimensionSet = dimensionSetFor(
    input.errorCode,
    input.installationId,
  );
  const key = tallyMapKey(timeBucket, dimensionSet);
  guardRejectionTally.set(key, (guardRejectionTally.get(key) ?? 0) + 1);
}

export async function flushGuardRejectionCounters(bindings: {
  DB: D1Database;
}): Promise<void> {
  if (guardRejectionTally.size === 0) {
    return;
  }

  for (const [mapKey, count] of guardRejectionTally) {
    const separator = mapKey.indexOf("\0");
    const timeBucket = mapKey.slice(0, separator);
    const dimensionSet = mapKey.slice(separator + 1);
    const counterId = await counterIdFor(dimensionSet, timeBucket);

    await bindings.DB.prepare(
      `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(counter_id) DO UPDATE SET count = count + excluded.count`,
    )
      .bind(counterId, dimensionSet, timeBucket, count)
      .run();
  }

  guardRejectionTally.clear();
}
