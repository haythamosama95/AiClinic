import {
  CHANNEL_VERSIONS,
  canonicalize,
  grantIdPaid,
  sha256Hex,
  ulid,
} from "vendor-contracts";
import { refreshCoverageView } from "./coverage/view.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "./clock.js";
import {
  PAYMOB_PROVIDER_ID,
  PAYMOB_ADAPTER_VERSION,
  providerForId,
  type ProviderRegistryEnv,
} from "./provider/registry.js";
import type { InquireResult, ProviderTxn } from "./provider/port.js";
import { insertFactLog } from "./records/append.js";
import {
  commandFactStatements,
  hasForbiddenCommandFactSecret,
} from "./records/command-facts.js";
import {
  deleteScopedEvidenceBodies,
  eraseOrgRawEvidence,
} from "./evidence/raw.js";
import { runReconciliation } from "./reconciliation/run.js";
import { runDueGrantWork } from "./work/grant.js";
import {
  recordRebuiltInquiryEvidence,
  recordRebuiltPaidConfirmation,
} from "./work/runner.js";
import { verifyTransferReceipt } from "./work/transfer-receipt.js";
import {
  acquireAboRecovery,
  publishAboRecovery,
  renewAboRecovery,
} from "./recovery-fence.js";
import {
  processReverseWork,
  recordReversalFromProviderTxn,
  type ReversalEnv,
} from "./work/reversal.js";

type LedgerLine = {
  payload_version: number;
  fact_seq: number;
  table: string;
  key: string;
  row_sha256: string;
  fact_created_at: string;
  row: Record<string, unknown>;
  recovery_created_at?: string;
  recovery_created_at_provenance?: string;
};

