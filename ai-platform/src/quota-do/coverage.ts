import {
  CHANNEL_VERSIONS,
  canonicalize,
  coverageEventId,
  grantEnvelopeHash,
  receiptSigningBytes,
  sha256Hex,
  signCompactJws,
} from "vendor-contracts";
import { addDuration, type DurationScale } from "../coverage/calendar";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import { generateUlid } from "../trace";
type SqlStorage = DurableObjectStorage & {
  sql?: {
    exec: (query: string, ...bindings: unknown[]) => Iterable<Record<string, unknown>>;
  };
};

export function sqlExec(storage: DurableObjectStorage, query: string): void {
  const sqlStorage = storage as SqlStorage;
  if (!sqlStorage.sql) {
    return;
  }
  sqlStorage.sql.exec(query);
}

export function sqlSelect<T extends Record<string, unknown>>(
  storage: DurableObjectStorage,
  query: string,
): T[] {
  const sqlStorage = storage as SqlStorage;
  if (!sqlStorage.sql) {
    return [];
  }
  return [...sqlStorage.sql.exec(query)] as T[];
}

export function sqlString(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

export type HotRow = {
  suspended: number;
  transferred_out_to?: string | null;
  awaiting_transfer?: number;
  transfer_pending?: number;
  active_term_id: string | null;
  used: number;
  reserved: number;
  grace_base_used: number;
  reservations: string;
  replay: string;
  idempotency: string;
  band_emitted: string;
  binding_epoch: number;
  clinic_seq: number;
  next_alarm_at: string | null;
};

export type TermRow = {
  term_id: string;
  grant_id: string;
  origin_grant_id: string;
  position: number;
  state: string;
  end_reason: string | null;
  plan_snapshot: string;
  allowance: number | null;
  used_final: number | null;
  duration_unit: string | null;
  duration_count: number | null;
  grace_days: number | null;
  grace_cap: string | null;
  calendar_start: string | null;
  starts_at: string | null;
  ends_at: string | null;
  grace_ends_at: string | null;
  ended_at: string | null;
};

type GrantRow = {
  grant_id: string;
  envelope_sha256: string;
  receipt: string | null;
};

export type PlanSnapshot = {
  plan_id: string;
  version: number;
  display_name: string;
  capabilities: unknown;
  max_cost_class: string;
  concurrency_limit: number;
};

export type CeilingPolicyNumbers = {
  per_grant_max_days: number;
  per_grant_max_allowance_months: number;
  window_days: number;
  window_max_days: number;
  window_max_allowance_months: number;
};

export interface ApplyGrantRequest {
  kind: "apply_grant";
  installationId: string;
  bindingEpoch: number;
  vendorContractVersion: number;
  orgId: string;
  envelope: Record<string, unknown>;
  aboKid?: string;
  planSnapshot: PlanSnapshot;
  durationUnit?: "month" | "day";
  durationCount?: number;
  allowanceCredits: number;
  graceDays?: number;
  operatorCredentialId: string;
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  nowIso: string;
  db: D1Database;
  sourceKind?: "paid" | "complimentary";
  envelopeKind?: "term" | "term_adjustment";
  planMaxAllowancePerMonth?: number;
  ceilingPolicy?: CeilingPolicyNumbers;
  skipCeilingCheck?: boolean;
  adjustment?: Record<string, unknown>;
}

export interface ApplyGrantResponse {
  kind: "apply_grant";
  result:
    | "applied"
    | "already_applied"
    | "conflict"
    | "exceeds_ceiling"
    | "bad_request"
    | "rejected"
    | "transient";
  code?: string;
  detail?: string;
  receipt?: Record<string, unknown>;
}

export interface ReadCoverageRequest {
  kind: "read_coverage";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  durationScale?: DurationScale;
  nowIso?: string;
}

export interface ReadCoverageResponse {
  kind: "read_coverage";
  snapshot: Record<string, unknown>;
  queued_terms: Record<string, unknown>[];
  recent_terms: Record<string, unknown>[];
}

export type CoverageShipEnv = CoverageAlertEnv & {
  DB: D1Database;
  R2: R2Bucket;
};

type PlatformSigningMaterial = {
  kid: string;
  privateKey: CryptoKey;
};

function base64UrlToBytes(segment: string): Uint8Array {
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function loadPlatformSigningKey(
  json: string,
): Promise<PlatformSigningMaterial | null> {
  try {
    const parsed = JSON.parse(json) as {
      kid?: string;
      pkcs8?: string;
    };
    if (typeof parsed.kid !== "string" || typeof parsed.pkcs8 !== "string") {
      return null;
    }
    const pkcs8 = base64UrlToBytes(parsed.pkcs8);
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      pkcs8,
      { name: "Ed25519" },
      false,
      ["sign"],
    );
    return { kid: parsed.kid, privateKey };
  } catch {
    return null;
  }
}

function ensureHotRow(storage: DurableObjectStorage, bindingEpoch: number): void {
  const rows = sqlSelect<HotRow>(storage, "SELECT binding_epoch FROM hot LIMIT 1");
  if (rows.length > 0) {
    return;
  }
  sqlExec(
    storage,
    `INSERT INTO hot (
      suspended, transferred_out_to, awaiting_transfer, transfer_pending,
      active_term_id, used, reserved, grace_base_used, reservations, replay,
      idempotency, band_emitted, binding_epoch, clinic_seq, next_alarm_at
    ) VALUES (
      0, NULL, 0, 0, NULL, 0, 0, 0, '[]', '{}', '{}', '{}', ${bindingEpoch}, 0, NULL
    )`,
  );
}

export function loadHot(storage: DurableObjectStorage): HotRow {
  const rows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
  if (rows.length === 0) {
    throw new Error("hot row missing");
  }
  return rows[0]!;
}

export function loadTerms(storage: DurableObjectStorage): TermRow[] {
  return sqlSelect<TermRow>(
    storage,
    "SELECT * FROM term ORDER BY position ASC",
  );
}

function termGraceEndsAtDisplay(term: TermRow): string {
  return term.grace_ends_at ?? "";
}

function computeCoverageThrough(
  terms: TermRow[],
  hot: HotRow,
  durationScale?: DurationScale,
): string {
  const active = terms.find((term) => term.state === "active");
  if (active === undefined || active.ends_at === null) {
    return "";
  }
  let cursor = active.ends_at;
  const queued = terms.filter((term) => term.state === "queued");
  for (const term of queued) {
    if (term.duration_unit === null || term.duration_count === null) {
      continue;
    }
    cursor = addDuration(
      cursor,
      term.duration_unit as "month" | "day",
      term.duration_count,
      durationScale,
    );
  }
  return cursor;
}

export function allowanceBand(
  used: number,
  allowance: number,
  termState: string,
): "ok" | "75" | "90" | "exhausted" {
  if (termState === "exhausted") {
    return "exhausted";
  }
  if (!(allowance > 0)) {
    return "ok";
  }
  const ratio = used / allowance;
  if (ratio >= 0.9) {
    return "90";
  }
  if (ratio >= 0.75) {
    return "75";
  }
  return "ok";
}

function snapshotTermObject(
  term: TermRow,
  hot: HotRow,
): Record<string, unknown> {
  const used =
    term.term_id === hot.active_term_id ? hot.used : (term.used_final ?? 0);
  const snapshot = JSON.parse(term.plan_snapshot) as {
    display_name?: string;
    capabilities?: unknown;
  };
  const allowance = term.allowance ?? 0;
  const capabilities = Array.isArray(snapshot.capabilities)
    ? snapshot.capabilities.filter((entry): entry is string => typeof entry === "string")
    : [];
  return {
    ref: term.term_id,
    plan_display_name: snapshot.display_name ?? "",
    starts_at: term.starts_at ?? "",
    ends_at: term.ends_at ?? "",
    grace_ends_at: termGraceEndsAtDisplay(term),
    allowance,
    used,
    band: allowanceBand(used, allowance, term.state),
    capabilities,
  };
}

function lastEndedTermForSnapshot(terms: TermRow[]): TermRow | undefined {
  const ended = terms.filter(
    (term) => term.state === "ended" || term.state === "exhausted",
  );
  if (ended.length === 0) {
    return undefined;
  }
  return ended.sort((left, right) => right.position - left.position)[0];
}

function lapsedSnapshotReason(terms: TermRow[]): string {
  const last = lastEndedTermForSnapshot(terms);
  if (last?.end_reason === "expired") {
    return "expired";
  }
  if (last?.end_reason === "grace_exhausted") {
    return "grace_exhausted";
  }
  return "none";
}

function coverageSnapshotHotFields(hot: HotRow): Record<string, unknown> {
  const fields: Record<string, unknown> = {
    grace_base_used: hot.grace_base_used,
    awaiting_transfer: hot.awaiting_transfer ?? 0,
    transfer_pending: hot.transfer_pending ?? 0,
  };
  if (
    hot.transferred_out_to !== undefined &&
    hot.transferred_out_to !== null &&
    hot.transferred_out_to.length > 0
  ) {
    fields.transferred_out_to = hot.transferred_out_to;
  }
  return fields;
}

function buildSnapshotTermsArray(
  terms: TermRow[],
  hot: HotRow,
): Record<string, unknown>[] {
  return terms.map((term) => ({
    term_id: term.term_id,
    grant_id: term.grant_id,
    origin_grant_id: term.origin_grant_id,
    position: term.position,
    state: term.state,
    end_reason: term.end_reason,
    plan_snapshot: term.plan_snapshot,
    allowance: term.allowance,
    used:
      term.term_id === hot.active_term_id ? hot.used : (term.used_final ?? 0),
    used_final: term.used_final,
    duration_unit: term.duration_unit,
    duration_count: term.duration_count,
    grace_days: term.grace_days,
    grace_cap: term.grace_cap,
    calendar_start: term.calendar_start,
    starts_at: term.starts_at,
    ends_at: term.ends_at,
    grace_ends_at: term.grace_ends_at,
    ended_at: term.ended_at,
    held: term.state === "held",
  }));
}

export function buildCoverageSnapshot(input: {
  vendorContractVersion: number;
  orgId: string;
  hot: HotRow;
  terms: TermRow[];
  durationScale?: DurationScale;
}): Record<string, unknown> {
  if (
    input.hot.transferred_out_to !== undefined &&
    input.hot.transferred_out_to !== null &&
    input.hot.transferred_out_to.length > 0
  ) {
    const queued = input.terms.filter((term) => term.state === "queued");
    const held = input.terms.filter((term) => term.state === "held");
    return {
      contract_version: input.vendorContractVersion,
      state: "transferred",
      reason: "none",
      suspended: input.hot.suspended !== 0,
      term: null,
      queued_count: queued.length,
      held_count: held.length,
      coverage_through: computeCoverageThrough(
        input.terms,
        input.hot,
        input.durationScale,
      ),
      binding_epoch: input.hot.binding_epoch,
      clinic_seq: input.hot.clinic_seq,
      terms: buildSnapshotTermsArray(input.terms, input.hot),
      ...coverageSnapshotHotFields(input.hot),
    };
  }

  const active = input.terms.find((term) => term.state === "active");
  const grace = input.terms.find((term) => term.state === "grace");
  const queued = input.terms.filter((term) => term.state === "queued");
  const held = input.terms.filter((term) => term.state === "held");
  let termObject: Record<string, unknown> | null = null;
  let coverageState: string;
  let reason = "none";

  if (active !== undefined) {
    coverageState = "active";
    termObject = snapshotTermObject(active, input.hot);
  } else if (grace !== undefined) {
    coverageState = "grace";
    termObject = snapshotTermObject(grace, input.hot);
  } else {
    const lastEnded = lastEndedTermForSnapshot(input.terms);
    if (lastEnded?.state === "exhausted") {
      coverageState = "exhausted";
    } else if (lastEnded?.end_reason === "reversed") {
      coverageState = "reversed";
      reason = "reversed";
    } else {
      coverageState = "lapsed";
      reason = lapsedSnapshotReason(input.terms);
    }
  }

  return {
    contract_version: input.vendorContractVersion,
    state: coverageState,
    reason,
    suspended: input.hot.suspended !== 0,
    term: termObject,
    queued_count: queued.length,
    held_count: held.length,
    coverage_through: computeCoverageThrough(
      input.terms,
      input.hot,
      input.durationScale,
    ),
    binding_epoch: input.hot.binding_epoch,
    clinic_seq: input.hot.clinic_seq,
    terms: buildSnapshotTermsArray(input.terms, input.hot),
    ...coverageSnapshotHotFields(input.hot),
  };
}

function buildQueuedTerms(terms: TermRow[]): Record<string, unknown>[] {
  return terms
    .filter((term) => term.state === "queued")
    .map((term) => {
      const snapshot = JSON.parse(term.plan_snapshot) as {
        plan_id: string;
        version: number;
        display_name: string;
      };
      return {
        plan_id: snapshot.plan_id,
        plan_version: snapshot.version,
        plan_display_name: snapshot.display_name,
        duration_unit: term.duration_unit,
        duration_count: term.duration_count,
      };
    });
}

function buildRecentTerms(terms: TermRow[], hot: HotRow): Record<string, unknown>[] {
  const eligible = terms
    .filter((term) =>
      term.state === "active" || term.state === "grace" || term.state === "ended",
    )
    .sort((left, right) => right.position - left.position)
    .slice(0, 12);
  return eligible.map((term) => {
    const snapshot = JSON.parse(term.plan_snapshot) as { display_name?: string };
    const used =
      term.term_id === hot.active_term_id ? hot.used : (term.used_final ?? 0);
    return {
      term_id: term.term_id,
      state: term.state,
      plan_display_name: snapshot.display_name ?? "",
      starts_at: term.starts_at ?? "",
      ends_at: term.ends_at ?? "",
      grace_ends_at: termGraceEndsAtDisplay(term),
      allowance: term.allowance ?? 0,
      used,
    };
  });
}

function nextTermPosition(terms: TermRow[]): number {
  if (terms.length === 0) {
    return 1;
  }
  return Math.max(...terms.map((term) => term.position)) + 1;
}

async function signReceipt(input: {
  signingKey: PlatformSigningMaterial;
  vendorContractVersion: number;
  grantId: string;
  installationId: string;
  orgId: string;
  termIds: string[];
  appliedAt: string;
  ledgerSeq: number;
  envelopeSha256: string;
}): Promise<Record<string, unknown>> {
  const unsigned = {
    contract_version: input.vendorContractVersion,
    grant_id: input.grantId,
    installation_id: input.installationId,
    org_id: input.orgId,
    result: "applied",
    term_ids: input.termIds,
    applied_at: input.appliedAt,
    ledger_seq: input.ledgerSeq,
    envelope_sha256: input.envelopeSha256,
    kid: input.signingKey.kid,
  };
  const signature = await signCompactJws({
    payload: receiptSigningBytes(unsigned),
    privateKey: input.signingKey.privateKey,
    kid: input.signingKey.kid,
  });
  return { ...unsigned, signature };
}

async function signReversalVoidReceipt(input: {
  signingKey: PlatformSigningMaterial;
  vendorContractVersion: number;
  reversalId: string;
  installationId: string;
  orgId: string;
  termIds: string[];
  appliedAt: string;
  ledgerSeq: number;
  envelopeSha256: string;
}): Promise<Record<string, unknown>> {
  const unsigned = {
    contract_version: input.vendorContractVersion,
    reversal_id: input.reversalId,
    installation_id: input.installationId,
    org_id: input.orgId,
    result: "applied",
    term_ids: input.termIds,
    applied_at: input.appliedAt,
    ledger_seq: input.ledgerSeq,
    envelope_sha256: input.envelopeSha256,
    kid: input.signingKey.kid,
  };
  const signature = await signCompactJws({
    payload: receiptSigningBytes(unsigned),
    privateKey: input.signingKey.privateKey,
    kid: input.signingKey.kid,
  });
  return { ...unsigned, signature };
}

type StoredVoidReplay = {
  grant_id: string;
  reason: string;
  evidence_sha256: string;
  receipt: Record<string, unknown>;
};

function readVoidReplay(storage: DurableObjectStorage): Record<string, StoredVoidReplay> {
  const hot = loadHot(storage);
  try {
    const parsed = JSON.parse(hot.replay) as Record<string, StoredVoidReplay>;
    return parsed ?? {};
  } catch {
    return {};
  }
}

function writeVoidReplay(
  storage: DurableObjectStorage,
  reversalId: string,
  entry: StoredVoidReplay,
): void {
  const replay = readVoidReplay(storage);
  replay[reversalId] = entry;
  updateHot(storage, { replay: JSON.stringify(replay) });
}

function readHpReplayReceipt(
  storage: DurableObjectStorage,
  key: string,
): Record<string, unknown> | null {
  const hot = loadHot(storage);
  try {
    const parsed = JSON.parse(hot.replay) as Record<string, Record<string, unknown>>;
    const entry = parsed[key];
    if (entry === undefined || typeof entry.receipt !== "object" || entry.receipt === null) {
      return null;
    }
    return entry.receipt as Record<string, unknown>;
  } catch {
    return null;
  }
}

function writeHpReplayReceipt(
  storage: DurableObjectStorage,
  key: string,
  receipt: Record<string, unknown>,
): void {
  const hot = loadHot(storage);
  let parsed: Record<string, Record<string, unknown>> = {};
  try {
    parsed = JSON.parse(hot.replay) as Record<string, Record<string, unknown>>;
  } catch {
    parsed = {};
  }
  parsed[key] = { receipt };
  updateHot(storage, { replay: JSON.stringify(parsed) });
}

function findTermForGrant(terms: TermRow[], grantId: string): TermRow | undefined {
  return terms.find(
    (term) => term.grant_id === grantId || term.origin_grant_id === grantId,
  );
}

function emitCoverageEvent(
  storage: DurableObjectStorage,
  input: {
    installationId: string;
    orgId: string;
    vendorContractVersion: number;
    kind: string;
    at: string;
    durationScale?: DurationScale;
  },
): number {
  let hot = loadHot(storage);
  hot = { ...hot, clinic_seq: hot.clinic_seq + 1 };
  updateHot(storage, { clinic_seq: hot.clinic_seq });
  const terms = loadTerms(storage);
  const snapshot = buildCoverageSnapshot({
    vendorContractVersion: input.vendorContractVersion,
    orgId: input.orgId,
    hot,
    terms,
    durationScale: input.durationScale,
  });
  snapshot.clinic_seq = hot.clinic_seq;
  insertOutbox(storage, "coverage_event", {
    event_id: coverageEventId(input.installationId, hot.clinic_seq),
    org_id: input.orgId,
    installation_id: input.installationId,
    binding_epoch: hot.binding_epoch,
    clinic_seq: hot.clinic_seq,
    kind: input.kind,
    at: input.at,
    snapshot,
  });
  return hot.clinic_seq;
}

async function scheduleCoverageAlarm(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  nowIso: string,
): Promise<void> {
  const terms = loadTerms(storage);
  const hot = loadHot(storage);
  const outboxCount =
    sqlSelect<{ count: number }>(
      storage,
      "SELECT COUNT(*) AS count FROM outbox",
    )[0]?.count ?? 0;
  const nextAlarm = computeNextAlarmAt(terms, outboxCount > 0, nowIso);
  updateHot(storage, { next_alarm_at: nextAlarm });
  await syncAlarm(state, storage, nextAlarm, hot.next_alarm_at);
}

export function insertOutbox(
  storage: DurableObjectStorage,
  kind: string,
  payload: unknown,
): void {
  sqlExec(
    storage,
    `INSERT INTO outbox (kind, payload) VALUES (${sqlString(kind)}, ${sqlString(JSON.stringify(payload))})`,
  );
}

const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;
const MS_PER_DAY = ONE_DAY_MS;

export function unscaledTermLengthDays(term: TermRow): number {
  if (
    term.calendar_start === null ||
    term.duration_unit === null ||
    term.duration_count === null
  ) {
    return 31;
  }
  const unscaledEnd = addDuration(
    term.calendar_start,
    term.duration_unit as "month" | "day",
    term.duration_count,
  );
  return (Date.parse(unscaledEnd) - Date.parse(term.calendar_start)) / MS_PER_DAY;
}

export function computeGraceAllowance(
  term: TermRow,
  graceBaseUsed: number,
): number {
  const allowance = term.allowance ?? 0;
  const graceDays = term.grace_days ?? 0;
  const termDays = unscaledTermLengthDays(term);
  if (termDays <= 0) {
    return 0;
  }
  const ceiling = Math.ceil((allowance * graceDays) / termDays);
  return Math.min(allowance - graceBaseUsed, ceiling);
}

export function resolveOrgIdFromStorage(storage: DurableObjectStorage): string {
  const row = sqlSelect<{ envelope: string }>(
    storage,
    "SELECT envelope FROM grant ORDER BY applied_at DESC LIMIT 1",
  )[0];
  if (row === undefined) {
    return "";
  }
  try {
    const envelope = JSON.parse(row.envelope) as { org_id?: string };
    return typeof envelope.org_id === "string" ? envelope.org_id : "";
  } catch {
    return "";
  }
}

function resolveInstallationIdFromStorage(storage: DurableObjectStorage): string {
  const row = sqlSelect<{ receipt: string }>(
    storage,
    "SELECT receipt FROM grant ORDER BY applied_at DESC LIMIT 1",
  )[0];
  if (row === undefined) {
    return "";
  }
  try {
    const receipt = JSON.parse(row.receipt) as { installation_id?: string };
    return typeof receipt.installation_id === "string"
      ? receipt.installation_id
      : "";
  } catch {
    return "";
  }
}

export type ApplyDueBoundariesInput = {
  storage: DurableObjectStorage;
  clockNowIso: string;
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  durationScale?: DurationScale;
  /** When false, an expiring active term does not promote queued terms (read path). */
  promoteQueued?: boolean;
};

function emitBoundaryCoverageEvent(
  storage: DurableObjectStorage,
  input: ApplyDueBoundariesInput & { kind: string; at: string },
): void {
  const hot = loadHot(storage);
  const terms = loadTerms(storage);
  const clinicSeq = hot.clinic_seq + 1;
  updateHot(storage, { clinic_seq: clinicSeq });
  const hotAfter = loadHot(storage);
  const snapshot = buildCoverageSnapshot({
    vendorContractVersion: input.vendorContractVersion,
    orgId: input.orgId,
    hot: hotAfter,
    terms,
    durationScale: input.durationScale,
  });
  snapshot.clinic_seq = clinicSeq;
  insertOutbox(storage, "coverage_event", {
    event_id: coverageEventId(input.installationId, clinicSeq),
    org_id: input.orgId,
    installation_id: input.installationId,
    binding_epoch: hotAfter.binding_epoch,
    clinic_seq: clinicSeq,
    kind: input.kind,
    at: input.at,
    snapshot,
  });
}

export function applyDueBoundaries(input: ApplyDueBoundariesInput): boolean {
  const nowMs = Date.parse(input.clockNowIso);
  let changed = false;

  while (true) {
    const terms = loadTerms(input.storage);
    const active = terms.find((term) => term.state === "active");
    if (
      active !== undefined &&
      active.ends_at !== null &&
      Date.parse(active.ends_at) <= nowMs
    ) {
      changed = true;
      const boundaryAt = active.ends_at;
      const hot = loadHot(input.storage);
      const usedFinal = hot.used;
      const queued = terms
        .filter((term) => term.state === "queued")
        .sort((left, right) => left.position - right.position)[0];

      if (queued !== undefined && input.promoteQueued !== false) {
        sqlExec(
          input.storage,
          `UPDATE term SET state = 'ended', end_reason = 'expired', ended_at = ${sqlString(boundaryAt)}, used_final = ${usedFinal}
           WHERE term_id = ${sqlString(active.term_id)}`,
        );
        emitBoundaryCoverageEvent(input.storage, {
          ...input,
          kind: "term_ended",
          at: input.clockNowIso,
        });

        const durationUnit = (queued.duration_unit ?? "month") as "month" | "day";
        const durationCount = queued.duration_count ?? 1;
        const endsAt = addDuration(
          boundaryAt,
          durationUnit,
          durationCount,
          input.durationScale,
        );
        sqlExec(
          input.storage,
          `UPDATE term SET state = 'active', starts_at = ${sqlString(boundaryAt)}, calendar_start = ${sqlString(boundaryAt)}, ends_at = ${sqlString(endsAt)}
           WHERE term_id = ${sqlString(queued.term_id)}`,
        );
        updateHot(input.storage, {
          active_term_id: queued.term_id,
          used: 0,
        });
        emitBoundaryCoverageEvent(input.storage, {
          ...input,
          kind: "term_activated",
          at: input.clockNowIso,
        });
      } else if (queued !== undefined && input.promoteQueued === false) {
        break;
      } else {
        const graceDays = active.grace_days ?? 0;
        const graceEndsAt = addDuration(
          boundaryAt,
          "day",
          graceDays,
          input.durationScale,
        );
        sqlExec(
          input.storage,
          `UPDATE term SET state = 'grace', grace_ends_at = ${sqlString(graceEndsAt)}
           WHERE term_id = ${sqlString(active.term_id)}`,
        );
        updateHot(input.storage, { grace_base_used: hot.used });
        emitBoundaryCoverageEvent(input.storage, {
          ...input,
          kind: "grace_started",
          at: input.clockNowIso,
        });
      }
      continue;
    }

    const grace = terms.find((term) => term.state === "grace");
    if (
      grace !== undefined &&
      grace.grace_ends_at !== null &&
      Date.parse(grace.grace_ends_at) <= nowMs
    ) {
      changed = true;
      const hot = loadHot(input.storage);
      const usedFinal = hot.used;
      sqlExec(
        input.storage,
        `UPDATE term SET state = 'ended', end_reason = 'expired', ended_at = ${sqlString(input.clockNowIso)}, used_final = ${usedFinal}
         WHERE term_id = ${sqlString(grace.term_id)}`,
      );
      updateHot(input.storage, {
        active_term_id: null,
        grace_base_used: 0,
      });
      emitBoundaryCoverageEvent(input.storage, {
        ...input,
        kind: "term_ended",
        at: input.clockNowIso,
      });
      continue;
    }

    break;
  }

  return changed;
}

function countDoPaidGrantsLast24Hours(
  storage: DurableObjectStorage,
  nowIso: string,
): number {
  const windowStart = new Date(Date.parse(nowIso) - ONE_DAY_MS).toISOString();
  const row = sqlSelect<{ count: number }>(
    storage,
    `SELECT COUNT(*) AS count FROM grant WHERE source_kind = 'paid' AND applied_at >= ${sqlString(windowStart)}`,
  )[0];
  return row?.count ?? 0;
}

async function countD1PaidGrantsLastHour(
  db: D1Database,
  nowIso: string,
): Promise<number> {
  const windowStart = new Date(Date.parse(nowIso) - ONE_HOUR_MS).toISOString();
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS count FROM grant_ledger
       WHERE source_kind = 'paid' AND applied_at >= ?`,
    )
    .bind(windowStart)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

export function updateHot(
  storage: DurableObjectStorage,
  patch: Partial<HotRow>,
): void {
  const sets: string[] = [];
  if (patch.active_term_id !== undefined) {
    sets.push(`active_term_id = ${patch.active_term_id === null ? "NULL" : sqlString(patch.active_term_id)}`);
  }
  if (patch.used !== undefined) {
    sets.push(`used = ${patch.used}`);
  }
  if (patch.reserved !== undefined) {
    sets.push(`reserved = ${patch.reserved}`);
  }
  if (patch.grace_base_used !== undefined) {
    sets.push(`grace_base_used = ${patch.grace_base_used}`);
  }
  if (patch.reservations !== undefined) {
    sets.push(`reservations = ${sqlString(patch.reservations)}`);
  }
  if (patch.replay !== undefined) {
    sets.push(`replay = ${sqlString(patch.replay)}`);
  }
  if (patch.idempotency !== undefined) {
    sets.push(`idempotency = ${sqlString(patch.idempotency)}`);
  }
  if (patch.band_emitted !== undefined) {
    sets.push(`band_emitted = ${sqlString(patch.band_emitted)}`);
  }
  if (patch.suspended !== undefined) {
    sets.push(`suspended = ${patch.suspended}`);
  }
  if (patch.transferred_out_to !== undefined) {
    sets.push(
      `transferred_out_to = ${patch.transferred_out_to === null ? "NULL" : sqlString(patch.transferred_out_to)}`,
    );
  }
  if (patch.awaiting_transfer !== undefined) {
    sets.push(`awaiting_transfer = ${patch.awaiting_transfer}`);
  }
  if (patch.transfer_pending !== undefined) {
    sets.push(`transfer_pending = ${patch.transfer_pending}`);
  }
  if (patch.binding_epoch !== undefined) {
    sets.push(`binding_epoch = ${patch.binding_epoch}`);
  }
  if (patch.clinic_seq !== undefined) {
    sets.push(`clinic_seq = ${patch.clinic_seq}`);
  }
  if (patch.next_alarm_at !== undefined) {
    sets.push(
      `next_alarm_at = ${patch.next_alarm_at === null ? "NULL" : sqlString(patch.next_alarm_at)}`,
    );
  }
  if (sets.length > 0) {
    sqlExec(storage, `UPDATE hot SET ${sets.join(", ")}`);
  }
}

async function syncAlarm(
  state: DurableObjectState,
  _storage: DurableObjectStorage,
  nextAlarmAt: string | null,
  currentAlarmAt: string | null,
): Promise<void> {
  if (nextAlarmAt === currentAlarmAt) {
    return;
  }
  if (nextAlarmAt === null) {
    await state.storage.deleteAlarm();
    return;
  }
  const targetMs = Date.parse(nextAlarmAt);
  const scheduleMs = Math.max(targetMs, Date.now() + 5_000);
  await state.storage.setAlarm(scheduleMs);
}

export async function scheduleOutboxAlarmIfPending(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  nowIso: string,
): Promise<void> {
  const outboxCount =
    sqlSelect<{ count: number }>(
      storage,
      "SELECT COUNT(*) AS count FROM outbox",
    )[0]?.count ?? 0;
  if (outboxCount === 0) {
    return;
  }
  const hot = loadHot(storage);
  const terms = loadTerms(storage);
  const nextAlarm = computeNextAlarmAt(terms, true, nowIso);
  updateHot(storage, { next_alarm_at: nextAlarm });
  await syncAlarm(state, storage, nextAlarm, hot.next_alarm_at);
}

function computeNextAlarmAt(
  terms: TermRow[],
  hasOutbox: boolean,
  nowIso: string,
): string | null {
  const boundaries: number[] = [];
  const active = terms.find((term) => term.state === "active");
  const grace = terms.find((term) => term.state === "grace");
  if (active?.ends_at) {
    boundaries.push(Date.parse(active.ends_at));
  }
  if (grace?.grace_ends_at) {
    boundaries.push(Date.parse(grace.grace_ends_at));
  }
  const nextBoundary =
    boundaries.length > 0
      ? new Date(Math.min(...boundaries)).toISOString()
      : null;
  if (hasOutbox) {
    if (nextBoundary === null) {
      return nowIso;
    }
    return Date.parse(nowIso) <= Date.parse(nextBoundary) ? nowIso : nextBoundary;
  }
  return nextBoundary;
}

function isEnvelopeRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function complimentaryDurationDays(unit: string, count: number): number {
  if (unit === "month") {
    return count * 31;
  }
  return count;
}

type WindowGrantRow = {
  kind: string;
  source_kind: string;
  envelope: string;
};

function windowGrantRows(
  storage: DurableObjectStorage,
  appliedAtIso: string,
  windowDays: number,
): WindowGrantRow[] {
  const windowStart = new Date(
    Date.parse(appliedAtIso) - windowDays * ONE_DAY_MS,
  ).toISOString();
  return sqlSelect<WindowGrantRow>(
    storage,
    `SELECT kind, source_kind, envelope FROM grant
     WHERE applied_at > ${sqlString(windowStart)}
       AND applied_at <= ${sqlString(appliedAtIso)}`,
  );
}

function contributionFromGrantRow(row: WindowGrantRow): {
  days: number;
  credits: number;
} {
  try {
    const envelope = JSON.parse(row.envelope) as Record<string, unknown>;
    if (row.kind === "term_adjustment" && row.source_kind === "complimentary") {
      const adjustment = envelope.adjustment;
      let days = 0;
      let credits = 0;
      if (isEnvelopeRecord(adjustment)) {
        const extendDays = adjustment.extend_days;
        if (Number.isInteger(extendDays) && (extendDays as number) > 0) {
          days = extendDays as number;
        }
        const addAllowance = adjustment.add_allowance;
        if (Number.isInteger(addAllowance) && (addAllowance as number) > 0) {
          credits = addAllowance as number;
        }
      }
      return { days, credits };
    }
    if (row.kind === "term" && row.source_kind === "complimentary") {
      const duration = envelope.duration;
      if (!isEnvelopeRecord(duration)) {
        return { days: 0, credits: 0 };
      }
      const unit = String(duration.unit);
      const count = Number(duration.count);
      const days = Number.isFinite(count)
        ? complimentaryDurationDays(unit, count)
        : 0;
      const credits = Number.isInteger(envelope.allowance_credits)
        ? (envelope.allowance_credits as number)
        : 0;
      return { days, credits };
    }
  } catch {
    return { days: 0, credits: 0 };
  }
  return { days: 0, credits: 0 };
}

function grantExceedsCeiling(input: {
  storage: DurableObjectStorage;
  appliedAtIso: string;
  policy: CeilingPolicyNumbers;
  planMaxAllowancePerMonth: number;
  grantDays: number;
  grantCredits: number;
  applyPerGrantCaps: boolean;
}): boolean {
  if (input.applyPerGrantCaps) {
    if (input.grantDays > input.policy.per_grant_max_days) {
      return true;
    }
    if (
      input.grantCredits >
      input.policy.per_grant_max_allowance_months * input.planMaxAllowancePerMonth
    ) {
      return true;
    }
  }
  let windowDays = 0;
  let windowCredits = 0;
  for (const row of windowGrantRows(
    input.storage,
    input.appliedAtIso,
    input.policy.window_days,
  )) {
    const part = contributionFromGrantRow(row);
    windowDays += part.days;
    windowCredits += part.credits;
  }
  windowDays += input.grantDays;
  windowCredits += input.grantCredits;
  if (windowDays > input.policy.window_max_days) {
    return true;
  }
  if (
    windowCredits >
    input.policy.window_max_allowance_months * input.planMaxAllowancePerMonth
  ) {
    return true;
  }
  return false;
}

function buildGrantAlertBody(
  orgId: string,
  envelope: Record<string, unknown>,
  attention: boolean,
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    code: "AL-11",
    org_id: orgId,
    operation: { op: "grant", params: envelope },
  };
  if (attention) {
    body.attention = true;
  }
  return body;
}

async function finalizeGrantApply(input: {
  state: DurableObjectState;
  storage: DurableObjectStorage;
  request: ApplyGrantRequest;
  signingKey: PlatformSigningMaterial;
  grantId: string;
  envelopeSha256: string;
  termIds: string[];
  grantKind: string;
  grantSourceKind: string;
  attentionAl11: boolean;
  emitAl12: boolean;
  logger: Logger;
}): Promise<ApplyGrantResponse> {
  const { storage, request, signingKey, grantId, envelopeSha256 } = input;
  let hot = loadHot(storage);
  let terms = loadTerms(storage);

  hot = { ...hot, clinic_seq: hot.clinic_seq + 1 };
  updateHot(storage, { clinic_seq: hot.clinic_seq });
  terms = loadTerms(storage);
  const grantAppliedSnapshot = buildCoverageSnapshot({
    vendorContractVersion: request.vendorContractVersion,
    orgId: request.orgId,
    hot,
    terms,
    durationScale: request.durationScale,
  });
  grantAppliedSnapshot.clinic_seq = hot.clinic_seq;
  const ledgerSeq = hot.clinic_seq;
  insertOutbox(storage, "coverage_event", {
    event_id: coverageEventId(request.installationId, hot.clinic_seq),
    org_id: request.orgId,
    installation_id: request.installationId,
    binding_epoch: hot.binding_epoch,
    clinic_seq: hot.clinic_seq,
    kind: "grant_applied",
    at: request.nowIso,
    snapshot: grantAppliedSnapshot,
  });

  const receipt = await signReceipt({
    signingKey,
    vendorContractVersion: request.vendorContractVersion,
    grantId,
    installationId: request.installationId,
    orgId: request.orgId,
    termIds: input.termIds,
    appliedAt: request.nowIso,
    ledgerSeq,
    envelopeSha256,
  });

  sqlExec(
    storage,
    `INSERT INTO grant (
      grant_id, kind, source_kind, envelope_sha256, envelope, evidence, receipt, applied_at, voided_at, void_reason
    ) VALUES (
      ${sqlString(grantId)}, ${sqlString(input.grantKind)}, ${sqlString(input.grantSourceKind)}, ${sqlString(envelopeSha256)},
      ${sqlString(JSON.stringify(request.envelope))},
      ${sqlString(JSON.stringify(request.envelope.evidence ?? {}))},
      ${sqlString(JSON.stringify(receipt))},
      ${sqlString(request.nowIso)}, NULL, NULL
    )`,
  );

  insertOutbox(storage, "grant_ledger", {
    grant_id: grantId,
    origin_grant_id: grantId,
    org_id: request.orgId,
    installation_id: request.installationId,
    kind: input.grantKind,
    source_kind: input.grantSourceKind,
    operator_credential_id: request.operatorCredentialId,
    envelope_sha256: envelopeSha256,
    receipt,
    applied_at: request.nowIso,
  });

  insertOutbox(storage, "alert", {
    alert_key: `AL-11:${grantId}`,
    code: "AL-11",
    body: buildGrantAlertBody(
      request.orgId,
      request.envelope,
      input.attentionAl11,
    ),
  });

  if (input.emitAl12) {
    insertOutbox(storage, "alert", {
      alert_key: `AL-12:${grantId}`,
      code: "AL-12",
      body: {
        code: "AL-12",
        org_id: request.orgId,
        operation: { op: "grant", params: request.envelope },
      },
    });
  }

  hot = loadHot(storage);
  terms = loadTerms(storage);
  const outboxCount =
    sqlSelect<{ count: number }>(
      storage,
      "SELECT COUNT(*) AS count FROM outbox",
    )[0]?.count ?? 0;
  const nextAlarm = computeNextAlarmAt(terms, outboxCount > 0, request.nowIso);
  updateHot(storage, { next_alarm_at: nextAlarm });
  await syncAlarm(input.state, storage, nextAlarm, hot.next_alarm_at);

  input.logger.info("apply_grant completed", {
    installation_id: request.installationId,
    grant_id: grantId,
    result: "applied",
  });

  return { kind: "apply_grant", result: "applied", receipt };
}

async function applyComplimentaryTermGrant(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  request: ApplyGrantRequest,
  signingKey: PlatformSigningMaterial,
  grantId: string,
  envelopeSha256: string,
  logger: Logger,
): Promise<ApplyGrantResponse> {
  const durationUnit = request.durationUnit;
  const durationCount = request.durationCount;
  if (
    (durationUnit !== "day" && durationUnit !== "month") ||
    !Number.isInteger(durationCount) ||
    (durationCount as number) < 1
  ) {
    return { kind: "apply_grant", result: "bad_request" };
  }

  const planMax = request.planMaxAllowancePerMonth ?? request.allowanceCredits;
  const grantDays = complimentaryDurationDays(
    durationUnit,
    durationCount as number,
  );
  const grantCredits = request.allowanceCredits;

  if (
    !request.skipCeilingCheck &&
    request.ceilingPolicy !== undefined &&
    grantExceedsCeiling({
      storage,
      appliedAtIso: request.nowIso,
      policy: request.ceilingPolicy,
      planMaxAllowancePerMonth: planMax,
      grantDays,
      grantCredits,
      applyPerGrantCaps: true,
    })
  ) {
    return { kind: "apply_grant", result: "exceeds_ceiling" };
  }

  let terms = loadTerms(storage);
  const hasActiveGraceOrQueued = terms.some(
    (term) =>
      term.state === "active" ||
      term.state === "grace" ||
      term.state === "queued",
  );

  const termId = crypto.randomUUID();
  const position = nextTermPosition(terms);
  const planSnapshotJson = JSON.stringify(request.planSnapshot);
  const graceDays = request.graceDays ?? 0;
  const graceCap = "proportional";

  let newTermState: "active" | "queued" = hasActiveGraceOrQueued
    ? "queued"
    : "active";
  let calendarStart: string | null = request.nowIso;
  let startsAt: string | null = request.nowIso;
  let endsAt: string | null = null;

  if (newTermState === "active") {
    endsAt = addDuration(
      request.nowIso,
      durationUnit,
      durationCount as number,
      request.durationScale,
    );
    sqlExec(
      storage,
      `INSERT INTO term (
        term_id, grant_id, origin_grant_id, position, state, end_reason,
        plan_snapshot, allowance, used_final, duration_unit, duration_count,
        grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
      ) VALUES (
        ${sqlString(termId)}, ${sqlString(grantId)}, ${sqlString(grantId)}, ${position},
        'active', NULL, ${sqlString(planSnapshotJson)}, ${request.allowanceCredits},
        NULL, ${sqlString(durationUnit)}, ${durationCount as number},
        ${graceDays}, ${sqlString(graceCap)},
        ${sqlString(calendarStart!)}, ${sqlString(startsAt!)},
        ${sqlString(endsAt!)}, NULL, NULL
      )`,
    );
    updateHot(storage, { active_term_id: termId, used: 0 });
    let hot = loadHot(storage);
    hot = { ...hot, clinic_seq: hot.clinic_seq + 1 };
    updateHot(storage, { clinic_seq: hot.clinic_seq });
    terms = loadTerms(storage);
    const activatedSnapshot = buildCoverageSnapshot({
      vendorContractVersion: request.vendorContractVersion,
      orgId: request.orgId,
      hot,
      terms,
      durationScale: request.durationScale,
    });
    activatedSnapshot.clinic_seq = hot.clinic_seq;
    insertOutbox(storage, "coverage_event", {
      event_id: coverageEventId(request.installationId, hot.clinic_seq),
      org_id: request.orgId,
      installation_id: request.installationId,
      binding_epoch: hot.binding_epoch,
      clinic_seq: hot.clinic_seq,
      kind: "term_activated",
      at: request.nowIso,
      snapshot: activatedSnapshot,
    });
  } else {
    sqlExec(
      storage,
      `INSERT INTO term (
        term_id, grant_id, origin_grant_id, position, state, end_reason,
        plan_snapshot, allowance, used_final, duration_unit, duration_count,
        grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
      ) VALUES (
        ${sqlString(termId)}, ${sqlString(grantId)}, ${sqlString(grantId)}, ${position},
        'queued', NULL, ${sqlString(planSnapshotJson)}, ${request.allowanceCredits},
        NULL, ${sqlString(durationUnit)}, ${durationCount as number},
        ${graceDays}, ${sqlString(graceCap)},
        NULL, NULL, NULL, NULL, NULL
      )`,
    );
  }

  return finalizeGrantApply({
    state,
    storage,
    request,
    signingKey,
    grantId,
    envelopeSha256,
    termIds: [termId],
    grantKind: "term",
    grantSourceKind: "complimentary",
    attentionAl11: true,
    emitAl12: request.skipCeilingCheck === true,
    logger,
  });
}

async function applyTermAdjustmentGrant(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  request: ApplyGrantRequest,
  signingKey: PlatformSigningMaterial,
  grantId: string,
  envelopeSha256: string,
  logger: Logger,
): Promise<ApplyGrantResponse> {
  const terms = loadTerms(storage);
  const activeTerm = terms.find((term) => term.state === "active");
  if (activeTerm === undefined || activeTerm.ends_at === null) {
    return { kind: "apply_grant", result: "bad_request" };
  }

  const adjustment = request.adjustment ?? {};
  const extendDays = adjustment.extend_days;
  const addAllowance = adjustment.add_allowance;
  const planMax = request.planMaxAllowancePerMonth ?? request.allowanceCredits;

  let grantDays = 0;
  let grantCredits = 0;
  if (Number.isInteger(extendDays)) {
    if ((extendDays as number) < 0) {
      return { kind: "apply_grant", result: "bad_request" };
    }
    if ((extendDays as number) > 0) {
      grantDays = extendDays as number;
      const newEndsAt = addDuration(
        activeTerm.ends_at,
        "day",
        extendDays as number,
        request.durationScale,
      );
      if (Date.parse(newEndsAt) < Date.parse(activeTerm.ends_at)) {
        return { kind: "apply_grant", result: "bad_request" };
      }
    }
  }
  if (Number.isInteger(addAllowance) && (addAllowance as number) > 0) {
    grantCredits = addAllowance as number;
  }

  if (
    !request.skipCeilingCheck &&
    request.ceilingPolicy !== undefined &&
    grantExceedsCeiling({
      storage,
      appliedAtIso: request.nowIso,
      policy: request.ceilingPolicy,
      planMaxAllowancePerMonth: planMax,
      grantDays,
      grantCredits,
      applyPerGrantCaps: false,
    })
  ) {
    return { kind: "apply_grant", result: "exceeds_ceiling" };
  }

  let allowance = activeTerm.allowance ?? 0;
  let endsAt = activeTerm.ends_at;
  if (Number.isInteger(extendDays) && (extendDays as number) > 0) {
    endsAt = addDuration(
      activeTerm.ends_at,
      "day",
      extendDays as number,
      request.durationScale,
    );
  }
  if (Number.isInteger(addAllowance) && (addAllowance as number) > 0) {
    allowance += addAllowance as number;
  }

  const adjustmentPlan = adjustment.plan;
  const termSets = [
    `allowance = ${allowance}`,
    `ends_at = ${sqlString(endsAt)}`,
  ];
  if (isEnvelopeRecord(adjustmentPlan)) {
    termSets.unshift(
      `plan_snapshot = ${sqlString(JSON.stringify(request.planSnapshot))}`,
    );
  }

  sqlExec(
    storage,
    `UPDATE term SET ${termSets.join(", ")}
     WHERE term_id = ${sqlString(activeTerm.term_id)}`,
  );

  return finalizeGrantApply({
    state,
    storage,
    request,
    signingKey,
    grantId,
    envelopeSha256,
    termIds: [activeTerm.term_id],
    grantKind: "term_adjustment",
    grantSourceKind: "complimentary",
    attentionAl11: true,
    emitAl12: request.skipCeilingCheck === true,
    logger,
  });
}

export async function applyGrantRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: ApplyGrantRequest,
  logger: Logger = noopLogger,
): Promise<ApplyGrantResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const hotForTransfer = loadHot(storage);
    if (hotForTransfer.awaiting_transfer !== 0) {
      return {
        kind: "apply_grant",
        result: "transient",
        detail: "awaiting_transfer",
      };
    }
    if (
      hotForTransfer.transferred_out_to !== undefined &&
      hotForTransfer.transferred_out_to !== null &&
      hotForTransfer.transferred_out_to.length > 0
    ) {
      return {
        kind: "apply_grant",
        result: "rejected",
        code: "transferred_out",
      };
    }
    const grantId = String(request.envelope.grant_id);
    const envelopeSha256 = await grantEnvelopeHash(request.envelope);

    const existing = sqlSelect<GrantRow>(
      storage,
      `SELECT grant_id, envelope_sha256, receipt FROM grant WHERE grant_id = ${sqlString(grantId)} LIMIT 1`,
    )[0];
    if (existing !== undefined) {
      if (existing.envelope_sha256 === envelopeSha256 && existing.receipt) {
        return {
          kind: "apply_grant",
          result: "already_applied",
          receipt: JSON.parse(existing.receipt) as Record<string, unknown>,
        };
      }
      return { kind: "apply_grant", result: "conflict" };
    }

    const signingKey = await loadPlatformSigningKey(request.platformSigningKeyJson);
    if (signingKey === null) {
      throw new Error("invalid_platform_signing_key");
    }

    const envelopeKind = request.envelopeKind ?? "term";
    const sourceKind = request.sourceKind ?? "paid";

    if (envelopeKind === "term_adjustment") {
      return applyTermAdjustmentGrant(
        state,
        storage,
        request,
        signingKey,
        grantId,
        envelopeSha256,
        logger,
      );
    }

    if (sourceKind === "complimentary") {
      return applyComplimentaryTermGrant(
        state,
        storage,
        request,
        signingKey,
        grantId,
        envelopeSha256,
        logger,
      );
    }

    let hot = loadHot(storage);
    let terms = loadTerms(storage);
    const graceTerm = terms.find((term) => term.state === "grace");
    const activeTerm = terms.find((term) => term.state === "active");
    const hasQueued = terms.some((term) => term.state === "queued");

    const paidDurationUnit = request.durationUnit ?? "month";
    const paidDurationCount = request.durationCount ?? 1;

    const termId = crypto.randomUUID();
    const position = nextTermPosition(terms);
    const planSnapshotJson = JSON.stringify(request.planSnapshot);
    const paidSourceKind = "paid";

    type PendingEvent = {
      kind: string;
      mutate?: () => void;
    };
    const pendingEvents: PendingEvent[] = [];

    let newTermState: "active" | "queued" = "active";
    let calendarStart: string | null = request.nowIso;
    let startsAt: string | null = request.nowIso;
    let endsAt: string | null = null;

    if (graceTerm !== undefined) {
      pendingEvents.push({
        kind: "term_ended",
        mutate: () => {
          const hotBeforeRenewal = loadHot(storage);
          sqlExec(
            storage,
            `UPDATE term SET state = 'ended', end_reason = 'renewed', ended_at = ${sqlString(request.nowIso)}, used_final = ${hotBeforeRenewal.used}
             WHERE term_id = ${sqlString(graceTerm.term_id)}`,
          );
          updateHot(storage, { grace_base_used: 0 });
          terms = loadTerms(storage);
        },
      });
      newTermState = "active";
      calendarStart = graceTerm.ends_at ?? request.nowIso;
      startsAt = graceTerm.ends_at ?? request.nowIso;
      endsAt = addDuration(
        calendarStart!,
        paidDurationUnit,
        paidDurationCount,
        request.durationScale,
      );
    } else if (activeTerm !== undefined || hasQueued) {
      newTermState = "queued";
      calendarStart = null;
      startsAt = null;
      endsAt = null;
    } else {
      endsAt = addDuration(
        request.nowIso,
        paidDurationUnit,
        paidDurationCount,
        request.durationScale,
      );
    }

    if (newTermState === "active") {
      pendingEvents.push({
        kind: "term_activated",
        mutate: () => {
          sqlExec(
            storage,
            `INSERT INTO term (
              term_id, grant_id, origin_grant_id, position, state, end_reason,
              plan_snapshot, allowance, used_final, duration_unit, duration_count,
              grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
            ) VALUES (
              ${sqlString(termId)}, ${sqlString(grantId)}, ${sqlString(grantId)}, ${position},
              'active', NULL, ${sqlString(planSnapshotJson)}, ${request.allowanceCredits},
              NULL, ${sqlString(paidDurationUnit)}, ${paidDurationCount},
              ${request.graceDays ?? 0}, 'proportional',
              ${sqlString(calendarStart!)}, ${sqlString(startsAt!)},
              ${sqlString(endsAt!)}, NULL, NULL
            )`,
          );
          updateHot(storage, { active_term_id: termId, used: 0 });
          terms = loadTerms(storage);
          hot = loadHot(storage);
        },
      });
    } else {
      sqlExec(
        storage,
        `INSERT INTO term (
          term_id, grant_id, origin_grant_id, position, state, end_reason,
          plan_snapshot, allowance, used_final, duration_unit, duration_count,
          grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
        ) VALUES (
          ${sqlString(termId)}, ${sqlString(grantId)}, ${sqlString(grantId)}, ${position},
          'queued', NULL, ${sqlString(planSnapshotJson)}, ${request.allowanceCredits},
          NULL, ${sqlString(paidDurationUnit)}, ${paidDurationCount},
          ${request.graceDays ?? 0}, 'proportional',
          NULL, NULL, NULL, NULL, NULL
        )`,
      );
      terms = loadTerms(storage);
    }

    const eventPayloads: Record<string, unknown>[] = [];
    for (const pending of pendingEvents) {
      pending.mutate?.();
      hot = loadHot(storage);
      hot = { ...hot, clinic_seq: hot.clinic_seq + 1 };
      updateHot(storage, { clinic_seq: hot.clinic_seq });
      terms = loadTerms(storage);
      const snapshot = buildCoverageSnapshot({
        vendorContractVersion: request.vendorContractVersion,
        orgId: request.orgId,
        hot,
        terms,
        durationScale: request.durationScale,
      });
      snapshot.clinic_seq = hot.clinic_seq;
      eventPayloads.push({
        event_id: coverageEventId(request.installationId, hot.clinic_seq),
        org_id: request.orgId,
        installation_id: request.installationId,
        binding_epoch: hot.binding_epoch,
        clinic_seq: hot.clinic_seq,
        kind: pending.kind,
        at: request.nowIso,
        snapshot,
      });
    }

    hot = loadHot(storage);
    hot = { ...hot, clinic_seq: hot.clinic_seq + 1 };
    updateHot(storage, { clinic_seq: hot.clinic_seq });
    terms = loadTerms(storage);
    const grantAppliedSnapshot = buildCoverageSnapshot({
      vendorContractVersion: request.vendorContractVersion,
      orgId: request.orgId,
      hot,
      terms,
      durationScale: request.durationScale,
    });
    grantAppliedSnapshot.clinic_seq = hot.clinic_seq;
    const ledgerSeq = hot.clinic_seq;
    eventPayloads.push({
      event_id: coverageEventId(request.installationId, hot.clinic_seq),
      org_id: request.orgId,
      installation_id: request.installationId,
      binding_epoch: hot.binding_epoch,
      clinic_seq: hot.clinic_seq,
      kind: "grant_applied",
      at: request.nowIso,
      snapshot: grantAppliedSnapshot,
    });

    const receipt = await signReceipt({
      signingKey,
      vendorContractVersion: request.vendorContractVersion,
      grantId,
      installationId: request.installationId,
      orgId: request.orgId,
      termIds: [termId],
      appliedAt: request.nowIso,
      ledgerSeq,
      envelopeSha256,
    });

    sqlExec(
      storage,
      `INSERT INTO grant (
        grant_id, kind, source_kind, envelope_sha256, envelope, evidence, receipt, applied_at, voided_at, void_reason
      ) VALUES (
        ${sqlString(grantId)}, 'term', ${sqlString(paidSourceKind)}, ${sqlString(envelopeSha256)},
        ${sqlString(JSON.stringify(request.envelope))},
        ${sqlString(JSON.stringify(request.envelope.evidence ?? {}))},
        ${sqlString(JSON.stringify(receipt))},
        ${sqlString(request.nowIso)}, NULL, NULL
      )`,
    );

    for (const event of eventPayloads) {
      insertOutbox(storage, "coverage_event", event);
    }

    const ledgerRow = {
      grant_id: grantId,
      origin_grant_id: grantId,
      org_id: request.orgId,
      installation_id: request.installationId,
      kind: "term",
      source_kind: paidSourceKind,
      operator_credential_id: request.operatorCredentialId,
      envelope_sha256: envelopeSha256,
      receipt,
      applied_at: request.nowIso,
    };
    insertOutbox(storage, "grant_ledger", ledgerRow);

    insertOutbox(
      storage,
      "alert",
      {
        alert_key: `AL-11:${grantId}`,
        code: "AL-11",
        body: buildGrantAlertBody(request.orgId, request.envelope, false),
      },
    );

    if (countDoPaidGrantsLast24Hours(storage, request.nowIso) > 3) {
      insertOutbox(storage, "alert", {
        alert_key: `AL-17:clinic:${request.orgId}`,
        code: "AL-17",
        body: { code: "AL-17", org_id: request.orgId },
      });
    }

    const globalPaidLastHour = await countD1PaidGrantsLastHour(
      request.db,
      request.nowIso,
    );
    if (globalPaidLastHour + 1 > 20) {
      insertOutbox(storage, "alert", {
        alert_key: "AL-17:global",
        code: "AL-17",
        body: { code: "AL-17" },
      });
    }

    hot = loadHot(storage);
    terms = loadTerms(storage);
    const outboxCount = sqlSelect<{ count: number }>(
      storage,
      "SELECT COUNT(*) AS count FROM outbox",
    )[0]?.count ?? 0;
    const nextAlarm = computeNextAlarmAt(terms, outboxCount > 0, request.nowIso);
    updateHot(storage, { next_alarm_at: nextAlarm });
    await syncAlarm(state, storage, nextAlarm, hot.next_alarm_at);

    logger.info("apply_grant completed", {
      installation_id: request.installationId,
      grant_id: grantId,
      result: "applied",
    });

    return { kind: "apply_grant", result: "applied", receipt };
  });
}

export interface SuspendResumeRequest {
  kind: "suspend" | "resume";
  installationId: string;
  orgId: string;
  reason: string;
  vendorContractVersion: number;
  bindingEpoch: number;
  nowIso: string;
}

export interface SuspendResumeResponse {
  kind: "suspend" | "resume";
  snapshot: Record<string, unknown>;
}

export interface InspectCoverageRequest {
  kind: "inspect_coverage";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
}

export interface InspectCoverageResponse {
  kind: "inspect_coverage";
  terms: Record<string, unknown>[];
  grants: Record<string, unknown>[];
  reservations: unknown;
}

export async function suspendResumeRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: SuspendResumeRequest,
): Promise<SuspendResumeResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const hot = loadHot(storage);
    const terms = loadTerms(storage);
    const targetSuspended = request.kind === "suspend" ? 1 : 0;

    if (hot.suspended !== targetSuspended) {
      updateHot(storage, { suspended: targetSuspended });
      let hotAfterToggle = loadHot(storage);
      hotAfterToggle = { ...hotAfterToggle, clinic_seq: hotAfterToggle.clinic_seq + 1 };
      updateHot(storage, { clinic_seq: hotAfterToggle.clinic_seq });
      const termsAfterToggle = loadTerms(storage);
      const snapshotAfterToggle = buildCoverageSnapshot({
        vendorContractVersion: request.vendorContractVersion,
        orgId: request.orgId,
        hot: hotAfterToggle,
        terms: termsAfterToggle,
      });
      snapshotAfterToggle.clinic_seq = hotAfterToggle.clinic_seq;
      insertOutbox(storage, "coverage_event", {
        event_id: coverageEventId(
          request.installationId,
          hotAfterToggle.clinic_seq,
        ),
        org_id: request.orgId,
        installation_id: request.installationId,
        binding_epoch: hotAfterToggle.binding_epoch,
        clinic_seq: hotAfterToggle.clinic_seq,
        kind: request.kind,
        at: request.nowIso,
        snapshot: snapshotAfterToggle,
      });
      const alertOp = request.kind;
      insertOutbox(storage, "alert", {
        alert_key: `AL-19:${alertOp}:${request.orgId}`,
        code: "AL-19",
        body: {
          code: "AL-19",
          org_id: request.orgId,
          operation: {
            op: alertOp,
            params: { org_id: request.orgId, reason: request.reason },
          },
        },
      });
      const outboxCount =
        sqlSelect<{ count: number }>(
          storage,
          "SELECT COUNT(*) AS count FROM outbox",
        )[0]?.count ?? 0;
      const nextAlarm = computeNextAlarmAt(
        termsAfterToggle,
        outboxCount > 0,
        request.nowIso,
      );
      updateHot(storage, { next_alarm_at: nextAlarm });
      await syncAlarm(state, storage, nextAlarm, hot.next_alarm_at);
    }

    const hotAfter = loadHot(storage);
    const termsAfter = loadTerms(storage);
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: request.vendorContractVersion,
      orgId: request.orgId,
      hot: hotAfter,
      terms: termsAfter,
    });
    return { kind: request.kind, snapshot };
  });
}

export async function inspectCoverageRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: InspectCoverageRequest,
): Promise<InspectCoverageResponse> {
  return blockConcurrencyWhile(async () => {
    const terms = sqlSelect<Record<string, unknown>>(
      storage,
      "SELECT * FROM term ORDER BY position ASC",
    );
    const grants = sqlSelect<Record<string, unknown>>(
      storage,
      "SELECT * FROM grant ORDER BY applied_at ASC",
    );
    const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
    const reservations =
      hotRows.length > 0
        ? (JSON.parse(hotRows[0]!.reservations) as unknown)
        : [];
    return {
      kind: "inspect_coverage",
      terms,
      grants,
      reservations,
    };
  });
}

export async function readCoverageRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: ReadCoverageRequest,
): Promise<ReadCoverageResponse> {
  return blockConcurrencyWhile(async () => {
    const nowIso = request.nowIso ?? new Date().toISOString();
    const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
    if (hotRows.length > 0) {
      applyDueBoundaries({
        storage,
        clockNowIso: nowIso,
        installationId: request.installationId,
        orgId: request.orgId,
        vendorContractVersion: request.vendorContractVersion,
        durationScale: request.durationScale,
        promoteQueued: false,
      });
    }
    const terms = loadTerms(storage);
    if (hotRows.length === 0) {
      const emptyHot: HotRow = {
        suspended: 0,
        active_term_id: null,
        used: 0,
        reserved: 0,
        grace_base_used: 0,
        reservations: "[]",
        replay: "{}",
        idempotency: "{}",
        band_emitted: "{}",
        binding_epoch: 0,
        clinic_seq: 0,
        next_alarm_at: null,
      };
      const snapshot = buildCoverageSnapshot({
        vendorContractVersion: request.vendorContractVersion,
        orgId: request.orgId,
        hot: emptyHot,
        terms: [],
      });
      snapshot.state = "active";
      return {
        kind: "read_coverage",
        snapshot,
        queued_terms: [],
        recent_terms: [],
      };
    }
    const hot = hotRows[0]!;
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: request.vendorContractVersion,
      orgId: request.orgId,
      hot,
      terms,
    });
    return {
      kind: "read_coverage",
      snapshot,
      queued_terms: buildQueuedTerms(terms),
      recent_terms: buildRecentTerms(terms, hot),
    };
  });
}

export interface VoidForReversalRequest {
  kind: "void_for_reversal";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  bindingEpoch: number;
  grantId: string;
  reversalId: string;
  reason: string;
  evidenceSha256: string;
  envelopeSha256: string;
  nowIso: string;
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  replayOnly?: boolean;
}

export interface VoidForReversalResponse {
  kind: "void_for_reversal";
  result: "applied" | "already_applied" | "conflict" | "bad_request";
  receipt?: Record<string, unknown>;
}

export async function voidForReversalRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: VoidForReversalRequest,
  logger: Logger = noopLogger,
): Promise<VoidForReversalResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const replay = readVoidReplay(storage);
    const stored = replay[request.reversalId];
    if (stored !== undefined) {
      if (
        stored.grant_id === request.grantId &&
        stored.reason === request.reason &&
        stored.evidence_sha256 === request.evidenceSha256
      ) {
        return {
          kind: "void_for_reversal",
          result: "already_applied",
          receipt: stored.receipt,
        };
      }
      return { kind: "void_for_reversal", result: "conflict" };
    }
    if (request.replayOnly === true) {
      return { kind: "void_for_reversal", result: "bad_request" };
    }

    const signingKey = await loadPlatformSigningKey(request.platformSigningKeyJson);
    if (signingKey === null) {
      return { kind: "void_for_reversal", result: "bad_request" };
    }

    const terms = loadTerms(storage);
    const term = findTermForGrant(terms, request.grantId);
    if (term === undefined) {
      return { kind: "void_for_reversal", result: "bad_request" };
    }

    let effect: "end_current" | "remove_queued" | "none";
    if (term.state === "active" || term.state === "grace") {
      effect = "end_current";
    } else if (term.state === "queued" || term.state === "held") {
      effect = "remove_queued";
    } else if (term.state === "ended" || term.state === "exhausted") {
      effect = "none";
    } else {
      return { kind: "void_for_reversal", result: "bad_request" };
    }

    const endedTermIds: string[] = [];
    const heldTermIds: string[] = [];

    if (effect === "end_current") {
      sqlExec(
        storage,
        `UPDATE term SET state = 'ended', end_reason = 'reversed', ended_at = ${sqlString(request.nowIso)}, grace_ends_at = NULL
         WHERE term_id = ${sqlString(term.term_id)}`,
      );
      endedTermIds.push(term.term_id);
      const hot = loadHot(storage);
      if (hot.active_term_id === term.term_id) {
        updateHot(storage, { active_term_id: null });
      }
      const queuedBeforeHold = loadTerms(storage).filter(
        (row) => row.state === "queued",
      );
      for (const queued of queuedBeforeHold) {
        sqlExec(
          storage,
          `UPDATE term SET state = 'held' WHERE term_id = ${sqlString(queued.term_id)}`,
        );
        heldTermIds.push(queued.term_id);
      }
      emitCoverageEvent(storage, {
        installationId: request.installationId,
        orgId: request.orgId,
        vendorContractVersion: request.vendorContractVersion,
        kind: "term_ended",
        at: request.nowIso,
        durationScale: request.durationScale,
      });
      for (const heldId of heldTermIds) {
        emitCoverageEvent(storage, {
          installationId: request.installationId,
          orgId: request.orgId,
          vendorContractVersion: request.vendorContractVersion,
          kind: "term_held",
          at: request.nowIso,
          durationScale: request.durationScale,
        });
      }
    } else if (effect === "remove_queued") {
      sqlExec(
        storage,
        `UPDATE term SET state = 'ended', end_reason = 'reversed', ended_at = ${sqlString(request.nowIso)}
         WHERE term_id = ${sqlString(term.term_id)}`,
      );
      endedTermIds.push(term.term_id);
      emitCoverageEvent(storage, {
        installationId: request.installationId,
        orgId: request.orgId,
        vendorContractVersion: request.vendorContractVersion,
        kind: "term_ended",
        at: request.nowIso,
        durationScale: request.durationScale,
      });
    }

    const grantVoidedSeq = emitCoverageEvent(storage, {
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      kind: "grant_voided",
      at: request.nowIso,
      durationScale: request.durationScale,
    });

    const termIdsForReceipt =
      effect === "none" ? [] : endedTermIds.length > 0 ? [endedTermIds[0]!] : [];

    const receipt = await signReversalVoidReceipt({
      signingKey,
      vendorContractVersion: request.vendorContractVersion,
      reversalId: request.reversalId,
      installationId: request.installationId,
      orgId: request.orgId,
      termIds: termIdsForReceipt,
      appliedAt: request.nowIso,
      ledgerSeq: grantVoidedSeq,
      envelopeSha256: request.envelopeSha256,
    });

    insertOutbox(storage, "grant_void", {
      grant_id: request.grantId,
      reason: request.reason,
      source: "reversal",
      evidence_sha256: request.evidenceSha256,
      at: request.nowIso,
      receipt,
    });

    writeVoidReplay(storage, request.reversalId, {
      grant_id: request.grantId,
      reason: request.reason,
      evidence_sha256: request.evidenceSha256,
      receipt,
    });

    await scheduleCoverageAlarm(state, storage, request.nowIso);

    logger.info("void_for_reversal completed", {
      installation_id: request.installationId,
      grant_id: request.grantId,
      effect,
    });

    return { kind: "void_for_reversal", result: "applied", receipt };
  });
}

export interface ReleaseHeldRequest {
  kind: "release_held";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  bindingEpoch: number;
  grantId: string;
  reason: string;
  assertionSha256: string;
  nowIso: string;
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  replayOnly?: boolean;
}

export interface ReleaseHeldResponse {
  kind: "release_held";
  result: "applied" | "already_applied" | "bad_request";
  receipt?: Record<string, unknown>;
}

export interface VoidGrantRequest {
  kind: "void_grant";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  bindingEpoch: number;
  grantId: string;
  reason: string;
  assertionSha256: string;
  evidenceSha256: string;
  nowIso: string;
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  replayOnly?: boolean;
}

export interface VoidGrantResponse {
  kind: "void_grant";
  result: "applied" | "already_applied" | "bad_request";
  receipt?: Record<string, unknown>;
}

export async function releaseHeldRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: ReleaseHeldRequest,
  logger: Logger = noopLogger,
): Promise<ReleaseHeldResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const replayKey = `release_held:${request.assertionSha256}`;
    const existingReceipt = readHpReplayReceipt(storage, replayKey);
    if (existingReceipt !== null) {
      return {
        kind: "release_held",
        result: "already_applied",
        receipt: existingReceipt,
      };
    }
    if (request.replayOnly === true) {
      return { kind: "release_held", result: "bad_request" };
    }

    const signingKey = await loadPlatformSigningKey(request.platformSigningKeyJson);
    if (signingKey === null) {
      return { kind: "release_held", result: "bad_request" };
    }

    const terms = loadTerms(storage);
    const held = terms.find(
      (term) => term.state === "held" && term.grant_id === request.grantId,
    );
    if (held === undefined) {
      return { kind: "release_held", result: "bad_request" };
    }

    const position = nextTermPosition(terms);
    const hasActive = terms.some((term) => term.state === "active");

    if (!hasActive) {
      const endsAt =
        held.duration_unit !== null && held.duration_count !== null
          ? addDuration(
              request.nowIso,
              held.duration_unit as "month" | "day",
              held.duration_count,
              request.durationScale,
            )
          : addDuration(request.nowIso, "month", 1, request.durationScale);
      sqlExec(
        storage,
        `UPDATE term SET state = 'active', position = ${position},
         starts_at = ${sqlString(request.nowIso)}, calendar_start = ${sqlString(request.nowIso)},
         ends_at = ${sqlString(endsAt)}
         WHERE term_id = ${sqlString(held.term_id)}`,
      );
      updateHot(storage, { active_term_id: held.term_id, used: 0 });
    } else {
      sqlExec(
        storage,
        `UPDATE term SET state = 'queued', position = ${position}
         WHERE term_id = ${sqlString(held.term_id)}`,
      );
    }

    const releasedSeq = emitCoverageEvent(storage, {
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      kind: "term_released",
      at: request.nowIso,
      durationScale: request.durationScale,
    });

    if (!hasActive) {
      emitCoverageEvent(storage, {
        installationId: request.installationId,
        orgId: request.orgId,
        vendorContractVersion: request.vendorContractVersion,
        kind: "term_activated",
        at: request.nowIso,
        durationScale: request.durationScale,
      });
    }

    const receipt = await signReceipt({
      signingKey,
      vendorContractVersion: request.vendorContractVersion,
      grantId: request.grantId,
      installationId: request.installationId,
      orgId: request.orgId,
      termIds: [held.term_id],
      appliedAt: request.nowIso,
      ledgerSeq: releasedSeq,
      envelopeSha256: "",
    });

    writeHpReplayReceipt(storage, replayKey, receipt);
    await scheduleCoverageAlarm(state, storage, request.nowIso);

    logger.info("release_held completed", {
      installation_id: request.installationId,
      grant_id: request.grantId,
    });

    return { kind: "release_held", result: "applied", receipt };
  });
}

export async function voidGrantRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: VoidGrantRequest,
  logger: Logger = noopLogger,
): Promise<VoidGrantResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const replayKey = `void_grant:${request.evidenceSha256}`;
    const existingReceipt = readHpReplayReceipt(storage, replayKey);
    if (existingReceipt !== null) {
      return {
        kind: "void_grant",
        result: "already_applied",
        receipt: existingReceipt,
      };
    }
    if (request.replayOnly === true) {
      return { kind: "void_grant", result: "bad_request" };
    }

    const signingKey = await loadPlatformSigningKey(request.platformSigningKeyJson);
    if (signingKey === null) {
      return { kind: "void_grant", result: "bad_request" };
    }

    const terms = loadTerms(storage);
    const term = findTermForGrant(terms, request.grantId);
    if (term === undefined || term.state === "ended" || term.state === "exhausted") {
      return { kind: "void_grant", result: "bad_request" };
    }

    const wasActive = term.state === "active";
    sqlExec(
      storage,
      `UPDATE term SET state = 'ended', end_reason = 'voided', ended_at = ${sqlString(request.nowIso)}, grace_ends_at = NULL
       WHERE term_id = ${sqlString(term.term_id)}`,
    );
    const hot = loadHot(storage);
    if (hot.active_term_id === term.term_id) {
      updateHot(storage, { active_term_id: null });
    }

    emitCoverageEvent(storage, {
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      kind: "term_ended",
      at: request.nowIso,
      durationScale: request.durationScale,
    });

    if (wasActive) {
      const successor = loadTerms(storage)
        .filter((row) => row.state === "queued")
        .sort((left, right) => left.position - right.position)[0];
      if (successor !== undefined) {
        const endsAt =
          successor.duration_unit !== null &&
          successor.duration_count !== null
            ? addDuration(
                request.nowIso,
                successor.duration_unit as "month" | "day",
                successor.duration_count,
                request.durationScale,
              )
            : addDuration(request.nowIso, "month", 1, request.durationScale);
        sqlExec(
          storage,
          `UPDATE term SET state = 'active', starts_at = ${sqlString(request.nowIso)},
           calendar_start = ${sqlString(request.nowIso)}, ends_at = ${sqlString(endsAt)}
           WHERE term_id = ${sqlString(successor.term_id)}`,
        );
        updateHot(storage, { active_term_id: successor.term_id, used: 0 });
        emitCoverageEvent(storage, {
          installationId: request.installationId,
          orgId: request.orgId,
          vendorContractVersion: request.vendorContractVersion,
          kind: "term_activated",
          at: request.nowIso,
          durationScale: request.durationScale,
        });
      }
    }

    const grantVoidedSeq = emitCoverageEvent(storage, {
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      kind: "grant_voided",
      at: request.nowIso,
      durationScale: request.durationScale,
    });

    const receipt = await signReceipt({
      signingKey,
      vendorContractVersion: request.vendorContractVersion,
      grantId: request.grantId,
      installationId: request.installationId,
      orgId: request.orgId,
      termIds: [term.term_id],
      appliedAt: request.nowIso,
      ledgerSeq: grantVoidedSeq,
      envelopeSha256: "",
    });

    insertOutbox(storage, "grant_void", {
      grant_id: request.grantId,
      reason: request.reason,
      source: "operator",
      evidence_sha256: request.evidenceSha256,
      at: request.nowIso,
      receipt,
    });

    writeHpReplayReceipt(storage, replayKey, receipt);
    await scheduleCoverageAlarm(state, storage, request.nowIso);

    logger.info("void_grant completed", {
      installation_id: request.installationId,
      grant_id: request.grantId,
    });

    return { kind: "void_grant", result: "applied", receipt };
  });
}

export type MirrorTermView = {
  ref: string;
  capabilities: string[];
};

/** `coverage_mirror.term_snapshot` may be the full coverage snapshot or legacy term-only JSON. */
export function mirrorTermViewFromSnapshot(
  termSnapshotJson: string,
): MirrorTermView | null {
  try {
    const parsed = JSON.parse(termSnapshotJson) as Record<string, unknown>;
    const termRaw =
      parsed.term !== null &&
      typeof parsed.term === "object" &&
      !Array.isArray(parsed.term)
        ? (parsed.term as Record<string, unknown>)
        : parsed;
    const ref =
      typeof termRaw.ref === "string"
        ? termRaw.ref
        : typeof termRaw.term_id === "string"
          ? termRaw.term_id
          : "";
    const capabilities = Array.isArray(termRaw.capabilities)
      ? termRaw.capabilities.filter(
          (entry): entry is string => typeof entry === "string",
        )
      : [];
    if (!ref || capabilities.length === 0) {
      return null;
    }
    return { ref, capabilities };
  } catch {
    return null;
  }
}

async function mirrorFromSnapshot(
  db: D1Database,
  installationId: string,
  orgId: string,
  snapshot: Record<string, unknown>,
): Promise<void> {
  const bindingEpoch = snapshot.binding_epoch as number;
  const clinicSeq = snapshot.clinic_seq as number;
  const existing = await db
    .prepare(
      `SELECT binding_epoch, clinic_seq FROM coverage_mirror WHERE installation_id = ?`,
    )
    .bind(installationId)
    .first<{ binding_epoch: number; clinic_seq: number }>();

  if (
    existing !== null &&
    (existing.binding_epoch > bindingEpoch ||
      (existing.binding_epoch === bindingEpoch && existing.clinic_seq >= clinicSeq))
  ) {
    return;
  }

  const term = snapshot.term as Record<string, unknown> | null;
  const snapshotState = String(snapshot.state);
  const mirrorState = snapshotState === "reversed" ? "lapsed" : snapshotState;
  let hardStopAt: string | null = null;
  if (term !== null) {
    if (snapshotState === "active") {
      hardStopAt =
        typeof term.ends_at === "string" && term.ends_at.length > 0
          ? term.ends_at
          : null;
    } else if (snapshotState === "grace") {
      hardStopAt =
        typeof term.grace_ends_at === "string" && term.grace_ends_at.length > 0
          ? term.grace_ends_at
          : null;
    }
  }
  if (hardStopAt === null && snapshotState === "lapsed") {
    const mirrorRow = await db
      .prepare(
        `SELECT hard_stop_at FROM coverage_mirror WHERE installation_id = ?`,
      )
      .bind(installationId)
      .first<{ hard_stop_at: string | null }>();
    hardStopAt = mirrorRow?.hard_stop_at ?? null;
  }

  await db
    .prepare(
      `INSERT OR REPLACE INTO coverage_mirror (
        installation_id, org_id, binding_epoch, clinic_seq, state, suspended, hard_stop_at, term_snapshot
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      installationId,
      orgId,
      bindingEpoch,
      clinicSeq,
      mirrorState,
      snapshot.suspended ? 1 : 0,
      hardStopAt,
      JSON.stringify(snapshot),
    )
    .run();
}

export type ShippedCoverageAlert = {
  alert_key: string;
  code: string;
  body: Record<string, unknown>;
};

async function shipCoverageOutboxInLock(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  env: CoverageShipEnv,
  installationId: string,
  nowIso: string,
  logger: Logger,
  durationScale?: DurationScale,
): Promise<ShippedCoverageAlert[]> {
    const boundInstallationId =
      resolveInstallationIdFromStorage(storage) || installationId;
    applyDueBoundaries({
      storage,
      clockNowIso: nowIso,
      installationId: boundInstallationId,
      orgId: resolveOrgIdFromStorage(storage),
      vendorContractVersion: CHANNEL_VERSIONS.platformDo,
      durationScale,
    });

    const shippedAlerts: ShippedCoverageAlert[] = [];
    const rows = sqlSelect<{ seq: number; kind: string; payload: string }>(
      storage,
      "SELECT seq, kind, payload FROM outbox ORDER BY seq ASC",
    );

    for (const row of rows) {
      const payload = JSON.parse(row.payload) as Record<string, unknown>;
      if (row.kind === "coverage_event") {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO coverage_event (
            event_id, org_id, installation_id, binding_epoch, clinic_seq, kind, snapshot, at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        )
          .bind(
            payload.event_id,
            payload.org_id,
            payload.installation_id,
            payload.binding_epoch,
            payload.clinic_seq,
            payload.kind,
            JSON.stringify(payload.snapshot),
            payload.at,
          )
          .run();
        await mirrorFromSnapshot(
          env.DB,
          String(payload.installation_id),
          String(payload.org_id),
          payload.snapshot as Record<string, unknown>,
        );
      } else if (row.kind === "grant_ledger") {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO grant_ledger (
            grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
            operator_credential_id, envelope_sha256, receipt, applied_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        )
          .bind(
            payload.grant_id,
            payload.origin_grant_id,
            payload.org_id,
            payload.installation_id,
            payload.kind,
            payload.source_kind,
            payload.operator_credential_id,
            payload.envelope_sha256,
            JSON.stringify(payload.receipt),
            payload.applied_at,
          )
          .run();

        const grantId = String(payload.grant_id);
        const key = `grant-ledger/${grantId}.ndjson`;
        const existing = await env.R2.head(key);
        if (existing === null) {
          const line = JSON.stringify({
            grant_id: payload.grant_id,
            origin_grant_id: payload.origin_grant_id,
            org_id: payload.org_id,
            installation_id: payload.installation_id,
            kind: payload.kind,
            source_kind: payload.source_kind,
            operator_credential_id: payload.operator_credential_id,
            envelope_sha256: payload.envelope_sha256,
            applied_at: payload.applied_at,
            receipt: payload.receipt,
          });
          await env.R2.put(key, `${line}\n`);
        }
      } else if (row.kind === "grant_void") {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO grant_void (grant_id, reason, source, evidence_sha256, at)
           VALUES (?, ?, ?, ?, ?)`,
        )
          .bind(
            payload.grant_id,
            payload.reason,
            payload.source,
            payload.evidence_sha256,
            payload.at,
          )
          .run();

        const voidGrantId = String(payload.grant_id);
        const voidKey = `grant-ledger/${voidGrantId}.void.ndjson`;
        const existingVoid = await env.R2.head(voidKey);
        if (existingVoid === null) {
          const voidLine = JSON.stringify({
            grant_id: payload.grant_id,
            reason: payload.reason,
            source: payload.source,
            evidence_sha256: payload.evidence_sha256,
            at: payload.at,
            receipt: payload.receipt,
          });
          await env.R2.put(voidKey, `${voidLine}\n`);
        }
      } else if (row.kind === "usage_adjustment") {
        const usageEventId = crypto.randomUUID();
        await env.DB.prepare(
          `INSERT OR IGNORE INTO usage_event (
            usage_event_id, installation_id, term_id, request_id, quota_weight, tokens, cost, recorded_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        )
          .bind(
            usageEventId,
            payload.installation_id,
            payload.term_id,
            payload.request_id,
            payload.quota_weight,
            payload.tokens,
            payload.cost,
            payload.recorded_at,
          )
          .run();
      } else if (row.kind === "alert") {
        shippedAlerts.push({
          alert_key: String(payload.alert_key),
          code: String(payload.code),
          body: payload.body as Record<string, unknown>,
        });
      }

      sqlExec(storage, `DELETE FROM outbox WHERE seq = ${row.seq}`);
    }

    const hot = loadHot(storage);
    const terms = loadTerms(storage);
    const outboxCount = sqlSelect<{ count: number }>(
      storage,
      "SELECT COUNT(*) AS count FROM outbox",
    )[0]?.count ?? 0;
    const nextAlarm = computeNextAlarmAt(terms, outboxCount > 0, nowIso);
    updateHot(storage, { next_alarm_at: nextAlarm });
    await syncAlarm(state, storage, nextAlarm, hot.next_alarm_at);

    logger.info("coverage outbox shipped", {
      installation_id: installationId,
      rows: rows.length,
    });
    return shippedAlerts;
}

export async function shipCoverageOutboxAlarm(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  env: CoverageShipEnv,
  installationId: string,
  nowIso: string,
  logger: Logger = noopLogger,
  durationScale?: DurationScale,
): Promise<ShippedCoverageAlert[]> {
  return blockConcurrencyWhile(async () =>
    shipCoverageOutboxInLock(
      state,
      storage,
      env,
      installationId,
      nowIso,
      logger,
      durationScale,
    ),
  );
}

export interface OpenAwaitingTransferRequest {
  kind: "open_awaiting_transfer";
  bindingEpoch: number;
}

export interface OpenAwaitingTransferResponse {
  kind: "open_awaiting_transfer";
  result: "ok" | "bad_request";
}

export async function openAwaitingTransferRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: OpenAwaitingTransferRequest,
): Promise<OpenAwaitingTransferResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    sqlExec(
      storage,
      `UPDATE hot SET awaiting_transfer = 1, binding_epoch = ${request.bindingEpoch}`,
    );
    return { kind: "open_awaiting_transfer", result: "ok" };
  });
}

