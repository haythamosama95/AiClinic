import { buildErrorBody, type TaxonomyCode } from "../errors";
import {
  EnrolledKeyVerifier,
  type Principal,
} from "../identity";
import type { InteractionMode, Manifest } from "../manifest";
import {
  generateRequestReference,
  normalizeRequestReference,
} from "../reference";
import { generateUlid } from "../trace";
import { ConfigCache, createD1ConfigReader } from "../config-cache";
import type { CanonicalResult } from "../contracts/canonical";

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
  | { found: true; state: "Completed"; resultMissing: true }
  | { found: true; state: "Failed"; terminalErrorCode: TaxonomyCode }
  | { found: true; state: "Cancelled" }
  | { found: true; state: "AwaitingContext" }
  | { found: true; state: TransitionState; pending: true }
  | { found: false };

type CreateRequestRowResult =
  | { ok: true }
  | {
      ok: false;
      code: "internal_error";
      request_reference: string;
      trace_id: string;
    };

type WritePostResponseBindings = {
  db: D1Database;
  r2: R2Bucket;
  ctx: { waitUntil(promise: Promise<unknown>): void };
};

type GetRequestBindings = {
  db: D1Database;
  r2: R2Bucket;
};

export type GetRequestOptions = {
  installationId?: string;
};

const TERMINAL_TRANSITION_STATES = new Set<TransitionState>([
  "Completed",
  "Failed",
  "Cancelled",
  "AwaitingContext",
]);

const KNOWN_TRANSITION_STATES = new Set<TransitionState>([
  "Accepted",
  "Composing",
  "Invoking",
  "Streaming",
  "Validating",
  "Repairing",
  "AwaitingContext",
  "Completed",
  "Failed",
  "Cancelled",
]);

/** SQL fragment: refuse writes once a terminal state is reached (§6.3). */
const TERMINAL_IMMUTABLE_WHERE =
  "request_id = ? AND state NOT IN ('Completed','Failed','Cancelled','AwaitingContext')";

export const JOURNAL_TERMINAL_IMMUTABLE_STATES: readonly TransitionState[] = [
  "Completed",
  "Failed",
  "Cancelled",
  "AwaitingContext",
];

export function isJournalTerminalState(state: TransitionState): boolean {
  return TERMINAL_TRANSITION_STATES.has(state);
}

export function isJournalTransitionAllowed(
  from: TransitionState,
  to: TransitionState,
): boolean {
  if (TERMINAL_TRANSITION_STATES.has(from)) {
    return false;
  }
  return true;
}