type LedgerColumn = {
  name: string;
  notnull: number;
  dflt_value: unknown;
  pk: number;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function resolveHistoricalCheckoutTimestamp(input: {
  checkoutId: string;
  createdAt: unknown;
  provenance: unknown;
  factCreatedAt: string;
  openedEventAt?: string;
}): { createdAt: string; provenance: "recorded" | "fact_log" | "opened_event" } {
  const factTimeValid = Number.isFinite(Date.parse(input.factCreatedAt));
  if (input.provenance === "recorded" || input.provenance === "fact_log" ||
      input.provenance === "opened_event") {
    if (typeof input.createdAt !== "string" || !Number.isFinite(Date.parse(input.createdAt))) {
      throw new Error(`checkout_timestamp_unrecoverable:${input.checkoutId}`);
    }
    return { createdAt: input.createdAt, provenance: input.provenance };
  }
  if (input.provenance === "expiry_inferred") {
    throw new Error(`checkout_timestamp_inferred_from_expiry:${input.checkoutId}`);
  }
  if (!factTimeValid) {
    throw new Error(`checkout_timestamp_unrecoverable:${input.checkoutId}`);
  }
  if (input.createdAt === null || input.createdAt === undefined) {
    return { createdAt: input.factCreatedAt, provenance: "fact_log" };
  }
  if (input.createdAt === input.factCreatedAt) {
    return { createdAt: input.factCreatedAt, provenance: "fact_log" };
  }
  if (typeof input.openedEventAt === "string" &&
      input.createdAt === input.openedEventAt &&
      Number.isFinite(Date.parse(input.openedEventAt))) {
    return { createdAt: input.openedEventAt, provenance: "opened_event" };
  }
  throw new Error(`checkout_timestamp_provenance_unverified:${input.checkoutId}`);
}

const LEDGER_TABLES = new Set([
  "offer", "terms_version", "offer_version", "offer_event",
  "checkout", "checkout_event", "notification", "inquiry_result", "payment",
  "payment_release", "grant_request", "grant_outcome", "grant_outcome_event", "reversal",
  "operator_action", "command_recovery_fact", "finding", "finding_resolution", "payout_import",
  "payout_line", "paymob_intention_attempt_event", "rebuild_inquiry_attempt",
  "reversal_request",
]);

const LEDGER_COLUMN_FIELDS: Record<string, readonly string[]> = {
  offer: ["offer_id", "code", "contract_version"],
  terms_version: ["terms_version", "locale", "text_r2_key", "text_sha256", "published_by", "contract_version"],
  offer_version: ["offer_id", "version", "plan_id", "plan_version", "term_unit", "term_count", "price_minor", "currency", "allowance_credits", "grace_days", "grace_cap_rule", "copy", "terms_version", "published_by", "assertion_sha256", "contract_version"],
  offer_event: ["offer_id", "kind", "version", "actor", "at", "contract_version"],
  checkout: ["checkout_id", "reference", "org_id", "created_by_sub", "billing_token_jti", "client_request_id", "offer_id", "offer_version", "plan_id", "plan_version", "term_unit", "term_count", "allowance_credits", "grace_days", "grace_cap_rule", "list_price_minor", "charged_price_minor", "adjustment_id", "currency", "terms_version", "billing_contact_version", "billing_contact_sha256", "opened_with_coverage_through", "coverage_source", "provider_id", "initiator", "expires_at", "contract_version", "created_at", "created_at_provenance", "coverage_starts", "projected_start"],
  checkout_event: ["checkout_id", "kind", "source", "ref", "actor", "at", "contract_version"],
  notification: ["notification_id", "provider_id", "channel", "hmac_valid", "body_r2_key", "body_sha256", "dedupe_key", "checkout_id", "disposition", "adapter_version", "provider_txn_id"],
  inquiry_result: ["inquiry_id", "subject", "normalized_state", "cumulative_reversed_minor", "raw_r2_key", "raw_sha256", "at", "adapter_version"],
  payment: ["payment_id", "reference", "org_id", "checkout_id", "provider_id", "amount_minor", "currency", "paid_at", "confirmed_at", "confirmation_inquiry_id", "offer_id", "offer_version", "billing_contact_version", "classification", "disposition", "mismatch_detail", "evidence_sha256"],
  payment_release: ["payment_id", "operator_action_id", "at"],
  grant_request: ["grant_id", "org_id", "source_kind", "source_ref", "envelope", "envelope_sha256", "assertion"],
  grant_outcome: ["grant_id", "result", "abo_kid", "abo_signature", "receipt", "term_ids", "at"],
  grant_outcome_event: ["outcome_seq", "attempt_id", "grant_id", "result", "code", "terminal", "abo_kid", "abo_signature", "receipt", "term_ids", "at"],
  reversal: ["reversal_id", "payment_id", "reference", "amount_minor", "kind", "is_full", "source", "cumulative_reversed_minor", "detected_via", "recorded_by", "evidence_sha256", "effect", "dedupe_key"],
  reversal_request: ["reversal_id", "grant_id", "reason", "evidence_sha256", "partial", "contract_version", "canonical_body", "body_sha256", "created_at"],
  rebuild_inquiry_attempt: ["attempt_id", "checkout_id", "payment_id", "provider_txn_ref", "outcome", "decision", "inquiry_id", "evidence_sha256", "observed_at", "adapter_version"],
  operator_action: ["action_id", "actor_email", "access_jti", "action", "subject", "params_sha256", "assertion_sha256", "result"],
  command_recovery_fact: ["fact_id", "command_id", "fact_kind", "payload_json", "payload_sha256", "created_at"],
  finding: ["finding_id", "kind", "subject", "detail", "detected_at"],
  finding_resolution: ["finding_id", "resolved_by", "note", "at"],
  payout_import: ["import_id", "provider_id", "file_sha256", "r2_key", "imported_by", "period"],
  payout_line: ["import_id", "line_no", "kind", "gross_minor", "fee_minor", "net_minor", "settled_at", "payment_id"],
  paymob_intention_attempt_event: ["event_key", "checkout_id", "attempt_no", "state", "lease_token", "lease_until", "special_reference", "intention_id", "order_id", "expires_at", "started_at", "finished_at", "event_at"],
};

const LEDGER_KEY_FIELDS: Record<string, readonly string[]> = {
  offer: ["offer_id"],
  terms_version: ["terms_version", "locale"],
  offer_version: ["offer_id", "version"],
  offer_event: ["offer_id", "kind", "version", "at"],
  checkout: ["checkout_id"],
  checkout_event: ["checkout_id", "kind", "at"],
  notification: ["notification_id"],
  inquiry_result: ["inquiry_id"],
  payment: ["payment_id"],
  payment_release: ["payment_id"],
  grant_request: ["grant_id"],
  grant_outcome: ["grant_id"],
  grant_outcome_event: ["attempt_id"],
  reversal: ["reversal_id"],
  reversal_request: ["reversal_id"],
  rebuild_inquiry_attempt: ["attempt_id"],
  operator_action: ["action_id"],
  command_recovery_fact: ["fact_id"],
  finding: ["finding_id"],
  finding_resolution: ["finding_id"],
  payout_import: ["import_id"],
  payout_line: ["import_id", "line_no"],
  paymob_intention_attempt_event: ["event_key"],
};

type CheckoutRow = {
  checkout_id: string;
  org_id: string;
  offer_id: string;
  offer_version: number;
  charged_price_minor: number;
  currency: string;
  billing_contact_version: number;
  opened_with_coverage_through: string | null;
  contract_version: number;
};

export type RebuildEnv = ProviderRegistryEnv &
  ClockEnv & {
    DB: D1Database;
    R2: R2Bucket;
    PLATFORM_PUBLIC_KEYS: string;
    PLATFORM: {
      grant(args: Record<string, unknown>): Promise<Record<string, unknown>>;
      listGrants(args: Record<string, unknown>): Promise<Record<string, unknown>>;
      readCoverageEvents(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      voidForReversal(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    };
  };

export type RebuildOptions = {
  providerTransactionReferences: string[];
};

async function newId(env: RebuildEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

function ledgerInsertStatement(
  env: RebuildEnv,
  table: string,
  row: Record<string, unknown>,
): D1PreparedStatement {
  const columns = Object.keys(row);
  const placeholders = columns.map(() => "?").join(", ");
  const values = columns.map((column) => row[column]);
  return env.DB.prepare(
    `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${placeholders})`,
  ).bind(...values);
}

async function listLedgerLines(env: RebuildEnv, recoveryToken: string): Promise<LedgerLine[]> {
  const lines: LedgerLine[] = [];
  let cursor: string | undefined;
  let truncated = true;
  while (truncated) {
    const listed = await env.R2.list({ prefix: "ledger/", cursor });
    for (const object of listed.objects) {
      await renewAboRecovery(env, recoveryToken);
      const match = /^ledger\/([1-9][0-9]*)\.ndjson$/u.exec(object.key);
      if (match === null || !Number.isSafeInteger(Number(match[1]))) {
        throw new Error(`ledger_object_key_invalid:${object.key}`);
      }
      const body = await env.R2.get(object.key);
      if (body === null) {
        throw new Error(`ledger_object_missing:${object.key}`);
      }
      const parsed = JSON.parse(await body.text()) as LedgerLine;
      if (
        parsed.payload_version !== 2 ||
        parsed.fact_seq !== Number(match[1]) ||
        typeof parsed.table !== "string" ||
        typeof parsed.key !== "string" ||
        typeof parsed.row_sha256 !== "string" ||
        typeof parsed.fact_created_at !== "string" ||
        parsed.fact_created_at.length === 0 ||
        parsed.row === null || typeof parsed.row !== "object" || Array.isArray(parsed.row)
      ) {
        throw new Error(`ledger_payload_invalid:${object.key}`);
      }
      lines.push(parsed);
    }
    truncated = listed.truncated;
    cursor = listed.truncated ? listed.cursor : undefined;
    await renewAboRecovery(env, recoveryToken);
  }
  lines.sort((left, right) => left.fact_seq - right.fact_seq);

  const manifests: Array<{ key: string; through: number }> = [];
  cursor = undefined;
  truncated = true;
  while (truncated) {
    const listed = await env.R2.list({ prefix: "ledger-manifest/", cursor });
    for (const object of listed.objects) {
      await renewAboRecovery(env, recoveryToken);
      const match = /^ledger-manifest\/([1-9][0-9]*)\.json$/u.exec(object.key);
      if (match === null || !Number.isSafeInteger(Number(match[1]))) {
        throw new Error(`ledger_manifest_key_invalid:${object.key}`);
      }
      const body = await env.R2.get(object.key);
      if (body === null) {
        throw new Error(`ledger_manifest_missing:${object.key}`);
      }
      const parsed = JSON.parse(await body.text()) as {
        payload_version?: unknown;
        exported_through?: unknown;
      };
      if (
        parsed.payload_version !== 1 ||
        parsed.exported_through !== Number(match[1])
      ) {
        throw new Error(`ledger_manifest_invalid:${object.key}`);
      }
      manifests.push({ key: object.key, through: Number(match[1]) });
    }
    truncated = listed.truncated;
    cursor = listed.truncated ? listed.cursor : undefined;
    await renewAboRecovery(env, recoveryToken);
  }
  const highWater = manifests.reduce((max, item) => Math.max(max, item.through), 0);
  if (highWater === 0 && lines.length === 0) {
    return lines;
  }
  if (highWater === 0 || lines.length !== highWater) {
    throw new Error("ledger_manifest_prefix_incomplete");
  }
  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index]!.fact_seq !== index + 1) {
      throw new Error(`ledger_sequence_gap:${index + 1}`);
    }
  }
  const openedAtByCheckout = new Map<string, string>();
  for (const line of lines) {
    if (line.table === "checkout_event" && line.row.kind === "opened" &&
        typeof line.row.checkout_id === "string" && typeof line.row.at === "string") {
      openedAtByCheckout.set(line.row.checkout_id, line.row.at);
    }
  }
  for (const line of lines) {
    if (line.table !== "checkout") continue;
    const resolved = resolveHistoricalCheckoutTimestamp({
      checkoutId: String(line.row.checkout_id),
      createdAt: line.row.created_at,
      provenance: line.row.created_at_provenance,
      factCreatedAt: line.fact_created_at,
      openedEventAt: openedAtByCheckout.get(String(line.row.checkout_id)),
    });
    line.recovery_created_at = resolved.createdAt;
    line.recovery_created_at_provenance = resolved.provenance;
  }
  return lines;
}

async function ledgerTableColumns(env: RebuildEnv, table: string): Promise<LedgerColumn[]> {
  if (!LEDGER_TABLES.has(table)) {
    throw new Error(`ledger_table_unregistered:${table}`);
  }
  const physicalTable = table === "grant_outcome" ? "grant_outcome_legacy" : table;
  const columns = await env.DB.prepare(`PRAGMA table_info(${physicalTable})`).all<LedgerColumn>();
  const result = columns.results ?? [];
  if (result.length === 0) {
    throw new Error(`ledger_table_missing:${table}`);
  }
  return result;
}

async function validateLedgerLine(env: RebuildEnv, line: LedgerLine): Promise<void> {
  if (!Number.isSafeInteger(line.fact_seq) || line.fact_seq <= 0) {
    throw new Error(`ledger_sequence_invalid:${line.fact_seq}`);
  }
  if (!/^([a-f0-9]{64})$/u.test(line.row_sha256)) {
    throw new Error(`ledger_hash_invalid:${line.fact_seq}`);
  }
  const canonicalRow = canonicalize(line.row);
  if (await sha256Hex(canonicalRow) !== line.row_sha256) {
    throw new Error(`ledger_hash_mismatch:${line.fact_seq}`);
  }
  const columns = await ledgerTableColumns(env, line.table);
  const names = new Set(columns.map((column) => column.name));
  const allowedFields = LEDGER_COLUMN_FIELDS[line.table];
  if (allowedFields === undefined) {
    throw new Error(`ledger_column_registry_missing:${line.table}`);
  }
  for (const key of Object.keys(line.row)) {
    if (!allowedFields.includes(key) || !names.has(key)) {
      throw new Error(`ledger_column_unregistered:${line.table}.${key}`);
    }
  }
  for (const column of columns) {
    if (
      column.notnull === 1 && column.dflt_value === null &&
      !Object.hasOwn(line.row, column.name)
    ) {
      throw new Error(`ledger_column_missing:${line.table}.${column.name}`);
    }
  }
  const keyFields = LEDGER_KEY_FIELDS[line.table];
  if (keyFields === undefined || keyFields.length === 0) {
    throw new Error(`ledger_identity_unregistered:${line.table}`);
  }
  const identity = keyFields.map((field) => {
    if (!names.has(field)) {
      throw new Error(`ledger_identity_column_unregistered:${line.table}.${field}`);
    }
    const value = line.row[field];
    if (value === null || value === undefined) {
      throw new Error(`ledger_identity_missing:${line.table}.${field}`);
    }
    return String(value);
  }).join(":");
  if (identity !== line.key) {
    throw new Error(`ledger_identity_mismatch:${line.fact_seq}`);
  }
  if (!Number.isSafeInteger(Date.parse(line.fact_created_at))) {
    throw new Error(`ledger_created_at_invalid:${line.fact_seq}`);
  }
  if (Object.hasOwn(line.row, "contract_version")) {
    const version = line.row.contract_version;
    if (
      typeof version !== "number" || !Number.isSafeInteger(version) ||
      !Object.values(CHANNEL_VERSIONS).includes(version as number)
    ) {
      throw new Error(`ledger_contract_version_unknown:${line.fact_seq}`);
    }
  }
  if (line.table === "checkout" && Object.hasOwn(line.row, "created_at_provenance") &&
      !["recorded", "fact_log", "opened_event", "legacy_unknown", "expiry_inferred"]
        .includes(String(line.row.created_at_provenance))) {
    throw new Error(`ledger_checkout_timestamp_provenance_unknown:${line.fact_seq}`);
  }
  if (line.table === "command_recovery_fact") {
    const payloadJson = line.row.payload_json;
    const payloadHash = line.row.payload_sha256;
    const factId = line.row.fact_id;
    const commandId = line.row.command_id;
    const factKind = line.row.fact_kind;
    if (
      typeof payloadJson !== "string" || typeof payloadHash !== "string" ||
      typeof factId !== "string" || typeof commandId !== "string" ||
      typeof factKind !== "string"
    ) throw new Error(`ledger_command_fact_invalid:${line.fact_seq}`);
    const payload = JSON.parse(payloadJson) as Record<string, unknown>;
    const payloadCanonical = new TextDecoder().decode(canonicalize(payload));
    if (
      payloadCanonical !== payloadJson ||
      await sha256Hex(canonicalize(payload)) !== payloadHash ||
      await hasForbiddenCommandFactSecret(payload, factKind, env.PLATFORM_PUBLIC_KEYS) ||
      payload.payload_version !== 1 ||
      payload.command_id !== commandId ||
      !["command_intent", "relay_reserved", "platform_result", "local_result", "erasure_ack"].includes(factKind)
    ) throw new Error(`ledger_command_fact_invalid:${line.fact_seq}`);
    const expectedFactId = await sha256Hex(canonicalize({
      command_id: commandId,
      fact_kind: factKind,
      payload_sha256: payloadHash,
    }));
    if (expectedFactId !== factId) throw new Error(`ledger_command_fact_identity_mismatch:${line.fact_seq}`);
  }
}

async function replayLedger(
  env: RebuildEnv,
  lines: LedgerLine[],
  recoveryToken: string,
): Promise<void> {
  // Validate the complete immutable prefix before inserting any part of it.
  for (const line of lines) {
    await renewAboRecovery(env, recoveryToken);
    await validateLedgerLine(env, line);
  }

  const checkpoint = await env.DB.prepare(
    `SELECT last_fact_seq FROM rebuild_checkpoint WHERE id = 1`,
  ).first<{ last_fact_seq: number }>();
  let lastFactSeq = checkpoint?.last_fact_seq ?? 0;
  if (lastFactSeq > (lines.at(-1)?.fact_seq ?? 0)) {
    throw new Error("ledger_checkpoint_ahead_of_manifest");
  }
  for (const line of lines) {
    await renewAboRecovery(env, recoveryToken);
    const row = line.row;
    const columns = await ledgerTableColumns(env, line.table);
    const physicalTable = line.table === "grant_outcome" ? "grant_outcome_legacy" : line.table;
    const identityFields = LEDGER_KEY_FIELDS[line.table];
    if (identityFields === undefined || identityFields.length === 0) {
      throw new Error(`ledger_identity_unregistered:${line.table}`);
    }
    const where = identityFields.map((column) => `${column} = ?`).join(" AND ");
    const keyValues = identityFields.map((column) => row[column]);
    const existingRow = await env.DB.prepare(`SELECT * FROM ${physicalTable} WHERE ${where}`)
      .bind(...keyValues).first<Record<string, unknown>>();
    if (existingRow !== null) {
      const projected = Object.fromEntries(Object.keys(row).map((column) => [column, existingRow[column]]));
      const decoder = new TextDecoder();
      if (decoder.decode(canonicalize(projected)) !== decoder.decode(canonicalize(row))) {
        throw new Error(`ledger_business_row_conflict:${line.fact_seq}`);
      }
    }
    const existingFact = await env.DB.prepare(
      `SELECT "table", key, row_sha256, row_json, created_at
       FROM fact_log WHERE fact_seq = ?`,
    ).bind(line.fact_seq).first<{
      table: string; key: string; row_sha256: string; row_json: string | null; created_at: string;
    }>();
    const rowJson = new TextDecoder().decode(canonicalize(row));
    if (existingFact !== null && (
      existingFact.table !== line.table || existingFact.key !== line.key ||
      existingFact.row_sha256 !== line.row_sha256 || existingFact.row_json !== rowJson ||
      existingFact.created_at !== line.fact_created_at
    )) {
      throw new Error(`ledger_fact_log_conflict:${line.fact_seq}`);
    }
    if (line.fact_seq > lastFactSeq + 1) {
      throw new Error(`ledger_checkpoint_gap:${lastFactSeq + 1}`);
    }
    const exportMarker = await env.DB.prepare(
      `SELECT fact_seq FROM fact_export WHERE fact_seq = ?`,
    ).bind(line.fact_seq).first();
    const statements: D1PreparedStatement[] = [];
    if (existingRow === null) {
      if (line.table === "grant_outcome") {
        // Migration 0014 defines this deterministic legacy projection exactly.
        const grantId = String(row.grant_id);
        const result = typeof row.result === "string" ? row.result : "rejected";
        const event = {
          attempt_id: `legacy:${grantId}`,
          grant_id: grantId,
          result,
          code: null,
          terminal: result === "applied" || result === "already_applied" ? 1 : 0,
          abo_kid: row.abo_kid ?? null,
          abo_signature: row.abo_signature ?? null,
          receipt: row.receipt ?? null,
          term_ids: row.term_ids ?? null,
          at: row.at,
        };
        const existingEvent = await env.DB.prepare(
          `SELECT * FROM grant_outcome_event WHERE attempt_id = ?`,
        ).bind(event.attempt_id).first<Record<string, unknown>>();
        if (existingEvent !== null) {
          const projected = Object.fromEntries(
            Object.keys(event).map((column) => [column, existingEvent[column]]),
          );
          if (new TextDecoder().decode(canonicalize(projected)) !==
              new TextDecoder().decode(canonicalize(event))) {
            throw new Error(`ledger_business_row_conflict:${line.fact_seq}`);
          }
        } else {
          statements.push(ledgerInsertStatement(
            env,
            "grant_outcome_event",
            event as unknown as Record<string, unknown>,
          ));
        }
      } else {
        const replayRow = line.table === "checkout"
          ? {
              ...row,
              created_at: line.recovery_created_at,
              created_at_provenance: line.recovery_created_at_provenance,
            }
          : row;
        statements.push(ledgerInsertStatement(env, line.table, replayRow));
      }
    }
    if (existingFact === null) {
      statements.push(env.DB.prepare(
        `INSERT INTO fact_log (fact_seq, "table", key, row_sha256, row_json, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).bind(line.fact_seq, line.table, line.key, line.row_sha256, rowJson, line.fact_created_at));
    }
    if (exportMarker === null) {
      statements.push(env.DB.prepare(
        `INSERT INTO fact_export (fact_seq, exported_at) VALUES (?, ?)`,
      ).bind(line.fact_seq, line.fact_created_at));
    }
    const checkpointAt = await clockNowIso(env);
    statements.push(env.DB.prepare(
      `INSERT INTO rebuild_checkpoint (id, last_fact_seq, payload_sha256, updated_at)
       VALUES (1, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET last_fact_seq = excluded.last_fact_seq,
         payload_sha256 = excluded.payload_sha256, updated_at = excluded.updated_at
       WHERE rebuild_checkpoint.last_fact_seq <= excluded.last_fact_seq`,
    ).bind(line.fact_seq, line.row_sha256, checkpointAt));
    await env.DB.batch(statements);
    await renewAboRecovery(env, recoveryToken);
    lastFactSeq = Math.max(lastFactSeq, line.fact_seq);
  }
}

type IntentionAttemptEventRow = {
  event_key: string;
  checkout_id: string;
  attempt_no: number;
  state: "pending" | "created" | "abandoned_unconfirmed";
  lease_token: string;
  lease_until: string;
  special_reference: string;
  intention_id: string | null;
  order_id: string | null;
  client_secret: string | null;
  expires_at: string | null;
  started_at: string | null;
  finished_at: string | null;
  event_at: string;
};

async function appendLegacyAttemptEvent(
  env: RebuildEnv,
  event: IntentionAttemptEventRow,
): Promise<void> {
  const existing = await env.DB.prepare(
    `SELECT 1 FROM paymob_intention_attempt_event WHERE event_key = ?`,
  )
    .bind(event.event_key)
    .first();
  if (existing === null) {
    await ledgerInsertStatement(
      env,
      "paymob_intention_attempt_event",
      event as unknown as Record<string, unknown>,
    ).run();
  }

  // Migration-created legacy events are derived from old facts and have no
  // fact_log entry. Add one so a subsequent ledger export carries the event.
  const fact = await env.DB.prepare(
    `SELECT 1 FROM fact_log
     WHERE "table" = 'paymob_intention_attempt_event' AND key = ? LIMIT 1`,
  )
    .bind(event.event_key)
    .first();
  if (fact === null) {
    const recoveryRow = Object.fromEntries(
      Object.entries(event).filter(([field]) => field !== "client_secret"),
    );
    await (
      await insertFactLog(
        env,
        "paymob_intention_attempt_event",
        event.event_key,
        recoveryRow,
        event.event_at,
      )
    ).run();
  }
}

async function ensureLegacyAttemptEvents(env: RebuildEnv): Promise<void> {
  const intentions = await env.DB.prepare(
    `SELECT pi.checkout_id, pi.intention_id, pi.order_id, pi.client_secret,
            pi.special_reference, pi.expires_at, c.created_at,
            c.created_at_provenance,
            (SELECT fl.created_at FROM fact_log fl
             WHERE fl."table" = 'checkout' AND fl.key = c.checkout_id
             ORDER BY fl.fact_seq LIMIT 1) AS fact_created_at,
            (SELECT ce.at FROM checkout_event ce
             WHERE ce.checkout_id = c.checkout_id AND ce.kind = 'opened'
             ORDER BY ce.at LIMIT 1) AS opened_event_at
     FROM paymob_intention pi
     INNER JOIN checkout c ON c.checkout_id = pi.checkout_id`,
  ).all<{
    checkout_id: string;
    intention_id: string;
    order_id: string;
    client_secret: string;
    special_reference: string;
    expires_at: string;
    created_at: string | null;
    created_at_provenance: string;
    fact_created_at: string | null;
    opened_event_at: string | null;
  }>();
  const resolvedIntentionTimes = new Map<string, string>();
  for (const intention of intentions.results ?? []) {
    const resolved = resolveHistoricalCheckoutTimestamp({
      checkoutId: intention.checkout_id,
      createdAt: intention.created_at,
      provenance: intention.created_at_provenance,
      factCreatedAt: intention.fact_created_at ?? "",
      openedEventAt: intention.opened_event_at ?? undefined,
    });
    resolvedIntentionTimes.set(intention.checkout_id, resolved.createdAt);
  }
  for (const intention of intentions.results ?? []) {
    const eventKey = `${intention.checkout_id}:1:created:legacy`;
    const prior = await env.DB.prepare(
      `SELECT event_key FROM paymob_intention_attempt_event
       WHERE checkout_id = ? AND attempt_no = 1 LIMIT 1`,
    )
      .bind(intention.checkout_id)
      .first<{ event_key: string }>();
    if (prior !== null && prior.event_key !== eventKey) {
      continue;
    }
    const eventAt = resolvedIntentionTimes.get(intention.checkout_id)!;
    await appendLegacyAttemptEvent(env, {
      event_key: eventKey,
      checkout_id: intention.checkout_id,
      attempt_no: 1,
      state: "created",
      lease_token: "legacy",
      lease_until: intention.expires_at,
      special_reference: intention.special_reference,
      intention_id: intention.intention_id,
      order_id: intention.order_id,
      client_secret: null,
      expires_at: intention.expires_at,
      started_at: eventAt,
      finished_at: eventAt,
      event_at: eventAt,
    });
  }

  const failedCheckouts = await env.DB.prepare(
    `SELECT c.checkout_id, c.reference, c.expires_at, c.created_at,
            c.created_at_provenance,
            (SELECT fl.created_at FROM fact_log fl
             WHERE fl."table" = 'checkout' AND fl.key = c.checkout_id
             ORDER BY fl.fact_seq LIMIT 1) AS fact_created_at,
            (SELECT ce.at FROM checkout_event ce
             WHERE ce.checkout_id = c.checkout_id AND ce.kind = 'opened'
             ORDER BY ce.at LIMIT 1) AS opened_event_at,
            COALESCE(cs.last_event_at, (
              SELECT MAX(oe.at) FROM checkout_event oe
              WHERE oe.checkout_id = c.checkout_id AND oe.kind = 'open_failed'
            )) AS failed_at
     FROM checkout c
     INNER JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
     LEFT JOIN paymob_intention pi ON pi.checkout_id = c.checkout_id
     WHERE cs.state = 'open_failed' AND pi.checkout_id IS NULL`,
  ).all<{
    checkout_id: string;
    reference: string;
    expires_at: string;
    created_at: string | null;
    created_at_provenance: string;
    fact_created_at: string | null;
    opened_event_at: string | null;
    failed_at: string | null;
  }>();
  for (const checkout of failedCheckouts.results ?? []) {
    const failedAt = checkout.failed_at;
    if (failedAt === null || !Number.isFinite(Date.parse(failedAt))) {
      throw new Error(`legacy_failed_checkout_timestamp_unrecoverable:${checkout.checkout_id}`);
    }
    const createdAt = resolveHistoricalCheckoutTimestamp({
      checkoutId: checkout.checkout_id,
      createdAt: checkout.created_at,
      provenance: checkout.created_at_provenance,
      factCreatedAt: checkout.fact_created_at ?? "",
      openedEventAt: checkout.opened_event_at ?? undefined,
    }).createdAt;
    const eventKey = `${checkout.checkout_id}:1:abandoned_unconfirmed:legacy`;
    const prior = await env.DB.prepare(
      `SELECT event_key FROM paymob_intention_attempt_event
       WHERE checkout_id = ? AND attempt_no = 1 LIMIT 1`,
    )
      .bind(checkout.checkout_id)
      .first<{ event_key: string }>();
    if (prior !== null && prior.event_key !== eventKey) {
      continue;
    }
    await appendLegacyAttemptEvent(env, {
      event_key: eventKey,
      checkout_id: checkout.checkout_id,
      attempt_no: 1,
      state: "abandoned_unconfirmed",
      lease_token: "legacy",
      lease_until: checkout.expires_at,
      special_reference: checkout.reference,
      intention_id: null,
      order_id: null,
      client_secret: null,
      expires_at: null,
      started_at: createdAt,
      finished_at: failedAt,
      event_at: failedAt,
    });
  }
}

async function rebuildIntentionAttempts(env: RebuildEnv): Promise<void> {
  const listed = await env.DB.prepare(
    `SELECT event_key, checkout_id, attempt_no, state, lease_token, lease_until,
            special_reference, intention_id, order_id, client_secret, expires_at,
            started_at, finished_at, event_at
     FROM paymob_intention_attempt_event ORDER BY rowid ASC`,
  ).all<IntentionAttemptEventRow>();
  const latest = new Map<string, IntentionAttemptEventRow>();
  for (const event of listed.results ?? []) {
    latest.set(`${event.checkout_id}:${event.attempt_no}`, event);
  }

  // paymob_intention_attempt is an operational projection. Replacing it from
  // append-only event rows prevents ledger replay from trying to insert every
  // historical snapshot into its (checkout_id, attempt_no) primary key.
  await env.DB.prepare(`DELETE FROM paymob_intention_attempt`).run();
  for (const event of latest.values()) {
    await env.DB.prepare(
      `INSERT INTO paymob_intention_attempt (
         checkout_id, attempt_no, state, lease_token, lease_until,
         special_reference, intention_id, order_id, client_secret, expires_at,
         started_at, finished_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        event.checkout_id,
        event.attempt_no,
        event.state,
        event.lease_token,
        event.lease_until,
        event.special_reference,
        event.intention_id,
        event.order_id,
        event.client_secret,
        event.expires_at,
        event.started_at,
        event.finished_at,
      )
      .run();
  }
}

function checkoutStatusFromEventKind(kind: string): string {
  if (kind === "opened") {
    return "open";
  }
  if (kind === "late_paid") {
    return "paid_late";
  }
  return kind;
}

async function recomputeCheckoutStatus(env: RebuildEnv): Promise<void> {
  const checkouts = await env.DB.prepare(
    `SELECT checkout_id FROM checkout`,
  ).all<{ checkout_id: string }>();
  for (const checkout of checkouts.results ?? []) {
    const latest = await env.DB.prepare(
      `SELECT kind, at FROM checkout_event
       WHERE checkout_id = ?
       ORDER BY at DESC, rowid DESC
       LIMIT 1`,
    )
      .bind(checkout.checkout_id)
      .first<{ kind: string; at: string }>();

    const payment = await env.DB.prepare(
      `SELECT classification, confirmed_at FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkout.checkout_id)
      .first<{ classification: string; confirmed_at: string }>();

    let state: string | null = null;
    let lastEventAt: string | null = null;
    if (latest !== null) {
      state = checkoutStatusFromEventKind(latest.kind);
      lastEventAt = latest.at;
    }
    if (payment !== null) {
      const paidState =
        payment.classification === "late" ? "paid_late" : "paid";
      const paidAtMs = Date.parse(payment.confirmed_at);
      const eventAtMs = lastEventAt === null ? Number.NaN : Date.parse(lastEventAt);
      if (
        state === null ||
        state === "open" ||
        (!Number.isNaN(paidAtMs) &&
          !Number.isNaN(eventAtMs) &&
          paidAtMs >= eventAtMs)
      ) {
        state = paidState;
        lastEventAt = payment.confirmed_at;
      }
    }
    if (state === null || lastEventAt === null) {
      continue;
    }
    await env.DB.prepare(
      `INSERT INTO checkout_status (checkout_id, state, last_event_at)
       VALUES (?, ?, ?)
       ON CONFLICT(checkout_id) DO UPDATE SET
         state = excluded.state, last_event_at = excluded.last_event_at`,
    )
      .bind(checkout.checkout_id, state, lastEventAt)
      .run();
  }
}

async function loadCheckout(
  env: RebuildEnv,
  checkoutId: string,
): Promise<CheckoutRow | null> {
  return env.DB.prepare(
    `SELECT checkout_id, org_id, offer_id, offer_version, charged_price_minor,
            currency, billing_contact_version, opened_with_coverage_through,
            contract_version
     FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<CheckoutRow>();
}

async function paymentExists(
  env: RebuildEnv,
  paymentId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first();
  return row !== null;
}

async function grantOutcomeExists(
  env: RebuildEnv,
  grantId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM grant_outcome_event
     WHERE grant_id = ? AND terminal = 1 AND result IN ('applied', 'already_applied')`,
  )
    .bind(grantId)
    .first();
  return row !== null;
}

async function awaitPlatformGrantInList(
  env: RebuildEnv,
  grantId: string,
): Promise<void> {
  let listingWasAvailable = false;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const grants = await parsePlatformGrants(env);
    if (grants !== null) {
      listingWasAvailable = true;
      if (grants.some((grant) => String(grant.grant_id ?? "") === grantId)) {
        return;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  const reason = listingWasAvailable
    ? "grant was missing from the available platform grant listing"
    : "platform grant listing remained unavailable";
  throw new Error(`Timed out waiting for platform grant ${grantId}: ${reason}`);
}

async function awaitGapGrantsInList(
  env: RebuildEnv,
  paymentIds: Iterable<string>,
): Promise<void> {
  for (const paymentId of paymentIds) {
    await awaitPlatformGrantInList(env, await grantIdPaid(paymentId));
  }
}

async function maybeRecordSucceededPayment(
  env: RebuildEnv,
  checkoutId: string,
  confirmedTxn: ProviderTxn,
  inquiry: InquireResult,
  paymobTxnId?: string,
): Promise<boolean> {
  if (confirmedTxn.kind !== "payment_succeeded") {
    return false;
  }
  if (await paymentExists(env, confirmedTxn.payment_id)) {
    return false;
  }
  const checkout = await loadCheckout(env, checkoutId);
  if (checkout === null) {
    return false;
  }
  const nowIso = await clockNowIso(env);
  const recorded = await recordRebuiltPaidConfirmation(env, {
    checkout,
    confirmedTxn,
    inquiry,
    nowIso,
    paymobTxnId,
    allowMissingContactForRecoveredAttempt: true,
  });
  if (!recorded) return false;
  const payment = await env.DB.prepare(
    `SELECT disposition FROM payment WHERE payment_id = ?`,
  ).bind(confirmedTxn.payment_id).first<{ disposition: string }>();
  return payment?.disposition === "grant";
}

async function recordRebuildInquiryAttempt(
  env: RebuildEnv,
  input: {
    checkoutId: string;
    paymentId?: string;
    providerTxnRef?: string;
    outcome: "confirmed" | "already_recorded" | "deferred" | "unavailable" | "discovery_unavailable" | "unbound";
    decision: string;
    inquiryId?: string;
    evidenceSha256?: string;
    observedAt: string;
  },
): Promise<void> {
  const canonicalCore = {
    checkout_id: input.checkoutId,
    payment_id: input.paymentId ?? null,
    provider_txn_ref: input.providerTxnRef ?? null,
    outcome: input.outcome,
    decision: input.decision,
    inquiry_id: input.inquiryId ?? null,
    evidence_sha256: input.evidenceSha256 ?? null,
    adapter_version: PAYMOB_ADAPTER_VERSION,
  };
  const attemptId = await sha256Hex(canonicalize(canonicalCore));
  const row = {
    attempt_id: attemptId,
    ...canonicalCore,
    observed_at: input.observedAt,
  };
  const factRowJson = new TextDecoder().decode(canonicalize(row));
  const factRowSha256 = await sha256Hex(canonicalize(row));
  const statements = [
    env.DB.prepare(
      `INSERT INTO rebuild_inquiry_attempt (
         attempt_id, checkout_id, payment_id, provider_txn_ref, outcome,
         decision, inquiry_id, evidence_sha256, observed_at, adapter_version
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(attempt_id) DO NOTHING`,
    ).bind(
      row.attempt_id, row.checkout_id, row.payment_id, row.provider_txn_ref,
      row.outcome, row.decision, row.inquiry_id, row.evidence_sha256,
      row.observed_at, row.adapter_version,
    ),
  ];
  statements.push(env.DB.prepare(
    `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
     SELECT 'rebuild_inquiry_attempt', ?, ?, ?, ?
     WHERE NOT EXISTS (SELECT 1 FROM fact_log
       WHERE "table" = 'rebuild_inquiry_attempt' AND key = ?)`,
  ).bind(attemptId, factRowSha256, factRowJson, input.observedAt, attemptId));
  await env.DB.batch(statements);
}

async function processAuthoritativeInquiry(
  env: RebuildEnv,
  checkoutId: string,
  inquiry: InquireResult,
  paymobTxnId?: string,
): Promise<string[]> {
  const checkout = await loadCheckout(env, checkoutId);
  if (checkout === null) return [];
  const nowIso = await clockNowIso(env);
  if (inquiry.deferred) {
    await recordRebuildInquiryAttempt(env, {
      checkoutId,
      ...(paymobTxnId === undefined ? {} : { providerTxnRef: paymobTxnId }),
      outcome: "deferred",
      decision: "shared_inquiry_budget_unavailable",
      observedAt: nowIso,
    });
    return [];
  }
  if (inquiry.unavailable) {
    await recordRebuildInquiryAttempt(env, {
      checkoutId,
      ...(paymobTxnId === undefined ? {} : { providerTxnRef: paymobTxnId }),
      outcome: "unavailable",
      decision: "provider_inquiry_result_unavailable",
      observedAt: nowIso,
    });
    return [];
  }
  if (inquiry.discovery_unavailable) {
    await recordRebuildInquiryAttempt(env, {
      checkoutId,
      ...(paymobTxnId === undefined ? {} : { providerTxnRef: paymobTxnId }),
      outcome: "discovery_unavailable",
      decision: "original_provider_transaction_reference_required",
      observedAt: nowIso,
    });
    return [];
  }
  if (!inquiry.bound) {
    await recordRebuildInquiryAttempt(env, {
      checkoutId,
      ...(paymobTxnId === undefined ? {} : { providerTxnRef: paymobTxnId }),
      outcome: "unbound",
      decision: "provider_inquiry_not_bound_to_original_order",
      observedAt: nowIso,
    });
    return [];
  }
  if (inquiry.transactions.length === 0) {
    await recordRebuildInquiryAttempt(env, {
      checkoutId,
      ...(paymobTxnId === undefined ? {} : { providerTxnRef: paymobTxnId }),
      outcome: "unbound",
      decision: "bound_response_without_transactions",
      observedAt: nowIso,
    });
    return [];
  }
  const recordedPayments: string[] = [];
  for (const txn of inquiry.transactions) {
    const providerTxnRef = paymobTxnId ?? txn.provider_txn_id;
    const evidence = await recordRebuiltInquiryEvidence(env, {
      checkout,
      txn,
      inquiry,
      nowIso,
      allowMissingContactForRecoveredAttempt: true,
    });
    if (txn.kind === "payment_succeeded") {
      const existing = await env.DB.prepare(
        `SELECT checkout_id, provider_id, amount_minor, currency, disposition
         FROM payment WHERE payment_id = ?`,
      ).bind(txn.payment_id).first<{
        checkout_id: string; provider_id: string; amount_minor: number;
        currency: string; disposition: string;
      }>();
      if (existing !== null) {
        const matches = existing.checkout_id === checkoutId &&
          existing.provider_id === PAYMOB_PROVIDER_ID &&
          existing.amount_minor === txn.amount_minor && existing.currency === txn.currency;
        await recordRebuildInquiryAttempt(env, {
          checkoutId,
          paymentId: txn.payment_id,
          ...(providerTxnRef === undefined ? {} : { providerTxnRef }),
          outcome: matches ? "already_recorded" : "unbound",
          decision: matches ? `existing_payment_${existing.disposition}_reconfirmed`
            : "existing_payment_identity_conflict",
          ...(evidence === null ? {} : {
            inquiryId: evidence.inquiryId,
            evidenceSha256: evidence.evidenceSha256,
          }),
          observedAt: nowIso,
        });
        continue;
      }
      const newlyRecorded = await maybeRecordSucceededPayment(
        env, checkoutId, txn, inquiry, paymobTxnId,
      );
      const payment = await env.DB.prepare(
        `SELECT confirmation_inquiry_id, evidence_sha256, disposition
         FROM payment WHERE payment_id = ?`,
      ).bind(txn.payment_id).first<{
        confirmation_inquiry_id: string; evidence_sha256: string; disposition: string;
      }>();
      await recordRebuildInquiryAttempt(env, {
        checkoutId,
        paymentId: txn.payment_id,
        ...(providerTxnRef === undefined ? {} : { providerTxnRef }),
        outcome: newlyRecorded ? "confirmed" : "unbound",
        decision: payment === null ? "no_payment_write_after_authenticated_inquiry"
          : `payment_${payment.disposition}`,
        ...(payment === null ? (evidence === null ? {} : {
          inquiryId: evidence.inquiryId,
          evidenceSha256: evidence.evidenceSha256,
        }) : {
          inquiryId: payment.confirmation_inquiry_id,
          evidenceSha256: payment.evidence_sha256,
        }),
        observedAt: nowIso,
      });
      if (newlyRecorded) {
        recordedPayments.push(txn.payment_id);
      }
      continue;
    }
    await recordRebuildInquiryAttempt(env, {
      checkoutId,
      paymentId: txn.payment_id,
      ...(providerTxnRef === undefined ? {} : { providerTxnRef }),
      outcome: evidence === null ? "unbound" : "confirmed",
      decision: evidence === null ? "authenticated_evidence_not_retained"
        : `authenticated_${txn.kind}_evidence_retained`,
      ...(evidence === null ? {} : {
        inquiryId: evidence.inquiryId,
        evidenceSha256: evidence.evidenceSha256,
      }),
      observedAt: nowIso,
    });
    if (evidence === null) continue;
    if (txn.kind === "reversal") {
      await recordReversalFromProviderTxn(
        env as RebuildEnv & ReversalEnv,
        txn,
        "inquiry",
        evidence.evidenceSha256,
        txn.payment_id,
      );
    }
  }
  return recordedPayments;
}

async function parsePlatformGrants(
  env: RebuildEnv,
): Promise<Record<string, unknown>[] | null> {
  const envelope = await env.PLATFORM.listGrants({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
  });
  if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
    return null;
  }
  const parsed = JSON.parse(envelope.detail) as unknown;
  return Array.isArray(parsed) ? (parsed as Record<string, unknown>[]) : [];
}

async function markUncorrelatedCheckoutsDisputed(env: RebuildEnv): Promise<void> {
  const listed = await env.DB.prepare(
    `SELECT c.checkout_id FROM checkout c
     INNER JOIN checkout_status s ON s.checkout_id = c.checkout_id
     LEFT JOIN payment p ON p.checkout_id = c.checkout_id
     WHERE p.payment_id IS NULL AND s.state NOT IN ('cancelled', 'paid', 'paid_late')
       AND NOT EXISTS (
         SELECT 1 FROM paymob_intention_attempt a
         WHERE a.checkout_id = c.checkout_id AND a.state = 'created'
           AND a.order_id IS NOT NULL
       )
     ORDER BY c.checkout_id ASC`,
  ).all<{ checkout_id: string }>();
  for (const checkout of listed.results ?? []) {
    const detail = "Original provider order correlation is absent; await operator evidence and inquiry. No replacement order was created.";
    const nowIso = await clockNowIso(env);
    const existing = await env.DB.prepare(
      `SELECT finding_id FROM finding
       WHERE kind = 'rebuild_missing_provider_correlation' AND subject = ? LIMIT 1`,
    ).bind(checkout.checkout_id).first<{ finding_id: string }>();
    const statements: D1PreparedStatement[] = [env.DB.prepare(
      `UPDATE checkout_status SET state = 'disputed', last_event_at = ?
       WHERE checkout_id = ? AND state NOT IN ('cancelled', 'paid', 'paid_late')`,
    ).bind(nowIso, checkout.checkout_id)];
    if (existing === null) {
      const findingId = await newId(env);
      const row = {
        finding_id: findingId,
        kind: "rebuild_missing_provider_correlation",
        subject: checkout.checkout_id,
        detail,
        detected_at: nowIso,
      };
      statements.push(
        env.DB.prepare(
          `INSERT INTO finding (finding_id, kind, subject, detail, detected_at)
           VALUES (?, ?, ?, ?, ?)`,
        ).bind(findingId, row.kind, row.subject, row.detail, row.detected_at),
        await insertFactLog(env, "finding", findingId, row, nowIso),
      );
    }
    statements.push(env.DB.prepare(
      `INSERT INTO alert (
         alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
       ) VALUES (?, 'AL-05', 1, 1, NULL, NULL, ?)
       ON CONFLICT(alert_key) DO UPDATE SET
         active = 1,
         unsent = CASE
           WHEN alert.active = 0 OR alert.unsent = 1 OR alert.last_sent_at IS NULL THEN 1
           ELSE alert.unsent
         END,
         code = 'AL-05', detail_id = excluded.detail_id`,
    ).bind(`AL-05:rebuild-correlation:${checkout.checkout_id}`, checkout.checkout_id));
    await env.DB.batch(statements);
  }
}

async function restoreDueWorkFromFacts(
  env: RebuildEnv,
  factHighWater: number,
  recoveryToken: string,
): Promise<string[]> {
  const checkpoint = await env.DB.prepare(
    `SELECT last_fact_seq FROM rebuild_due_checkpoint WHERE id = 1`,
  ).first<{ last_fact_seq: number }>();
  if (checkpoint !== null && checkpoint.last_fact_seq > factHighWater) {
    throw new Error("rebuild_due_checkpoint_ahead_of_ledger");
  }
  const statements: D1PreparedStatement[] = [];
  const nowIso = await clockNowIso(env);
  const payments = await env.DB.prepare(
    `SELECT p.payment_id FROM payment p
     WHERE p.disposition = 'grant'
        OR (p.disposition = 'withheld_mismatch' AND EXISTS (
          SELECT 1 FROM payment_release pr WHERE pr.payment_id = p.payment_id
        ))
     ORDER BY p.payment_id ASC`,
  ).all<{ payment_id: string }>();
  for (const payment of payments.results ?? []) {
    await renewAboRecovery(env, recoveryToken);
    const grantId = await grantIdPaid(payment.payment_id);
    if (await grantOutcomeExists(env, grantId)) continue;
    const legacyOutcome = await env.DB.prepare(
      `SELECT result FROM grant_outcome WHERE grant_id = ?`,
    ).bind(grantId).first<{ result: string }>();
    const rejected = legacyOutcome?.result === "rejected" || legacyOutcome?.result === "conflict";
    const dedupeKey = `grant:${payment.payment_id}`;
    const existing = await env.DB.prepare(
      `SELECT work_id, state FROM work WHERE dedupe_key = ?`,
    ).bind(dedupeKey).first<{ work_id: string; state: string }>();
    if (existing === null) {
      const workId = await newId(env);
      statements.push(env.DB.prepare(
        `INSERT INTO work (
           work_id, kind, subject_id, dedupe_key, state, attempts,
           next_attempt_at, lease_until, last_error, opened_at
         ) VALUES (?, 'grant', ?, ?, ?, 0, ?, NULL, ?, ?)`,
      ).bind(
        workId, payment.payment_id, dedupeKey,
        rejected ? "parked" : "open", nowIso,
        rejected ? `recovered_${legacyOutcome!.result}` : null, nowIso,
      ));
    } else if (existing.state === "done" && !rejected) {
      statements.push(env.DB.prepare(
        `UPDATE work SET state = 'open', attempts = 0, next_attempt_at = ?,
           lease_until = NULL, lease_token = NULL, last_error = NULL
         WHERE work_id = ? AND state = 'done'`,
      ).bind(nowIso, existing.work_id));
    }
  }

  const reversals = await env.DB.prepare(
    `SELECT r.reversal_id, r.effect FROM reversal r
     LEFT JOIN reversal_outcome o ON o.reversal_id = r.reversal_id
     WHERE r.is_full = 1 AND r.effect IN ('tombstone', 'end_current', 'remove_queued')
       AND o.reversal_id IS NULL
     ORDER BY r.reversal_id ASC`,
  ).all<{ reversal_id: string; effect: string }>();
  for (const reversal of reversals.results ?? []) {
    await renewAboRecovery(env, recoveryToken);
    const dedupeKey = `reverse:${reversal.reversal_id}`;
    const existing = await env.DB.prepare(
      `SELECT work_id, state FROM work WHERE dedupe_key = ?`,
    ).bind(dedupeKey).first<{ work_id: string; state: string }>();
    if (existing !== null) {
      if (existing.state === "done") {
        statements.push(env.DB.prepare(
          `UPDATE work SET state = 'open', attempts = 0, next_attempt_at = ?,
             lease_until = NULL, lease_token = NULL, last_error = NULL
           WHERE work_id = ? AND state = 'done'`,
        ).bind(nowIso, existing.work_id));
      }
      continue; // In particular, retain a parked rejection.
    }
    const workId = await newId(env);
    statements.push(env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) VALUES (?, 'reverse', ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
    ).bind(workId, reversal.reversal_id, dedupeKey, nowIso, nowIso));
  }
  statements.push(env.DB.prepare(
    `INSERT INTO rebuild_due_checkpoint (id, last_fact_seq, updated_at)
     VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET last_fact_seq = excluded.last_fact_seq,
       updated_at = excluded.updated_at
     WHERE rebuild_due_checkpoint.last_fact_seq <= excluded.last_fact_seq`,
  ).bind(factHighWater, nowIso));
  await env.DB.batch(statements);

  const openReverse = await env.DB.prepare(
    `SELECT work_id FROM work WHERE kind = 'reverse' AND state = 'open'
     ORDER BY opened_at ASC, work_id ASC`,
  ).all<{ work_id: string }>();
  return (openReverse.results ?? []).map((row) => row.work_id);
}

async function restoreAcceptedErasureFences(
  env: RebuildEnv,
  recoveryToken: string,
): Promise<void> {
  const facts = await env.DB.prepare(
    `SELECT command_id, payload_json
     FROM command_recovery_fact
     WHERE fact_kind = 'command_intent'
     ORDER BY created_at ASC, fact_id ASC`,
  ).all<{ command_id: string; payload_json: string }>();
  for (const row of facts.results ?? []) {
    await renewAboRecovery(env, recoveryToken);
    const payload = JSON.parse(row.payload_json) as Record<string, unknown>;
    if (payload.method !== "erase_contact") continue;
    const orgId = payload.subject_id;
    const actorEmail = payload.actor_email;
    const generation = payload.erasure_generation;
    const cutoff = payload.acceptance_cutoff;
    const versions = payload.scope_contact_versions;
    if (
      typeof orgId !== "string" || typeof actorEmail !== "string" ||
      typeof generation !== "number" || !Number.isSafeInteger(generation) || generation < 1 ||
      typeof cutoff !== "string" || !Array.isArray(versions) || versions.length === 0 ||
      versions.some((v) => typeof v !== "number" || !Number.isSafeInteger(v) || v < 1)
    ) throw new Error(`rebuild_erasure_fact_invalid:${row.command_id}`);
    const scopeVersions = versions as number[];
    await env.DB.prepare(
      `INSERT INTO org_erasure_fence (org_id, generation, updated_at)
       VALUES (?, ?, ?)
       ON CONFLICT(org_id) DO UPDATE SET
         generation = MAX(org_erasure_fence.generation, excluded.generation),
         updated_at = CASE WHEN org_erasure_fence.generation < excluded.generation
           THEN excluded.updated_at ELSE org_erasure_fence.updated_at END`,
    ).bind(orgId, generation, cutoff).run();
    const placeholders = scopeVersions.map(() => "?").join(", ");
    await env.DB.prepare(
      `UPDATE billing_contact
       SET name = '', email = '', phone = '', erased_at = ?, erased_by = ?,
           erasure_generation = ?
       WHERE org_id = ? AND version IN (${placeholders})`,
    ).bind(cutoff, actorEmail, generation, orgId, ...scopeVersions).run();
    await eraseOrgRawEvidence(env, orgId, generation);
    await deleteScopedEvidenceBodies(env, {
      orgId,
      contactVersions: scopeVersions,
      cutoff,
    });
  }
}

async function restoreAcceptedLocalCommands(
  env: RebuildEnv,
  recoveryToken: string,
): Promise<void> {
  const intents = await env.DB.prepare(
    `SELECT command_id, payload_json
     FROM command_recovery_fact
     WHERE fact_kind = 'command_intent'
     ORDER BY created_at ASC, fact_id ASC`,
  ).all<{ command_id: string; payload_json: string }>();
  for (const row of intents.results ?? []) {
    await renewAboRecovery(env, recoveryToken);
    const payload = JSON.parse(row.payload_json) as Record<string, unknown>;
    if (payload.command_kind !== "local_hp") continue;
    const commandId = payload.command_id;
    const method = payload.method;
    const subject = payload.subject_id;
    const actor = payload.actor_email;
    const operationJson = payload.operation_json;
    const argsJson = payload.args_json;
    const challengeSha256 = payload.operation_sha256;
    const contractVersion = payload.contract_version;
    const acceptedAt = payload.accepted_at;
    const assertionJson = payload.assertion_json;
    if (
      typeof commandId !== "string" || commandId !== row.command_id ||
      typeof method !== "string" || !["release_payment", "manual_chargeback", "erase_contact"].includes(method) ||
      typeof subject !== "string" || typeof actor !== "string" ||
      typeof operationJson !== "string" || typeof argsJson !== "string" ||
      typeof challengeSha256 !== "string" || typeof contractVersion !== "number" ||
      typeof acceptedAt !== "string" || typeof assertionJson !== "string"
    ) throw new Error(`rebuild_local_command_fact_invalid:${row.command_id}`);
    const progress = await env.DB.prepare(
      `SELECT
         MAX(CASE WHEN fact_kind = 'local_result' THEN 1 ELSE 0 END) AS local_done
       FROM command_recovery_fact WHERE command_id = ?`,
    ).bind(commandId).first<{ local_done: number | null }>();
    const latestPlatformResult = await env.DB.prepare(
      `SELECT payload_json FROM command_recovery_fact
       WHERE command_id = ? AND fact_kind = 'platform_result'
       ORDER BY created_at DESC, fact_id DESC LIMIT 1`,
    ).bind(commandId).first<{ payload_json: string }>();
    const platformAccepted = latestPlatformResult !== null &&
      JSON.parse(latestPlatformResult.payload_json).result === "ok";
    const stage = platformAccepted
      ? "complete"
      : progress?.local_done === 1
        ? "local_applied"
        : "accepted";
    const generation = typeof payload.erasure_generation === "number"
      ? payload.erasure_generation
      : null;
    const maxVersion = typeof payload.scope_max_contact_version === "number"
      ? payload.scope_max_contact_version
      : null;
    const existing = await env.DB.prepare(
      `SELECT method, args_json, operation_json, actor_email, target,
              contract_version, action_id, command_kind, recovery_generation,
              recovery_scope_max_version
       FROM accepted_operator_command WHERE command_id = ?`,
    ).bind(commandId).first<Record<string, unknown>>();
    const expected = {
      method,
      args_json: argsJson,
      operation_json: operationJson,
      actor_email: actor,
      target: subject,
      contract_version: contractVersion,
      action_id: commandId,
      command_kind: "local_hp",
      recovery_generation: generation,
      recovery_scope_max_version: maxVersion,
    };
    if (existing !== null && new TextDecoder().decode(canonicalize(existing)) !==
        new TextDecoder().decode(canonicalize(expected))) {
      throw new Error(`rebuild_local_command_conflict:${commandId}`);
    }
    if (existing === null) {
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO accepted_operator_command (
             challenge_sha256, command_id, method, args_json, operation_json,
             assertion_json, actor_email, target, contract_version, action_id,
             command_kind, stage, due_at, lease_until, lease_token, result_json,
             created_at, updated_at, recovery_generation, recovery_scope_max_version
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'local_hp', ?, ?, NULL, NULL, ?, ?, ?, ?, ?)`
        ).bind(
          challengeSha256,
          commandId,
          method,
          argsJson,
          operationJson,
          assertionJson,
          actor,
          subject,
          contractVersion,
          commandId,
          stage,
          acceptedAt,
          stage === "complete" ? "{}" : null,
          acceptedAt,
          acceptedAt,
          generation,
          maxVersion,
        ),
        env.DB.prepare(
          `INSERT INTO assertion_used (challenge_sha256)
           VALUES (?) ON CONFLICT(challenge_sha256) DO NOTHING`,
        ).bind(challengeSha256),
      ]);
    } else {
      await env.DB.prepare(
        `INSERT INTO assertion_used (challenge_sha256)
         VALUES (?) ON CONFLICT(challenge_sha256) DO NOTHING`,
      ).bind(challengeSha256).run();
    }
  }
}

async function restoreAcceptedRelayCommands(
  env: RebuildEnv,
  recoveryToken: string,
): Promise<void> {
  const facts = await env.DB.prepare(
    `SELECT command_id, payload_json
     FROM command_recovery_fact
     WHERE fact_kind = 'relay_reserved'
     ORDER BY created_at ASC, fact_id ASC`,
  ).all<{ command_id: string; payload_json: string }>();
  for (const row of facts.results ?? []) {
    await renewAboRecovery(env, recoveryToken);
    const payload = JSON.parse(row.payload_json) as Record<string, unknown>;
    if (payload.method !== "beginTransfer" || payload.command_kind !== "relay") continue;
    const safeArgs = payload.safe_args;
    if (
      typeof payload.command_id !== "string" || payload.command_id !== row.command_id ||
      typeof payload.operation_sha256 !== "string" ||
      typeof payload.actor_email !== "string" || typeof payload.subject_id !== "string" ||
      typeof payload.contract_version !== "number" || typeof payload.accepted_at !== "string" ||
      !isRecord(safeArgs) || safeArgs.org_id !== payload.subject_id ||
      typeof safeArgs.from_installation_id !== "string" ||
      typeof safeArgs.reason_sha256 !== "string"
    ) throw new Error(`rebuild_relay_command_fact_invalid:${row.command_id}`);
    const argsJson = new TextDecoder().decode(canonicalize(safeArgs));
    const existing = await env.DB.prepare(
      `SELECT challenge_sha256, method, args_json, actor_email,
              target, contract_version, action_id, command_kind
       FROM accepted_operator_command WHERE command_id = ?`,
    ).bind(row.command_id).first<Record<string, unknown>>();
    const expected = {
      challenge_sha256: payload.operation_sha256,
      method: "beginTransfer",
      args_json: argsJson,
      actor_email: payload.actor_email,
      target: payload.subject_id,
      contract_version: payload.contract_version,
      action_id: row.command_id,
      command_kind: "relay",
    };
    if (existing !== null) {
      const existingIdentity = { ...existing };
      if (new TextDecoder().decode(canonicalize(existingIdentity)) !==
          new TextDecoder().decode(canonicalize(expected))) {
        throw new Error(`rebuild_relay_command_conflict:${row.command_id}`);
      }
      continue;
    }
    await env.DB.prepare(
      `INSERT INTO accepted_operator_command (
         challenge_sha256, command_id, method, args_json, operation_json,
         assertion_json, actor_email, target, contract_version, action_id,
         command_kind, stage, due_at, lease_until, lease_token, result_json,
         created_at, updated_at
       ) VALUES (?, ?, 'beginTransfer', ?, '', NULL, ?, ?, ?, ?, 'relay',
                 'awaiting_operator_auth', ?, NULL, NULL, NULL, ?, ?)`,
    ).bind(
      payload.operation_sha256,
      row.command_id,
      argsJson,
      payload.actor_email,
      payload.subject_id,
      payload.contract_version,
      row.command_id,
      payload.accepted_at,
      payload.accepted_at,
      payload.accepted_at,
    ).run();
  }
}

async function insertRecoveryFinding(
  env: RebuildEnv,
  kind: string,
  subject: string,
  detail: string,
  at: string,
): Promise<void> {
  const findingId = await sha256Hex(canonicalize({ kind, subject }));
  const row = { finding_id: findingId, kind, subject, detail, detected_at: at };
  const rowJson = new TextDecoder().decode(canonicalize(row));
  const rowSha256 = await sha256Hex(canonicalize(row));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO finding (finding_id, kind, subject, detail, detected_at)
       VALUES (?, ?, ?, ?, ?) ON CONFLICT(finding_id) DO NOTHING`,
    ).bind(findingId, kind, subject, detail, at),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
       SELECT 'finding', ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM finding WHERE finding_id = ?)
         AND NOT EXISTS (SELECT 1 FROM fact_log WHERE "table" = 'finding' AND key = ?)`,
    ).bind(findingId, rowSha256, rowJson, at, findingId, findingId),
  ]);
}