type TransferPackageTerm = {
  origin_grant_id: string;
  position: number;
  state: string;
  plan_snapshot: unknown;
  allowance: number | null;
  /** Full plan allowance before transfer adjustments (active/grace). */
  plan_allowance?: number | null;
  duration_unit: string | null;
  duration_count: number | null;
  grace_days: number | null;
  grace_cap: string | null;
  calendar_start: string | null;
  starts_at: string | null;
  ends_at: string | null;
  grace_ends_at: string | null;
  hot_grace_base_used?: number;
  hot_used?: number;
};

function graceAllowanceForPackage(
  term: TermRow,
  hot: HotRow,
): number | null {
  if (term.allowance === null) {
    return null;
  }
  const graceBudget = computeGraceAllowance(term, hot.grace_base_used);
  const graceUsed = hot.used - hot.grace_base_used;
  return Math.max(0, graceBudget - graceUsed);
}

function buildTransferPackageTerm(
  term: TermRow,
  hot: HotRow,
): TransferPackageTerm {
  const planSnapshot = JSON.parse(term.plan_snapshot) as unknown;
  const planAllowance = term.allowance;
  let allowance = term.allowance;
  if (term.state === "active" && allowance !== null) {
    allowance = allowance - hot.used;
  } else if (term.state === "grace") {
    allowance = graceAllowanceForPackage(term, hot);
  }
  return {
    origin_grant_id: term.origin_grant_id,
    position: term.position,
    state: term.state,
    plan_snapshot: planSnapshot,
    allowance,
    ...(term.state === "active" || term.state === "grace"
      ? { plan_allowance: planAllowance }
      : {}),
    ...(term.state === "grace"
      ? { hot_grace_base_used: hot.grace_base_used, hot_used: hot.used }
      : {}),
    duration_unit: term.duration_unit,
    duration_count: term.duration_count,
    grace_days: term.grace_days,
    grace_cap: term.grace_cap,
    calendar_start: term.calendar_start,
    starts_at: term.starts_at,
    ends_at: term.ends_at,
    grace_ends_at: term.grace_ends_at,
  };
}