export function canReachAwaitingContext(
  interactionMode: InteractionMode,
): boolean {
  return interactionMode === "conversational";
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

function isTransitionState(value: string): value is TransitionState {
  return KNOWN_TRANSITION_STATES.has(value as TransitionState);
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
    const body = buildErrorBody({
      code: "internal_error",
      requestReference: input.requestReference,
      traceId: input.traceId,
    });
    return {
      ok: false,
      code: "internal_error",
      request_reference: body.request_reference,
      trace_id: body.trace_id,
    };
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
         WHERE ${TERMINAL_IMMUTABLE_WHERE}`,
      )
      .bind(state, now, now, requestId)
      .run();
    return;
  }

  await db
    .prepare(
      `UPDATE ai_request SET state = ?, updated_at = ?
       WHERE ${TERMINAL_IMMUTABLE_WHERE}`,
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
    if (terminalErrorCode === undefined) {
      throw new Error("Failed terminal state requires terminalErrorCode");
    }
    await db
      .prepare(
        `UPDATE ai_request
         SET state = ?, updated_at = ?, completed_at = ?, terminal_error_code = ?
         WHERE ${TERMINAL_IMMUTABLE_WHERE}`,
      )
      .bind(state, now, now, terminalErrorCode, requestId)
      .run();
    return;
  }

  await db
    .prepare(
      `UPDATE ai_request
       SET state = ?, updated_at = ?, completed_at = ?
       WHERE ${TERMINAL_IMMUTABLE_WHERE}`,
    )
    .bind(state, now, now, requestId)
    .run();
}

async function persistPostResponseDetail(
  input: PostResponseInput,
  db: D1Database,
  r2: R2Bucket,
): Promise<void> {
  const statements: D1PreparedStatement[] = input.attempts.map((attempt) =>
    db
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
      ),
  );

  statements.push(
    db
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
      ),
  );

  await db.batch(statements);

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
      (err) => {
        console.error("stage16_post_response_detail_failed", {
          request_id: input.requestId,
          error: err instanceof Error ? err.message : String(err),
        });
      },
    ),
  );
}

type AiRequestLookupRow = {
  request_id: string;
  installation_id: string;
  state: string;
  terminal_error_code: string | null;
  payload_pointer: string | null;
};

export async function getRequest(
  reference: string,
  bindings: GetRequestBindings,
  options?: GetRequestOptions,
): Promise<GetRequestResult> {
  const normalized = normalizeRequestReference(reference);
  const row = await bindings.db
    .prepare(
      `SELECT request_id, installation_id, state, terminal_error_code, payload_pointer
       FROM ai_request WHERE request_reference = ?`,
    )
    .bind(normalized)
    .first<AiRequestLookupRow>();

  if (!row) {
    return { found: false };
  }

  if (
    options?.installationId !== undefined &&
    row.installation_id !== options.installationId
  ) {
    return { found: false };
  }

  if (row.state === "Completed") {
    if (row.payload_pointer === null) {
      return { found: true, state: "Completed", resultMissing: true };
    }

    const object = await bindings.r2.get(row.payload_pointer);
    if (!object) {
      return { found: true, state: "Completed", resultMissing: true };
    }

    try {
      const envelope = JSON.parse(await object.text()) as Envelope;
      return {
        found: true,
        state: "Completed",
        result: envelope.result,
      };
    } catch {
      return { found: true, state: "Completed", resultMissing: true };
    }
  }

  if (row.state === "Failed") {
    const code =
      row.terminal_error_code && row.terminal_error_code.length > 0
        ? (row.terminal_error_code as TaxonomyCode)
        : "internal_error";
    return {
      found: true,
      state: "Failed",
      terminalErrorCode: code,
    };
  }

  if (row.state === "Cancelled") {
    return { found: true, state: "Cancelled" };
  }

  if (row.state === "AwaitingContext") {
    return { found: true, state: "AwaitingContext" };
  }

  if (isTransitionState(row.state) && !TERMINAL_TRANSITION_STATES.has(row.state)) {
    return { found: true, state: row.state, pending: true };
  }

  return { found: false };
}

export type AuthenticateGetRequestResult =
  | { ok: true; principal: Principal }
  | { ok: false; code: "unauthenticated" | "installation_suspended" };

/**
 * Authenticate GET /v1/requests/{reference} with the §5.6 enrolled-key verifier.
 * Requires `Authorization: Bearer <token>`; scopes subsequent getRequest by installation.
 */
export async function authenticateGetRequest(
  request: Request,
  env: { DB: D1Database },
): Promise<AuthenticateGetRequestResult> {
  const header = request.headers.get("Authorization");
  if (header === null || !header.startsWith("Bearer ")) {
    return { ok: false, code: "unauthenticated" };
  }

  const token = header.slice("Bearer ".length).trim();
  if (token.length === 0) {
    return { ok: false, code: "unauthenticated" };
  }

  const verifier = new EnrolledKeyVerifier();
  const result = await verifier.verify(token, {
    audience: "ai-platform",
    clockSkewSeconds: 60,
    now: Math.floor(Date.now() / 1000),
    cache: new ConfigCache(),
    reader: createD1ConfigReader(env.DB),
  });

  if (!result.ok) {
    return { ok: false, code: result.code };
  }

  return { ok: true, principal: result.principal };
}

/** Build a taxonomy error body for failed get-request authentication. */
export function getRequestAuthErrorBody(
  code: "unauthenticated" | "installation_suspended" = "unauthenticated",
): ReturnType<typeof buildErrorBody> {
  return buildErrorBody({
    code,
    requestReference: generateRequestReference(),
    traceId: generateUlid(),
  });
}

export type ConversationLegRow = {
  request_id: string;
  conversation_id: string;
  turn_ordinal: number;
  state: TransitionState;
};

export async function listConversationLegs(
  conversationId: string,
  db: D1Database,
): Promise<ConversationLegRow[]> {
  const result = await db
    .prepare(
      `SELECT request_id, conversation_id, turn_ordinal, state
       FROM ai_request
       WHERE conversation_id = ?
       ORDER BY turn_ordinal`,
    )
    .bind(conversationId)
    .all<ConversationLegRow>();

  return result.results ?? [];
}