async function hasExactTransferAcknowledgement(
  commandId: string,
  reservation: Record<string, unknown>,
  result: Record<string, unknown>,
): Promise<boolean> {
  const safeArgs = reservation.safe_args;
  const mapping = result.transfer_mapping;
  if (!isRecord(safeArgs) || !isRecord(mapping)) return false;
  if (
    reservation.command_id !== commandId || reservation.method !== "beginTransfer" ||
    reservation.command_kind !== "relay" || reservation.authority_action_id !== commandId ||
    typeof reservation.operation_sha256 !== "string" ||
    !/^[a-f0-9]{64}$/u.test(reservation.operation_sha256) ||
    typeof reservation.subject_id !== "string" ||
    typeof reservation.actor_email !== "string" || reservation.actor_email.length === 0 ||
    typeof reservation.signer_credential_id !== "string" ||
    reservation.signer_credential_id.length === 0 ||
    typeof reservation.signer_public_key_cose !== "string" ||
    reservation.signer_public_key_cose.length === 0 ||
    typeof reservation.assertion_sha256 !== "string" ||
    !/^[a-f0-9]{64}$/u.test(reservation.assertion_sha256) ||
    reservation.contract_version !== result.contract_version ||
    safeArgs.org_id !== reservation.subject_id ||
    typeof safeArgs.from_installation_id !== "string" ||
    result.command_id !== commandId || result.method !== "beginTransfer" ||
    result.phase !== "beginTransfer" ||
    result.provenance !== "authenticated_platform_beginTransfer_call" ||
    result.result !== "ok" || result.subject_id !== reservation.subject_id ||
    result.transfer_id !== mapping.transfer_id ||
    mapping.org_id !== reservation.subject_id ||
    mapping.from_installation_id !== safeArgs.from_installation_id ||
    typeof mapping.transfer_id !== "string" || mapping.transfer_id.length === 0 ||
    typeof mapping.to_installation_id !== "string" || mapping.to_installation_id.length === 0 ||
    mapping.assertion_sha256 !== reservation.operation_sha256 ||
    typeof mapping.created_at !== "string" || !Number.isSafeInteger(Date.parse(mapping.created_at)) ||
    typeof result.response_sha256 !== "string" || !/^[a-f0-9]{64}$/u.test(result.response_sha256) ||
    typeof result.response_json !== "string"
  ) return false;
  try {
    const response = JSON.parse(result.response_json) as Record<string, unknown>;
    const responseMapping = typeof response.detail === "string"
      ? JSON.parse(response.detail) as unknown
      : null;
    const canonicalResponse = canonicalize(response);
    return response.result === "ok" && response.contract_version === result.contract_version &&
      new TextDecoder().decode(canonicalResponse) === result.response_json &&
      await sha256Hex(canonicalResponse) === result.response_sha256 &&
      isRecord(responseMapping) &&
      new TextDecoder().decode(canonicalize(responseMapping)) ===
        new TextDecoder().decode(canonicalize(mapping));
  } catch {
    return false;
  }
}