export interface TransferOutRequest {
  kind: "transfer_out";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  bindingEpoch: number;
  transferId: string;
  toInstallationId: string;
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  nowIso: string;
}

export interface TransferOutResponse {
  kind: "transfer_out";
  result: "applied" | "bad_request";
  package?: TransferPackageTerm[];
  term_ids?: string[];
  ledger_seq?: number;
  receipt?: Record<string, unknown>;
}

export async function transferOutRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: TransferOutRequest,
): Promise<TransferOutResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const signingKey = await loadPlatformSigningKey(request.platformSigningKeyJson);
    if (signingKey === null) {
      return { kind: "transfer_out", result: "bad_request" };
    }

    const hot = loadHot(storage);
    const terms = loadTerms(storage);
    const notEnded = terms.filter(
      (term) =>
        term.state === "active" ||
        term.state === "grace" ||
        term.state === "queued" ||
        term.state === "held",
    );
    const packageTerms = notEnded.map((term) =>
      buildTransferPackageTerm(term, hot),
    );

    const endedTermIds: string[] = [];
    for (const term of notEnded) {
      sqlExec(
        storage,
        `UPDATE term SET state = 'ended', end_reason = 'transferred', ended_at = ${sqlString(request.nowIso)}
         WHERE term_id = ${sqlString(term.term_id)}`,
      );
      endedTermIds.push(term.term_id);
    }

    updateHot(storage, {
      transferred_out_to: request.toInstallationId,
      active_term_id: null,
    });

    const ledgerSeq = emitCoverageEvent(storage, {
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      kind: "transfer",
      at: request.nowIso,
      durationScale: request.durationScale,
    });

    const packageJson = JSON.stringify(packageTerms);
    const envelopeSha256 = await sha256Hex(
      new TextEncoder().encode(canonicalize(packageTerms)),
    );

    const receipt = await signTransferReceiptInDo({
      signingKey,
      vendorContractVersion: request.vendorContractVersion,
      transferId: request.transferId,
      installationId: request.installationId,
      orgId: request.orgId,
      termIds: endedTermIds,
      appliedAt: request.nowIso,
      ledgerSeq,
      envelopeSha256,
    });

    await scheduleCoverageAlarm(state, storage, request.nowIso);

    return {
      kind: "transfer_out",
      result: "applied",
      package: packageTerms,
      term_ids: endedTermIds,
      ledger_seq: ledgerSeq,
      receipt,
    };
  });
}

