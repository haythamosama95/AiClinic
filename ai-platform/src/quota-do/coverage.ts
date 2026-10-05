import {
  CHANNEL_VERSIONS,
  coverageEventId,
  grantEnvelopeHash,
  receiptSigningBytes,
  signCompactJws,
} from "vendor-contracts";
import { addDuration, type DurationScale } from "../coverage/calendar";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
type SqlStorage = DurableObjectStorage & {
  sql?: {
    exec: (query: string, ...bindings: unknown[]) => Iterable<Record<string, unknown>>;
  };
};

function sqlExec(storage: DurableObjectStorage, query: string): void {
  const sqlStorage = storage as SqlStorage;
  if (!sqlStorage.sql) {
    return;
  }
  sqlStorage.sql.exec(query);
}

function sqlSelect<T extends Record<string, unknown>>(
  storage: DurableObjectStorage,
  query: string,
): T[] {
  const sqlStorage = storage as SqlStorage;
  if (!sqlStorage.sql) {
    return [];
  }
  return [...sqlStorage.sql.exec(query)] as T[];
}

function sqlString(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

type HotRow = {
  suspended: number;
  active_term_id: string | null;
  used: number;
  binding_epoch: number;
  clinic_seq: number;
  next_alarm_at: string | null;
};

type TermRow = {
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

export interface ApplyGrantRequest {
  kind: "apply_grant";
  installationId: string;
  bindingEpoch: number;
  vendorContractVersion: number;
  orgId: string;
  envelope: Record<string, unknown>;
  aboKid: string;
  planSnapshot: PlanSnapshot;
  durationUnit: "month";
  durationCount: number;
  allowanceCredits: number;
  graceDays: number;
  operatorCredentialId: string;
  platformSigningKeyJson: string;
  durationScale?: DurationScale;
  nowIso: string;
  db: D1Database;
}

export interface ApplyGrantResponse {
  kind: "apply_grant";
  result: "applied" | "already_applied" | "conflict";
  receipt?: Record<string, unknown>;
}

export interface ReadCoverageRequest {
  kind: "read_coverage";
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
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

function loadHot(storage: DurableObjectStorage): HotRow {
  const rows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
  if (rows.length === 0) {
    throw new Error("hot row missing");
  }
  return rows[0]!;
}

function loadTerms(storage: DurableObjectStorage): TermRow[] {
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

function buildCoverageSnapshot(input: {
  vendorContractVersion: number;
  orgId: string;
  hot: HotRow;
  terms: TermRow[];
  durationScale?: DurationScale;
}): Record<string, unknown> {
  const active = input.terms.find((term) => term.state === "active");
  const queued = input.terms.filter((term) => term.state === "queued");
  let termObject: Record<string, unknown> | null = null;
  if (active !== undefined) {
    const used =
      active.term_id === input.hot.active_term_id
        ? input.hot.used
        : (active.used_final ?? 0);
    const snapshot = JSON.parse(active.plan_snapshot) as {
      display_name?: string;
    };
    termObject = {
      ref: active.term_id,
      plan_display_name: snapshot.display_name ?? "",
      starts_at: active.starts_at ?? "",
      ends_at: active.ends_at ?? "",
      grace_ends_at: termGraceEndsAtDisplay(active),
      allowance: active.allowance ?? 0,
      used,
      band: "ok",
    };
  }

  return {
    contract_version: input.vendorContractVersion,
    state: active !== undefined ? "active" : "active",
    reason: "none",
    suspended: false,
    term: termObject,
    queued_count: queued.length,
    held_count: 0,
    coverage_through: computeCoverageThrough(
      input.terms,
      input.hot,
      input.durationScale,
    ),
    binding_epoch: input.hot.binding_epoch,
    clinic_seq: input.hot.clinic_seq,
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

function insertOutbox(storage: DurableObjectStorage, kind: string, payload: unknown): void {
  sqlExec(
    storage,
    `INSERT INTO outbox (kind, payload) VALUES (${sqlString(kind)}, ${sqlString(JSON.stringify(payload))})`,
  );
}

const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;

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

function updateHot(
  storage: DurableObjectStorage,
  patch: Partial<HotRow> & { clinic_seq?: number },
): void {
  const sets: string[] = [];
  if (patch.active_term_id !== undefined) {
    sets.push(`active_term_id = ${patch.active_term_id === null ? "NULL" : sqlString(patch.active_term_id)}`);
  }
  if (patch.used !== undefined) {
    sets.push(`used = ${patch.used}`);
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

function computeNextAlarmAt(
  terms: TermRow[],
  hasOutbox: boolean,
  nowIso: string,
): string | null {
  const boundaries: number[] = [];
  const active = terms.find((term) => term.state === "active");
  if (active?.ends_at) {
    boundaries.push(Date.parse(active.ends_at));
  }
  if (active?.grace_ends_at) {
    boundaries.push(Date.parse(active.grace_ends_at));
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

export async function applyGrantRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: ApplyGrantRequest,
  logger: Logger = noopLogger,
): Promise<ApplyGrantResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
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

    let hot = loadHot(storage);
    let terms = loadTerms(storage);
    const graceTerm = terms.find((term) => term.state === "grace");
    const activeTerm = terms.find((term) => term.state === "active");
    const hasQueued = terms.some((term) => term.state === "queued");

    const termId = crypto.randomUUID();
    const position = nextTermPosition(terms);
    const planSnapshotJson = JSON.stringify(request.planSnapshot);
    const sourceKind = "paid";

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
          sqlExec(
            storage,
            `UPDATE term SET state = 'ended', end_reason = 'renewed', ended_at = ${sqlString(request.nowIso)}
             WHERE term_id = ${sqlString(graceTerm.term_id)}`,
          );
          terms = loadTerms(storage);
        },
      });
      newTermState = "active";
      calendarStart = graceTerm.ends_at ?? request.nowIso;
      startsAt = graceTerm.ends_at ?? request.nowIso;
      endsAt = addDuration(
        calendarStart!,
        request.durationUnit,
        request.durationCount,
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
        request.durationUnit,
        request.durationCount,
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
              NULL, ${sqlString(request.durationUnit)}, ${request.durationCount},
              ${request.graceDays}, 'proportional',
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
          NULL, ${sqlString(request.durationUnit)}, ${request.durationCount},
          ${request.graceDays}, 'proportional',
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
        ${sqlString(grantId)}, 'term', ${sqlString(sourceKind)}, ${sqlString(envelopeSha256)},
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
      source_kind: sourceKind,
      operator_credential_id: request.operatorCredentialId,
      envelope_sha256: envelopeSha256,
      receipt,
      applied_at: request.nowIso,
    };
    insertOutbox(storage, "grant_ledger", ledgerRow);

    insertOutbox(storage, "alert", {
      alert_key: `AL-11:${grantId}`,
      code: "AL-11",
      body: {
        code: "AL-11",
        org_id: request.orgId,
        operation: { op: "grant", params: request.envelope },
      },
    });

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

export async function readCoverageRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: ReadCoverageRequest,
): Promise<ReadCoverageResponse> {
  return blockConcurrencyWhile(async () => {
    const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
    const terms = loadTerms(storage);
    if (hotRows.length === 0) {
      const emptyHot: HotRow = {
        suspended: 0,
        active_term_id: null,
        used: 0,
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
  await db
    .prepare(
      `INSERT OR REPLACE INTO coverage_mirror (
        installation_id, org_id, binding_epoch, clinic_seq, state, suspended, hard_stop_at, term_snapshot
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)`,
    )
    .bind(
      installationId,
      orgId,
      bindingEpoch,
      clinicSeq,
      String(snapshot.state),
      snapshot.suspended ? 1 : 0,
      JSON.stringify(term),
    )
    .run();
}

export type ShippedCoverageAlert = {
  alert_key: string;
  code: string;
  body: Record<string, unknown>;
};

export async function shipCoverageOutboxAlarm(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  env: CoverageShipEnv,
  installationId: string,
  nowIso: string,
  logger: Logger = noopLogger,
): Promise<ShippedCoverageAlert[]> {
  return blockConcurrencyWhile(async () => {
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
  });
}