async function verifiedTerminalTransferResult(
  env: RebuildEnv,
  commandId: string,
  commandFacts: Array<{ kind: string; payload: Record<string, unknown>; at: string }>,
  transferId: string,
  mapping: Record<string, unknown>,
  contractVersion: number,
): Promise<string | null> {
  for (const fact of commandFacts) {
    const payload = fact.payload;
    if (
      fact.kind !== "platform_result" || payload.phase !== "transferIn" ||
      payload.command_id !== commandId || payload.transfer_id !== transferId ||
      payload.subject_id !== transferId ||
      (payload.result !== "applied" && payload.result !== "already_applied") ||
      payload.provenance !== "authenticated_platform_transfer_step_call" ||
      payload.contract_version !== contractVersion ||
      typeof payload.response_sha256 !== "string" ||
      !/^[a-f0-9]{64}$/u.test(payload.response_sha256) ||
      !Number.isSafeInteger(Date.parse(String(payload.at ?? ""))) ||
      typeof payload.response_json !== "string"
    ) continue;
    try {
      const response = JSON.parse(payload.response_json) as Record<string, unknown>;
      const canonicalResponse = canonicalize(response);
      if (
        response.result === payload.result &&
        response.code === payload.code &&
        response.contract_version === contractVersion &&
        new TextDecoder().decode(canonicalResponse) === payload.response_json &&
        await sha256Hex(canonicalResponse) === payload.response_sha256 &&
        response.receipt !== undefined && await verifyTransferReceipt({
          platformPublicKeys: env.PLATFORM_PUBLIC_KEYS,
          receipt: response.receipt,
          transferId,
          orgId: String(mapping.org_id),
          installationId: String(mapping.to_installation_id),
          contractVersion,
        })
      ) return payload.response_json;
    } catch {
      continue;
    }
  }
  return null;
}