async function signTransferReceiptInDo(input: {
  signingKey: PlatformSigningMaterial;
  vendorContractVersion: number;
  transferId: string;
  installationId: string;
  orgId: string;
  termIds: string[];
  appliedAt: string;
  ledgerSeq: number;
  envelopeSha256: string;
}): Promise<Record<string, unknown>> {
  const unsigned = {
    contract_version: input.vendorContractVersion,
    transfer_id: input.transferId,
    installation_id: input.installationId,
    org_id: input.orgId,
    result: "applied",
    term_ids: input.termIds,
    applied_at: input.appliedAt,
    ledger_seq: input.ledgerSeq,
    envelope_sha256: input.envelopeSha256,
    kid: input.signingKey.kid,
  };
  const signature = await signCompactJws({
    payload: receiptSigningBytes(unsigned),
    privateKey: input.signingKey.privateKey,
    kid: input.signingKey.kid,
  });
  return { ...unsigned, signature };
}

function sqlNullableString(value: string | null | undefined): string {
  if (value === null || value === undefined) {
    return "NULL";
  }
  return sqlString(value);
}

function sqlNullableNumber(value: number | null | undefined): string {
  if (value === null || value === undefined) {
    return "NULL";
  }
  return String(value);
}

async function transferGrantId(transferId: string, index: number): Promise<string> {
  return sha256Hex(
    new TextEncoder().encode(`grant:transfer:${transferId}:${index}`),
  );
}

export interface SetTransferPendingRequest {
  kind: "set_transfer_pending";
  bindingEpoch: number;
}

export interface SetTransferPendingResponse {
  kind: "set_transfer_pending";
  result: "ok" | "bad_request";
}

export async function setTransferPendingRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: SetTransferPendingRequest,
): Promise<SetTransferPendingResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    updateHot(storage, { transfer_pending: 1 });
    return { kind: "set_transfer_pending", result: "ok" };
  });
}

export interface TransferInRequest {
  kind: "transfer_in";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  bindingEpoch: number;
  transferId: string;
  package: TransferPackageTerm[];
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  nowIso: string;
}

export interface TransferInResponse {
  kind: "transfer_in";
  result: "applied" | "bad_request";
  term_ids?: string[];
  ledger_seq?: number;
  receipt?: Record<string, unknown>;
}

export async function transferInRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: TransferInRequest,
): Promise<TransferInResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const signingKey = await loadPlatformSigningKey(request.platformSigningKeyJson);
    if (signingKey === null) {
      return { kind: "transfer_in", result: "bad_request" };
    }

    const createdTermIds: string[] = [];
    let activeTermId: string | null = null;
    let hotUsed = 0;
    let hotGraceBaseUsed = 0;

    for (let index = 0; index < request.package.length; index += 1) {
      const pkg = request.package[index]!;
      const termId = generateUlid();
      const grantId = await transferGrantId(request.transferId, index);
      const planSnapshotJson = JSON.stringify(pkg.plan_snapshot);
      const graceCap =
        pkg.grace_cap === null || pkg.grace_cap === undefined
          ? "proportional"
          : String(pkg.grace_cap);
      const storedAllowance =
        pkg.plan_allowance !== undefined && pkg.plan_allowance !== null
          ? pkg.plan_allowance
          : pkg.allowance;

      sqlExec(
        storage,
        `INSERT INTO term (
          term_id, grant_id, origin_grant_id, position, state, end_reason,
          plan_snapshot, allowance, used_final, duration_unit, duration_count,
          grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
        ) VALUES (
          ${sqlString(termId)}, ${sqlString(grantId)}, ${sqlString(pkg.origin_grant_id)},
          ${pkg.position}, ${sqlString(pkg.state)}, NULL,
          ${sqlString(planSnapshotJson)}, ${sqlNullableNumber(storedAllowance)}, NULL,
          ${sqlNullableString(pkg.duration_unit)}, ${sqlNullableNumber(pkg.duration_count)},
          ${sqlNullableNumber(pkg.grace_days)}, ${sqlString(graceCap)},
          ${sqlNullableString(pkg.calendar_start)}, ${sqlNullableString(pkg.starts_at)},
          ${sqlNullableString(pkg.ends_at)}, ${sqlNullableString(pkg.grace_ends_at)}, NULL
        )`,
      );
      createdTermIds.push(termId);
      if (pkg.state === "active") {
        activeTermId = termId;
        hotUsed = 0;
        hotGraceBaseUsed = 0;
      } else if (pkg.state === "grace") {
        activeTermId = termId;
        hotUsed = pkg.hot_used ?? 0;
        hotGraceBaseUsed = pkg.hot_grace_base_used ?? 0;
      }

      const envelopeSha256 = await sha256Hex(
        new TextEncoder().encode(canonicalize(pkg)),
      );
      let hot = loadHot(storage);
      hot = { ...hot, clinic_seq: hot.clinic_seq + 1 };
      updateHot(storage, { clinic_seq: hot.clinic_seq });
      const terms = loadTerms(storage);
      const snapshot = buildCoverageSnapshot({
        vendorContractVersion: request.vendorContractVersion,
        orgId: request.orgId,
        hot,
        terms,
        durationScale: request.durationScale,
      });
      snapshot.clinic_seq = hot.clinic_seq;
      const ledgerSeq = hot.clinic_seq;

      const receipt = await signReceipt({
        signingKey,
        vendorContractVersion: request.vendorContractVersion,
        grantId,
        installationId: request.installationId,
        orgId: request.orgId,
        termIds: [termId],
        appliedAt: request.nowIso,
        ledgerSeq,
        envelopeSha256,
      });

      sqlExec(
        storage,
        `INSERT INTO grant (
          grant_id, kind, source_kind, envelope_sha256, envelope, evidence, receipt, applied_at, voided_at, void_reason
        ) VALUES (
          ${sqlString(grantId)}, 'term', 'transfer', ${sqlString(envelopeSha256)},
          ${sqlString(JSON.stringify({ transfer_id: request.transferId, index }))},
          ${sqlString("{}")},
          ${sqlString(JSON.stringify(receipt))},
          ${sqlString(request.nowIso)}, NULL, NULL
        )`,
      );

      insertOutbox(storage, "grant_ledger", {
        grant_id: grantId,
        origin_grant_id: pkg.origin_grant_id,
        org_id: request.orgId,
        installation_id: request.installationId,
        kind: "term",
        source_kind: "transfer",
        operator_credential_id: "",
        envelope_sha256: envelopeSha256,
        receipt,
        applied_at: request.nowIso,
      });
    }

    updateHot(storage, {
      awaiting_transfer: 0,
      active_term_id: activeTermId,
      used: hotUsed,
      grace_base_used: hotGraceBaseUsed,
    });

    const ledgerSeq = emitCoverageEvent(storage, {
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      kind: "transfer",
      at: request.nowIso,
      durationScale: request.durationScale,
    });

    const envelopeSha256 = await sha256Hex(
      new TextEncoder().encode(canonicalize(request.package)),
    );

    const receipt = await signTransferReceiptInDo({
      signingKey,
      vendorContractVersion: request.vendorContractVersion,
      transferId: request.transferId,
      installationId: request.installationId,
      orgId: request.orgId,
      termIds: createdTermIds,
      appliedAt: request.nowIso,
      ledgerSeq,
      envelopeSha256,
    });

    await scheduleCoverageAlarm(state, storage, request.nowIso);

    return {
      kind: "transfer_in",
      result: "applied",
      term_ids: createdTermIds,
      ledger_seq: ledgerSeq,
      receipt,
    };
  });
}