async function restoreCommandRecoveryWork(
  env: RebuildEnv,
  recoveryToken: string,
): Promise<void> {
  const facts = await env.DB.prepare(
    `SELECT command_id, fact_kind, payload_json, created_at
     FROM command_recovery_fact
     WHERE fact_kind IN ('command_intent', 'relay_reserved', 'platform_result', 'local_result')
     ORDER BY created_at ASC, fact_id ASC`,
  ).all<{ command_id: string; fact_kind: string; payload_json: string; created_at: string }>();
  const byCommand = new Map<string, Array<{ kind: string; payload: Record<string, unknown>; at: string }>>();
  for (const fact of facts.results ?? []) {
    const list = byCommand.get(fact.command_id) ?? [];
    list.push({
      kind: fact.fact_kind,
      payload: JSON.parse(fact.payload_json) as Record<string, unknown>,
      at: fact.created_at,
    });
    byCommand.set(fact.command_id, list);
  }
  const now = await clockNowIso(env);
  for (const [commandId, commandFacts] of byCommand) {
    await renewAboRecovery(env, recoveryToken);
    const intent = commandFacts.find((fact) =>
      fact.kind === "command_intent" || fact.kind === "relay_reserved",
    );
    if (intent === undefined) continue;
    const method = intent.payload.method;
    const subjectId = intent.payload.subject_id;
    const resultFact = commandFacts.find((fact) =>
      fact.kind === "platform_result" &&
      (fact.payload.phase === "beginTransfer" || fact.payload.phase === "platform_operator_action"),
    );
    if (method === "beginTransfer") {
      const transferId = resultFact?.payload.transfer_id;
      const transferMapping = resultFact?.payload.transfer_mapping;
      const accepted = await env.DB.prepare(
        `SELECT challenge_sha256, method, actor_email, target, contract_version,
                action_id, command_kind
         FROM accepted_operator_command WHERE command_id = ?`,
      ).bind(commandId).first<{
        challenge_sha256: string;
        method: string;
        actor_email: string;
        target: string;
        contract_version: number;
        action_id: string;
        command_kind: string;
      }>();
      const confirmed = resultFact !== undefined &&
        intent.payload.command_kind === "relay" &&
        typeof intent.payload.command_id === "string" &&
        intent.payload.command_id === commandId &&
        accepted !== null && accepted.challenge_sha256 === intent.payload.operation_sha256 &&
        accepted.method === "beginTransfer" && accepted.actor_email === intent.payload.actor_email &&
        accepted.target === subjectId && accepted.contract_version === intent.payload.contract_version &&
        accepted.action_id === commandId && accepted.command_kind === "relay" &&
        isRecord(transferMapping) && transferMapping.transfer_id === transferId &&
        await hasExactTransferAcknowledgement(commandId, intent.payload, resultFact.payload);
      if (confirmed && typeof transferId === "string") {
        const terminalResult = await verifiedTerminalTransferResult(
          env,
          commandId,
          commandFacts,
          transferId,
          transferMapping as Record<string, unknown>,
          Number(intent.payload.contract_version),
        );
        if (terminalResult !== null) {
          await env.DB.prepare(
            `UPDATE accepted_operator_command
             SET stage = 'complete', result_json = ?, lease_until = NULL, lease_token = NULL
             WHERE command_id = ? AND method = 'beginTransfer'`,
          ).bind(terminalResult, commandId).run();
          continue;
        }
      }
      // A recovered ACK proves correlation only. It cannot authorize remaining
      // value-moving steps; only a verified terminal receipt restores completion.
      const blockedKind = !confirmed && resultFact !== undefined
        ? "blocked_missing_transfer_correlation"
        : "blocked_missing_original_authorization";
      const disputedDetail = confirmed
        ? `${blockedKind}:transfer_id=${transferId}`
        : blockedKind;
      await env.DB.batch(await commandFactStatements(env, {
        commandId,
        kind: "local_result",
        payload: {
          payload_version: 1,
          command_id: commandId,
          method: "beginTransfer",
          subject_id: subjectId,
          result: blockedKind,
          code: "recovery_evidence_required",
          contract_version: intent.payload.contract_version,
          ...(confirmed && typeof transferId === "string"
            ? { transfer_id: transferId }
            : {}),
          at: intent.at,
        },
        createdAt: intent.at,
      }));
      await insertRecoveryFinding(
        env,
        "accepted_transfer_disputed",
        commandId,
        disputedDetail,
        intent.at,
      );
      await env.DB.prepare(
        `INSERT INTO work (
           work_id, kind, subject_id, dedupe_key, state, attempts,
           next_attempt_at, lease_until, last_error, opened_at
         ) VALUES (?, 'accepted_command', ?, ?, 'awaiting_operator_auth', 0, NULL, NULL, ?, ?)
         ON CONFLICT(dedupe_key) DO UPDATE SET
           state = 'awaiting_operator_auth', last_error = excluded.last_error,
           lease_until = NULL`,
      ).bind(await newId(env), commandId, `accepted_command:${commandId}`, blockedKind, intent.at).run();
      continue;
    }
    if (intent.payload.command_kind === "local_hp" && resultFact === undefined) {
      await env.DB.prepare(
        `INSERT INTO work (
           work_id, kind, subject_id, dedupe_key, state, attempts,
           next_attempt_at, lease_until, last_error, opened_at
         ) VALUES (?, 'accepted_command', ?, ?, 'awaiting_operator_auth', 0, NULL, NULL, 'awaiting_operator_auth', ?)
         ON CONFLICT(dedupe_key) DO NOTHING`,
      ).bind(await newId(env), commandId, `accepted_command:${commandId}`, now).run();
    }
  }
}

async function stopLegacyAcceptedCommands(
  env: RebuildEnv,
  recoveryToken: string,
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT command_id, target, created_at
     FROM accepted_operator_command c
     WHERE c.method IN ('beginTransfer', 'erase_contact', 'release_payment', 'manual_chargeback')
       AND NOT EXISTS (
         SELECT 1 FROM command_recovery_fact f
         WHERE f.command_id = c.command_id
           AND f.fact_kind IN ('command_intent', 'relay_reserved')
       )
     ORDER BY c.created_at, c.command_id`,
  ).all<{ command_id: string; target: string; created_at: string }>();
  for (const row of rows.results ?? []) {
    await renewAboRecovery(env, recoveryToken);
    await insertRecoveryFinding(
      env,
      "accepted_command_disputed",
      row.command_id,
      "blocked_missing_original_authorization",
      row.created_at,
    );
    await env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) VALUES (?, 'accepted_command', ?, ?, 'awaiting_operator_auth', 0, NULL, NULL,
                'blocked_missing_original_authorization', ?)
       ON CONFLICT(dedupe_key) DO NOTHING`,
    ).bind(
      await newId(env),
      row.command_id,
      `accepted_command:${row.command_id}`,
      row.created_at,
    ).run();
  }
}

async function inquireGapPayments(
  env: RebuildEnv,
  provider: NonNullable<ReturnType<typeof providerForId>>,
  options: RebuildOptions,
): Promise<string[]> {
  const gapFilledPaymentIds: string[] = [];

  // Explicit transaction references are the operator's stated repair target.
  // Give them the shared inquiry slots before broad recovery scans consume the
  // per-minute cap; remaining scans stay read-only when they are deferred.
  for (const reference of options.providerTransactionReferences) {
    const candidates = await env.DB.prepare(
      `SELECT DISTINCT a.checkout_id
       FROM paymob_intention_attempt a
       LEFT JOIN payment p ON p.checkout_id = a.checkout_id
       WHERE a.state = 'created' AND a.order_id IS NOT NULL AND p.payment_id IS NULL`,
    ).all<{ checkout_id: string }>();
    for (const candidate of candidates.results ?? []) {
      const inquiry = await provider.inquire({
        checkout_id: candidate.checkout_id,
        paymob_txn_id: reference,
      });
      gapFilledPaymentIds.push(...await processAuthoritativeInquiry(
        env,
        candidate.checkout_id,
        inquiry,
        reference,
      ));
    }
  }

  const checkouts = await env.DB.prepare(
    `SELECT checkout_id FROM checkout`,
  ).all<{ checkout_id: string }>();
  for (const checkout of checkouts.results ?? []) {
    const inquiry = await provider.inquire({ checkout_id: checkout.checkout_id });
    gapFilledPaymentIds.push(...await processAuthoritativeInquiry(
      env,
      checkout.checkout_id,
      inquiry,
    ));
  }

  const payments = await env.DB.prepare(
    `SELECT payment_id FROM payment`,
  ).all<{ payment_id: string }>();
  for (const payment of payments.results ?? []) {
    const inquiry = await provider.inquire({ payment_id: payment.payment_id });
    const row = await env.DB.prepare(
      `SELECT checkout_id FROM payment WHERE payment_id = ?`,
    ).bind(payment.payment_id).first<{ checkout_id: string }>();
    if (row !== null) {
      gapFilledPaymentIds.push(...await processAuthoritativeInquiry(
        env,
        row.checkout_id,
        inquiry,
      ));
    }
  }

  return gapFilledPaymentIds;
}