export function wipeCoverageDoTables(storage: DurableObjectStorage): void {
  sqlExec(storage, "DELETE FROM hot");
  sqlExec(storage, "DELETE FROM term");
  sqlExec(storage, "DELETE FROM grant");
  sqlExec(storage, "DELETE FROM outbox");
}

type SnapshotTermEntry = Record<string, unknown>;

function snapshotTermPlanSnapshot(term: SnapshotTermEntry): string {
  const raw = term.plan_snapshot;
  if (typeof raw === "string") {
    return raw;
  }
  return JSON.stringify(raw ?? {});
}

function snapshotTermUsedFinal(entry: SnapshotTermEntry): number | null {
  const usedFinal = entry.used_final;
  if (usedFinal === null || usedFinal === undefined) {
    if (entry.state === "active" || entry.state === "grace") {
      return null;
    }
    return typeof entry.used === "number" ? entry.used : null;
  }
  return typeof usedFinal === "number" ? usedFinal : null;
}

function hotActiveUsageFromSnapshot(snapshot: Record<string, unknown>): {
  activeTermId: string | null;
  hotUsed: number;
} {
  const termsRaw = snapshot.terms;
  const termEntries: SnapshotTermEntry[] = Array.isArray(termsRaw)
    ? (termsRaw as SnapshotTermEntry[])
    : [];

  let activeTermId: string | null = null;
  let hotUsed = 0;

  const termObject = snapshot.term as Record<string, unknown> | null;
  if (termObject !== null && typeof termObject.ref === "string") {
    activeTermId = termObject.ref;
    hotUsed =
      typeof termObject.used === "number" ? termObject.used : hotUsed;
  }

  for (const entry of termEntries) {
    const state = String(entry.state ?? "");
    const termId = String(entry.term_id ?? "");
    if (state === "active" || state === "grace") {
      activeTermId = termId;
      hotUsed =
        typeof entry.used === "number" ? entry.used : hotUsed;
    }
  }

  return { activeTermId, hotUsed };
}