export async function rebuildAbo(
  env: RebuildEnv,
  options: RebuildOptions,
): Promise<void> {
  const recoveryToken = await acquireAboRecovery(env);
  const lines = await listLedgerLines(env, recoveryToken);
  await replayLedger(env, lines, recoveryToken);
  await restoreAcceptedErasureFences(env, recoveryToken);
  await restoreAcceptedLocalCommands(env, recoveryToken);
  await restoreAcceptedRelayCommands(env, recoveryToken);
  await restoreCommandRecoveryWork(env, recoveryToken);
  await stopLegacyAcceptedCommands(env, recoveryToken);
  await renewAboRecovery(env, recoveryToken);
  await recomputeCheckoutStatus(env);
  await ensureLegacyAttemptEvents(env);
  await rebuildIntentionAttempts(env);
  await markUncorrelatedCheckoutsDisputed(env);
  await refreshCoverageView(env);
  await renewAboRecovery(env, recoveryToken);

  const reverseWorkIds = await restoreDueWorkFromFacts(
    env,
    lines.at(-1)?.fact_seq ?? 0,
    recoveryToken,
  );
  // Publish only after immutable facts, erasure fences, projections, and due
  // work are complete. Worker fetches and scheduled work stay fenced until here.
  await publishAboRecovery(env, recoveryToken);

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  let gapFilledPaymentIds: string[] = [];
  if (provider !== null) {
    gapFilledPaymentIds = await inquireGapPayments(env, provider, options);
  }

  await runDueGrantWork(env, 100);
  for (const workId of reverseWorkIds) {
    await processReverseWork(env as unknown as ReversalEnv, workId);
  }
  if (provider !== null) {
    // Platform listing is an independent witness for known payment identities;
    // it never supplies a payment id or creates an order/request during rebuild.
    await awaitGapGrantsInList(env, gapFilledPaymentIds);
  }
  await refreshCoverageView(env);

  // R9-CRON1: an incomplete reconciliation is not a verified rebuild.
  if ((await runReconciliation(env)) !== "succeeded") {
    throw new Error("reconciliation_incomplete");
  }
}