function insertOrUpdateTermFromSnapshotEntry(
  storage: DurableObjectStorage,
  entry: SnapshotTermEntry,
): void {
  const termId = String(entry.term_id ?? "");
  if (termId.length === 0) {
    return;
  }
  const usedFinal = snapshotTermUsedFinal(entry);
  const existing = sqlSelect<{ term_id: string }>(
    storage,
    `SELECT term_id FROM term WHERE term_id = ${sqlString(termId)} LIMIT 1`,
  )[0];
  const columns = `term_id, grant_id, origin_grant_id, position, state, end_reason,
        plan_snapshot, allowance, used_final, duration_unit, duration_count,
        grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at`;
  const values = `
        ${sqlString(termId)},
        ${sqlString(String(entry.grant_id ?? ""))},
        ${sqlString(String(entry.origin_grant_id ?? entry.grant_id ?? ""))},
        ${Number(entry.position ?? 0)},
        ${sqlString(String(entry.state ?? "ended"))},
        ${entry.end_reason === null || entry.end_reason === undefined ? "NULL" : sqlString(String(entry.end_reason))},
        ${sqlString(snapshotTermPlanSnapshot(entry))},
        ${entry.allowance === null || entry.allowance === undefined ? "NULL" : String(entry.allowance)},
        ${usedFinal === null ? "NULL" : String(usedFinal)},
        ${entry.duration_unit === null || entry.duration_unit === undefined ? "NULL" : sqlString(String(entry.duration_unit))},
        ${entry.duration_count === null || entry.duration_count === undefined ? "NULL" : String(entry.duration_count)},
        ${entry.grace_days === null || entry.grace_days === undefined ? "NULL" : String(entry.grace_days)},
        ${entry.grace_cap === null || entry.grace_cap === undefined ? "NULL" : sqlString(String(entry.grace_cap))},
        ${entry.calendar_start === null || entry.calendar_start === undefined ? "NULL" : sqlString(String(entry.calendar_start))},
        ${entry.starts_at === null || entry.starts_at === undefined ? "NULL" : sqlString(String(entry.starts_at))},
        ${entry.ends_at === null || entry.ends_at === undefined ? "NULL" : sqlString(String(entry.ends_at))},
        ${entry.grace_ends_at === null || entry.grace_ends_at === undefined ? "NULL" : sqlString(String(entry.grace_ends_at))},
        ${entry.ended_at === null || entry.ended_at === undefined ? "NULL" : sqlString(String(entry.ended_at))}`;
  if (existing === undefined) {
    sqlExec(storage, `INSERT INTO term (${columns}) VALUES (${values})`);
    return;
  }
  sqlExec(
    storage,
    `UPDATE term SET
      grant_id = ${sqlString(String(entry.grant_id ?? ""))},
      origin_grant_id = ${sqlString(String(entry.origin_grant_id ?? entry.grant_id ?? ""))},
      position = ${Number(entry.position ?? 0)},
      state = ${sqlString(String(entry.state ?? "ended"))},
      end_reason = ${entry.end_reason === null || entry.end_reason === undefined ? "NULL" : sqlString(String(entry.end_reason))},
      plan_snapshot = ${sqlString(snapshotTermPlanSnapshot(entry))},
      allowance = ${entry.allowance === null || entry.allowance === undefined ? "NULL" : String(entry.allowance)},
      used_final = ${usedFinal === null ? "NULL" : String(usedFinal)},
      duration_unit = ${entry.duration_unit === null || entry.duration_unit === undefined ? "NULL" : sqlString(String(entry.duration_unit))},
      duration_count = ${entry.duration_count === null || entry.duration_count === undefined ? "NULL" : String(entry.duration_count)},
      grace_days = ${entry.grace_days === null || entry.grace_days === undefined ? "NULL" : String(entry.grace_days)},
      grace_cap = ${entry.grace_cap === null || entry.grace_cap === undefined ? "NULL" : sqlString(String(entry.grace_cap))},
      calendar_start = ${entry.calendar_start === null || entry.calendar_start === undefined ? "NULL" : sqlString(String(entry.calendar_start))},
      starts_at = ${entry.starts_at === null || entry.starts_at === undefined ? "NULL" : sqlString(String(entry.starts_at))},
      ends_at = ${entry.ends_at === null || entry.ends_at === undefined ? "NULL" : sqlString(String(entry.ends_at))},
      grace_ends_at = ${entry.grace_ends_at === null || entry.grace_ends_at === undefined ? "NULL" : sqlString(String(entry.grace_ends_at))},
      ended_at = ${entry.ended_at === null || entry.ended_at === undefined ? "NULL" : sqlString(String(entry.ended_at))}
     WHERE term_id = ${sqlString(termId)}`,
  );
}

function syncDoTermsAndHotFromCoverageSnapshot(
  storage: DurableObjectStorage,
  snapshot: Record<string, unknown>,
): void {
  const termsRaw = snapshot.terms;
  const termEntries: SnapshotTermEntry[] = Array.isArray(termsRaw)
    ? (termsRaw as SnapshotTermEntry[])
    : [];
  const { activeTermId, hotUsed } = hotActiveUsageFromSnapshot(snapshot);
  const graceBaseUsed =
    typeof snapshot.grace_base_used === "number" ? snapshot.grace_base_used : 0;
  const awaitingTransfer =
    snapshot.awaiting_transfer === true || snapshot.awaiting_transfer === 1 ? 1 : 0;
  const transferPending =
    snapshot.transfer_pending === true || snapshot.transfer_pending === 1 ? 1 : 0;
  const transferredOutTo =
    typeof snapshot.transferred_out_to === "string" &&
    snapshot.transferred_out_to.length > 0
      ? snapshot.transferred_out_to
      : null;
  updateHot(storage, {
    active_term_id: activeTermId,
    used: hotUsed,
    grace_base_used: graceBaseUsed,
    awaiting_transfer: awaitingTransfer,
    transfer_pending: transferPending,
    transferred_out_to: transferredOutTo,
  });
  for (const entry of termEntries) {
    insertOrUpdateTermFromSnapshotEntry(storage, entry);
  }
}

function hydrateDoFromCoverageSnapshot(
  storage: DurableObjectStorage,
  snapshot: Record<string, unknown>,
  bindingEpoch: number,
): void {
  const termsRaw = snapshot.terms;
  const termEntries: SnapshotTermEntry[] = Array.isArray(termsRaw)
    ? (termsRaw as SnapshotTermEntry[])
    : [];

  const { activeTermId, hotUsed } = hotActiveUsageFromSnapshot(snapshot);
  const graceBaseUsed =
    typeof snapshot.grace_base_used === "number" ? snapshot.grace_base_used : 0;
  const awaitingTransfer =
    snapshot.awaiting_transfer === true || snapshot.awaiting_transfer === 1 ? 1 : 0;
  const transferPending =
    snapshot.transfer_pending === true || snapshot.transfer_pending === 1 ? 1 : 0;
  const transferredOutTo =
    typeof snapshot.transferred_out_to === "string" &&
    snapshot.transferred_out_to.length > 0
      ? snapshot.transferred_out_to
      : null;

  const suspended = snapshot.suspended === true ? 1 : 0;
  const clinicSeq =
    typeof snapshot.clinic_seq === "number" ? snapshot.clinic_seq : 0;
  const snapshotBindingEpoch =
    typeof snapshot.binding_epoch === "number"
      ? snapshot.binding_epoch
      : bindingEpoch;

  sqlExec(
    storage,
    `INSERT INTO hot (
      suspended, transferred_out_to, awaiting_transfer, transfer_pending,
      active_term_id, used, reserved, grace_base_used, reservations, replay,
      idempotency, band_emitted, binding_epoch, clinic_seq, next_alarm_at
    ) VALUES (
      ${suspended},
      ${transferredOutTo === null ? "NULL" : sqlString(transferredOutTo)},
      ${awaitingTransfer}, ${transferPending},
      ${activeTermId === null ? "NULL" : sqlString(activeTermId)},
      ${hotUsed}, 0, ${graceBaseUsed}, '[]', '{}', '{}', '{}',
      ${snapshotBindingEpoch}, ${clinicSeq}, NULL
    )`,
  );

  for (const entry of termEntries) {
    insertOrUpdateTermFromSnapshotEntry(storage, entry);
  }
}

function applyUsageToDoTerm(
  storage: DurableObjectStorage,
  termId: string,
  quotaWeight: number,
): void {
  const hot = loadHot(storage);
  if (hot.active_term_id === termId) {
    updateHot(storage, { used: hot.used + quotaWeight });
    return;
  }
  const terms = loadTerms(storage);
  const term = terms.find((row) => row.term_id === termId);
  if (term === undefined) {
    return;
  }
  const nextUsed = (term.used_final ?? 0) + quotaWeight;
  sqlExec(
    storage,
    `UPDATE term SET used_final = ${nextUsed} WHERE term_id = ${sqlString(termId)}`,
  );
}

function snapshotUsedByTermId(
  snapshot: Record<string, unknown>,
): Map<string, number> {
  const usedByTerm = new Map<string, number>();
  const termsRaw = snapshot.terms;
  if (Array.isArray(termsRaw)) {
    for (const entry of termsRaw) {
      if (entry === null || typeof entry !== "object") {
        continue;
      }
      const term = entry as Record<string, unknown>;
      const termId = typeof term.term_id === "string" ? term.term_id : "";
      if (termId.length === 0 || typeof term.used !== "number") {
        continue;
      }
      usedByTerm.set(termId, term.used);
    }
  }
  const termObject = snapshot.term;
  if (
    termObject !== null &&
    typeof termObject === "object" &&
    !Array.isArray(termObject)
  ) {
    const active = termObject as Record<string, unknown>;
    const ref = typeof active.ref === "string" ? active.ref : "";
    if (ref.length > 0 && typeof active.used === "number") {
      usedByTerm.set(ref, active.used);
    }
  }
  return usedByTerm;
}

async function reapplyUsageEventsAfterSnapshot(
  db: D1Database,
  storage: DurableObjectStorage,
  installationId: string,
  snapshotAt: string,
  termIds: string[],
  anchorSnapshot: Record<string, unknown>,
): Promise<void> {
  if (termIds.length === 0) {
    return;
  }
  const placeholders = termIds.map(() => "?").join(", ");
  const rows = await db
    .prepare(
      `SELECT request_id, term_id, quota_weight, recorded_at FROM usage_event
       WHERE installation_id = ? AND recorded_at >= ?
         AND term_id IN (${placeholders})
       ORDER BY recorded_at ASC, request_id ASC`,
    )
    .bind(installationId, snapshotAt, ...termIds)
    .all<{
      request_id: string;
      term_id: string;
      quota_weight: number;
      recorded_at: string;
    }>();

  const snapshotUsedRemaining = snapshotUsedByTermId(anchorSnapshot);
  const appliedRequestIds = new Set<string>();
  for (const row of rows.results ?? []) {
    if (appliedRequestIds.has(row.request_id)) {
      continue;
    }
    appliedRequestIds.add(row.request_id);

    let quotaWeight = row.quota_weight;
    if (row.recorded_at === snapshotAt) {
      const covered = snapshotUsedRemaining.get(row.term_id) ?? 0;
      if (covered >= quotaWeight) {
        snapshotUsedRemaining.set(row.term_id, covered - quotaWeight);
        continue;
      }
      snapshotUsedRemaining.set(row.term_id, 0);
      quotaWeight -= covered;
    }

    if (quotaWeight <= 0) {
      continue;
    }
    applyUsageToDoTerm(storage, row.term_id, quotaWeight);
  }
}

type GrantLedgerRebuildRow = {
  grant_id: string;
  origin_grant_id: string;
  org_id: string;
  installation_id: string;
  kind: string;
  source_kind: string;
  envelope_sha256: string;
  receipt: string;
  applied_at: string;
};

async function loadGrantLedgerR2Line(
  r2: R2Bucket,
  grantId: string,
): Promise<Record<string, unknown> | null> {
  const key = `grant-ledger/${grantId}.ndjson`;
  const object = await r2.get(key);
  if (object === null) {
    return null;
  }
  const text = await object.text();
  const line = text.trim().split("\n")[0] ?? "";
  if (line.length === 0) {
    return null;
  }
  return JSON.parse(line) as Record<string, unknown>;
}

function insertDoGrantRowFromLedger(
  storage: DurableObjectStorage,
  row: GrantLedgerRebuildRow,
  r2Line: Record<string, unknown> | null,
): void {
  const existing = sqlSelect<{ grant_id: string }>(
    storage,
    `SELECT grant_id FROM grant WHERE grant_id = ${sqlString(row.grant_id)} LIMIT 1`,
  )[0];
  if (existing !== undefined) {
    return;
  }
  const receipt =
    r2Line !== null &&
    typeof r2Line.receipt === "object" &&
    r2Line.receipt !== null
      ? (r2Line.receipt as Record<string, unknown>)
      : (JSON.parse(row.receipt) as Record<string, unknown>);
  const envelopeJson =
    r2Line !== null ? JSON.stringify(r2Line) : JSON.stringify({ grant_id: row.grant_id });
  sqlExec(
    storage,
    `INSERT INTO grant (
      grant_id, kind, source_kind, envelope_sha256, envelope, evidence, receipt, applied_at, voided_at, void_reason
    ) VALUES (
      ${sqlString(row.grant_id)}, ${sqlString(row.kind)}, ${sqlString(row.source_kind)},
      ${sqlString(row.envelope_sha256)}, ${sqlString(envelopeJson)},
      ${sqlString("{}")}, ${sqlString(JSON.stringify(receipt))},
      ${sqlString(row.applied_at)}, NULL, NULL
    )`,
  );
}

async function restoreDoGrantRowsFromLedger(
  storage: DurableObjectStorage,
  db: D1Database,
  installationId: string,
  anchorAt: string,
  r2: R2Bucket,
): Promise<void> {
  const rows = await db
    .prepare(
      `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
              envelope_sha256, receipt, applied_at
       FROM grant_ledger
       WHERE installation_id = ? AND applied_at <= ?
       ORDER BY applied_at ASC, grant_id ASC`,
    )
    .bind(installationId, anchorAt)
    .all<GrantLedgerRebuildRow>();
  for (const row of rows.results ?? []) {
    const r2Line = await loadGrantLedgerR2Line(r2, row.grant_id);
    insertDoGrantRowFromLedger(storage, row, r2Line);
  }
}

function snapshotTermsIncludeGrant(
  snapshot: Record<string, unknown>,
  grantId: string,
): boolean {
  const termsRaw = snapshot.terms;
  if (!Array.isArray(termsRaw)) {
    return false;
  }
  for (const entry of termsRaw) {
    if (entry === null || typeof entry !== "object") {
      continue;
    }
    const term = entry as Record<string, unknown>;
    if (term.grant_id === grantId || term.origin_grant_id === grantId) {
      return true;
    }
  }
  return false;
}

async function findGrantAppliedSnapshotForGrant(
  db: D1Database,
  installationId: string,
  grantId: string,
  afterClinicSeq: number,
): Promise<Record<string, unknown> | null> {
  const rows = await db
    .prepare(
      `SELECT snapshot, clinic_seq FROM coverage_event
       WHERE installation_id = ? AND kind = 'grant_applied' AND clinic_seq > ?
       ORDER BY clinic_seq ASC`,
    )
    .bind(installationId, afterClinicSeq)
    .all<{ snapshot: string; clinic_seq: number }>();
  for (const row of rows.results ?? []) {
    try {
      const snapshot = JSON.parse(row.snapshot) as Record<string, unknown>;
      if (snapshotTermsIncludeGrant(snapshot, grantId)) {
        return snapshot;
      }
    } catch {
      continue;
    }
  }
  return null;
}

async function applyGrantLedgerRowToDo(
  storage: DurableObjectStorage,
  row: GrantLedgerRebuildRow,
  r2: R2Bucket,
  db: D1Database,
  installationId: string,
  anchorClinicSeq: number,
): Promise<void> {
  const r2Line = await loadGrantLedgerR2Line(r2, row.grant_id);
  insertDoGrantRowFromLedger(storage, row, r2Line);

  const grantAppliedSnapshot = await findGrantAppliedSnapshotForGrant(
    db,
    installationId,
    row.grant_id,
    anchorClinicSeq,
  );
  if (grantAppliedSnapshot !== null) {
    syncDoTermsAndHotFromCoverageSnapshot(storage, grantAppliedSnapshot);
  }
}

function applyGrantVoidRowToDo(
  storage: DurableObjectStorage,
  row: { grant_id: string; reason: string; at: string },
): void {
  const terms = loadTerms(storage);
  const term = findTermForGrant(terms, row.grant_id);
  if (term === undefined) {
    return;
  }

  if (term.state === "active" || term.state === "grace") {
    sqlExec(
      storage,
      `UPDATE term SET state = 'ended', end_reason = 'reversed', ended_at = ${sqlString(row.at)}, grace_ends_at = NULL
       WHERE term_id = ${sqlString(term.term_id)}`,
    );
    const hot = loadHot(storage);
    if (hot.active_term_id === term.term_id) {
      updateHot(storage, { active_term_id: null });
    }
    const queuedBeforeHold = loadTerms(storage).filter(
      (entry) => entry.state === "queued",
    );
    for (const queued of queuedBeforeHold) {
      sqlExec(
        storage,
        `UPDATE term SET state = 'held' WHERE term_id = ${sqlString(queued.term_id)}`,
      );
    }
    return;
  }

  if (term.state === "queued" || term.state === "held") {
    sqlExec(
      storage,
      `UPDATE term SET state = 'ended', end_reason = 'reversed', ended_at = ${sqlString(row.at)}
       WHERE term_id = ${sqlString(term.term_id)}`,
    );
  }
}

const REBUILD_COVERAGE_EVENT_KINDS = new Set([
  "term_held",
  "term_released",
  "suspension_changed",
  "suspend",
  "resume",
  "transfer",
]);

export type RebuildClinicDoRequest = {
  kind: "rebuild_clinic_do";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  bindingEpoch: number;
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  db: D1Database;
  r2: R2Bucket;
};

export type RebuildClinicDoResponse = {
  kind: "rebuild_clinic_do";
  result: "ok" | "not_found";
  snapshot?: Record<string, unknown>;
};

export type RunRebuildClinicDoResult =
  | { status: "not_found" }
  | { status: "ok"; compare: "clean" | "mismatch" };

export async function rebuildClinicDoRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: RebuildClinicDoRequest,
): Promise<RebuildClinicDoResponse> {
  return blockConcurrencyWhile(async () => {
    const anchor = await request.db
      .prepare(
        `SELECT event_id, org_id, installation_id, binding_epoch, clinic_seq, kind, snapshot, at
         FROM coverage_event
         WHERE installation_id = ?
         ORDER BY clinic_seq DESC
         LIMIT 1`,
      )
      .bind(request.installationId)
      .first<{
        event_id: string;
        org_id: string;
        installation_id: string;
        binding_epoch: number;
        clinic_seq: number;
        kind: string;
        snapshot: string;
        at: string;
      }>();

    if (anchor === null) {
      return { kind: "rebuild_clinic_do", result: "not_found" };
    }

    const anchorSnapshot = JSON.parse(anchor.snapshot) as Record<
      string,
      unknown
    >;

    wipeCoverageDoTables(storage);
    hydrateDoFromCoverageSnapshot(
      storage,
      anchorSnapshot,
      request.bindingEpoch,
    );
    updateHot(storage, { reservations: "[]", reserved: 0 });
    await restoreDoGrantRowsFromLedger(
      storage,
      request.db,
      request.installationId,
      anchor.at,
      request.r2,
    );

    const ledgerRows = await request.db
      .prepare(
        `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
                operator_credential_id, envelope_sha256, receipt, applied_at
         FROM grant_ledger
         WHERE installation_id = ? AND applied_at > ?
         ORDER BY applied_at ASC, grant_id ASC`,
      )
      .bind(request.installationId, anchor.at)
      .all<{
        grant_id: string;
        origin_grant_id: string;
        org_id: string;
        installation_id: string;
        kind: string;
        source_kind: string;
        operator_credential_id: string;
        envelope_sha256: string;
        receipt: string;
        applied_at: string;
      }>();

    for (const row of ledgerRows.results ?? []) {
      await applyGrantLedgerRowToDo(
        storage,
        row,
        request.r2,
        request.db,
        request.installationId,
        anchor.clinic_seq,
      );
    }

    const voidRows = await request.db
      .prepare(
        `SELECT grant_id, reason, source, evidence_sha256, at
         FROM grant_void
         WHERE grant_id IN (
           SELECT grant_id FROM grant_ledger WHERE installation_id = ?
         ) AND at > ?
         ORDER BY at ASC, grant_id ASC`,
      )
      .bind(request.installationId, anchor.at)
      .all<{ grant_id: string; reason: string; at: string }>();

    for (const row of voidRows.results ?? []) {
      applyGrantVoidRowToDo(storage, row);
    }

    const coverageRows = await request.db
      .prepare(
        `SELECT kind, snapshot, clinic_seq, at
         FROM coverage_event
         WHERE installation_id = ? AND clinic_seq > ?
         ORDER BY clinic_seq ASC`,
      )
      .bind(request.installationId, anchor.clinic_seq)
      .all<{ kind: string; snapshot: string; clinic_seq: number; at: string }>();

    for (const row of coverageRows.results ?? []) {
      if (!REBUILD_COVERAGE_EVENT_KINDS.has(row.kind)) {
        continue;
      }
      const eventSnapshot = JSON.parse(row.snapshot) as Record<string, unknown>;
      wipeCoverageDoTables(storage);
      hydrateDoFromCoverageSnapshot(
        storage,
        eventSnapshot,
        request.bindingEpoch,
      );
      updateHot(storage, { reservations: "[]", reserved: 0 });
    }

    const terms = loadTerms(storage);
    const termIds = terms.map((term) => term.term_id);
    await reapplyUsageEventsAfterSnapshot(
      request.db,
      storage,
      request.installationId,
      anchor.at,
      termIds,
      anchorSnapshot,
    );

    const hotAfter = loadHot(storage);
    const termsAfter = loadTerms(storage);
    const rebuiltSnapshot = buildCoverageSnapshot({
      vendorContractVersion: request.vendorContractVersion,
      orgId: request.orgId,
      hot: hotAfter,
      terms: termsAfter,
      durationScale: request.durationScale,
    });
    rebuiltSnapshot.clinic_seq = hotAfter.clinic_seq;

    return { kind: "rebuild_clinic_do", result: "ok", snapshot: rebuiltSnapshot };
  });
}

export async function coverageMirrorMatchesSnapshot(
  db: D1Database,
  installationId: string,
  snapshot: Record<string, unknown>,
): Promise<boolean> {
  const mirror = await db
    .prepare(
      `SELECT state, suspended, binding_epoch, clinic_seq, term_snapshot
       FROM coverage_mirror WHERE installation_id = ?`,
    )
    .bind(installationId)
    .first<{
      state: string;
      suspended: number;
      binding_epoch: number;
      clinic_seq: number;
      term_snapshot: string;
    }>();
  if (mirror === null) {
    return false;
  }

  const snapshotState = String(snapshot.state);
  const expectedMirrorState =
    snapshotState === "reversed" ? "lapsed" : snapshotState;
  if (mirror.state !== expectedMirrorState) {
    return false;
  }

  const suspended = snapshot.suspended ? 1 : 0;
  if (mirror.suspended !== suspended) {
    return false;
  }
  if (mirror.binding_epoch !== snapshot.binding_epoch) {
    return false;
  }
  if (mirror.clinic_seq !== snapshot.clinic_seq) {
    return false;
  }

  let mirrorSnapshot: Record<string, unknown> | null;
  try {
    const parsed = JSON.parse(mirror.term_snapshot) as Record<string, unknown>;
    mirrorSnapshot =
      parsed.contract_version !== undefined
        ? parsed
        : { term: parsed };
  } catch {
    return false;
  }
  if (
    normalizeCoverageSnapshotForMirrorCompare(mirrorSnapshot) !==
    normalizeCoverageSnapshotForMirrorCompare(snapshot)
  ) {
    return false;
  }

  return true;
}

function normalizeCoverageSnapshotForMirrorCompare(
  snapshot: Record<string, unknown>,
): string {
  return canonicalize(snapshot);
}

export async function runRebuildClinicDo(
  env: {
    DB: D1Database;
    DO: DurableObjectNamespace;
    R2: R2Bucket;
    PLATFORM_SIGNING_KEY: string;
    DURATION_SCALE?: string;
  },
  installationId: string,
  options?: { onMismatch: (installationId: string) => Promise<void> },
): Promise<RunRebuildClinicDoResult> {
  const binding = await env.DB.prepare(
    `SELECT org_id, binding_epoch FROM coverage_event
     WHERE installation_id = ?
     ORDER BY clinic_seq DESC
     LIMIT 1`,
  )
    .bind(installationId)
    .first<{ org_id: string; binding_epoch: number }>();
  if (binding === null) {
    return { status: "not_found" };
  }

  const durationScale =
    env.DURATION_SCALE === "staging" ? ("staging" as DurationScale) : undefined;
  const id = env.DO.idFromName(installationId);
  const stub = env.DO.get(id);
  const response = await stub.fetch("https://quota-do.internal/rpc", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contract_version: CHANNEL_VERSIONS.platformDo,
      kind: "rebuild_clinic_do",
      installationId,
      orgId: binding.org_id,
      bindingEpoch: binding.binding_epoch,
      vendorContractVersion: CHANNEL_VERSIONS.platformDo,
      platformSigningKeyJson: env.PLATFORM_SIGNING_KEY,
      durationScale,
    }),
  });
  if (!response.ok) {
    return { status: "not_found" };
  }
  const body = (await response.json()) as RebuildClinicDoResponse;
  if (body.result !== "ok" || body.snapshot === undefined) {
    return { status: "not_found" };
  }

  const matches = await coverageMirrorMatchesSnapshot(
    env.DB,
    installationId,
    body.snapshot,
  );
  if (!matches && options?.onMismatch !== undefined) {
    await options.onMismatch(installationId);
  }
  return { status: "ok", compare: matches ? "clean" : "mismatch" };
}

export async function runRebuildGrantLedger(
  env: { DB: D1Database; R2: R2Bucket },
): Promise<{ grant_ledger: number; grant_void: number }> {
  let grantLedger = 0;
  let grantVoid = 0;
  let cursor: string | undefined;
  do {
    const listed = await env.R2.list({ prefix: "grant-ledger/", cursor });
    for (const object of listed.objects) {
      const key = object.key;
      const stored = await env.R2.get(key);
      if (stored === null) {
        continue;
      }
      const text = await stored.text();
      const line = text.trim().split("\n")[0] ?? "";
      if (line.length === 0) {
        continue;
      }
      const parsed = JSON.parse(line) as Record<string, unknown>;
      if (key.endsWith(".void.ndjson")) {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO grant_void (grant_id, reason, source, evidence_sha256, at)
           VALUES (?, ?, ?, ?, ?)`,
        )
          .bind(
            parsed.grant_id,
            parsed.reason,
            parsed.source,
            parsed.evidence_sha256,
            parsed.at,
          )
          .run();
        grantVoid += 1;
      } else {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO grant_ledger (
            grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
            operator_credential_id, envelope_sha256, receipt, applied_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        )
          .bind(
            parsed.grant_id,
            parsed.origin_grant_id,
            parsed.org_id,
            parsed.installation_id,
            parsed.kind,
            parsed.source_kind,
            parsed.operator_credential_id,
            parsed.envelope_sha256,
            JSON.stringify(parsed.receipt),
            parsed.applied_at,
          )
          .run();
        grantLedger += 1;
      }
    }
    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor !== undefined);

  return { grant_ledger: grantLedger, grant_void: grantVoid };
}

export type RefreshCoverageSnapshotRequest = {
  kind: "refresh_coverage_snapshot";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  durationScale?: DurationScale;
  db: D1Database;
  r2: R2Bucket;
  nowIso: string;
};

export type RefreshCoverageSnapshotResponse = {
  kind: "refresh_coverage_snapshot";
  result: "ok" | "not_found";
  event_id?: string;
};

export async function refreshCoverageSnapshotRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: RefreshCoverageSnapshotRequest,
  logger: Logger = noopLogger,
): Promise<RefreshCoverageSnapshotResponse> {
  return blockConcurrencyWhile(async () => {
    const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
    if (hotRows.length === 0) {
      return { kind: "refresh_coverage_snapshot", result: "not_found" };
    }

    const clinicSeq = emitCoverageEvent(storage, {
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      kind: "snapshot",
      at: request.nowIso,
      durationScale: request.durationScale,
    });
    const eventId = coverageEventId(request.installationId, clinicSeq);
    await scheduleCoverageAlarm(state, storage, request.nowIso);
    await shipCoverageOutboxInLock(
      state,
      storage,
      { DB: request.db, R2: request.r2 },
      request.installationId,
      request.nowIso,
      logger,
      request.durationScale,
    );

    return {
      kind: "refresh_coverage_snapshot",
      result: "ok",
      event_id: eventId,
    };
  });
}

export async function runRefreshCoverageSnapshot(
  env: {
    DB: D1Database;
    DO: DurableObjectNamespace;
    R2: R2Bucket;
    DURATION_SCALE?: string;
  },
  installationId: string,
  nowIso: string,
): Promise<{ event_id: string } | "not_found"> {
  const binding = await env.DB.prepare(
    `SELECT org_id FROM coverage_event WHERE installation_id = ? LIMIT 1`,
  )
    .bind(installationId)
    .first<{ org_id: string }>();
  if (binding === null) {
    return "not_found";
  }

  const durationScale =
    env.DURATION_SCALE === "staging" ? ("staging" as DurationScale) : undefined;
  const id = env.DO.idFromName(installationId);
  const stub = env.DO.get(id);
  const response = await stub.fetch("https://quota-do.internal/rpc", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contract_version: CHANNEL_VERSIONS.platformDo,
      kind: "refresh_coverage_snapshot",
      installationId,
      orgId: binding.org_id,
      vendorContractVersion: CHANNEL_VERSIONS.platformDo,
      durationScale,
      nowIso,
    }),
  });
  if (!response.ok) {
    return "not_found";
  }
  const body = (await response.json()) as RefreshCoverageSnapshotResponse;
  if (body.result !== "ok" || body.event_id === undefined) {
    return "not_found";
  }
  return { event_id: body.event_id };
}
