import {
  CHANNEL_VERSIONS,
  canonicalize,
  coverageEventId,
  grantEnvelopeHash,
  receiptSigningBytes,
  sha256Hex,
  signCompactJws,
  verifyReceiptSignature,
} from "vendor-contracts";
import { addDuration, type DurationScale } from "../coverage/calendar";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import { generateUlid } from "../trace";
import { decodeDoResponse } from "./response-decoder";
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

function canonicalJsonText(value: unknown): string {
  return new TextDecoder().decode(canonicalize(value));
}

export type HotRow = {
  suspended: number;
  transferred_out_to?: string | null;
  awaiting_transfer?: number;
  awaiting_transfer_id?: string | null;
  transfer_pending?: number;
  transfer_pending_id?: string | null;
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
  kind: string;
  source_kind: string;
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

export type ComplimentaryCeilingClaimIdentity = {
  grantId: string;
  orgId: string;
  envelopeSha256: string;
  planId: string;
  planVersion: number;
  allowanceDenominator: number;
  dayContribution: number;
  allowanceContribution: number;
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
  operatorEmail?: string;
  platformSigningKeyJson?: string;
  environment?: string;
  durationScale?: DurationScale;
  nowIso: string;
  db: D1Database;
  sourceKind?: "paid" | "complimentary";
  envelopeKind?: "term" | "term_adjustment";
  planMaxAllowancePerMonth?: number;
  ceilingPolicy?: CeilingPolicyNumbers;
  ceilingClaim?: ComplimentaryCeilingClaimIdentity;
  skipCeilingCheck?: boolean;
  adjustment?: Record<string, unknown>;
  routeGeneration?: number;
}

export interface SealCeilingClaimRequest {
  kind: "seal_ceiling_claim";
  installationId: string;
  orgId: string;
  bindingEpoch: number;
  routeGeneration: number;
  vendorContractVersion: number;
  grantId: string;
  envelopeSha256: string;
  nowIso: string;
  platformSigningKeyJson?: string;
  environment?: string;
  db: D1Database;
}

export interface SealCeilingClaimResponse {
  kind: "seal_ceiling_claim";
  result: "sealed" | "already_applied" | "sealed_no_effect" | "conflict";
  receipt?: Record<string, unknown>;
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

export interface SealGrantRouteRequest {
  kind: "seal_grant_route";
  installationId: string;
  orgId: string;
  grantId: string;
  envelopeSha256: string;
  routeGeneration: number;
  bindingEpoch: number;
  sealedAt: string;
}

export interface SealGrantRouteResponse {
  kind: "seal_grant_route";
  result: "sealed" | "already_applied" | "conflict";
  receipt?: Record<string, unknown>;
}

/** Persist a no-effect proof before a pending grant claim changes routes. */
export async function sealGrantRouteRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: SealGrantRouteRequest,
): Promise<SealGrantRouteResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const existingGrant = sqlSelect<{ envelope_sha256: string; receipt: string | null }>(
      storage,
      `SELECT envelope_sha256, receipt FROM grant WHERE grant_id = ${sqlString(request.grantId)} LIMIT 1`,
    )[0];
    if (existingGrant !== undefined) {
      if (existingGrant.envelope_sha256 !== request.envelopeSha256) {
        return { kind: "seal_grant_route", result: "conflict" };
      }
      if (typeof existingGrant.receipt === "string") {
        try {
          return {
            kind: "seal_grant_route",
            result: "already_applied",
            receipt: JSON.parse(existingGrant.receipt) as Record<string, unknown>,
          };
        } catch {
          return { kind: "seal_grant_route", result: "conflict" };
        }
      }
      return { kind: "seal_grant_route", result: "conflict" };
    }

    const seal = sqlSelect<{ envelope_sha256: string; route_generation: number }>(
      storage,
      `SELECT envelope_sha256, route_generation FROM grant_route_seal WHERE grant_id = ${sqlString(request.grantId)} LIMIT 1`,
    )[0];
    if (seal !== undefined) {
      return seal.envelope_sha256 === request.envelopeSha256
        ? { kind: "seal_grant_route", result: "sealed" }
        : { kind: "seal_grant_route", result: "conflict" };
    }
    sqlExec(
      storage,
      `INSERT INTO grant_route_seal (grant_id, envelope_sha256, route_generation, sealed_at)
       VALUES (${sqlString(request.grantId)}, ${sqlString(request.envelopeSha256)}, ${request.routeGeneration}, ${sqlString(request.sealedAt)})`,
    );
    return { kind: "seal_grant_route", result: "sealed" };
  });
}

export async function sealCeilingClaimRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: SealCeilingClaimRequest,
): Promise<SealCeilingClaimResponse> {
  return blockConcurrencyWhile(async () => {
    ensureHotRow(storage, request.bindingEpoch);
    const grant = sqlSelect<{ envelope_sha256: string; receipt: string | null }>(
      storage,
      `SELECT envelope_sha256, receipt FROM grant WHERE grant_id = ${sqlString(request.grantId)} LIMIT 1`,
    )[0];
    if (grant !== undefined) {
      if (grant.envelope_sha256 !== request.envelopeSha256) {
        return { kind: "seal_ceiling_claim", result: "conflict" };
      }
      if (typeof grant.receipt === "string") {
        return {
          kind: "seal_ceiling_claim",
          result: "already_applied",
          receipt: JSON.parse(grant.receipt) as Record<string, unknown>,
        };
      }
      return { kind: "seal_ceiling_claim", result: "conflict" };
    }
    const existing = sqlSelect<{ envelope_sha256: string; receipt: string }>(
      storage,
      `SELECT envelope_sha256, receipt FROM grant_ceiling_no_effect_seal
       WHERE grant_id = ${sqlString(request.grantId)} LIMIT 1`,
    )[0];
    if (existing !== undefined) {
      return existing.envelope_sha256 === request.envelopeSha256
        ? {
          kind: "seal_ceiling_claim",
          result: "sealed_no_effect",
          receipt: JSON.parse(existing.receipt) as Record<string, unknown>,
        }
        : { kind: "seal_ceiling_claim", result: "conflict" };
    }
    const claim = await request.db.prepare(
      `SELECT grant_id FROM complimentary_ceiling_claim
       WHERE grant_id = ? AND org_id = ? AND envelope_sha256 = ? AND status = 'pending'`,
    ).bind(request.grantId, request.orgId, request.envelopeSha256).first<{ grant_id: string }>();
    const route = await request.db.prepare(
      `SELECT grant_id FROM grant_claim
       WHERE grant_id = ? AND org_id = ? AND envelope_sha256 = ?
         AND installation_id = ? AND route_generation = ? AND state = 'pending'`,
    ).bind(
      request.grantId,
      request.orgId,
      request.envelopeSha256,
      request.installationId,
      request.routeGeneration,
    ).first<{ grant_id: string }>();
    if (claim === null || route === null) {
      return { kind: "seal_ceiling_claim", result: "conflict" };
    }
    const signingKey = await loadPlatformSigningKey(
      request.platformSigningKeyJson,
      request.environment,
    );
    if (signingKey === null) return { kind: "seal_ceiling_claim", result: "conflict" };
    const hot = loadHot(storage);
    const unsigned = {
      contract_version: request.vendorContractVersion,
      grant_id: request.grantId,
      installation_id: request.installationId,
      org_id: request.orgId,
      result: "sealed_no_effect",
      term_ids: [],
      applied_at: request.nowIso,
      ledger_seq: hot.clinic_seq,
      envelope_sha256: request.envelopeSha256,
      route_generation: request.routeGeneration,
      kid: signingKey.kid,
    };
    const receipt = {
      ...unsigned,
      signature: await signCompactJws({
        payload: receiptSigningBytes(unsigned),
        privateKey: signingKey.privateKey,
        kid: signingKey.kid,
      }),
    };
    const storageWithSql = storage as DurableObjectStorage & {
      sql?: { exec: (query: string, ...bindings: unknown[]) => Iterable<Record<string, unknown>> };
    };
    if (!storageWithSql.sql) return { kind: "seal_ceiling_claim", result: "conflict" };
    storage.transactionSync(() => sqlExec(storage, `INSERT INTO grant_ceiling_no_effect_seal (
      grant_id, org_id, envelope_sha256, route_generation, sealed_at, receipt
    ) VALUES (
      ${sqlString(request.grantId)}, ${sqlString(request.orgId)},
      ${sqlString(request.envelopeSha256)}, ${request.routeGeneration},
      ${sqlString(request.nowIso)}, ${sqlString(JSON.stringify(receipt))}
    )`));
    return { kind: "seal_ceiling_claim", result: "sealed", receipt };
  });
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

export type PlatformSigningMaterial = {
  kid: string;
  privateKey: CryptoKey;
};

const PUBLISHED_DEVELOPMENT_SIGNING_KEY_PKCS8 =
  "MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk";
const PUBLISHED_DEVELOPMENT_SIGNING_KEY_BYTES = base64UrlToBytes(
  PUBLISHED_DEVELOPMENT_SIGNING_KEY_PKCS8,
);
const PUBLISHED_DEVELOPMENT_SIGNING_KEY_PUBLIC =
  "GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0";

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
  json: string | undefined,
  environment = "unknown",
): Promise<PlatformSigningMaterial | null> {
  try {
    if (typeof json !== "string" || json.length === 0) {
      return null;
    }
    const parsed = JSON.parse(json) as {
      kid?: string;
      pkcs8?: string;
    };
    if (typeof parsed.kid !== "string" || typeof parsed.pkcs8 !== "string") {
      return null;
    }
    const pkcs8 = base64UrlToBytes(parsed.pkcs8);
    if (
      environment !== "development" &&
      pkcs8.length === PUBLISHED_DEVELOPMENT_SIGNING_KEY_BYTES.length &&
      pkcs8.every(
        (value, index) => value === PUBLISHED_DEVELOPMENT_SIGNING_KEY_BYTES[index],
      )
    ) {
      return null;
    }
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      pkcs8,
      { name: "Ed25519" },
      false,
      ["sign"],
    );
    if (environment !== "development") {
      // Check both the published PKCS8 bytes and the corresponding public-key
      // identity so re-encoding or renaming the exposed key cannot bypass K-3.
      const publishedPublicKey = await crypto.subtle.importKey(
        "raw",
        base64UrlToBytes(PUBLISHED_DEVELOPMENT_SIGNING_KEY_PUBLIC),
        { name: "Ed25519" },
        false,
        ["verify"],
      );
      const probe = new TextEncoder().encode("R9-RT3 published-key check");
      const signature = await crypto.subtle.sign("Ed25519", privateKey, probe);
      const matchesPublishedBytes =
        pkcs8.length === PUBLISHED_DEVELOPMENT_SIGNING_KEY_BYTES.length &&
        pkcs8.every(
          (value, index) => value === PUBLISHED_DEVELOPMENT_SIGNING_KEY_BYTES[index],
        );
      const matchesPublishedPublicKey = await crypto.subtle.verify(
        "Ed25519",
        publishedPublicKey,
        signature,
        probe,
      );
      if (matchesPublishedBytes || matchesPublishedPublicKey) {
        return null;
      }
    }
    return { kid: parsed.kid, privateKey };
  } catch {
    return null;
  }
}

export { loadPlatformSigningKey };

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
  const used = snapshotTermUsage(term, hot);
  const snapshot = JSON.parse(term.plan_snapshot) as {
    display_name?: string;
    capabilities?: unknown;
    max_cost_class?: unknown;
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
    max_cost_class:
      snapshot.max_cost_class === "standard" ||
      snapshot.max_cost_class === "premium"
        ? snapshot.max_cost_class
        : "economy",
  };
}

function snapshotTermUsage(term: TermRow, hot: HotRow): number {
  let reservations: Array<{ term_id?: string; weight?: number }> = [];
  try {
    reservations = JSON.parse(hot.reservations || "[]") as Array<{
      term_id?: string;
      weight?: number;
    }>;
  } catch {
    reservations = [];
  }
  const reserved = reservations.reduce(
    (total, reservation) =>
      total + (reservation.term_id === term.term_id ? Number(reservation.weight ?? 0) : 0),
    0,
  );
  const settled = term.term_id === hot.active_term_id ? hot.used : (term.used_final ?? 0);
  return settled + reserved;
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
    used: snapshotTermUsage(term, hot),
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

  const hasOpenCoverage = input.terms.some((term) =>
    term.state === "active" || term.state === "grace" ||
    term.state === "queued" || term.state === "held"
  );
  if (input.hot.transfer_pending === 1 && hasOpenCoverage) {
    coverageState = "transfer_pending";
    reason = "transfer_pending";
    if (active !== undefined) {
      termObject = snapshotTermObject(active, input.hot);
    } else if (grace !== undefined) {
      termObject = snapshotTermObject(grace, input.hot);
    }
  } else if (active !== undefined) {
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
  envelope_sha256: string;
  partial: boolean;
  receipt: Record<string, unknown>;
};

type StoredHpReplay = {
  operation: string;
  arguments_sha256: string;
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

function readHpReplayEntry(
  storage: DurableObjectStorage,
  key: string,
): StoredHpReplay | null {
  const hot = loadHot(storage);
  try {
    const parsed = JSON.parse(hot.replay) as Record<string, Record<string, unknown>>;
    const entry = parsed[key];
    if (entry === undefined || typeof entry.receipt !== "object" || entry.receipt === null) {
      return null;
    }
    return entry as unknown as StoredHpReplay;
  } catch {
    return null;
  }
}

function writeHpReplayEntry(
  storage: DurableObjectStorage,
  key: string,
  entry: StoredHpReplay,
): void {
  const hot = loadHot(storage);
  let parsed: Record<string, Record<string, unknown>> = {};
  try {
    parsed = JSON.parse(hot.replay) as Record<string, Record<string, unknown>>;
  } catch {
    parsed = {};
  }
  parsed[key] = entry as unknown as Record<string, unknown>;
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

function prepareCoverageEvents(input: {
  installationId: string;
  orgId: string;
  vendorContractVersion: number;
  at: string;
  durationScale?: DurationScale;
  kinds: string[];
  hotAfter: HotRow;
  termsAfter: TermRow[];
  eventHots?: HotRow[];
  eventTerms?: TermRow[][];
}): { rows: Record<string, unknown>[]; finalHot: HotRow; lastSeq: number } {
  let seq = input.hotAfter.clinic_seq;
  const rows = input.kinds.map((kind, index) => {
    seq += 1;
    const eventHot = { ...(input.eventHots?.[index] ?? input.hotAfter), clinic_seq: seq };
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: input.vendorContractVersion,
      orgId: input.orgId,
      hot: eventHot,
      terms: input.eventTerms?.[index] ?? input.termsAfter,
      durationScale: input.durationScale,
    });
    snapshot.clinic_seq = seq;
    return {
      event_id: coverageEventId(input.installationId, seq),
      org_id: input.orgId,
      installation_id: input.installationId,
      binding_epoch: eventHot.binding_epoch,
      clinic_seq: seq,
      kind,
      at: input.at,
      snapshot,
    };
  });
  return { rows, finalHot: { ...input.hotAfter, clinic_seq: seq }, lastSeq: seq };
}

function commitPreparedEvents(
  storage: DurableObjectStorage,
  rows: Record<string, unknown>[],
): void {
  for (const row of rows) insertOutbox(storage, "coverage_event", row);
}

async function scheduleCoverageAlarm(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  nowIso: string,
): Promise<void> {
  const terms = loadTerms(storage);
  const outboxCount =
    sqlSelect<{ count: number }>(
      storage,
      "SELECT COUNT(*) AS count FROM outbox",
    )[0]?.count ?? 0;
  const nextAlarm = computeNextAlarmAt(terms, outboxCount > 0, nowIso);
  updateHot(storage, { next_alarm_at: nextAlarm });
  await syncAlarm(state, storage, nextAlarm);
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
const MAX_TEST_ALARM_DELIVERY_DELAY_MS = ONE_DAY_MS;

// Workers-pool tests isolate and restore Durable Object SQLite storage after
// each test. Keep a real alarm scheduled (R4-D4 depends on it), but let tests
// invoke it explicitly before the pool can deliver it concurrently with a
// storage-frame teardown. Production never configures this delay.
let testAlarmDeliveryDelayMs = 0;

export function configureTestAlarmDeliveryDelay(runtimeEnv: {
  TEST_DO_ALARM_DELIVERY_DELAY_MS?: string;
}): void {
  const delayMs = Number(runtimeEnv.TEST_DO_ALARM_DELIVERY_DELAY_MS);
  testAlarmDeliveryDelayMs = Number.isSafeInteger(delayMs) && delayMs > 0
    ? Math.min(delayMs, MAX_TEST_ALARM_DELIVERY_DELAY_MS)
    : 0;
}

function physicalAlarmAt(targetMs: number): number {
  const earliestMs = Math.max(targetMs, Date.now() + 5_000);
  if (testAlarmDeliveryDelayMs === 0) return earliestMs;
  return Math.max(earliestMs, Date.now() + testAlarmDeliveryDelayMs);
}

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
};

type PlannedBoundaryEvent = {
  kind: string;
  at: string;
  hot: HotRow;
  terms: TermRow[];
};

type DueBoundaryPlan = {
  termWrites: string[];
  events: PlannedBoundaryEvent[];
  hotAfter: HotRow;
  termsAfter: TermRow[];
};

function planDueBoundaries(input: ApplyDueBoundariesInput): DueBoundaryPlan {
  const nowMs = Date.parse(input.clockNowIso);
  const writes: string[] = [];
  const events: PlannedBoundaryEvent[] = [];
  let terms = loadTerms(input.storage).map((term) => ({ ...term }));
  let hot = { ...loadHot(input.storage) };

  const emit = (kind: string, at: string): void => {
    events.push({ kind, at, hot: { ...hot }, terms: terms.map((term) => ({ ...term })) });
  };

  while (true) {
    const active = terms.find((term) => term.state === "active");
    if (active?.ends_at !== null && active?.ends_at !== undefined && Date.parse(active.ends_at) <= nowMs) {
      const boundaryAt = active.ends_at;
      const queued = terms
        .filter((term) => term.state === "queued")
        .sort((left, right) => left.position - right.position)[0];
      const usedFinal = hot.used;
      terms = terms.map((term) => term.term_id === active.term_id
        ? { ...term, state: queued === undefined ? "grace" : "ended",
            end_reason: queued === undefined ? null : "expired",
            ...(queued === undefined
              ? { grace_ends_at: addDuration(boundaryAt, "day", term.grace_days ?? 0, input.durationScale) }
              : { ended_at: boundaryAt, used_final: usedFinal }) }
        : term);
      if (queued !== undefined) {
        writes.push(`UPDATE term SET state = 'ended', end_reason = 'expired', ended_at = ${sqlString(boundaryAt)}, used_final = ${usedFinal} WHERE term_id = ${sqlString(active.term_id)}`);
        hot = { ...hot, active_term_id: null, grace_base_used: 0 };
        emit("term_ended", input.clockNowIso);
        const durationUnit = (queued.duration_unit ?? "month") as "month" | "day";
        const durationCount = queued.duration_count ?? 1;
        const endsAt = addDuration(boundaryAt, durationUnit, durationCount, input.durationScale);
        writes.push(`UPDATE term SET state = 'active', starts_at = ${sqlString(boundaryAt)}, calendar_start = ${sqlString(boundaryAt)}, ends_at = ${sqlString(endsAt)} WHERE term_id = ${sqlString(queued.term_id)}`);
        terms = terms.map((term) => term.term_id === queued.term_id
          ? { ...term, state: "active", starts_at: boundaryAt, calendar_start: boundaryAt, ends_at: endsAt }
          : term);
        hot = { ...hot, active_term_id: queued.term_id, used: 0, grace_base_used: 0 };
        emit("term_activated", input.clockNowIso);
      } else {
        const graceEndsAt = addDuration(boundaryAt, "day", active.grace_days ?? 0, input.durationScale);
        writes.push(`UPDATE term SET state = 'grace', grace_ends_at = ${sqlString(graceEndsAt)} WHERE term_id = ${sqlString(active.term_id)}`);
        hot = { ...hot, grace_base_used: hot.used };
        emit("grace_started", input.clockNowIso);
        terms = terms.map((term) => term.term_id === active.term_id
          ? { ...term, state: "grace", grace_ends_at: graceEndsAt }
          : term);
      }
      continue;
    }

    const grace = terms.find((term) => term.state === "grace");
    if (grace?.grace_ends_at !== null && grace?.grace_ends_at !== undefined && Date.parse(grace.grace_ends_at) <= nowMs) {
      const usedFinal = hot.used;
      writes.push(`UPDATE term SET state = 'ended', end_reason = 'expired', ended_at = ${sqlString(grace.grace_ends_at)}, used_final = ${usedFinal} WHERE term_id = ${sqlString(grace.term_id)}`);
      terms = terms.map((term) => term.term_id === grace.term_id
        ? { ...term, state: "ended", end_reason: "expired", ended_at: grace.grace_ends_at, used_final: usedFinal }
        : term);
      hot = { ...hot, active_term_id: null, grace_base_used: 0 };
      emit("term_ended", input.clockNowIso);
      continue;
    }
    break;
  }

  return { termWrites: writes, events, hotAfter: hot, termsAfter: terms };
}

function commitDueBoundaryPlan(
  storage: DurableObjectStorage,
  input: ApplyDueBoundariesInput,
  plan: DueBoundaryPlan,
): void {
  if (plan.events.length === 0) return;
  const currentHot = loadHot(storage);
  let seq = currentHot.clinic_seq;
  const payloads = plan.events.map((event) => {
    seq += 1;
    const hot = { ...event.hot, clinic_seq: seq };
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: input.vendorContractVersion,
      orgId: input.orgId,
      hot,
      terms: event.terms,
      durationScale: input.durationScale,
    });
    snapshot.clinic_seq = seq;
    return { ...event, hot, payload: {
      event_id: coverageEventId(input.installationId, seq),
      org_id: input.orgId,
      installation_id: input.installationId,
      binding_epoch: hot.binding_epoch,
      clinic_seq: seq,
      kind: event.kind,
      at: event.at,
      snapshot,
    } };
  });
  storage.transactionSync(() => {
    for (const statement of plan.termWrites) sqlExec(storage, statement);
    updateHot(storage, { ...plan.hotAfter, clinic_seq: seq });
    for (const event of payloads) insertOutbox(storage, "coverage_event", event.payload);
  });
}

function buildBoundaryEventPayloads(
  input: ApplyDueBoundariesInput,
  plan: DueBoundaryPlan,
  startingSeq: number,
): Record<string, unknown>[] {
  return plan.events.map((event, index) => {
    const clinicSeq = startingSeq + index + 1;
    const eventHot = { ...event.hot, clinic_seq: clinicSeq };
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: input.vendorContractVersion,
      orgId: input.orgId,
      hot: eventHot,
      terms: event.terms,
      durationScale: input.durationScale,
    });
    snapshot.clinic_seq = clinicSeq;
    return {
      event_id: coverageEventId(input.installationId, clinicSeq),
      org_id: input.orgId,
      installation_id: input.installationId,
      binding_epoch: eventHot.binding_epoch,
      clinic_seq: clinicSeq,
      kind: event.kind,
      at: event.at,
      snapshot,
    };
  });
}

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
  if (loadTerms(input.storage).length === 0) return false;
  const plan = planDueBoundaries(input);
  commitDueBoundaryPlan(input.storage, input, plan);
  return plan.events.length > 0;
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
  if (patch.awaiting_transfer_id !== undefined) {
    sets.push(`awaiting_transfer_id = ${patch.awaiting_transfer_id === null ? "NULL" : sqlString(patch.awaiting_transfer_id)}`);
  }
  if (patch.transfer_pending !== undefined) {
    sets.push(`transfer_pending = ${patch.transfer_pending}`);
  }
  if (patch.transfer_pending_id !== undefined) {
    sets.push(`transfer_pending_id = ${patch.transfer_pending_id === null ? "NULL" : sqlString(patch.transfer_pending_id)}`);
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
  storage: DurableObjectStorage,
  nextAlarmAt: string | null,
): Promise<void> {
  const actualAlarmAt = await storage.getAlarm();
  if (nextAlarmAt === null) {
    if (actualAlarmAt !== null) await state.storage.deleteAlarm();
    return;
  }
  const targetMs = Date.parse(nextAlarmAt);
  const scheduleMs = physicalAlarmAt(targetMs);
  if (actualAlarmAt === null || actualAlarmAt > scheduleMs) {
    await state.storage.setAlarm(scheduleMs);
  }
}

async function prearmGrantWakeup(state: DurableObjectState): Promise<void> {
  const alarmAt = await state.storage.getAlarm();
  const wakeAt = physicalAlarmAt(Date.now() + 5_000);
  if (alarmAt === null || alarmAt > wakeAt) {
    await state.storage.setAlarm(wakeAt);
  }
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
  const terms = loadTerms(storage);
  const nextAlarm = computeNextAlarmAt(terms, true, nowIso);
  updateHot(storage, { next_alarm_at: nextAlarm });
  await syncAlarm(state, storage, nextAlarm);
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

function grantExceedsCeiling(input: {
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
  termWrites: string[];
  hotAfter: HotRow;
  termsAfter: TermRow[];
  eventKinds: string[];
  attentionAl11: boolean;
  emitAl12: boolean;
  observePaidVelocity?: boolean;
  clinicVelocityAlert?: boolean;
  boundaryPlan?: DueBoundaryPlan;
  logger: Logger;
}): Promise<ApplyGrantResponse> {
  const { storage, request, signingKey, grantId, envelopeSha256 } = input;
  const currentHot = loadHot(storage);
  const boundaryEvents = input.boundaryPlan?.events ?? [];
  const firstSeq = currentHot.clinic_seq + boundaryEvents.length + 1;
  const ledgerSeq = currentHot.clinic_seq + boundaryEvents.length + input.eventKinds.length;
  const finalHot = { ...input.hotAfter, clinic_seq: ledgerSeq };
  const boundaryPayloads = boundaryEvents.map((event, index) => {
    const clinicSeq = currentHot.clinic_seq + index + 1;
    const eventHot = { ...event.hot, clinic_seq: clinicSeq };
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: request.vendorContractVersion,
      orgId: request.orgId,
      hot: eventHot,
      terms: event.terms,
      durationScale: request.durationScale,
    });
    snapshot.clinic_seq = clinicSeq;
    return {
      event_id: coverageEventId(request.installationId, clinicSeq),
      org_id: request.orgId,
      installation_id: request.installationId,
      binding_epoch: eventHot.binding_epoch,
      clinic_seq: clinicSeq,
      kind: event.kind,
      at: event.at,
      snapshot,
    };
  });
  const eventPayloads = input.eventKinds.map((kind, index) => {
    const clinicSeq = firstSeq + index;
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: request.vendorContractVersion,
      orgId: request.orgId,
      hot: { ...finalHot, clinic_seq: clinicSeq },
      terms: input.termsAfter,
      durationScale: request.durationScale,
    });
    snapshot.clinic_seq = clinicSeq;
    return {
      event_id: coverageEventId(request.installationId, clinicSeq),
      org_id: request.orgId,
      installation_id: request.installationId,
      binding_epoch: finalHot.binding_epoch,
      clinic_seq: clinicSeq,
      kind,
      at: request.nowIso,
      snapshot,
    };
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
  const ledgerRow = {
    grant_id: grantId,
    origin_grant_id: grantId,
    org_id: request.orgId,
    installation_id: request.installationId,
    kind: input.grantKind,
    source_kind: input.grantSourceKind,
    operator_credential_id: request.operatorCredentialId,
    operator_email: request.operatorEmail ?? null,
    envelope_sha256: envelopeSha256,
    receipt,
    applied_at: request.nowIso,
    recovery_capsule: {
      version: 1,
      envelope: request.envelope,
      evidence: request.envelope.evidence ?? request.envelope,
      ceiling_claim: request.ceilingClaim ?? null,
    },
  };
  const outboxRows: Array<{ kind: string; payload: unknown }> = [
    ...boundaryPayloads.map((payload) => ({ kind: "coverage_event", payload })),
    ...eventPayloads.map((payload) => ({ kind: "coverage_event", payload })),
    { kind: "grant_ledger", payload: ledgerRow },
    { kind: "alert", payload: {
    alert_key: `AL-11:${grantId}`,
    code: "AL-11",
    body: buildGrantAlertBody(
      request.orgId,
      request.envelope,
      input.attentionAl11,
    ),
    } },
  ];

  if (input.emitAl12) {
    outboxRows.push({ kind: "alert", payload: {
      alert_key: `AL-12:${grantId}`,
      code: "AL-12",
      body: {
        code: "AL-12",
        org_id: request.orgId,
        operation: { op: "grant", params: request.envelope },
      },
    } });
  }
  if (input.observePaidVelocity) {
    outboxRows.push({
      kind: "paid_velocity_observation",
      payload: { now_iso: request.nowIso },
    });
  }
  if (input.clinicVelocityAlert) {
    outboxRows.push({ kind: "alert", payload: {
      alert_key: `AL-17:clinic:${request.orgId}`,
      code: "AL-17",
      body: { code: "AL-17", org_id: request.orgId },
    } });
  }

  await prearmGrantWakeup(input.state);
  const sqlStorage = storage as DurableObjectStorage & {
    sql?: { exec: (query: string, ...bindings: unknown[]) => Iterable<Record<string, unknown>> };
  };
  if (!sqlStorage.sql) throw new Error("grant_storage_unavailable");
  const commitResult = storage.transactionSync(() => {
    const existing = sqlSelect<GrantRow>(
      storage,
      `SELECT grant_id, kind, source_kind, envelope_sha256, receipt FROM grant WHERE grant_id = ${sqlString(grantId)} LIMIT 1`,
    )[0];
    if (existing !== undefined) {
      const termCount = sqlSelect<{ count: number }>(
        storage,
        `SELECT COUNT(*) AS count FROM term WHERE grant_id = ${sqlString(grantId)}`,
      )[0]?.count ?? 0;
      if ((existing.kind === "term" && termCount !== 1) || (existing.kind !== "term" && termCount !== 0)) {
        return { kind: "reconciliation_required" as const };
      }
      return existing.envelope_sha256 === envelopeSha256 && existing.receipt
        ? { kind: "already_applied" as const, receipt: existing.receipt }
        : { kind: "conflict" as const };
    }
    if (input.termWrites.some((statement) => statement.startsWith("INSERT INTO term"))) {
      const existingTerms = sqlSelect<{ count: number }>(
        storage,
        `SELECT COUNT(*) AS count FROM term WHERE grant_id = ${sqlString(grantId)}`,
      )[0]?.count ?? 0;
      if (existingTerms !== 0) throw new Error("grant_term_reconciliation_required");
    }
    for (const statement of [...(input.boundaryPlan?.termWrites ?? []), ...input.termWrites]) sqlExec(storage, statement);
    updateHot(storage, finalHot);
    sqlExec(
      storage,
      `INSERT INTO grant (
        grant_id, kind, source_kind, envelope_sha256, envelope, evidence, receipt, applied_at, voided_at, void_reason
      ) VALUES (
        ${sqlString(grantId)}, ${sqlString(input.grantKind)}, ${sqlString(input.grantSourceKind)}, ${sqlString(envelopeSha256)},
        ${sqlString(JSON.stringify(request.envelope))},
        ${sqlString(JSON.stringify(request.envelope.evidence ?? {}))},
        ${sqlString(JSON.stringify(receipt))}, ${sqlString(request.nowIso)}, NULL, NULL
      )`,
    );
    if (request.ceilingClaim !== undefined) {
      const claim = request.ceilingClaim;
      sqlExec(storage, `INSERT INTO grant_ceiling_claim (
        grant_id, org_id, envelope_sha256, plan_id, plan_version,
        allowance_denominator, day_contribution, allowance_contribution
      ) VALUES (
        ${sqlString(claim.grantId)}, ${sqlString(claim.orgId)}, ${sqlString(claim.envelopeSha256)},
        ${sqlString(claim.planId)}, ${claim.planVersion}, ${claim.allowanceDenominator},
        ${claim.dayContribution}, ${claim.allowanceContribution}
      )`);
    }
    for (const row of outboxRows) insertOutbox(storage, row.kind, row.payload);
    return { kind: "committed" as const };
  });
  if (commitResult.kind !== "committed") {
    await scheduleCoverageAlarm(input.state, storage, request.nowIso);
    if (commitResult.kind === "already_applied") {
      return { kind: "apply_grant", result: "already_applied", receipt: JSON.parse(commitResult.receipt) as Record<string, unknown> };
    }
    if (commitResult.kind === "reconciliation_required") {
      return { kind: "apply_grant", result: "rejected", code: "grant_term_reconciliation_required" };
    }
    return { kind: "apply_grant", result: "conflict" };
  }
  await scheduleCoverageAlarm(input.state, storage, request.nowIso);

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
  boundaryPlan: DueBoundaryPlan,
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
      policy: request.ceilingPolicy,
      planMaxAllowancePerMonth: planMax,
      grantDays,
      grantCredits,
      applyPerGrantCaps: true,
    })
  ) {
    return { kind: "apply_grant", result: "exceeds_ceiling" };
  }

  const terms = boundaryPlan.termsAfter;
  const baseHot = boundaryPlan.hotAfter;
  const graceTerm = terms.find((term) => term.state === "grace");
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

  let newTermState: "active" | "queued" = graceTerm !== undefined
    ? "active"
    : hasActiveGraceOrQueued ? "queued" : "active";
  let calendarStart: string | null = request.nowIso;
  let startsAt: string | null = request.nowIso;
  let endsAt: string | null = null;

  if (graceTerm !== undefined) {
    calendarStart = graceTerm.ends_at ?? request.nowIso;
    startsAt = calendarStart;
  }

  if (newTermState === "active") {
    endsAt = addDuration(
      calendarStart!,
      durationUnit,
      durationCount as number,
      request.durationScale,
    );
    // The prepared SQL is executed only after the receipt has been signed.
    const insertTerm = `INSERT INTO term (
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
      )`;
    const termsAfter = terms.map((term) => term.term_id === graceTerm?.term_id
      ? { ...term, state: "ended", end_reason: "renewed", ended_at: request.nowIso, used_final: baseHot.used }
      : term);
    const graceTermWrite = graceTerm === undefined ? [] : [
      `UPDATE term SET state = 'ended', end_reason = 'renewed', ended_at = ${sqlString(request.nowIso)}, used_final = ${baseHot.used} WHERE term_id = ${sqlString(graceTerm.term_id)}`,
    ];
    return finalizeGrantApply({
      state, storage, request, signingKey, grantId, envelopeSha256,
      termIds: [termId], grantKind: "term", grantSourceKind: "complimentary",
      termWrites: [...graceTermWrite, insertTerm],
      hotAfter: { ...baseHot, active_term_id: termId, used: 0, grace_base_used: graceTerm !== undefined ? 0 : baseHot.grace_base_used },
      termsAfter: [...termsAfter, {
        term_id: termId, grant_id: grantId, origin_grant_id: grantId, position,
        state: "active", end_reason: null, plan_snapshot: planSnapshotJson,
        allowance: request.allowanceCredits, used_final: null, duration_unit: durationUnit,
        duration_count: durationCount as number, grace_days: graceDays, grace_cap: graceCap,
        calendar_start: calendarStart, starts_at: startsAt, ends_at: endsAt,
        grace_ends_at: null, ended_at: null,
      }],
      eventKinds: [...(graceTerm !== undefined ? ["term_ended"] : []), "term_activated", "grant_applied"],
      attentionAl11: true, emitAl12: request.skipCeilingCheck === true, logger,
      boundaryPlan,
    });
  } else {
    const insertTerm = `INSERT INTO term (
        term_id, grant_id, origin_grant_id, position, state, end_reason,
        plan_snapshot, allowance, used_final, duration_unit, duration_count,
        grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
      ) VALUES (
        ${sqlString(termId)}, ${sqlString(grantId)}, ${sqlString(grantId)}, ${position},
        'queued', NULL, ${sqlString(planSnapshotJson)}, ${request.allowanceCredits},
        NULL, ${sqlString(durationUnit)}, ${durationCount as number},
        ${graceDays}, ${sqlString(graceCap)},
        NULL, NULL, NULL, NULL, NULL
      )`;
    return finalizeGrantApply({
      state, storage, request, signingKey, grantId, envelopeSha256,
      termIds: [termId], grantKind: "term", grantSourceKind: "complimentary",
      termWrites: [insertTerm],
      hotAfter: baseHot,
      termsAfter: [...terms, {
        term_id: termId, grant_id: grantId, origin_grant_id: grantId, position,
        state: "queued", end_reason: null, plan_snapshot: planSnapshotJson,
        allowance: request.allowanceCredits, used_final: null, duration_unit: durationUnit,
        duration_count: durationCount as number, grace_days: graceDays, grace_cap: graceCap,
        calendar_start: null, starts_at: null, ends_at: null, grace_ends_at: null, ended_at: null,
      }],
      eventKinds: ["grant_applied"],
      attentionAl11: true, emitAl12: request.skipCeilingCheck === true, logger,
      boundaryPlan,
    });
  }
}

async function applyTermAdjustmentGrant(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  request: ApplyGrantRequest,
  signingKey: PlatformSigningMaterial,
  grantId: string,
  envelopeSha256: string,
  logger: Logger,
  boundaryPlan: DueBoundaryPlan,
): Promise<ApplyGrantResponse> {
  const terms = boundaryPlan.termsAfter;
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

  const updateTerm = `UPDATE term SET ${termSets.join(", ")}
     WHERE term_id = ${sqlString(activeTerm.term_id)}`;

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
    termWrites: [updateTerm],
    hotAfter: boundaryPlan.hotAfter,
    termsAfter: terms.map((term) => term.term_id === activeTerm.term_id
      ? { ...term, allowance, ends_at: endsAt,
          ...(isEnvelopeRecord(adjustmentPlan)
            ? { plan_snapshot: JSON.stringify(request.planSnapshot) }
            : {}) }
      : term),
    eventKinds: ["grant_applied"],
    attentionAl11: true,
    emitAl12: request.skipCeilingCheck === true,
    boundaryPlan,
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
    const grantId = String(request.envelope.grant_id);
    const envelopeSha256 = await grantEnvelopeHash(request.envelope);
    const existing = sqlSelect<GrantRow>(
      storage,
      `SELECT grant_id, kind, source_kind, envelope_sha256, receipt FROM grant WHERE grant_id = ${sqlString(grantId)} LIMIT 1`,
    )[0];
    if (existing !== undefined) {
      if (request.sourceKind === "complimentary") {
        const storedCeilingClaim = sqlSelect<ComplimentaryCeilingClaimIdentity & Record<string, unknown>>(
          storage,
          `SELECT grant_id AS grantId, org_id AS orgId, envelope_sha256 AS envelopeSha256,
                  plan_id AS planId, plan_version AS planVersion,
                  allowance_denominator AS allowanceDenominator,
                  day_contribution AS dayContribution,
                  allowance_contribution AS allowanceContribution
           FROM grant_ceiling_claim WHERE grant_id = ${sqlString(grantId)} LIMIT 1`,
        )[0];
        if (
          request.ceilingClaim === undefined || storedCeilingClaim === undefined ||
          storedCeilingClaim.grantId !== request.ceilingClaim.grantId ||
          storedCeilingClaim.orgId !== request.ceilingClaim.orgId ||
          storedCeilingClaim.envelopeSha256 !== request.ceilingClaim.envelopeSha256 ||
          storedCeilingClaim.planId !== request.ceilingClaim.planId ||
          storedCeilingClaim.planVersion !== request.ceilingClaim.planVersion ||
          storedCeilingClaim.allowanceDenominator !== request.ceilingClaim.allowanceDenominator ||
          storedCeilingClaim.dayContribution !== request.ceilingClaim.dayContribution ||
          storedCeilingClaim.allowanceContribution !== request.ceilingClaim.allowanceContribution
        ) {
          return { kind: "apply_grant", result: "rejected", code: "grant_ceiling_claim_reconciliation_required" };
        }
      }
      if (existing.envelope_sha256 === envelopeSha256 && existing.receipt) {
        const termCount = sqlSelect<{ count: number }>(
          storage,
          `SELECT COUNT(*) AS count FROM term WHERE grant_id = ${sqlString(grantId)}`,
        )[0]?.count ?? 0;
        if ((existing.kind === "term" && termCount !== 1) || (existing.kind !== "term" && termCount !== 0)) {
          return { kind: "apply_grant", result: "rejected", code: "grant_term_reconciliation_required" };
        }
        await scheduleCoverageAlarm(state, storage, request.nowIso);
        return {
          kind: "apply_grant",
          result: "already_applied",
          receipt: JSON.parse(existing.receipt) as Record<string, unknown>,
        };
      }
      return { kind: "apply_grant", result: "conflict" };
    }

    const orphanTermCount = sqlSelect<{ count: number }>(
      storage,
      `SELECT COUNT(*) AS count FROM term WHERE grant_id = ${sqlString(grantId)}`,
    )[0]?.count ?? 0;
    if (orphanTermCount > 0) {
      return { kind: "apply_grant", result: "rejected", code: "grant_term_reconciliation_required" };
    }

    const routeSeal = sqlSelect<{ envelope_sha256: string }>(
      storage,
      `SELECT envelope_sha256 FROM grant_route_seal WHERE grant_id = ${sqlString(grantId)} LIMIT 1`,
    )[0];
    if (routeSeal !== undefined) {
      return routeSeal.envelope_sha256 === envelopeSha256
        ? { kind: "apply_grant", result: "rejected", code: "route_sealed" }
        : { kind: "apply_grant", result: "conflict" };
    }

    const noEffectSeal = sqlSelect<{ envelope_sha256: string }>(
      storage,
      `SELECT envelope_sha256 FROM grant_ceiling_no_effect_seal
       WHERE grant_id = ${sqlString(grantId)} LIMIT 1`,
    )[0];
    if (noEffectSeal !== undefined) {
      return noEffectSeal.envelope_sha256 === envelopeSha256
        ? { kind: "apply_grant", result: "rejected", code: "ceiling_claim_sealed" }
        : { kind: "apply_grant", result: "conflict" };
    }

    // Replays above remain available after a source is frozen. New value may
    // not be applied once a transfer preparation has fenced this installation.
    const currentHot = loadHot(storage);
    if (
      currentHot.binding_epoch !== request.bindingEpoch ||
      currentHot.transfer_pending === 1 ||
      currentHot.transferred_out_to !== null
    ) {
      return { kind: "apply_grant", result: "rejected", code: "transfer_pending" };
    }

    if (request.sourceKind === "complimentary") {
      const claim = request.ceilingClaim;
      if (
        claim === undefined || claim.grantId !== grantId || claim.orgId !== request.orgId ||
        claim.envelopeSha256 !== envelopeSha256 ||
        claim.allowanceDenominator < 1 ||
        !Number.isInteger(claim.planVersion) || !Number.isInteger(claim.dayContribution) ||
        !Number.isInteger(claim.allowanceContribution)
      ) {
        return { kind: "apply_grant", result: "rejected", code: "complimentary_ceiling_claim_required" };
      }
      const storedClaim = await request.db.prepare(
        `SELECT grant_id, org_id, envelope_sha256, plan_id, plan_version,
                allowance_denominator, day_contribution, allowance_contribution,
                status
         FROM complimentary_ceiling_claim WHERE grant_id = ?`,
      ).bind(grantId).first<{
        grant_id: string;
        org_id: string;
        envelope_sha256: string;
        plan_id: string;
        plan_version: number;
        allowance_denominator: number;
        day_contribution: number;
        allowance_contribution: number;
        status: string;
      }>();
      if (
        storedClaim === null || storedClaim.status !== "pending" ||
        storedClaim.org_id !== claim.orgId ||
        storedClaim.envelope_sha256 !== claim.envelopeSha256 ||
        storedClaim.plan_id !== claim.planId || storedClaim.plan_version !== claim.planVersion ||
        storedClaim.allowance_denominator !== claim.allowanceDenominator ||
        storedClaim.day_contribution !== claim.dayContribution ||
        storedClaim.allowance_contribution !== claim.allowanceContribution
      ) {
        return { kind: "apply_grant", result: "rejected", code: "complimentary_ceiling_claim_reconciliation_required" };
      }
      const boundClaim = await request.db.prepare(
        `SELECT grant_id FROM grant_claim
         WHERE grant_id = ? AND org_id = ? AND envelope_sha256 = ?
           AND installation_id = ? AND route_generation = ? AND state = 'pending'
           AND command_state = 'accepted'`,
      ).bind(
        grantId,
        request.orgId,
        envelopeSha256,
        request.installationId,
        request.routeGeneration ?? 1,
      ).first<{ grant_id: string }>();
      if (boundClaim === null) {
        return { kind: "apply_grant", result: "rejected", code: "complimentary_ceiling_claim_route_mismatch" };
      }
    }

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
    const signingKey = await loadPlatformSigningKey(
      request.platformSigningKeyJson,
      request.environment,
    );
    if (signingKey === null) {
      throw new Error("invalid_platform_signing_key");
    }

    const envelopeKind = request.envelopeKind ?? "term";
    const sourceKind = request.sourceKind ?? "paid";

    const boundaryPlan = planDueBoundaries({
      storage,
      clockNowIso: request.nowIso,
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      durationScale: request.durationScale,
    });

    if (envelopeKind === "term_adjustment") {
      return applyTermAdjustmentGrant(
        state,
        storage,
        request,
        signingKey,
        grantId,
        envelopeSha256,
        logger,
        boundaryPlan,
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
        boundaryPlan,
      );
    }

    const terms = boundaryPlan.termsAfter;
    const graceTerm = terms.find((term) => term.state === "grace");
    const activeTerm = terms.find((term) => term.state === "active");
    const hasQueued = terms.some((term) => term.state === "queued");

    const paidDurationUnit = request.durationUnit ?? "month";
    const paidDurationCount = request.durationCount ?? 1;
    const hot = boundaryPlan.hotAfter;

    const termId = crypto.randomUUID();
    const position = nextTermPosition(terms);
    const planSnapshotJson = JSON.stringify(request.planSnapshot);
    const paidSourceKind = "paid";

    const eventKinds: string[] = [];
    const termWrites: string[] = [];

    let newTermState: "active" | "queued" = "active";
    let calendarStart: string | null = request.nowIso;
    let startsAt: string | null = request.nowIso;
    let endsAt: string | null = null;

    if (graceTerm !== undefined) {
      eventKinds.push("term_ended");
      termWrites.push(
        `UPDATE term SET state = 'ended', end_reason = 'renewed', ended_at = ${sqlString(request.nowIso)}, used_final = ${hot.used}
         WHERE term_id = ${sqlString(graceTerm.term_id)}`,
      );
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
      eventKinds.push("term_activated");
      termWrites.push(`INSERT INTO term (
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
            )`);
    } else {
      termWrites.push(`INSERT INTO term (
          term_id, grant_id, origin_grant_id, position, state, end_reason,
          plan_snapshot, allowance, used_final, duration_unit, duration_count,
          grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
        ) VALUES (
          ${sqlString(termId)}, ${sqlString(grantId)}, ${sqlString(grantId)}, ${position},
          'queued', NULL, ${sqlString(planSnapshotJson)}, ${request.allowanceCredits},
          NULL, ${sqlString(paidDurationUnit)}, ${paidDurationCount},
          ${request.graceDays ?? 0}, 'proportional',
          NULL, NULL, NULL, NULL, NULL
        )`);
    }
    eventKinds.push("grant_applied");
    const finalTerms = terms.map((term) => term.term_id === graceTerm?.term_id
      ? { ...term, state: "ended", end_reason: "renewed", ended_at: request.nowIso, used_final: hot.used }
      : term);
    const newTerm: TermRow = {
      term_id: termId, grant_id: grantId, origin_grant_id: grantId, position,
      state: newTermState, end_reason: null, plan_snapshot: planSnapshotJson,
      allowance: request.allowanceCredits, used_final: null, duration_unit: paidDurationUnit,
      duration_count: paidDurationCount, grace_days: request.graceDays ?? 0,
      grace_cap: "proportional", calendar_start: newTermState === "active" ? calendarStart : null,
      starts_at: newTermState === "active" ? startsAt : null,
      ends_at: newTermState === "active" ? endsAt : null, grace_ends_at: null, ended_at: null,
    };
    finalTerms.push(newTerm);
    const hotAfter = {
      ...hot,
      active_term_id: newTermState === "active" ? termId : hot.active_term_id,
      used: newTermState === "active" ? 0 : hot.used,
      grace_base_used: graceTerm !== undefined ? 0 : hot.grace_base_used,
    };
    const clinicVelocityAlert =
      countDoPaidGrantsLast24Hours(storage, request.nowIso) + 1 > 3;
    return finalizeGrantApply({
      state, storage, request, signingKey, grantId, envelopeSha256,
      termIds: [termId], grantKind: "term", grantSourceKind: paidSourceKind,
      termWrites, hotAfter, termsAfter: finalTerms, eventKinds,
      attentionAl11: false, emitAl12: false, observePaidVelocity: true,
      clinicVelocityAlert, logger, boundaryPlan,
    });
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
        kind: "suspension_changed",
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
      await syncAlarm(state, storage, nextAlarm);
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
    const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
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
  routeGeneration: number;
  grantEnvelopeSha256: string;
  db: D1Database;
  grantId: string;
  reversalId: string;
  reason: string;
  evidenceSha256: string;
  envelopeSha256: string;
  nowIso: string;
  platformSigningKeyJson?: string;
  environment?: string;
  durationScale?: DurationScale;
  replayOnly?: boolean;
}

export interface VoidForReversalResponse {
  kind: "void_for_reversal";
  result: "applied" | "already_applied" | "conflict" | "bad_request" | "transient";
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
        stored.evidence_sha256 === request.evidenceSha256 &&
        stored.envelope_sha256 === request.envelopeSha256 &&
        stored.partial === false
      ) {
        await scheduleCoverageAlarm(state, storage, request.nowIso);
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

    const route = await request.db.prepare(
      `SELECT installation_id, binding_epoch, generation, state, reversal_id
       FROM live_value_route WHERE grant_id = ?`,
    ).bind(request.grantId).first<{
      installation_id: string;
      binding_epoch: number;
      generation: number;
      state: string;
      reversal_id: string | null;
    }>();
    if (
      route === null || route.installation_id !== request.installationId ||
      route.binding_epoch !== request.bindingEpoch ||
      route.generation !== request.routeGeneration || route.state !== "voiding" ||
      route.reversal_id !== request.reversalId
    ) {
      return { kind: "void_for_reversal", result: "transient" };
    }

    const signingKey = await loadPlatformSigningKey(
      request.platformSigningKeyJson,
      request.environment,
    );
    if (signingKey === null) {
      return { kind: "void_for_reversal", result: "bad_request" };
    }

    const terms = loadTerms(storage);
    const term = findTermForGrant(terms, request.grantId);
    if (term === undefined) {
      const routeSeal = sqlSelect<{ envelope_sha256: string; route_generation: number }>(
        storage,
        `SELECT envelope_sha256, route_generation FROM grant_route_seal WHERE grant_id = ${sqlString(request.grantId)} LIMIT 1`,
      )[0];
      if (routeSeal !== undefined && (
        routeSeal.envelope_sha256 !== request.grantEnvelopeSha256 ||
        routeSeal.route_generation !== request.routeGeneration
      )) {
        return { kind: "void_for_reversal", result: "conflict" };
      }
      const grant = sqlSelect<{ grant_id: string; envelope_sha256: string }>(
        storage,
        `SELECT grant_id, envelope_sha256 FROM grant WHERE grant_id = ${sqlString(request.grantId)} LIMIT 1`,
      )[0];
      if (grant !== undefined) return { kind: "void_for_reversal", result: "bad_request" };
      const hot = loadHot(storage);
      const receipt = await signReversalVoidReceipt({
        signingKey,
        vendorContractVersion: request.vendorContractVersion,
        reversalId: request.reversalId,
        installationId: request.installationId,
        orgId: request.orgId,
        termIds: [],
        appliedAt: request.nowIso,
        ledgerSeq: hot.clinic_seq,
        envelopeSha256: request.envelopeSha256,
      });
      const payload = {
        grant_id: request.grantId,
        reason: request.reason,
        source: "reversal",
        evidence_sha256: request.evidenceSha256,
        at: request.nowIso,
        receipt,
      };
      const replayEntry = {
        grant_id: request.grantId,
        reason: request.reason,
        evidence_sha256: request.evidenceSha256,
        envelope_sha256: request.envelopeSha256,
        partial: false,
        receipt,
      };
      await prearmGrantWakeup(state);
      storage.transactionSync(() => {
        sqlExec(storage,
          `INSERT OR IGNORE INTO grant_route_seal (grant_id, envelope_sha256, route_generation, sealed_at)
           VALUES (${sqlString(request.grantId)}, ${sqlString(request.grantEnvelopeSha256)}, ${request.routeGeneration}, ${sqlString(request.nowIso)})`,
        );
        insertOutbox(storage, "grant_void", payload);
        writeVoidReplay(storage, request.reversalId, replayEntry);
      });
      await scheduleCoverageAlarm(state, storage, request.nowIso);
      return { kind: "void_for_reversal", result: "applied", receipt };
    }

    if (term.state === "ended" && term.end_reason === "transferred") {
      return { kind: "void_for_reversal", result: "transient" };
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

    const termsAfter = terms.map((row) => ({ ...row }));
    const termWrites: string[] = [];
    const eventKinds: string[] = [];
    const eventTerms: TermRow[][] = [];
    const eventHots: HotRow[] = [];
    const hotBefore = loadHot(storage);
    let hotAfter = { ...hotBefore };
    if (effect === "end_current") {
      Object.assign(termsAfter.find((row) => row.term_id === term.term_id)!, {
        state: "ended", end_reason: "reversed", ended_at: request.nowIso, grace_ends_at: null,
      });
      if (hotAfter.active_term_id === term.term_id) hotAfter.active_term_id = null;
      termWrites.push(`UPDATE term SET state = 'ended', end_reason = 'reversed', ended_at = ${sqlString(request.nowIso)}, grace_ends_at = NULL WHERE term_id = ${sqlString(term.term_id)}`);
      eventKinds.push("term_ended");
      eventTerms.push(termsAfter.map((row) => ({ ...row })));
      eventHots.push({ ...hotAfter });
      for (const queued of termsAfter.filter((row) => row.state === "queued")) {
        queued.state = "held";
        termWrites.push(`UPDATE term SET state = 'held' WHERE term_id = ${sqlString(queued.term_id)}`);
        eventKinds.push("term_held");
        eventTerms.push(termsAfter.map((row) => ({ ...row })));
        eventHots.push({ ...hotAfter });
      }
    } else if (effect === "remove_queued") {
      Object.assign(termsAfter.find((row) => row.term_id === term.term_id)!, {
        state: "ended", end_reason: "reversed", ended_at: request.nowIso,
      });
      termWrites.push(`UPDATE term SET state = 'ended', end_reason = 'reversed', ended_at = ${sqlString(request.nowIso)} WHERE term_id = ${sqlString(term.term_id)}`);
      eventKinds.push("term_ended");
      eventTerms.push(termsAfter.map((row) => ({ ...row })));
      eventHots.push({ ...hotAfter });
    }
    eventKinds.push("grant_voided");
    eventTerms.push(termsAfter.map((row) => ({ ...row })));
    eventHots.push({ ...hotAfter });
    const prepared = prepareCoverageEvents({
      installationId: request.installationId, orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion, at: request.nowIso,
      durationScale: request.durationScale, kinds: eventKinds, hotAfter, termsAfter,
      eventHots, eventTerms,
    });
    const grantVoidedSeq = prepared.lastSeq;
    const termIdsForReceipt = effect === "none" ? [] : [term.term_id];

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

    const voidPayload = {
      grant_id: request.grantId,
      reason: request.reason,
      source: "reversal",
      evidence_sha256: request.evidenceSha256,
      at: request.nowIso,
      receipt,
    };
    const replayEntry = {
      grant_id: request.grantId,
      reason: request.reason,
      evidence_sha256: request.evidenceSha256,
      envelope_sha256: request.envelopeSha256,
      partial: false,
      receipt,
    };
    await prearmGrantWakeup(state);
    const transactionResult = storage.transactionSync(() => {
      const current = readVoidReplay(storage)[request.reversalId];
      if (current !== undefined) {
        return current.grant_id === request.grantId && current.reason === request.reason &&
          current.evidence_sha256 === request.evidenceSha256 && current.envelope_sha256 === request.envelopeSha256 && current.partial === false
          ? { result: "already_applied" as const, receipt: current.receipt }
          : { result: "conflict" as const };
      }
      for (const statement of termWrites) sqlExec(storage, statement);
      updateHot(storage, prepared.finalHot);
      commitPreparedEvents(storage, prepared.rows);
      insertOutbox(storage, "grant_void", voidPayload);
      writeVoidReplay(storage, request.reversalId, replayEntry);
      return { result: "applied" as const, receipt };
    });
    if (transactionResult.result !== "applied") {
      await scheduleCoverageAlarm(state, storage, request.nowIso);
      return { kind: "void_for_reversal", ...transactionResult };
    }
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
  platformSigningKeyJson?: string;
  environment?: string;
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
  platformSigningKeyJson?: string;
  environment?: string;
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
    const argumentsSha256 = await sha256Hex(canonicalize({
      org_id: request.orgId, grant_id: request.grantId, reason: request.reason,
      assertion_sha256: request.assertionSha256,
    }));
    const existing = readHpReplayEntry(storage, replayKey);
    if (existing !== null) {
      await scheduleCoverageAlarm(state, storage, request.nowIso);
      if (existing.operation !== "release_held" || existing.arguments_sha256 !== argumentsSha256) {
        return { kind: "release_held", result: "bad_request" };
      }
      return {
        kind: "release_held",
        result: "already_applied",
        receipt: existing.receipt,
      };
    }
    if (request.replayOnly === true) {
      return { kind: "release_held", result: "bad_request" };
    }

    const signingKey = await loadPlatformSigningKey(
      request.platformSigningKeyJson,
      request.environment,
    );
    if (signingKey === null) {
      return { kind: "release_held", result: "bad_request" };
    }

    const boundaryPlan = planDueBoundaries({
      storage,
      clockNowIso: request.nowIso,
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      durationScale: request.durationScale,
    });
    const terms = boundaryPlan.termsAfter;
    const held = terms.find(
      (term) => term.state === "held" && term.grant_id === request.grantId,
    );
    if (held === undefined) {
      return { kind: "release_held", result: "bad_request" };
    }

    const position = nextTermPosition(terms);
    const graceTerm = terms.find((term) => term.state === "grace");
    const hasActive = terms.some((term) => term.state === "active");
    const hasQueued = terms.some((term) => term.state === "queued");

    const termAfter = { ...held };
    const termWrites: string[] = [];
    if (graceTerm !== undefined) {
      const anchor = graceTerm.ends_at ?? request.nowIso;
      const endsAt = held.duration_unit !== null && held.duration_count !== null
        ? addDuration(anchor, held.duration_unit as "month" | "day", held.duration_count, request.durationScale)
        : addDuration(anchor, "month", 1, request.durationScale);
      Object.assign(termAfter, { state: "active", starts_at: anchor, calendar_start: anchor, ends_at: endsAt });
      termWrites.push(`UPDATE term SET state = 'ended', end_reason = 'renewed', ended_at = ${sqlString(request.nowIso)}, used_final = ${boundaryPlan.hotAfter.used} WHERE term_id = ${sqlString(graceTerm.term_id)}`);
      termWrites.push(`UPDATE term SET state = 'active', starts_at = ${sqlString(anchor)}, calendar_start = ${sqlString(anchor)}, ends_at = ${sqlString(endsAt)} WHERE term_id = ${sqlString(held.term_id)}`);
    } else if (!hasActive && !hasQueued) {
      const endsAt =
        held.duration_unit !== null && held.duration_count !== null
          ? addDuration(
              request.nowIso,
              held.duration_unit as "month" | "day",
              held.duration_count,
              request.durationScale,
            )
          : addDuration(request.nowIso, "month", 1, request.durationScale);
      Object.assign(termAfter, { state: "active", position, starts_at: request.nowIso, calendar_start: request.nowIso, ends_at: endsAt });
      termWrites.push(`UPDATE term SET state = 'active', position = ${position}, starts_at = ${sqlString(request.nowIso)}, calendar_start = ${sqlString(request.nowIso)}, ends_at = ${sqlString(endsAt)} WHERE term_id = ${sqlString(held.term_id)}`);
    } else {
      Object.assign(termAfter, { state: "queued", position });
      termWrites.push(`UPDATE term SET state = 'queued', position = ${position} WHERE term_id = ${sqlString(held.term_id)}`);
    }
    const hotBefore = boundaryPlan.hotAfter;
    const activates = graceTerm !== undefined || (!hasActive && !hasQueued);
    const hotAfter = activates
      ? { ...hotBefore, active_term_id: held.term_id, used: 0, grace_base_used: 0 }
      : hotBefore;
    const termsAfter = terms.map((row) => row.term_id === held.term_id ? termAfter : row.term_id === graceTerm?.term_id
      ? { ...row, state: "ended", end_reason: "renewed", ended_at: request.nowIso, used_final: hotBefore.used }
      : { ...row });
    const eventKinds = graceTerm !== undefined
      ? ["term_ended", "term_released", "term_activated"]
      : activates ? ["term_released", "term_activated"] : ["term_released"];
    const prepared = prepareCoverageEvents({
      installationId: request.installationId, orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion, at: request.nowIso,
      durationScale: request.durationScale, kinds: eventKinds,
      hotAfter: { ...hotAfter, clinic_seq: loadHot(storage).clinic_seq + boundaryPlan.events.length }, termsAfter,
    });
    const releasedSeq = prepared.rows.find((row) => row.kind === "term_released")!.clinic_seq as number;

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

    const replayEntry = { operation: "release_held", arguments_sha256: argumentsSha256, receipt };
    await prearmGrantWakeup(state);
    const boundaryRows = buildBoundaryEventPayloads({
      storage, clockNowIso: request.nowIso, installationId: request.installationId,
      orgId: request.orgId, vendorContractVersion: request.vendorContractVersion,
      durationScale: request.durationScale,
    }, boundaryPlan, loadHot(storage).clinic_seq);
    const transactionResult = storage.transactionSync(() => {
      const current = readHpReplayEntry(storage, replayKey);
      if (current !== null) {
        return current.operation === "release_held" && current.arguments_sha256 === argumentsSha256
          ? { result: "already_applied" as const, receipt: current.receipt }
          : { result: "bad_request" as const };
      }
      for (const statement of [...boundaryPlan.termWrites, ...termWrites]) sqlExec(storage, statement);
      updateHot(storage, prepared.finalHot);
      commitPreparedEvents(storage, [...boundaryRows, ...prepared.rows]);
      writeHpReplayEntry(storage, replayKey, replayEntry);
      return { result: "applied" as const, receipt };
    });
    await scheduleCoverageAlarm(state, storage, request.nowIso);

    logger.info("release_held completed", {
      installation_id: request.installationId,
      grant_id: request.grantId,
    });

    return { kind: "release_held", ...transactionResult };
  });
}

export type RecoverStrandedTermRequest = {
  kind: "recover_stranded_term";
  actionId: string;
  orgId: string;
  installationId: string;
  bindingEpoch: number;
  targetTermId: string;
  sourceGrantId: string;
  expectedClinicSeq: number;
  reason: string;
  evidenceSha256: string;
  actorEmail: string;
  credentialId: string;
  assertionSha256: string;
  nowIso: string;
  vendorContractVersion: number;
  durationScale?: DurationScale;
  replayOnly?: boolean;
};

export type RecoverStrandedTermResponse = {
  kind: "recover_stranded_term";
  result: "ok" | "already_applied" | "conflict" | "bad_request" | "not_found";
  detail?: Record<string, unknown>;
};

/**
 * Repairs only the R4-D2 orphan shape. Eligibility comes from the retained
 * term/grant/evidence rows in the tenant DO; client-supplied evidence hashes
 * are never treated as evidence by themselves.
 */
export async function recoverStrandedTermRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: RecoverStrandedTermRequest,
  logger: Logger = noopLogger,
): Promise<RecoverStrandedTermResponse> {
  return blockConcurrencyWhile(async () => {
    const required = [request.actionId, request.orgId, request.installationId,
      request.targetTermId, request.sourceGrantId, request.reason,
      request.evidenceSha256, request.actorEmail, request.credentialId,
      request.assertionSha256, request.nowIso];
    if (required.some((value) => typeof value !== "string" || value.length === 0) ||
        !Number.isInteger(request.bindingEpoch) || request.bindingEpoch < 0 ||
        !Number.isInteger(request.expectedClinicSeq) || request.expectedClinicSeq < 0 ||
        !/^[0-9a-f]{64}$/u.test(request.evidenceSha256) ||
        !/^[0-9a-f]{64}$/u.test(request.assertionSha256) ||
        Number.isNaN(Date.parse(request.nowIso))) {
      return { kind: "recover_stranded_term", result: "bad_request" };
    }

    ensureHotRow(storage, request.bindingEpoch);
    const requestIdentity = {
      action_id: request.actionId,
      org_id: request.orgId,
      installation_id: request.installationId,
      binding_epoch: request.bindingEpoch,
      target_term_id: request.targetTermId,
      source_grant_id: request.sourceGrantId,
      expected_clinic_seq: request.expectedClinicSeq,
      reason: request.reason,
      evidence_sha256: request.evidenceSha256,
      actor_email: request.actorEmail,
      credential_id: request.credentialId,
      assertion_sha256: request.assertionSha256,
      vendor_contract_version: request.vendorContractVersion,
    };
    const requestSha256 = await sha256Hex(canonicalize(requestIdentity));
    const existing = sqlSelect<{ request_sha256: string; result_json: string }>(
      storage,
      `SELECT request_sha256, result_json FROM stranded_term_recovery WHERE action_id = ${sqlString(request.actionId)} LIMIT 1`,
    )[0];
    if (existing !== undefined) {
      return existing.request_sha256 === requestSha256
        ? (JSON.parse(existing.result_json) as RecoverStrandedTermResponse)
        : { kind: "recover_stranded_term", result: "conflict" };
    }
    if (request.replayOnly === true) return { kind: "recover_stranded_term", result: "not_found" };
    const recoveredTarget = sqlSelect<{ action_id: string }>(
      storage,
      `SELECT action_id FROM stranded_term_recovery WHERE target_term_id = ${sqlString(request.targetTermId)} LIMIT 1`,
    )[0];
    if (recoveredTarget !== undefined) return { kind: "recover_stranded_term", result: "conflict" };

    const hot = loadHot(storage);
    const terms = loadTerms(storage);
    if (hot.binding_epoch !== request.bindingEpoch || hot.clinic_seq !== request.expectedClinicSeq ||
        hot.awaiting_transfer === 1 || hot.transfer_pending === 1 ||
        hot.transferred_out_to !== null) {
      return { kind: "recover_stranded_term", result: "conflict" };
    }
    const active = terms.find((term) => term.state === "active");
    const grace = terms.find((term) => term.state === "grace");
    if (active !== undefined ||
        (grace === undefined ? hot.active_term_id !== null : hot.active_term_id !== grace.term_id)) {
      return { kind: "recover_stranded_term", result: "conflict" };
    }
    const queued = terms.filter((term) => term.state === "queued")
      .sort((left, right) => left.position - right.position);
    const uniqueOldest = queued.length > 0 &&
      (queued.length === 1 || queued[0]!.position < queued[1]!.position);
    const target = terms.find((term) => term.term_id === request.targetTermId);
    if (active !== undefined || !uniqueOldest || target === undefined ||
        target.state !== "queued" || target.term_id !== queued[0]!.term_id ||
        target.grant_id !== request.sourceGrantId || target.allowance === null || target.allowance <= 0 ||
        target.starts_at !== null || target.calendar_start !== null || target.ends_at !== null ||
        target.ended_at !== null || target.used_final !== null && target.used_final !== 0 ||
        !["month", "day"].includes(target.duration_unit ?? "") ||
        target.duration_count === null || target.duration_count <= 0) {
      return { kind: "recover_stranded_term", result: "conflict" };
    }
    const grant = sqlSelect<{ source_kind: string; kind: string; evidence: string; envelope: string; receipt: string | null; voided_at: string | null }>(
      storage,
      `SELECT source_kind, kind, evidence, envelope, receipt, voided_at FROM grant WHERE grant_id = ${sqlString(request.sourceGrantId)} LIMIT 1`,
    )[0];
    if (grant === undefined || grant.source_kind !== "complimentary" || grant.kind !== "term" ||
        grant.receipt === null || grant.voided_at !== null) {
      return { kind: "recover_stranded_term", result: "conflict" };
    }
    let evidenceSha256: string;
    let originalOrgId: string;
    let originalEnvelope: Record<string, unknown>;
    try {
      const evidence = JSON.parse(grant.evidence) as unknown;
      const envelope = JSON.parse(grant.envelope) as Record<string, unknown>;
      if (typeof envelope !== "object" || envelope === null || Array.isArray(envelope)) {
        return { kind: "recover_stranded_term", result: "conflict" };
      }
      originalEnvelope = envelope;
      evidenceSha256 = await sha256Hex(canonicalize(evidence));
      originalOrgId = typeof envelope.org_id === "string" ? envelope.org_id : "";
    } catch {
      return { kind: "recover_stranded_term", result: "conflict" };
    }
    const originalDuration = originalEnvelope.duration;
    const originalPlan = originalEnvelope.plan;
    let storedPlan: Record<string, unknown>;
    try { storedPlan = JSON.parse(target.plan_snapshot) as Record<string, unknown>; }
    catch { return { kind: "recover_stranded_term", result: "conflict" }; }
    if (evidenceSha256 !== request.evidenceSha256 || originalOrgId !== request.orgId ||
        originalEnvelope.grant_id !== target.grant_id || !isEnvelopeRecord(originalEnvelope.source) ||
        originalEnvelope.source.kind !== "complimentary" || !isEnvelopeRecord(originalDuration) ||
        originalDuration.unit !== target.duration_unit || originalDuration.count !== target.duration_count ||
        originalEnvelope.allowance_credits !== target.allowance || !isEnvelopeRecord(originalPlan) ||
        originalPlan.plan_id !== storedPlan.plan_id || originalPlan.plan_version !== storedPlan.version) {
      return { kind: "recover_stranded_term", result: "conflict" };
    }
    const predecessors = terms.filter((term) => term.position < target.position);
    if (predecessors.some((term) =>
      !["ended", "exhausted", "grace"].includes(term.state) ||
      (term.state !== "grace" && term.used_final === null) ||
      ((term.state === "ended" || term.state === "exhausted") && term.ended_at === null))) {
      return { kind: "recover_stranded_term", result: "conflict" };
    }
    let reservations: unknown;
    try { reservations = JSON.parse(hot.reservations); } catch { reservations = null; }
    if (!Array.isArray(reservations) || reservations.length > 0 ||
        !Number.isSafeInteger(hot.used) || hot.used < 0 ||
        !Number.isSafeInteger(hot.reserved) || hot.reserved !== 0 ||
        !Number.isSafeInteger(hot.grace_base_used) || hot.grace_base_used < 0 ||
        (grace === undefined && (hot.used !== 0 || hot.grace_base_used !== 0)) ||
        (grace !== undefined && (grace.used_final !== null || grace.ended_at !== null ||
          grace.grace_ends_at === null || hot.used < hot.grace_base_used))) {
      return { kind: "recover_stranded_term", result: "conflict" };
    }

    const recoveryAt = request.nowIso;
    const oldUsed = hot.used;
    let termsBeforeActivation = terms.map((term) => ({ ...term }));
    let eventHot = { ...hot };
    const eventPayloads: Record<string, unknown>[] = [];
    let seq = hot.clinic_seq;
    const appendEvent = (kind: string, snapshotTerms: TermRow[], snapshotHot: HotRow): void => {
      seq += 1;
      const eventHotAfter = { ...snapshotHot, clinic_seq: seq };
      const snapshot = buildCoverageSnapshot({
        vendorContractVersion: request.vendorContractVersion,
        orgId: request.orgId,
        hot: eventHotAfter,
        terms: snapshotTerms,
        durationScale: request.durationScale,
      });
      snapshot.clinic_seq = seq;
      eventPayloads.push({
        event_id: coverageEventId(request.installationId, seq),
        org_id: request.orgId,
        installation_id: request.installationId,
        binding_epoch: request.bindingEpoch,
        clinic_seq: seq,
        kind,
        at: recoveryAt,
        snapshot,
      });
    };
    if (grace !== undefined) {
      termsBeforeActivation = termsBeforeActivation.map((term) => term.term_id === grace.term_id
        ? { ...term, state: "ended", end_reason: "renewed", ended_at: recoveryAt, used_final: oldUsed }
        : term);
      eventHot = { ...eventHot, active_term_id: null, grace_base_used: 0 };
      appendEvent("term_ended", termsBeforeActivation, eventHot);
    }
    const endsAt = addDuration(
      recoveryAt,
      target.duration_unit as "month" | "day",
      target.duration_count,
      request.durationScale,
    );
    const activatedTerms = termsBeforeActivation.map((term) => term.term_id === target.term_id
      ? { ...term, state: "active", starts_at: recoveryAt, calendar_start: recoveryAt, ends_at: endsAt }
      : term);
    const finalHot = { ...eventHot, active_term_id: target.term_id, used: 0, grace_base_used: 0 };
    appendEvent("term_activated", activatedTerms, finalHot);
    const result: RecoverStrandedTermResponse = {
      kind: "recover_stranded_term",
      result: "ok",
      detail: { action_id: request.actionId, term_id: target.term_id, grant_id: target.grant_id, recovered_at: recoveryAt, clinic_seq: seq },
    };
    const recoveryFact = {
      action_id: request.actionId,
      org_id: request.orgId,
      installation_id: request.installationId,
      binding_epoch: request.bindingEpoch,
      target_term_id: target.term_id,
      source_grant_id: request.sourceGrantId,
      expected_clinic_seq: request.expectedClinicSeq,
          reason: request.reason,
      request_sha256: requestSha256,
      evidence_sha256: request.evidenceSha256,
      actor_email: request.actorEmail,
      credential_id: request.credentialId,
      assertion_sha256: request.assertionSha256,
      recovered_at: recoveryAt,
      result_json: canonicalJsonText(result),
    };
    await prearmGrantWakeup(state);
    const transactionResult = storage.transactionSync(() => {
      const currentHot = loadHot(storage);
      if (currentHot.binding_epoch !== request.bindingEpoch || currentHot.clinic_seq !== request.expectedClinicSeq) {
        return { kind: "recover_stranded_term" as const, result: "conflict" as const };
      }
      if (grace !== undefined) {
        sqlExec(storage, `UPDATE term SET state = 'ended', end_reason = 'renewed', ended_at = ${sqlString(recoveryAt)}, used_final = ${oldUsed} WHERE term_id = ${sqlString(grace.term_id)}`);
      }
      sqlExec(storage, `UPDATE term SET state = 'active', starts_at = ${sqlString(recoveryAt)}, calendar_start = ${sqlString(recoveryAt)}, ends_at = ${sqlString(endsAt)} WHERE term_id = ${sqlString(target.term_id)} AND state = 'queued'`);
      updateHot(storage, { ...finalHot, clinic_seq: seq });
      insertOutbox(storage, "stranded_term_recovery", recoveryFact);
      for (const event of eventPayloads) insertOutbox(storage, "coverage_event", event);
      sqlExec(storage, `INSERT INTO stranded_term_recovery (action_id, target_term_id, reason, request_sha256, result_json, recorded_at) VALUES (${sqlString(request.actionId)}, ${sqlString(target.term_id)}, ${sqlString(request.reason)}, ${sqlString(requestSha256)}, ${sqlString(canonicalJsonText(result))}, ${sqlString(recoveryAt)})`);
      return result;
    });
    if (transactionResult.result === "ok") {
      await scheduleCoverageAlarm(state, storage, recoveryAt);
      logger.info("Stranded complimentary term recovered", { installation_id: request.installationId, action_id: request.actionId, term_id: target.term_id });
    }
    return transactionResult;
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
    const argumentsSha256 = await sha256Hex(canonicalize({
      org_id: request.orgId, grant_id: request.grantId, reason: request.reason,
      assertion_sha256: request.assertionSha256, evidence_sha256: request.evidenceSha256,
    }));
    const existing = readHpReplayEntry(storage, replayKey);
    if (existing !== null) {
      await scheduleCoverageAlarm(state, storage, request.nowIso);
      if (existing.operation !== "void_grant" || existing.arguments_sha256 !== argumentsSha256) {
        return { kind: "void_grant", result: "bad_request" };
      }
      return {
        kind: "void_grant",
        result: "already_applied",
        receipt: existing.receipt,
      };
    }
    if (request.replayOnly === true) {
      return { kind: "void_grant", result: "bad_request" };
    }

    const signingKey = await loadPlatformSigningKey(
      request.platformSigningKeyJson,
      request.environment,
    );
    if (signingKey === null) {
      return { kind: "void_grant", result: "bad_request" };
    }

    const terms = loadTerms(storage);
    const term = findTermForGrant(terms, request.grantId);
    if (term === undefined || term.state === "ended" || term.state === "exhausted") {
      return { kind: "void_grant", result: "bad_request" };
    }

    const wasActive = term.state === "active";
    const hotBefore = loadHot(storage);
    const settledUsedFinal =
      hotBefore.active_term_id === term.term_id ? hotBefore.used : (term.used_final ?? 0);
    const termsAfter = terms.map((row) => ({ ...row }));
    const endingTerm = termsAfter.find((row) => row.term_id === term.term_id)!;
    Object.assign(endingTerm, {
      state: "ended",
      end_reason: "voided",
      ended_at: request.nowIso,
      grace_ends_at: null,
      used_final: settledUsedFinal,
    });
    const termWrites = [`UPDATE term SET state = 'ended', end_reason = 'voided', ended_at = ${sqlString(request.nowIso)}, grace_ends_at = NULL, used_final = ${settledUsedFinal} WHERE term_id = ${sqlString(term.term_id)}`];
    const eventKinds = ["term_ended"];
    const eventTerms: TermRow[][] = [termsAfter.map((row) => ({ ...row }))];
    let hotAfter = {
      ...hotBefore,
      active_term_id: hotBefore.active_term_id === term.term_id ? null : hotBefore.active_term_id,
    };
    const eventHots: HotRow[] = [{ ...hotAfter }];
    if (wasActive) {
      const successor = termsAfter
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
        Object.assign(successor, { state: "active", starts_at: request.nowIso, calendar_start: request.nowIso, ends_at: endsAt });
        termWrites.push(`UPDATE term SET state = 'active', starts_at = ${sqlString(request.nowIso)}, calendar_start = ${sqlString(request.nowIso)}, ends_at = ${sqlString(endsAt)} WHERE term_id = ${sqlString(successor.term_id)}`);
        hotAfter = { ...hotAfter, active_term_id: successor.term_id, used: 0 };
        eventKinds.push("term_activated");
        eventTerms.push(termsAfter.map((row) => ({ ...row })));
        eventHots.push({ ...hotAfter });
      }
    }
    eventKinds.push("grant_voided");
    eventTerms.push(termsAfter.map((row) => ({ ...row })));
    eventHots.push({ ...hotAfter });
    const prepared = prepareCoverageEvents({
      installationId: request.installationId, orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion, at: request.nowIso,
      durationScale: request.durationScale, kinds: eventKinds, hotAfter, termsAfter,
      eventHots, eventTerms,
    });
    const grantVoidedSeq = prepared.lastSeq;

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

    const voidPayload = {
      grant_id: request.grantId,
      reason: request.reason,
      source: "operator",
      evidence_sha256: request.evidenceSha256,
      at: request.nowIso,
      receipt,
    };
    const replayEntry = { operation: "void_grant", arguments_sha256: argumentsSha256, receipt };
    await prearmGrantWakeup(state);
    const transactionResult = storage.transactionSync(() => {
      const current = readHpReplayEntry(storage, replayKey);
      if (current !== null) {
        return current.operation === "void_grant" && current.arguments_sha256 === argumentsSha256
          ? { result: "already_applied" as const, receipt: current.receipt }
          : { result: "bad_request" as const };
      }
      for (const statement of termWrites) sqlExec(storage, statement);
      updateHot(storage, prepared.finalHot);
      commitPreparedEvents(storage, prepared.rows);
      insertOutbox(storage, "grant_void", voidPayload);
      writeHpReplayEntry(storage, replayKey, replayEntry);
      return { result: "applied" as const, receipt };
    });
    await scheduleCoverageAlarm(state, storage, request.nowIso);

    logger.info("void_grant completed", {
      installation_id: request.installationId,
      grant_id: request.grantId,
    });

    return { kind: "void_grant", ...transactionResult };
  });
}

export type MirrorTermView = {
  ref: string;
  capabilities: string[];
  max_cost_class: "economy" | "standard" | "premium";
};

/** `coverage_mirror.term_snapshot` may be the full coverage snapshot or legacy term-only JSON. */
export function mirrorTermViewFromSnapshot(
  termSnapshotJson: string,
): MirrorTermView | null {
  try {
    const parsed = JSON.parse(termSnapshotJson) as Record<string, unknown>;
    const planSnapshotObject = (value: unknown): Record<string, unknown> | undefined => {
      if (value !== null && typeof value === "object" && !Array.isArray(value)) {
        return value as Record<string, unknown>;
      }
      if (typeof value === "string") {
        try {
          const decoded = JSON.parse(value) as unknown;
          if (
            decoded !== null &&
            typeof decoded === "object" &&
            !Array.isArray(decoded)
          ) {
            return decoded as Record<string, unknown>;
          }
        } catch {
          return undefined;
        }
      }
      return undefined;
    };
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
    const snapshotRaw = planSnapshotObject(termRaw.plan_snapshot);
    const planSnapshot =
      termRaw.max_cost_class !== undefined
        ? termRaw
        : snapshotRaw ?? (() => {
            const terms = Array.isArray(parsed.terms) ? parsed.terms : [];
            const matching = terms.find((entry) =>
              entry !== null &&
              typeof entry === "object" &&
              !Array.isArray(entry) &&
              ((entry as Record<string, unknown>).term_id === ref ||
                (entry as Record<string, unknown>).ref === ref),
            );
            if (
              matching !== null &&
              typeof matching === "object" &&
              !Array.isArray(matching)
            ) {
              const row = matching as Record<string, unknown>;
              return planSnapshotObject(row.plan_snapshot);
            }
            return undefined;
          })();
    const rawCostClass = planSnapshot?.max_cost_class;
    const maxCostClass =
      rawCostClass === "standard" || rawCostClass === "premium"
        ? rawCostClass
        : "economy";
    if (!ref || capabilities.length === 0) {
      return null;
    }
    return { ref, capabilities, max_cost_class: maxCostClass };
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

function canonicalValuesEqual(left: unknown, right: unknown): boolean {
  const leftBytes = canonicalize(left);
  const rightBytes = canonicalize(right);
  return leftBytes.length === rightBytes.length && leftBytes.every(
    (byte, index) => byte === rightBytes[index],
  );
}

async function persistGrantRecoveryCapsule(
  db: D1Database,
  r2: R2Bucket,
  storage: DurableObjectStorage,
  ledger: Record<string, unknown>,
): Promise<void> {
  const grantId = String(ledger.grant_id ?? "");
  if (ledger.source_kind === "transfer") {
    const transferId = typeof ledger.transfer_id === "string" ? ledger.transfer_id : "";
    if (transferId.length === 0) throw new Error(`transfer_recovery_evidence_missing:${grantId}`);
    const localGrant = sqlSelect<{
      envelope: string; evidence: string; receipt: string | null;
    }>(storage,
      `SELECT envelope, evidence, receipt FROM grant WHERE grant_id = ${sqlString(grantId)} LIMIT 1`,
    )[0];
    if (localGrant === undefined || localGrant.receipt === null) {
      throw new Error(`transfer_recovery_grant_missing:${grantId}`);
    }
    const transfer = await db.prepare(
      `SELECT transfer_id, org_id, from_installation_id, to_installation_id, package, created_at
       FROM transfer WHERE transfer_id = ?`,
    ).bind(transferId).first<{
      transfer_id: string; org_id: string; from_installation_id: string;
      to_installation_id: string; package: string | null; created_at: string;
    }>();
    if (transfer === null || transfer.package === null || transfer.org_id !== ledger.org_id ||
        transfer.to_installation_id !== ledger.installation_id) {
      throw new Error(`transfer_recovery_transfer_conflict:${grantId}`);
    }
    const preparation = await db.prepare(
      `SELECT org_id, from_installation_id, source_epoch, to_installation_id,
              destination_epoch, phase
       FROM transfer_preparation WHERE transfer_id = ?`,
    ).bind(transferId).first<{
      org_id: string; from_installation_id: string; source_epoch: number;
      to_installation_id: string; destination_epoch: number; phase: string;
    }>();
    if (preparation === null || preparation.phase !== "completed" ||
        preparation.org_id !== transfer.org_id ||
        preparation.from_installation_id !== transfer.from_installation_id ||
        preparation.to_installation_id !== transfer.to_installation_id) {
      throw new Error(`transfer_recovery_preparation_conflict:${grantId}`);
    }
    const transferSteps = await db.prepare(
      `SELECT step, receipt, applied_at FROM transfer_step WHERE transfer_id = ? ORDER BY step ASC`,
    ).bind(transferId).all<{ step: string; receipt: string; applied_at: string }>();
    const transferStepRows = transferSteps.results ?? [];
    const sourceStep = transferStepRows.find((step) => step.step === "transfer_out");
    const destinationStep = transferStepRows.find((step) => step.step === "transfer_in");
    const replay = sqlSelect<{ request_sha256: string; response_json: string }>(storage,
      `SELECT request_sha256, response_json FROM transfer_replay
       WHERE transfer_id = ${sqlString(transferId)} AND step = 'transfer_in' LIMIT 2`,
    );
    if (transferStepRows.length !== 2 || sourceStep === undefined || destinationStep === undefined || replay.length !== 1 ||
        !/^[a-f0-9]{64}$/u.test(replay[0]!.request_sha256)) {
      throw new Error(`transfer_recovery_evidence_missing:${grantId}`);
    }
    let packageTerms: unknown;
    let envelope: unknown;
    let localEvidence: unknown;
    let importedReceipt: unknown;
    let sourceReceipt: unknown;
    let destinationReceipt: unknown;
    let response: Record<string, unknown>;
    try {
      packageTerms = JSON.parse(transfer.package);
      envelope = JSON.parse(localGrant.envelope);
      localEvidence = JSON.parse(localGrant.evidence);
      importedReceipt = JSON.parse(localGrant.receipt);
      sourceReceipt = JSON.parse(sourceStep.receipt);
      destinationReceipt = JSON.parse(destinationStep.receipt);
      response = JSON.parse(replay[0]!.response_json) as Record<string, unknown>;
    } catch {
      throw new Error(`transfer_recovery_evidence_invalid:${grantId}`);
    }
    if (!Array.isArray(packageTerms) || !isEnvelopeRecord(envelope) || !isEnvelopeRecord(localEvidence) ||
        localEvidence.transfer_id !== transferId || localEvidence.step !== "transfer_in" ||
        replay[0]!.request_sha256 !== await sha256Hex(canonicalize({
          installation_id: transfer.to_installation_id,
          org_id: transfer.org_id,
          binding_epoch: preparation.destination_epoch,
          package: packageTerms,
        })) ||
        !canonicalValuesEqual(response.receipt, destinationReceipt) ||
        !isEnvelopeRecord(sourceReceipt) || !isEnvelopeRecord(destinationReceipt) ||
        response.kind !== "transfer_in" || response.result !== "applied" ||
        sourceReceipt.transfer_id !== transferId || sourceReceipt.installation_id !== transfer.from_installation_id ||
        sourceReceipt.org_id !== transfer.org_id || sourceReceipt.result !== "applied" ||
        sourceReceipt.applied_at !== sourceStep.applied_at ||
        destinationReceipt.transfer_id !== transferId || destinationReceipt.installation_id !== transfer.to_installation_id ||
        destinationReceipt.org_id !== transfer.org_id || destinationReceipt.result !== "applied" ||
        destinationReceipt.applied_at !== destinationStep.applied_at ||
        typeof sourceReceipt.signature !== "string" || typeof destinationReceipt.signature !== "string" ||
        typeof sourceReceipt.kid !== "string" || destinationReceipt.kid !== sourceReceipt.kid ||
        sourceReceipt.envelope_sha256 !== await sha256Hex(canonicalize(packageTerms)) ||
        destinationReceipt.envelope_sha256 !== sourceReceipt.envelope_sha256) {
      throw new Error(`transfer_recovery_evidence_conflict:${grantId}`);
    }
    const packageIndex = await (async () => {
      for (let index = 0; index < packageTerms.length; index += 1) {
        if (await transferGrantId(transferId, index) === grantId) return index;
      }
      return -1;
    })();
    if (packageIndex < 0 || !canonicalValuesEqual(envelope, packageTerms[packageIndex]) ||
        !canonicalValuesEqual(importedReceipt, ledger.receipt) ||
        !isEnvelopeRecord(importedReceipt) || importedReceipt.grant_id !== grantId ||
        importedReceipt.org_id !== ledger.org_id || importedReceipt.installation_id !== ledger.installation_id ||
        importedReceipt.envelope_sha256 !== ledger.envelope_sha256 || importedReceipt.applied_at !== ledger.applied_at ||
        await grantEnvelopeHash(envelope) !== ledger.envelope_sha256 ||
        !Array.isArray(response.term_ids) || response.term_ids.length !== packageTerms.length ||
        !Array.isArray(sourceReceipt.term_ids) || sourceReceipt.term_ids.length !== packageTerms.length ||
        !Array.isArray(destinationReceipt.term_ids) ||
        !canonicalValuesEqual(response.term_ids, destinationReceipt.term_ids) ||
        destinationReceipt.term_ids.length !== packageTerms.length) {
      throw new Error(`transfer_recovery_package_conflict:${grantId}`);
    }
    const transferEvidence = {
      transfer_id: transferId,
      step: "transfer_in",
      request_sha256: replay[0]!.request_sha256,
      response_json: replay[0]!.response_json,
      receipt_text: destinationStep.receipt,
      applied_at: destinationStep.applied_at,
      transfer: {
        org_id: transfer.org_id,
        from_installation_id: transfer.from_installation_id,
        to_installation_id: transfer.to_installation_id,
        package: transfer.package,
        created_at: transfer.created_at,
      },
      source_step: { receipt_text: sourceStep.receipt, applied_at: sourceStep.applied_at },
    };
    const capsule = {
      version: 1,
      grant_id: grantId,
      org_id: ledger.org_id,
      installation_id: ledger.installation_id,
      binding_epoch: null,
      route_generation: null,
      source_kind: "transfer",
      envelope,
      envelope_sha256: ledger.envelope_sha256,
      evidence: localEvidence,
      receipt: importedReceipt,
      accepted_command: null,
      accepted_actor: null,
      signer_credential_id: null,
      assertion_sha256: null,
      override_assertion_sha256: null,
      accepted_contract_version: null,
      accepted_ceiling_policy_version: null,
      plan_snapshot: null,
      accepted_at: null,
      created_at: null,
      completed_at: null,
      ceiling_claim: null,
      transfer_evidence: transferEvidence,
    };
    const key = `grant-ledger/${grantId}.recovery-v1.ndjson`;
    const line = `${new TextDecoder().decode(canonicalize(capsule))}\n`;
    const existing = await r2.get(key);
    if (existing !== null) {
      if (await existing.text() !== line) throw new Error(`grant_recovery_capsule_conflict:${grantId}`);
      return;
    }
    await r2.put(key, line);
    return;
  }
  const claim = await db.prepare(
    `SELECT grant_id, org_id, source_kind, envelope, envelope_sha256,
            installation_id, binding_epoch, route_generation, state, receipt,
            accepted_command, accepted_actor, signer_credential_id,
            assertion_sha256, override_assertion_sha256,
            accepted_contract_version, accepted_ceiling_policy_version,
            plan_snapshot, accepted_at, command_state, created_at, completed_at
     FROM grant_claim WHERE grant_id = ?`,
  ).bind(grantId).first<Record<string, unknown>>();
  if (
    claim === null || claim.state !== "completed" ||
    claim.org_id !== ledger.org_id || claim.installation_id !== ledger.installation_id ||
    claim.source_kind !== ledger.source_kind || claim.envelope_sha256 !== ledger.envelope_sha256 ||
    claim.receipt === null ||
    !canonicalValuesEqual(JSON.parse(String(claim.receipt)), ledger.receipt) ||
    !canonicalValuesEqual(
      JSON.parse(String(claim.envelope)),
      (ledger.recovery_capsule as Record<string, unknown>).envelope,
    )
  ) {
    throw new Error(`grant_recovery_claim_conflict:${grantId}`);
  }
  if (claim.source_kind === "complimentary" && (
    typeof claim.accepted_command !== "string" || claim.command_state !== "completed"
  )) {
    throw new Error(`grant_recovery_command_missing:${grantId}`);
  }
  const ceiling = await db.prepare(
    `SELECT grant_id, org_id, envelope_sha256, plan_id, plan_version,
            allowance_denominator, day_contribution, allowance_contribution,
            apply_per_grant_caps, source_reconciled, override_authorized,
            status, receipt, applied_at, created_at
     FROM complimentary_ceiling_claim WHERE grant_id = ?`,
  ).bind(grantId).first<Record<string, unknown>>();
  if (claim.source_kind === "complimentary" && (
    ceiling === null || ceiling.status !== "applied" ||
    ceiling.envelope_sha256 !== claim.envelope_sha256 ||
    ceiling.org_id !== claim.org_id || ceiling.receipt === null ||
    !canonicalValuesEqual(JSON.parse(String(ceiling.receipt)), ledger.receipt)
  )) {
    throw new Error(`grant_recovery_ceiling_conflict:${grantId}`);
  }
  const capsule = {
    version: 1,
    grant_id: grantId,
    org_id: claim.org_id,
    installation_id: claim.installation_id,
    binding_epoch: claim.binding_epoch,
    route_generation: claim.route_generation,
    source_kind: claim.source_kind,
    envelope: JSON.parse(String(claim.envelope)),
    envelope_sha256: claim.envelope_sha256,
    evidence: (ledger.recovery_capsule as Record<string, unknown>).evidence,
    receipt: JSON.parse(String(claim.receipt)),
    accepted_command: claim.accepted_command,
    accepted_actor: claim.accepted_actor,
    signer_credential_id: claim.signer_credential_id,
    assertion_sha256: claim.assertion_sha256,
    override_assertion_sha256: claim.override_assertion_sha256,
    accepted_contract_version: claim.accepted_contract_version,
    accepted_ceiling_policy_version: claim.accepted_ceiling_policy_version,
    plan_snapshot: claim.plan_snapshot,
    accepted_at: claim.accepted_at,
    created_at: claim.created_at,
    completed_at: claim.completed_at,
    ceiling_claim: ceiling,
  };
  if (capsule.evidence === null || capsule.evidence === undefined) {
    throw new Error(`grant_recovery_evidence_missing:${grantId}`);
  }
  const key = `grant-ledger/${grantId}.recovery-v1.ndjson`;
  const line = `${new TextDecoder().decode(canonicalize(capsule))}\n`;
  const existing = await r2.get(key);
  if (existing !== null) {
    if (await existing.text() !== line) {
      throw new Error(`grant_recovery_capsule_conflict:${grantId}`);
    }
    return;
  }
  await r2.put(key, line);
}

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
            operator_credential_id, operator_email, envelope_sha256, receipt, applied_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        )
          .bind(
            payload.grant_id,
            payload.origin_grant_id,
            payload.org_id,
            payload.installation_id,
            payload.kind,
            payload.source_kind,
            payload.operator_credential_id,
            payload.operator_email ?? null,
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
            operator_email: payload.operator_email ?? null,
            envelope_sha256: payload.envelope_sha256,
            applied_at: payload.applied_at,
            receipt: payload.receipt,
          });
          await env.R2.put(key, `${line}\n`);
        }
        await persistGrantRecoveryCapsule(env.DB, env.R2, storage, payload);
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
      } else if (row.kind === "stranded_term_recovery") {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO stranded_term_recovery (
            action_id, org_id, installation_id, binding_epoch, target_term_id,
            source_grant_id, expected_clinic_seq, reason, request_sha256, evidence_sha256,
            actor_email, credential_id, assertion_sha256, recovered_at, result_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).bind(
          payload.action_id,
          payload.org_id,
          payload.installation_id,
          payload.binding_epoch,
          payload.target_term_id,
          payload.source_grant_id,
          payload.expected_clinic_seq,
          payload.reason,
          payload.request_sha256,
          payload.evidence_sha256,
          payload.actor_email,
          payload.credential_id,
          payload.assertion_sha256,
          payload.recovered_at,
          payload.result_json,
        ).run();
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
      } else if (row.kind === "paid_velocity_observation") {
        const globalPaidLastHour = await countD1PaidGrantsLastHour(
          env.DB,
          String(payload.now_iso),
        );
        if (globalPaidLastHour > 20) {
          shippedAlerts.push({
            alert_key: "AL-17:global",
            code: "AL-17",
            body: { code: "AL-17" },
          });
        }
      }

      sqlExec(storage, `DELETE FROM outbox WHERE seq = ${row.seq}`);
    }

    const terms = loadTerms(storage);
    const outboxCount = sqlSelect<{ count: number }>(
      storage,
      "SELECT COUNT(*) AS count FROM outbox",
    )[0]?.count ?? 0;
    const nextAlarm = computeNextAlarmAt(terms, outboxCount > 0, nowIso);
    updateHot(storage, { next_alarm_at: nextAlarm });
    await syncAlarm(state, storage, nextAlarm);

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
  return blockConcurrencyWhile(async () => {
    const recovery = sqlSelect<{ status: string }>(
      storage,
      "SELECT status FROM recovery_state WHERE singleton = 1 LIMIT 1",
    )[0];
    if (recovery?.status === "building" || recovery?.status === "blocked") {
      await state.storage.setAlarm(Date.now() + 60_000);
      return [];
    }
    try {
      return await shipCoverageOutboxInLock(
        state,
        storage,
        env,
        installationId,
        nowIso,
        logger,
        durationScale,
      );
    } catch (error) {
      // Alarm delivery is at-least-once. Preserve the pending row and restore
      // a durable wake-up if a downstream write or D1 observation fails.
      const detail = error instanceof Error ? error.message : "coverage_outbox_ship_failed";
      logger.error("Coverage outbox evidence could not be shipped; retry scheduled", {
        installation_id: installationId,
        reason: detail,
      });
      await scheduleOutboxAlarmIfPending(state, storage, nowIso);
      throw error;
    }
  });
}

export interface OpenAwaitingTransferRequest {
  kind: "open_awaiting_transfer";
  transferId: string;
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
    const hot = loadHot(storage);
    if (hot.binding_epoch !== request.bindingEpoch) {
      return { kind: "open_awaiting_transfer", result: "bad_request" };
    }
    if (hot.awaiting_transfer === 1) {
      return hot.awaiting_transfer_id === request.transferId
        ? { kind: "open_awaiting_transfer", result: "ok" }
        : { kind: "open_awaiting_transfer", result: "bad_request" };
    }
    if (loadTerms(storage).length !== 0 || sqlSelect<{ count: number }>(storage,
      "SELECT COUNT(*) AS count FROM grant",
    )[0]?.count !== 0) {
      return { kind: "open_awaiting_transfer", result: "bad_request" };
    }
    updateHot(storage, {
      awaiting_transfer: 1,
      awaiting_transfer_id: request.transferId,
    });
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

function isNonNegativeFiniteInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

export function transferPackageAccountingIsValid(pkg: TransferPackageTerm): boolean {
  if (pkg.state === "active") {
    if (!isNonNegativeFiniteInteger(pkg.allowance)) return false;
    // Legacy packages only carried the remaining allowance. Keep supporting
    // that representation, but never accept malformed numeric value.
    if (pkg.plan_allowance === undefined || pkg.plan_allowance === null) return true;
    return isNonNegativeFiniteInteger(pkg.plan_allowance) &&
      pkg.allowance <= pkg.plan_allowance;
  }
  if (pkg.state !== "grace") return true;
  if (
    pkg.plan_allowance === undefined || pkg.plan_allowance === null ||
    !isNonNegativeFiniteInteger(pkg.plan_allowance) ||
    !isNonNegativeFiniteInteger(pkg.allowance) ||
    !isNonNegativeFiniteInteger(pkg.hot_grace_base_used) ||
    !isNonNegativeFiniteInteger(pkg.hot_used) ||
    pkg.hot_grace_base_used > pkg.hot_used ||
    pkg.hot_grace_base_used > pkg.plan_allowance
  ) return false;
  let graceBudget: number;
  try {
    const term = {
      allowance: pkg.plan_allowance,
      duration_unit: pkg.duration_unit,
      duration_count: pkg.duration_count,
      grace_days: pkg.grace_days,
      grace_cap: pkg.grace_cap,
      calendar_start: pkg.calendar_start,
      starts_at: pkg.starts_at,
      ends_at: pkg.ends_at,
      grace_ends_at: pkg.grace_ends_at,
    } as TermRow;
    graceBudget = computeGraceAllowance(term, pkg.hot_grace_base_used);
  } catch {
    return false;
  }
  const expectedRemaining = Math.max(0, graceBudget - (pkg.hot_used - pkg.hot_grace_base_used));
  return expectedRemaining === pkg.allowance;
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
  platformSigningKeyJson?: string;
  environment?: string;
  durationScale?: DurationScale;
  nowIso: string;
  db: D1Database;
}

export interface TransferOutResponse {
  kind: "transfer_out";
  result: "applied" | "bad_request" | "transient";
  detail?: string;
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
    const requestSha256 = await sha256Hex(canonicalize({
      installation_id: request.installationId,
      org_id: request.orgId,
      binding_epoch: request.bindingEpoch,
      to_installation_id: request.toInstallationId,
    }));
    const stored = sqlSelect<{ request_sha256: string; response_json: string }>(
      storage,
      `SELECT request_sha256, response_json FROM transfer_replay
       WHERE transfer_id = ${sqlString(request.transferId)} AND step = 'transfer_out' LIMIT 1`,
    )[0];
    if (stored !== undefined) {
      if (stored.request_sha256 !== requestSha256) {
        return { kind: "transfer_out", result: "bad_request" };
      }
      try {
        const replay = JSON.parse(stored.response_json) as TransferOutResponse;
        return replay.result === "applied"
          ? { ...replay, result: "already_applied" }
          : replay;
      } catch {
        return { kind: "transfer_out", result: "bad_request" };
      }
    }
    const signingKey = await loadPlatformSigningKey(
      request.platformSigningKeyJson,
      request.environment,
    );
    if (signingKey === null) {
      return { kind: "transfer_out", result: "bad_request" };
    }

    const hot = loadHot(storage);
    if (hot.binding_epoch !== request.bindingEpoch || hot.transfer_pending !== 1 ||
        hot.transfer_pending_id !== request.transferId) {
      return { kind: "transfer_out", result: "bad_request" };
    }
    let reservations: unknown[];
    try {
      reservations = JSON.parse(hot.reservations) as unknown[];
    } catch {
      return { kind: "transfer_out", result: "transient", detail: "reservation_state_unknown" };
    }
    if (hot.reserved > 0 || reservations.length > 0) {
      return { kind: "transfer_out", result: "transient", detail: "reservations_pending" };
    }
    const terms = loadTerms(storage);
    const notEnded = terms.filter(
      (term) =>
        term.state === "active" ||
        term.state === "grace" ||
        term.state === "queued" ||
        term.state === "held",
    );
    const routeRows = await request.db.prepare(
      `SELECT grant_id, generation, state, transfer_id FROM live_value_route
       WHERE org_id = ? AND installation_id = ? AND state IN ('stable', 'moving')`,
    ).bind(request.orgId, request.installationId).all<{
      grant_id: string; generation: number; state: string; transfer_id: string | null;
    }>();
    const routes = new Map((routeRows.results ?? []).map((row) => [row.grant_id, row]));
    if (notEnded.some((term) => {
      const route = routes.get(term.origin_grant_id);
      return route === undefined || route.state !== "moving" || route.transfer_id !== request.transferId;
    })) {
      return { kind: "transfer_out", result: "bad_request" };
    }
    const packageTerms = notEnded.map((term) =>
      buildTransferPackageTerm(term, hot),
    );
    const endedTermIds = notEnded.map((term) => term.term_id);
    const termsAfter = terms.map((term) => notEnded.some((row) => row.term_id === term.term_id)
      ? { ...term, state: "ended", end_reason: "transferred", ended_at: request.nowIso }
      : term);
    const hotAfter = { ...hot, transferred_out_to: request.toInstallationId, active_term_id: null };
    const prepared = prepareCoverageEvents({
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      at: request.nowIso,
      durationScale: request.durationScale,
      kinds: ["transfer"],
      hotAfter,
      termsAfter,
    });
    const ledgerSeq = prepared.lastSeq;
    const envelopeSha256 = await sha256Hex(canonicalize(packageTerms));
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
    const response: TransferOutResponse = {
      kind: "transfer_out",
      result: "applied",
      package: packageTerms,
      term_ids: endedTermIds,
      ledger_seq: ledgerSeq,
      receipt,
    };
    await prearmGrantWakeup(state);
    storage.transactionSync(() => {
      for (const term of notEnded) {
        sqlExec(storage,
          `UPDATE term SET state = 'ended', end_reason = 'transferred', ended_at = ${sqlString(request.nowIso)}
           WHERE term_id = ${sqlString(term.term_id)} AND state IN ('active', 'grace', 'queued', 'held')`,
        );
      }
      updateHot(storage, prepared.finalHot);
      commitPreparedEvents(storage, prepared.rows);
      sqlExec(storage,
        `INSERT INTO transfer_replay (transfer_id, step, request_sha256, response_json, created_at)
         VALUES (${sqlString(request.transferId)}, 'transfer_out', ${sqlString(requestSha256)},
           ${sqlString(JSON.stringify(response))}, ${sqlString(request.nowIso)})`,
      );
    });
    await scheduleCoverageAlarm(state, storage, request.nowIso);
    return response;
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
  transferId?: string;
  adoptDeletionId?: string;
  emitDeletionSnapshot?: boolean;
  bindingEpoch: number;
  installationId?: string;
  orgId?: string;
  vendorContractVersion?: number;
  nowIso?: string;
  durationScale?: DurationScale;
}

export interface SetTransferPendingResponse {
  kind: "set_transfer_pending";
  result: "ok" | "bad_request";
  terms?: Array<{ term_id: string; state: string }>;
  reservations?: unknown[];
}

export async function setTransferPendingRPC(
  state: DurableObjectState,
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: SetTransferPendingRequest,
): Promise<SetTransferPendingResponse> {
  return blockConcurrencyWhile(async () => {
    const emitsDeletionSnapshot = request.emitDeletionSnapshot === true;
    if (emitsDeletionSnapshot && (
      typeof request.installationId !== "string" || typeof request.orgId !== "string" ||
      !Number.isInteger(request.vendorContractVersion) || typeof request.nowIso !== "string"
    )) return { kind: "set_transfer_pending", result: "bad_request" };
    ensureHotRow(storage, request.bindingEpoch);
    let hot = loadHot(storage);
    if (hot.binding_epoch !== request.bindingEpoch || hot.transferred_out_to != null) {
      return { kind: "set_transfer_pending", result: "bad_request" };
    }
    const transitioned = hot.transfer_pending !== 1;
    if (hot.transfer_pending === 1) {
      if (request.transferId !== undefined && hot.transfer_pending_id !== request.transferId) {
        if (
          hot.transfer_pending_id !== null &&
          request.adoptDeletionId !== hot.transfer_pending_id
        ) {
          return { kind: "set_transfer_pending", result: "bad_request" };
        }
      }
      if (
        request.transferId === undefined || hot.transfer_pending_id === request.transferId
      ) {
        const terms = loadTerms(storage);
        const reservations = JSON.parse(hot.reservations) as unknown;
        if (!Array.isArray(reservations)) {
          return { kind: "set_transfer_pending", result: "bad_request" };
        }
        if (emitsDeletionSnapshot) {
          await scheduleOutboxAlarmIfPending(state, storage, request.nowIso!);
        }
        return {
          kind: "set_transfer_pending", result: "ok",
          ...(emitsDeletionSnapshot ? {
            terms: terms.map((term) => ({ term_id: term.term_id, state: term.state })),
            reservations,
          } : {}),
        };
      }
    }
    const reservations = JSON.parse(hot.reservations) as unknown;
    if (!Array.isArray(reservations)) {
      return { kind: "set_transfer_pending", result: "bad_request" };
    }
    let terms: TermRow[] = [];
    storage.transactionSync(() => {
      updateHot(storage, {
        transfer_pending: 1,
        transfer_pending_id: request.transferId ?? hot.transfer_pending_id ?? null,
      });
      hot = loadHot(storage);
      terms = loadTerms(storage);
      if (emitsDeletionSnapshot && transitioned) {
        hot = { ...hot, clinic_seq: hot.clinic_seq + 1 };
        updateHot(storage, { clinic_seq: hot.clinic_seq });
        const snapshot = buildCoverageSnapshot({
          vendorContractVersion: request.vendorContractVersion!,
          orgId: request.orgId!,
          hot,
          terms,
          durationScale: request.durationScale,
        });
        snapshot.clinic_seq = hot.clinic_seq;
        insertOutbox(storage, "coverage_event", {
          event_id: coverageEventId(request.installationId!, hot.clinic_seq),
          org_id: request.orgId!,
          installation_id: request.installationId!,
          binding_epoch: hot.binding_epoch,
          clinic_seq: hot.clinic_seq,
          kind: "transfer",
          at: request.nowIso!,
          snapshot,
        });
      }
    });
    if (emitsDeletionSnapshot && transitioned) {
      await scheduleOutboxAlarmIfPending(state, storage, request.nowIso!);
    }
    return {
      kind: "set_transfer_pending", result: "ok",
      ...(emitsDeletionSnapshot ? {
        terms: terms.map((term) => ({ term_id: term.term_id, state: term.state })),
        reservations,
      } : {}),
    };
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
  platformSigningKeyJson?: string;
  environment?: string;
  durationScale?: DurationScale;
  nowIso: string;
  db: D1Database;
}

export interface TransferInResponse {
  kind: "transfer_in";
  result: "applied" | "already_applied" | "bad_request";
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
    const requestSha256 = await sha256Hex(canonicalize({
      installation_id: request.installationId,
      org_id: request.orgId,
      binding_epoch: request.bindingEpoch,
      package: request.package,
    }));
    const stored = sqlSelect<{ request_sha256: string; response_json: string }>(
      storage,
      `SELECT request_sha256, response_json FROM transfer_replay
       WHERE transfer_id = ${sqlString(request.transferId)} AND step = 'transfer_in' LIMIT 1`,
    )[0];
    if (stored !== undefined) {
      if (stored.request_sha256 !== requestSha256) {
        return { kind: "transfer_in", result: "bad_request" };
      }
      try {
        const replay = JSON.parse(stored.response_json) as TransferInResponse;
        return replay.result === "applied"
          ? { ...replay, result: "already_applied" }
          : replay;
      } catch {
        return { kind: "transfer_in", result: "bad_request" };
      }
    }
    const quarantined = await request.db.prepare(
      `SELECT 1 AS quarantined FROM transfer_route_quarantine
       WHERE transfer_id = ? LIMIT 1`,
    ).bind(request.transferId).first<{ quarantined: number }>();
    if (quarantined !== null) {
      return { kind: "transfer_in", result: "bad_request" };
    }
    const transfer = await request.db.prepare(
      `SELECT org_id, from_installation_id, to_installation_id, package
       FROM transfer WHERE transfer_id = ?`,
    ).bind(request.transferId).first<{
      org_id: string;
      from_installation_id: string;
      to_installation_id: string;
      package: string | null;
    }>();
    const destinationBinding = await request.db.prepare(
      `SELECT installation_id FROM tenant_binding
       WHERE org_id = ? AND installation_id = ? AND epoch = ? AND status = 'active'`,
    ).bind(request.orgId, request.installationId, request.bindingEpoch).first<{
      installation_id: string;
    }>();
    if (
      transfer === null || transfer.org_id !== request.orgId ||
      transfer.to_installation_id !== request.installationId ||
      transfer.package === null || destinationBinding === null
    ) {
      return { kind: "transfer_in", result: "bad_request" };
    }
    let authorizedPackage: unknown;
    try {
      authorizedPackage = JSON.parse(transfer.package) as unknown;
    } catch {
      return { kind: "transfer_in", result: "bad_request" };
    }
    if (
      !Array.isArray(authorizedPackage) ||
      await sha256Hex(canonicalize(authorizedPackage)) !== await sha256Hex(canonicalize(request.package))
    ) {
      return { kind: "transfer_in", result: "bad_request" };
    }

    const originGrantIds = request.package.map((term) => term.origin_grant_id);
    const routeRows = originGrantIds.length === 0
      ? []
      : (await request.db.prepare(
          `SELECT grant_id, org_id, installation_id, binding_epoch, generation, state, transfer_id
           FROM live_value_route WHERE grant_id IN (${originGrantIds.map(() => "?").join(",")})`,
        ).bind(...originGrantIds).all<{
          grant_id: string;
          org_id: string;
          installation_id: string;
          binding_epoch: number;
          generation: number;
          state: string;
          transfer_id: string | null;
        }>()).results ?? [];
    const routeByGrant = new Map(routeRows.map((row) => [row.grant_id, row]));
    const manifestRows = originGrantIds.length === 0
      ? []
      : (await request.db.prepare(
          `SELECT grant_id, source_epoch, source_generation
           FROM transfer_route_manifest
           WHERE transfer_id = ? AND grant_id IN (${originGrantIds.map(() => "?").join(",")})`,
        ).bind(request.transferId, ...originGrantIds).all<{
          grant_id: string;
          source_epoch: number;
          source_generation: number;
        }>()).results ?? [];
    const manifestByGrant = new Map(manifestRows.map((row) => [row.grant_id, row]));
    if (request.package.some((term) => {
      const route = routeByGrant.get(term.origin_grant_id);
      const manifest = manifestByGrant.get(term.origin_grant_id);
      return route === undefined || route.org_id !== transfer.org_id ||
        route.installation_id !== transfer.from_installation_id ||
        route.state !== "moving" || route.transfer_id !== request.transferId ||
        manifest === undefined || route.binding_epoch !== manifest.source_epoch ||
        route.generation !== manifest.source_generation;
    })) {
      return { kind: "transfer_in", result: "bad_request" };
    }
    const signingKey = await loadPlatformSigningKey(
      request.platformSigningKeyJson,
      request.environment,
    );
    if (signingKey === null) {
      return { kind: "transfer_in", result: "bad_request" };
    }

    const createdTermIds: string[] = [];
    const grantWrites: Array<{ grantId: string; envelopeSha256: string; pkg: TransferPackageTerm; receipt: Record<string, unknown> }> = [];
    let activeTermId: string | null = null;
    let hotUsed = 0;
    let hotGraceBaseUsed = 0;
    let hot = loadHot(storage);
    const initialClinicSeq = hot.clinic_seq;
    let stagedTerms = loadTerms(storage).map((row) => ({ ...row }));
    if (stagedTerms.length !== 0 || sqlSelect<{ count: number }>(storage,
      "SELECT COUNT(*) AS count FROM grant",
    )[0]?.count !== 0) {
      return { kind: "transfer_in", result: "bad_request" };
    }

    for (let index = 0; index < request.package.length; index += 1) {
      const pkg = request.package[index]!;
      if (!transferPackageAccountingIsValid(pkg)) {
        return { kind: "transfer_in", result: "bad_request" };
      }
      const termId = generateUlid();
      const grantId = await transferGrantId(request.transferId, index);
      if (sqlSelect<{ count: number }>(storage,
        `SELECT COUNT(*) AS count FROM term WHERE grant_id = ${sqlString(grantId)}`,
      )[0]?.count !== 0) {
        // A deterministic transfer grant with pre-existing term rows but no replay
        // record is historical ambiguity. Leave it untouched for reconciliation.
        return { kind: "transfer_in", result: "bad_request" };
      }
      if (sqlSelect<{ count: number }>(storage,
        `SELECT COUNT(*) AS count FROM grant WHERE grant_id = ${sqlString(grantId)}`,
      )[0]?.count !== 0) {
        return { kind: "transfer_in", result: "bad_request" };
      }
      const planSnapshotJson = JSON.stringify(pkg.plan_snapshot);
      const graceCap =
        pkg.grace_cap === null || pkg.grace_cap === undefined
          ? "proportional"
          : String(pkg.grace_cap);
      const storedAllowance =
        pkg.plan_allowance !== undefined && pkg.plan_allowance !== null
          ? pkg.plan_allowance
          : pkg.allowance;
      const termRow: TermRow = {
        term_id: termId,
        grant_id: grantId,
        origin_grant_id: pkg.origin_grant_id,
        position: pkg.position,
        state: pkg.state,
        end_reason: null,
        plan_snapshot: planSnapshotJson,
        allowance: storedAllowance,
        used_final: null,
        duration_unit: pkg.duration_unit,
        duration_count: pkg.duration_count,
        grace_days: pkg.grace_days,
        grace_cap: graceCap,
        calendar_start: pkg.calendar_start,
        starts_at: pkg.starts_at,
        ends_at: pkg.ends_at,
        grace_ends_at: pkg.grace_ends_at,
        ended_at: null,
      };
      stagedTerms.push(termRow);
      createdTermIds.push(termId);
      if (pkg.state === "active") {
        activeTermId = termId;
        hotUsed = pkg.plan_allowance !== undefined && pkg.plan_allowance !== null
          ? pkg.plan_allowance - pkg.allowance
          : 0;
        hotGraceBaseUsed = 0;
      } else if (pkg.state === "grace") {
        activeTermId = termId;
        hotUsed = pkg.hot_used ?? 0;
        hotGraceBaseUsed = pkg.hot_grace_base_used ?? 0;
      }

      const envelopeSha256 = await sha256Hex(canonicalize(pkg));
      const ledgerSeq = initialClinicSeq + index + 1;

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
      grantWrites.push({ grantId, envelopeSha256, pkg, receipt });
    }

    const hotAfter = {
      ...hot,
      clinic_seq: initialClinicSeq,
      awaiting_transfer: 0,
      active_term_id: activeTermId,
      used: hotUsed,
      grace_base_used: hotGraceBaseUsed,
    };
    const incrementalTerms = request.package.map((_, index) =>
      stagedTerms.slice(0, stagedTerms.length - request.package.length + index + 1),
    );
    const prepared = prepareCoverageEvents({
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      at: request.nowIso,
      durationScale: request.durationScale,
      kinds: [...request.package.map(() => "grant_applied"), "transfer"],
      hotAfter,
      termsAfter: stagedTerms,
      eventTerms: [...incrementalTerms, stagedTerms],
    });

    const envelopeSha256 = await sha256Hex(canonicalize(request.package));

    const receipt = await signTransferReceiptInDo({
      signingKey,
      vendorContractVersion: request.vendorContractVersion,
      transferId: request.transferId,
      installationId: request.installationId,
      orgId: request.orgId,
      termIds: createdTermIds,
      appliedAt: request.nowIso,
      ledgerSeq: prepared.lastSeq,
      envelopeSha256,
    });
    const response: TransferInResponse = {
      kind: "transfer_in",
      result: "applied",
      term_ids: createdTermIds,
      ledger_seq: prepared.lastSeq,
      receipt,
    };
    await prearmGrantWakeup(state);
    storage.transactionSync(() => {
      const importedTerms = createdTermIds.length === 0
        ? []
        : stagedTerms.slice(-createdTermIds.length);
      for (const row of importedTerms) {
        sqlExec(storage,
          `INSERT INTO term (
            term_id, grant_id, origin_grant_id, position, state, end_reason,
            plan_snapshot, allowance, used_final, duration_unit, duration_count,
            grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
          ) VALUES (
            ${sqlString(row.term_id)}, ${sqlString(row.grant_id)}, ${sqlString(row.origin_grant_id)},
            ${row.position}, ${sqlString(row.state)}, NULL, ${sqlString(row.plan_snapshot)},
            ${sqlNullableNumber(row.allowance)}, NULL, ${sqlNullableString(row.duration_unit)},
            ${sqlNullableNumber(row.duration_count)}, ${sqlNullableNumber(row.grace_days)},
            ${sqlString(row.grace_cap ?? "proportional")}, ${sqlNullableString(row.calendar_start)},
            ${sqlNullableString(row.starts_at)}, ${sqlNullableString(row.ends_at)},
            ${sqlNullableString(row.grace_ends_at)}, NULL
          )`,
        );
      }
      for (const row of grantWrites) {
        sqlExec(storage,
          `INSERT INTO grant (
            grant_id, kind, source_kind, envelope_sha256, envelope, evidence, receipt,
            applied_at, voided_at, void_reason
          ) VALUES (${sqlString(row.grantId)}, 'term', 'transfer', ${sqlString(row.envelopeSha256)},
            ${sqlString(JSON.stringify(row.pkg))}, ${sqlString(JSON.stringify({ transfer_id: request.transferId, step: "transfer_in" }))},
            ${sqlString(JSON.stringify(row.receipt))}, ${sqlString(request.nowIso)}, NULL, NULL)`,
        );
        insertOutbox(storage, "grant_ledger", {
          grant_id: row.grantId,
          origin_grant_id: row.pkg.origin_grant_id,
          org_id: request.orgId,
          installation_id: request.installationId,
          kind: "term",
          source_kind: "transfer",
          operator_credential_id: "",
          envelope_sha256: row.envelopeSha256,
          transfer_id: request.transferId,
          receipt: row.receipt,
          applied_at: request.nowIso,
        });
      }
      updateHot(storage, prepared.finalHot);
      commitPreparedEvents(storage, prepared.rows);
      sqlExec(storage,
        `INSERT INTO transfer_replay (transfer_id, step, request_sha256, response_json, created_at)
         VALUES (${sqlString(request.transferId)}, 'transfer_in', ${sqlString(requestSha256)},
           ${sqlString(JSON.stringify(response))}, ${sqlString(request.nowIso)})`,
      );
    });
    await scheduleCoverageAlarm(state, storage, request.nowIso);
    return response;
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

function reapplyUsageEventsAfterSnapshot(
  storage: DurableObjectStorage,
  termIds: string[],
  anchorSnapshot: Record<string, unknown>,
  snapshotAt: string,
  rows: Array<{ request_id: string; term_id: string; quota_weight: number; recorded_at: string }>,
): void {
  if (termIds.length === 0) {
    return;
  }
  const snapshotUsedRemaining = snapshotUsedByTermId(anchorSnapshot);
  const appliedRequestIds = new Set<string>();
  for (const row of rows.filter((entry) => termIds.includes(entry.term_id))) {
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
  operator_credential_id: string;
  operator_email: string | null;
  envelope_sha256: string;
  receipt: string;
  applied_at: string;
};

async function verifyGrantRecoveryCapsule(
  db: D1Database,
  r2: R2Bucket,
  grantId: string,
  ledgerRow: GrantLedgerRebuildRow,
  platformSigningKeyJson?: string,
): Promise<Record<string, unknown>> {
  const key = `grant-ledger/${grantId}.recovery-v1.ndjson`;
  const object = await r2.get(key);
  if (object === null) throw new Error(`grant_recovery_capsule_required:${grantId}`);
  const lines = (await object.text()).trimEnd().split("\n");
  if (lines.length !== 1 || lines[0]!.length === 0) {
    throw new Error(`grant_recovery_capsule_invalid:${grantId}`);
  }
  let capsule: Record<string, unknown>;
  let ledgerReceipt: unknown;
  try {
    const parsed: unknown = JSON.parse(lines[0]!);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("capsule_not_object");
    }
    capsule = parsed as Record<string, unknown>;
    ledgerReceipt = typeof ledgerRow.receipt === "string"
      ? JSON.parse(ledgerRow.receipt)
      : ledgerRow.receipt;
  } catch {
    throw new Error(`grant_recovery_capsule_invalid:${grantId}`);
  }
  const commonFields = [
    "version", "grant_id", "org_id", "installation_id", "binding_epoch",
    "route_generation", "source_kind", "envelope", "envelope_sha256", "evidence",
    "receipt", "accepted_command", "accepted_actor", "signer_credential_id",
    "assertion_sha256", "override_assertion_sha256", "accepted_contract_version",
    "accepted_ceiling_policy_version", "plan_snapshot", "accepted_at", "created_at",
    "completed_at", "ceiling_claim",
  ];
  const expectedFields = [...commonFields, ...(ledgerRow.source_kind === "transfer" ? ["transfer_evidence"] : [])].sort();
  if (JSON.stringify(Object.keys(capsule).sort()) !== JSON.stringify(expectedFields)) {
    throw new Error(`grant_recovery_capsule_schema_conflict:${grantId}`);
  }
  if (!["paid", "complimentary", "transfer"].includes(String(ledgerRow.source_kind))) {
    throw new Error(`grant_recovery_source_kind_invalid:${grantId}`);
  }
  const envelope = capsule.envelope;
  const receipt = capsule.receipt;
  if (
    capsule.version !== 1 || capsule.grant_id !== grantId ||
    capsule.org_id !== ledgerRow.org_id ||
    capsule.installation_id !== ledgerRow.installation_id ||
    capsule.source_kind !== ledgerRow.source_kind ||
    capsule.envelope_sha256 !== ledgerRow.envelope_sha256 ||
    envelope === null || typeof envelope !== "object" || Array.isArray(envelope) ||
    receipt === null || typeof receipt !== "object" || Array.isArray(receipt) ||
    capsule.evidence === null || capsule.evidence === undefined ||
    !canonicalValuesEqual(capsule.receipt, ledgerReceipt) ||
    await grantEnvelopeHash(envelope as Record<string, unknown>) !== ledgerRow.envelope_sha256
  ) {
    throw new Error(`grant_recovery_capsule_link_conflict:${grantId}`);
  }
  const signedReceipt = receipt as Record<string, unknown>;
  if (
    signedReceipt.grant_id !== grantId || signedReceipt.org_id !== ledgerRow.org_id ||
    signedReceipt.installation_id !== ledgerRow.installation_id ||
    signedReceipt.envelope_sha256 !== ledgerRow.envelope_sha256 ||
    signedReceipt.applied_at !== ledgerRow.applied_at
  ) {
    throw new Error(`grant_recovery_receipt_identity_conflict:${grantId}`);
  }
  await verifyPlatformReceiptForRecovery(signedReceipt, platformSigningKeyJson, grantId);
  if (ledgerRow.source_kind === "complimentary" || ledgerRow.source_kind === "paid") {
    if (Object.hasOwn(capsule, "transfer_evidence")) {
      throw new Error(`grant_recovery_capsule_schema_conflict:${grantId}`);
    }
    await verifyClaimRecoveryMetadata(db, grantId, capsule);
  } else if (ledgerRow.source_kind === "transfer") {
    if (capsule.binding_epoch !== null || capsule.route_generation !== null ||
        capsule.accepted_command !== null || capsule.accepted_actor !== null ||
        capsule.signer_credential_id !== null || capsule.assertion_sha256 !== null ||
        capsule.override_assertion_sha256 !== null || capsule.accepted_contract_version !== null ||
        capsule.accepted_ceiling_policy_version !== null || capsule.plan_snapshot !== null ||
        capsule.accepted_at !== null || capsule.created_at !== null || capsule.completed_at !== null ||
        capsule.ceiling_claim !== null) {
      throw new Error(`grant_recovery_transfer_claim_fields_conflict:${grantId}`);
    }
    await verifyTransferRecoveryMetadata(db, grantId, ledgerRow, capsule, platformSigningKeyJson);
  } else {
    throw new Error(`grant_recovery_source_kind_invalid:${grantId}`);
  }
  return capsule;
}

function isRecoveryRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function recoveryNullableString(value: unknown): boolean {
  return value === null || typeof value === "string";
}

async function verifyClaimRecoveryMetadata(
  db: D1Database,
  grantId: string,
  capsule: Record<string, unknown>,
): Promise<void> {
  const envelope = capsule.envelope as Record<string, unknown>;
  const receipt = capsule.receipt as Record<string, unknown>;
  const sourceKind = capsule.source_kind;
  const claimOnlyFields = [
    capsule.accepted_command, capsule.accepted_actor, capsule.signer_credential_id,
    capsule.assertion_sha256, capsule.override_assertion_sha256,
    capsule.accepted_contract_version, capsule.accepted_ceiling_policy_version,
    capsule.plan_snapshot, capsule.accepted_at,
  ];
  if (sourceKind === "paid") {
    if (claimOnlyFields.some((value) => value !== null) || capsule.ceiling_claim !== null ||
        capsule.route_generation !== 1 || !Number.isInteger(capsule.binding_epoch) ||
        (envelope.evidence !== undefined
          ? !canonicalValuesEqual(capsule.evidence, envelope.evidence)
          : !canonicalValuesEqual(capsule.evidence, envelope))) {
      throw new Error(`grant_recovery_paid_metadata_conflict:${grantId}`);
    }
    await verifyRecoveryRouteMetadata(db, grantId, capsule);
    return;
  }
  const acceptedCommandText = capsule.accepted_command;
  if (
    typeof acceptedCommandText !== "string" || typeof capsule.accepted_actor !== "string" ||
    capsule.accepted_actor.length === 0 || typeof capsule.signer_credential_id !== "string" ||
    capsule.signer_credential_id.length === 0 ||
    typeof capsule.assertion_sha256 !== "string" || !/^[a-f0-9]{64}$/u.test(capsule.assertion_sha256) ||
    !recoveryNullableString(capsule.override_assertion_sha256) ||
    (capsule.override_assertion_sha256 !== null && !/^[a-f0-9]{64}$/u.test(String(capsule.override_assertion_sha256))) ||
    !Number.isInteger(capsule.accepted_contract_version) ||
    !Number.isInteger(capsule.accepted_ceiling_policy_version) ||
    !Number.isInteger(capsule.binding_epoch) || (capsule.binding_epoch as number) < 1 ||
    !Number.isInteger(capsule.route_generation) || (capsule.route_generation as number) < 1 ||
    typeof capsule.accepted_at !== "string" || !Number.isFinite(Date.parse(capsule.accepted_at)) ||
    typeof capsule.created_at !== "string" || !Number.isFinite(Date.parse(capsule.created_at)) ||
    typeof capsule.completed_at !== "string" || !Number.isFinite(Date.parse(capsule.completed_at))
  ) {
    throw new Error(`grant_recovery_command_metadata_invalid:${grantId}`);
  }
  let command: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(acceptedCommandText);
    if (!isRecoveryRecord(parsed)) throw new Error("accepted_command_not_object");
    command = parsed;
  } catch {
    throw new Error(`grant_recovery_command_invalid:${grantId}`);
  }
  if (
    JSON.stringify(Object.keys(command).sort()) !== JSON.stringify(["contract_version", "envelope", "operation", "override_operation"].sort()) ||
    command.contract_version !== capsule.accepted_contract_version ||
    !canonicalValuesEqual(command.envelope, envelope) ||
    !isRecoveryRecord(command.operation) ||
    command.override_operation !== null && !isRecoveryRecord(command.override_operation)
  ) {
    throw new Error(`grant_recovery_command_link_conflict:${grantId}`);
  }
  const operation = command.operation as Record<string, unknown>;
  if (
    operation.op !== "grant" || operation.contract_version !== capsule.accepted_contract_version ||
    operation.actor_email !== capsule.accepted_actor || !isRecoveryRecord(operation.params) ||
    !canonicalValuesEqual((operation.params as Record<string, unknown>).envelope, envelope) ||
    await sha256Hex(canonicalize(operation)) !== capsule.assertion_sha256
  ) {
    throw new Error(`grant_recovery_command_provenance_conflict:${grantId}`);
  }
  const used = await db.prepare(
    `SELECT credential_id FROM assertion_used WHERE challenge_sha256 = ?`,
  ).bind(capsule.assertion_sha256).first<{ credential_id: string }>();
  const audit = await db.prepare(
    `SELECT actor, assertion_sha256 FROM control_audit
     WHERE action = 'grant' AND target = ? AND assertion_sha256 = ?
     ORDER BY recorded_at DESC LIMIT 1`,
  ).bind(grantId, capsule.assertion_sha256).first<{ actor: string | null; assertion_sha256: string | null }>();
  if (used?.credential_id !== capsule.signer_credential_id ||
      audit?.actor !== capsule.accepted_actor || audit.assertion_sha256 !== capsule.assertion_sha256) {
    throw new Error(`grant_recovery_command_provenance_missing:${grantId}`);
  }
  if (capsule.override_assertion_sha256 === null) {
    if (command.override_operation !== null || envelope.ceiling_override !== undefined) {
      throw new Error(`grant_recovery_override_link_conflict:${grantId}`);
    }
  } else {
    const override = command.override_operation as Record<string, unknown>;
    const overrideUsed = await db.prepare(
      `SELECT credential_id FROM assertion_used WHERE challenge_sha256 = ?`,
    ).bind(capsule.override_assertion_sha256).first<{ credential_id: string }>();
    const withoutOverride = { ...envelope };
    delete withoutOverride.ceiling_override;
    if (
      !isRecoveryRecord(envelope.ceiling_override) || override.op !== "ceiling_override" ||
      override.contract_version !== capsule.accepted_contract_version ||
      override.actor_email !== capsule.accepted_actor || !isRecoveryRecord(override.params) ||
      !canonicalValuesEqual((override.params as Record<string, unknown>).envelope, withoutOverride) ||
      await sha256Hex(canonicalize(override)) !== capsule.override_assertion_sha256 ||
      overrideUsed?.credential_id !== capsule.signer_credential_id
    ) {
      throw new Error(`grant_recovery_override_provenance_conflict:${grantId}`);
    }
  }
  const plan = envelope.plan;
  const snapshot = typeof capsule.plan_snapshot === "string"
    ? JSON.parse(capsule.plan_snapshot)
    : capsule.plan_snapshot;
  if (
    !isRecoveryRecord(plan) || !isRecoveryRecord(snapshot) ||
    plan.plan_id !== snapshot.plan_id || plan.plan_version !== snapshot.version
  ) {
    throw new Error(`grant_recovery_plan_snapshot_conflict:${grantId}`);
  }
  const ceiling = capsule.ceiling_claim;
  const duration = envelope.duration;
  const ceilingFields = [
    "grant_id", "org_id", "envelope_sha256", "plan_id", "plan_version",
    "allowance_denominator", "day_contribution", "allowance_contribution",
    "apply_per_grant_caps", "source_reconciled", "override_authorized", "status",
    "receipt", "applied_at", "created_at",
  ];
  if (!isRecoveryRecord(ceiling) || !isRecoveryRecord(duration) ||
      JSON.stringify(Object.keys(ceiling).sort()) !== JSON.stringify([...ceilingFields].sort())) {
    throw new Error(`grant_recovery_ceiling_claim_required:${grantId}`);
  }
  const expectedDays = duration.unit === "month" && Number.isInteger(duration.count)
    ? (duration.count as number) * 31
    : duration.unit === "day" && Number.isInteger(duration.count)
      ? duration.count as number
      : null;
  const overrideAuthorized = capsule.override_assertion_sha256 === null ? 0 : 1;
  if (
    ceiling.grant_id !== grantId || ceiling.org_id !== capsule.org_id ||
    ceiling.envelope_sha256 !== capsule.envelope_sha256 ||
    ceiling.plan_id !== plan.plan_id || ceiling.plan_version !== plan.plan_version ||
    !Number.isInteger(ceiling.allowance_denominator) || (ceiling.allowance_denominator as number) < 1 ||
    ceiling.day_contribution !== expectedDays ||
    ceiling.allowance_contribution !== envelope.allowance_credits ||
    (ceiling.apply_per_grant_caps !== 0 && ceiling.apply_per_grant_caps !== 1) ||
    ceiling.source_reconciled !== 1 || ceiling.override_authorized !== overrideAuthorized ||
    ceiling.status !== "applied" || !canonicalValuesEqual(ceiling.receipt, receipt) ||
    ceiling.applied_at !== receipt.applied_at || typeof ceiling.created_at !== "string" ||
    !Number.isFinite(Date.parse(ceiling.created_at))
  ) {
    throw new Error(`grant_recovery_ceiling_claim_conflict:${grantId}`);
  }
  if (envelope.evidence !== undefined
    ? !canonicalValuesEqual(capsule.evidence, envelope.evidence)
    : !canonicalValuesEqual(capsule.evidence, envelope)) {
    throw new Error(`grant_recovery_evidence_conflict:${grantId}`);
  }
  await verifyRecoveryRouteMetadata(db, grantId, capsule);
}

async function verifyRecoveryRouteMetadata(
  db: D1Database,
  grantId: string,
  capsule: Record<string, unknown>,
): Promise<void> {
  const route = await db.prepare(
    `SELECT org_id, installation_id, binding_epoch, generation
     FROM live_value_route WHERE grant_id = ?`,
  ).bind(grantId).first<{
    org_id: string; installation_id: string; binding_epoch: number; generation: number;
  }>();
  if (route === null || route.org_id !== capsule.org_id ||
      route.installation_id !== capsule.installation_id ||
      route.binding_epoch !== capsule.binding_epoch ||
      route.generation !== capsule.route_generation) {
    throw new Error(`grant_recovery_route_provenance_conflict:${grantId}`);
  }
  const claim = await db.prepare(
    `SELECT org_id, installation_id, binding_epoch, route_generation, source_kind,
            envelope_sha256, accepted_command, accepted_actor, signer_credential_id,
            assertion_sha256, override_assertion_sha256, accepted_contract_version,
            accepted_ceiling_policy_version, plan_snapshot, accepted_at, created_at,
            completed_at, receipt
     FROM grant_claim WHERE grant_id = ?`,
  ).bind(grantId).first<Record<string, unknown>>();
  if (claim === null) return;
  const fields = [
    "org_id", "installation_id", "binding_epoch", "route_generation", "source_kind",
    "envelope_sha256", "accepted_command", "accepted_actor", "signer_credential_id",
    "assertion_sha256", "override_assertion_sha256", "accepted_contract_version",
    "accepted_ceiling_policy_version", "accepted_at", "created_at", "completed_at",
  ] as const;
  const planSnapshot = typeof claim.plan_snapshot === "string"
    ? JSON.parse(claim.plan_snapshot)
    : claim.plan_snapshot;
  if (fields.some((field) => claim[field] !== capsule[field]) ||
      !canonicalValuesEqual(typeof claim.receipt === "string" ? JSON.parse(claim.receipt) : claim.receipt, capsule.receipt) ||
      !canonicalValuesEqual(planSnapshot, typeof capsule.plan_snapshot === "string"
        ? JSON.parse(capsule.plan_snapshot)
        : capsule.plan_snapshot)) {
    throw new Error(`grant_recovery_claim_provenance_conflict:${grantId}`);
  }
}

async function verifyTransferRecoveryMetadata(
  db: D1Database,
  grantId: string,
  ledgerRow: GrantLedgerRebuildRow,
  capsule: Record<string, unknown>,
  platformSigningKeyJson: string | undefined,
): Promise<void> {
  const transferEvidence = capsule.transfer_evidence;
  if (!isRecoveryRecord(transferEvidence) ||
      JSON.stringify(Object.keys(transferEvidence).sort()) !== JSON.stringify([
        "applied_at", "receipt_text", "request_sha256", "response_json", "source_step",
        "transfer_id",
        "step", "transfer",
      ].sort())) {
    throw new Error(`grant_recovery_transfer_evidence_required:${grantId}`);
  }
  const transfer = transferEvidence.transfer;
  const sourceStep = transferEvidence.source_step;
  if (!isRecoveryRecord(transfer) || !isRecoveryRecord(sourceStep) ||
      JSON.stringify(Object.keys(transfer).sort()) !== JSON.stringify([
        "created_at", "from_installation_id", "org_id", "package", "to_installation_id",
      ].sort()) ||
      JSON.stringify(Object.keys(sourceStep).sort()) !== JSON.stringify(["applied_at", "receipt_text"].sort()) ||
      transferEvidence.step !== "transfer_in" ||
      typeof transferEvidence.transfer_id !== "string" ||
      typeof transferEvidence.request_sha256 !== "string" || !/^[a-f0-9]{64}$/u.test(transferEvidence.request_sha256) ||
      typeof transferEvidence.response_json !== "string" ||
      typeof transferEvidence.receipt_text !== "string" ||
      typeof transferEvidence.applied_at !== "string" ||
      typeof transfer.package !== "string" ||
      typeof transfer.created_at !== "string" ||
      typeof transfer.org_id !== "string" ||
      typeof transfer.from_installation_id !== "string" ||
      typeof transfer.to_installation_id !== "string" ||
      typeof sourceStep.receipt_text !== "string" || typeof sourceStep.applied_at !== "string") {
    throw new Error(`grant_recovery_transfer_evidence_invalid:${grantId}`);
  }
  let packageTerms: unknown;
  let response: Record<string, unknown>;
  let sourceReceipt: Record<string, unknown>;
  let destinationReceipt: Record<string, unknown>;
  let ledgerReceipt: Record<string, unknown>;
  try {
    packageTerms = JSON.parse(transfer.package);
    response = JSON.parse(transferEvidence.response_json) as Record<string, unknown>;
    sourceReceipt = JSON.parse(sourceStep.receipt_text) as Record<string, unknown>;
    destinationReceipt = JSON.parse(transferEvidence.receipt_text) as Record<string, unknown>;
    ledgerReceipt = typeof ledgerRow.receipt === "string"
      ? JSON.parse(ledgerRow.receipt) as Record<string, unknown>
      : ledgerRow.receipt as unknown as Record<string, unknown>;
  } catch {
    throw new Error(`grant_recovery_transfer_evidence_invalid:${grantId}`);
  }
  if (!Array.isArray(packageTerms) || !isRecoveryRecord(response) ||
      !isRecoveryRecord(sourceReceipt) || !isRecoveryRecord(destinationReceipt) ||
      response.kind !== "transfer_in" || response.result !== "applied" ||
      !canonicalValuesEqual(response.receipt, destinationReceipt) ||
      !Array.isArray(response.term_ids) || !Array.isArray(destinationReceipt.term_ids) ||
      !canonicalValuesEqual(response.term_ids, destinationReceipt.term_ids) ||
      !Array.isArray(sourceReceipt.term_ids) ||
      sourceReceipt.term_ids.length !== packageTerms.length ||
      destinationReceipt.term_ids.length !== packageTerms.length ||
      response.term_ids.length !== packageTerms.length ||
      transferEvidence.transfer_id === "" || transfer.org_id !== ledgerRow.org_id ||
      transfer.to_installation_id !== ledgerRow.installation_id ||
      destinationReceipt.transfer_id !== transferEvidence.transfer_id ||
      sourceReceipt.transfer_id !== transferEvidence.transfer_id ||
      destinationReceipt.org_id !== transfer.org_id || sourceReceipt.org_id !== transfer.org_id ||
      destinationReceipt.installation_id !== transfer.to_installation_id ||
      sourceReceipt.installation_id !== transfer.from_installation_id ||
      destinationReceipt.applied_at !== transferEvidence.applied_at ||
      sourceReceipt.applied_at !== sourceStep.applied_at ||
      destinationReceipt.result !== "applied" || sourceReceipt.result !== "applied" ||
      destinationReceipt.envelope_sha256 !== await sha256Hex(canonicalize(packageTerms)) ||
      sourceReceipt.envelope_sha256 !== destinationReceipt.envelope_sha256 ||
      !canonicalValuesEqual(capsule.evidence, { transfer_id: transferEvidence.transfer_id, step: "transfer_in" })) {
    throw new Error(`grant_recovery_transfer_evidence_conflict:${grantId}`);
  }
  const index = await (async () => {
    for (let i = 0; i < packageTerms.length; i += 1) {
      if (await transferGrantId(String(transferEvidence.transfer_id), i) === grantId) return i;
    }
    return -1;
  })();
  const prepared = await db.prepare(
    `SELECT destination_epoch, phase, org_id, from_installation_id, to_installation_id
     FROM transfer_preparation WHERE transfer_id = ?`,
  ).bind(transferEvidence.transfer_id).first<{
    destination_epoch: number; phase: string; org_id: string;
    from_installation_id: string; to_installation_id: string;
  }>();
  const storedTransfer = await db.prepare(
    `SELECT org_id, from_installation_id, to_installation_id, package, created_at
     FROM transfer WHERE transfer_id = ?`,
  ).bind(transferEvidence.transfer_id).first<{
    org_id: string; from_installation_id: string; to_installation_id: string;
    package: string | null; created_at: string;
  }>();
  const storedSteps = await db.prepare(
    `SELECT step, receipt, applied_at FROM transfer_step WHERE transfer_id = ?`,
  ).bind(transferEvidence.transfer_id).all<{
    step: string; receipt: string; applied_at: string;
  }>();
  const steps = storedSteps.results ?? [];
  const storedSource = steps.find((step) => step.step === "transfer_out");
  const storedDestination = steps.find((step) => step.step === "transfer_in");
  if (index < 0 || prepared === null || prepared.phase !== "completed" ||
      storedTransfer === null || storedTransfer.package === null ||
      steps.length !== 2 || storedSource === undefined || storedDestination === undefined ||
      prepared.org_id !== transfer.org_id ||
      prepared.from_installation_id !== transfer.from_installation_id ||
      prepared.to_installation_id !== transfer.to_installation_id ||
      storedTransfer.org_id !== transfer.org_id ||
      storedTransfer.from_installation_id !== transfer.from_installation_id ||
      storedTransfer.to_installation_id !== transfer.to_installation_id ||
      storedTransfer.package !== transfer.package || storedTransfer.created_at !== transfer.created_at ||
      storedSource.receipt !== sourceStep.receipt_text || storedSource.applied_at !== sourceStep.applied_at ||
      storedDestination.receipt !== transferEvidence.receipt_text ||
      storedDestination.applied_at !== transferEvidence.applied_at ||
      !canonicalValuesEqual(capsule.envelope, packageTerms[index]) ||
      await grantEnvelopeHash(capsule.envelope as Record<string, unknown>) !== ledgerRow.envelope_sha256 ||
      capsule.receipt === null || !canonicalValuesEqual(capsule.receipt, ledgerReceipt) ||
      ledgerReceipt.grant_id !== grantId || ledgerReceipt.org_id !== ledgerRow.org_id ||
      ledgerReceipt.installation_id !== ledgerRow.installation_id ||
      ledgerReceipt.envelope_sha256 !== ledgerRow.envelope_sha256 ||
      ledgerReceipt.applied_at !== ledgerRow.applied_at ||
      !canonicalValuesEqual(response.receipt, destinationReceipt)) {
    throw new Error(`grant_recovery_transfer_evidence_conflict:${grantId}`);
  }
  const expectedRequestHash = await sha256Hex(canonicalize({
    installation_id: transfer.to_installation_id,
    org_id: transfer.org_id,
    binding_epoch: prepared.destination_epoch,
    package: packageTerms,
  }));
  if (expectedRequestHash !== transferEvidence.request_sha256) {
    throw new Error(`grant_recovery_transfer_request_conflict:${grantId}`);
  }
  await verifyPlatformReceiptForRecovery(sourceReceipt, platformSigningKeyJson, grantId);
  await verifyPlatformReceiptForRecovery(destinationReceipt, platformSigningKeyJson, grantId);
}

async function verifyPlatformReceiptForRecovery(
  receipt: Record<string, unknown>,
  platformSigningKeyJson: string | undefined,
  identity: string,
): Promise<void> {
  if (typeof platformSigningKeyJson !== "string") {
    throw new Error(`grant_recovery_signing_key_unavailable:${identity}`);
  }
  let signing: { kid?: unknown; public_key?: unknown };
  try { signing = JSON.parse(platformSigningKeyJson) as typeof signing; }
  catch { throw new Error(`grant_recovery_signing_key_invalid:${identity}`); }
  if (typeof signing.kid !== "string" || receipt.kid !== signing.kid || typeof signing.public_key !== "string") {
    throw new Error(`grant_recovery_signing_key_unknown:${identity}`);
  }
  const base64 = signing.public_key.replace(/-/gu, "+").replace(/_/gu, "/");
  let raw: Uint8Array;
  try { raw = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0)); }
  catch { throw new Error(`grant_recovery_signing_key_invalid:${identity}`); }
  const publicKey = await crypto.subtle.importKey("raw", raw, { name: "Ed25519" }, false, ["verify"]);
  if (!(await verifyReceiptSignature({ receipt, publicKey }))) {
    throw new Error(`grant_recovery_receipt_invalid:${identity}`);
  }
}

function insertDoGrantRowFromLedger(
  storage: DurableObjectStorage,
  row: GrantLedgerRebuildRow,
  capsule: Record<string, unknown>,
): void {
  const existing = sqlSelect<{ grant_id: string }>(
    storage,
    `SELECT grant_id FROM grant WHERE grant_id = ${sqlString(row.grant_id)} LIMIT 1`,
  )[0];
  if (existing !== undefined) {
    return;
  }
  const receipt = capsule.receipt as Record<string, unknown>;
  const envelopeJson = JSON.stringify(capsule.envelope);
  const evidenceJson = JSON.stringify(capsule.evidence);
  sqlExec(
    storage,
    `INSERT INTO grant (
      grant_id, kind, source_kind, envelope_sha256, envelope, evidence, receipt, applied_at, voided_at, void_reason
    ) VALUES (
      ${sqlString(row.grant_id)}, ${sqlString(row.kind)}, ${sqlString(row.source_kind)},
      ${sqlString(row.envelope_sha256)}, ${sqlString(envelopeJson)},
      ${sqlString(evidenceJson)}, ${sqlString(JSON.stringify(receipt))},
      ${sqlString(row.applied_at)}, NULL, NULL
    )`,
  );
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

function applyGrantVoidRowToDo(
  storage: DurableObjectStorage,
  row: { grant_id: string; reason: string; at: string },
): void {
  const grant = sqlSelect<{ grant_id: string }>(
    storage,
    `SELECT grant_id FROM grant WHERE grant_id = ${sqlString(row.grant_id)} LIMIT 1`,
  )[0];
  if (grant === undefined) {
    throw new Error(`grant_void_recovery_grant_missing:${row.grant_id}`);
  }
  sqlExec(
    storage,
    `UPDATE grant SET voided_at = ${sqlString(row.at)}, void_reason = ${sqlString(row.reason)}
     WHERE grant_id = ${sqlString(row.grant_id)}`,
  );
  const terms = loadTerms(storage);
  const term = findTermForGrant(terms, row.grant_id);
  if (term === undefined) {
    return;
  }

  if (term.state === "active" || term.state === "grace") {
    const hot = loadHot(storage);
    const usedFinal = hot.active_term_id === term.term_id ? hot.used : (term.used_final ?? 0);
    sqlExec(
      storage,
      `UPDATE term SET state = 'ended', end_reason = 'reversed', ended_at = ${sqlString(row.at)}, grace_ends_at = NULL, used_final = ${usedFinal}
       WHERE term_id = ${sqlString(term.term_id)}`,
    );
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
  platformSigningKeyJson?: string;
  environment?: string;
  durationScale?: DurationScale;
  db: D1Database;
  r2: R2Bucket;
};

export type RebuildClinicDoResponse = {
  kind: "rebuild_clinic_do";
  result: "ok" | "not_found" | "blocked";
  blocked_reason?: string;
  snapshot?: Record<string, unknown>;
};

export type RunRebuildClinicDoResult =
  | { status: "not_found" }
  | { status: "blocked"; reason?: string }
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

    const binding = await request.db.prepare(
      `SELECT org_id, epoch FROM tenant_binding
       WHERE installation_id = ? AND org_id = ?
         AND status IN ('active', 'held_for_transfer')`,
    ).bind(request.installationId, request.orgId)
      .first<{ org_id: string; epoch: number }>();
    if (
      binding === null || binding.epoch !== request.bindingEpoch ||
      anchor.org_id !== request.orgId || anchor.installation_id !== request.installationId ||
      anchor.binding_epoch !== request.bindingEpoch
    ) {
      return { kind: "rebuild_clinic_do", result: "blocked" };
    }
    const existingState = sqlSelect<{
      generation: string;
      installation_id: string;
      org_id: string;
      binding_epoch: number;
      anchor_event_id: string;
      status: string;
    }>(storage, "SELECT * FROM recovery_state WHERE singleton = 1 LIMIT 1")[0];
    const coreTables = ["hot", "term", "grant", "outbox"];
    const occupiedCore = coreTables.some((table) => Number(sqlSelect<{ count: number }>(
      storage, `SELECT COUNT(*) AS count FROM ${table}`,
    )[0]?.count ?? 0) > 0);
    const generation = `${request.installationId}:${request.bindingEpoch}:${anchor.event_id}`;
    // A continuation marker is only a bypass for an empty, freshly wiped DO.
    // Never let a previous failed attempt authorize replacing authoritative rows.
    const sameCandidate = !occupiedCore && existingState !== undefined &&
      existingState.generation === generation &&
      existingState.installation_id === request.installationId &&
      existingState.org_id === request.orgId &&
      existingState.binding_epoch === request.bindingEpoch &&
      existingState.anchor_event_id === anchor.event_id &&
      existingState.status === "building";
    if ((occupiedCore && !sameCandidate) || (existingState !== undefined && (
      existingState.generation !== generation ||
      existingState.installation_id !== request.installationId ||
      existingState.org_id !== request.orgId ||
      existingState.binding_epoch !== request.bindingEpoch ||
      existingState.anchor_event_id !== anchor.event_id ||
      existingState.status === "complete" ||
      existingState.status === "blocked" ||
      (existingState.status === "building" && !sameCandidate)
    ))) {
      return { kind: "rebuild_clinic_do", result: "blocked" };
    }
    const persistBlockedRecoveryMarker = (): void => {
      storage.transactionSync(() => sqlExec(storage,
        `INSERT OR IGNORE INTO recovery_state (
           singleton, generation, installation_id, org_id, binding_epoch,
           anchor_event_id, status, updated_at
         ) VALUES (1, ${sqlString(generation)}, ${sqlString(request.installationId)},
           ${sqlString(request.orgId)}, ${request.bindingEpoch}, ${sqlString(anchor.event_id)},
           'blocked', ${sqlString(new Date().toISOString())})`,
      ));
    };
    if (!sameCandidate) persistBlockedRecoveryMarker();

    const transferHistory = await request.db.prepare(
      `SELECT transfer_id, org_id, from_installation_id, to_installation_id, package FROM transfer
       WHERE from_installation_id = ? OR to_installation_id = ?`,
    ).bind(request.installationId, request.installationId).all<{
      transfer_id: string; org_id: string; package: string | null;
      from_installation_id: string;
      to_installation_id: string;
    }>();
    const movedRouteClaims = await request.db.prepare(
      `SELECT grant_id, envelope_sha256, route_generation FROM grant_claim
       WHERE installation_id = ? AND route_generation > 1`,
    ).bind(request.installationId).all<{
      grant_id: string;
      envelope_sha256: string;
      route_generation: number;
    }>();
    const openTransferPreparation = await request.db.prepare(
      `SELECT transfer_id FROM transfer_preparation
       WHERE phase <> 'completed'
         AND (from_installation_id = ? OR to_installation_id = ?) LIMIT 1`,
    ).bind(request.installationId, request.installationId).first<{ transfer_id: string }>();
    if (openTransferPreparation !== null) {
      return { kind: "rebuild_clinic_do", result: "blocked" };
    }

    let missingRouteSeal = false;
    for (const claim of movedRouteClaims.results ?? []) {
      const seal = sqlSelect<{ envelope_sha256: string; route_generation: number }>(
        storage,
        `SELECT envelope_sha256, route_generation FROM grant_route_seal
         WHERE grant_id = ${sqlString(claim.grant_id)} LIMIT 1`,
      )[0];
      if (seal === undefined || seal.envelope_sha256 !== claim.envelope_sha256 ||
          seal.route_generation !== claim.route_generation) {
        missingRouteSeal = true;
        break;
      }
    }
    if (missingRouteSeal) {
      persistBlockedRecoveryMarker();
      return {
        kind: "rebuild_clinic_do",
        result: "blocked",
        blocked_reason: "grant_route_seal_evidence_missing",
      };
    }
    const transferRows = transferHistory.results ?? [];
    if (transferRows.length > 0) {
      let missingTransferReplay = false;
      for (const transfer of transferRows) {
        const transferId = transfer.transfer_id;
        const expectedStep = transfer.from_installation_id === request.installationId
          ? "transfer_out"
          : "transfer_in";
        const preparation = await request.db.prepare(
          `SELECT org_id, from_installation_id, source_epoch, to_installation_id,
                  destination_epoch, phase
           FROM transfer_preparation WHERE transfer_id = ?`,
        ).bind(transferId).first<{
          org_id: string; from_installation_id: string; source_epoch: number;
          to_installation_id: string; destination_epoch: number; phase: string;
        }>();
        if (transfer.package === null || preparation === null || preparation.phase !== "completed" ||
            preparation.org_id !== transfer.org_id ||
            preparation.from_installation_id !== transfer.from_installation_id ||
            preparation.to_installation_id !== transfer.to_installation_id) {
          missingTransferReplay = true;
          break;
        }
        const transferSteps = await request.db.prepare(
          `SELECT step, receipt, applied_at FROM transfer_step
           WHERE transfer_id = ? ORDER BY step ASC`,
        ).bind(transferId).all<{ step: string; receipt: string; applied_at: string }>();
        const steps = transferSteps.results ?? [];
        const sourceStep = steps.find((step) => step.step === "transfer_out");
        const destinationStep = steps.find((step) => step.step === "transfer_in");
        const localStep = expectedStep === "transfer_out" ? sourceStep : destinationStep;
        if (steps.length !== 2 || sourceStep === undefined || destinationStep === undefined || localStep === undefined) {
          missingTransferReplay = true;
          break;
        }
        const replayRows = sqlSelect<{ request_sha256: string; response_json: string }>(
          storage,
          `SELECT request_sha256, response_json FROM transfer_replay
           WHERE transfer_id = ${sqlString(transferId)} AND step = ${sqlString(expectedStep)}`,
        );
        if (replayRows.length !== 1 || !/^[a-f0-9]{64}$/u.test(replayRows[0]!.request_sha256)) {
          missingTransferReplay = true;
          break;
        }
        try {
          const packageTerms = JSON.parse(transfer.package) as unknown;
          const sourceReceipt = JSON.parse(sourceStep.receipt) as Record<string, unknown>;
          const destinationReceipt = JSON.parse(destinationStep.receipt) as Record<string, unknown>;
          const replay = replayRows[0]!;
          const response = JSON.parse(replay.response_json) as Record<string, unknown>;
          const requestHash = await sha256Hex(canonicalize(expectedStep === "transfer_out"
            ? {
              installation_id: request.installationId,
              org_id: request.orgId,
              binding_epoch: preparation.source_epoch,
              to_installation_id: transfer.to_installation_id,
            }
            : {
              installation_id: request.installationId,
              org_id: request.orgId,
              binding_epoch: preparation.destination_epoch,
              package: packageTerms,
            }));
          const packageHash = await sha256Hex(canonicalize(packageTerms));
          const validateStepReceipt = async (
            receipt: Record<string, unknown>,
            step: { receipt: string; applied_at: string },
            installationId: string,
            expectedTermIds?: unknown,
          ): Promise<boolean> => {
            const exact = JSON.parse(step.receipt) as unknown;
            if (!canonicalValuesEqual(receipt, exact) ||
                receipt.transfer_id !== transferId || receipt.org_id !== request.orgId ||
                receipt.installation_id !== installationId || receipt.result !== "applied" ||
                receipt.applied_at !== step.applied_at || receipt.envelope_sha256 !== packageHash ||
                receipt.contract_version !== request.vendorContractVersion ||
                !Number.isSafeInteger(receipt.ledger_seq) ||
                typeof receipt.kid !== "string" || typeof receipt.signature !== "string" ||
                !Array.isArray(receipt.term_ids) ||
                (expectedTermIds !== undefined && !canonicalValuesEqual(receipt.term_ids, expectedTermIds))) {
              return false;
            }
            await verifyPlatformReceiptForRecovery(receipt, request.platformSigningKeyJson, transferId);
            return true;
          };
          const sourceReceiptValid = await validateStepReceipt(
            sourceReceipt, sourceStep, transfer.from_installation_id,
          );
          const destinationReceiptValid = await validateStepReceipt(
            destinationReceipt, destinationStep, transfer.to_installation_id,
            expectedStep === "transfer_in" ? response.term_ids : undefined,
          );
          const responseReceipt = expectedStep === "transfer_out" ? sourceReceipt : destinationReceipt;
          const responseKind = expectedStep;
          const expectedResult = "applied";
          const responseValid = response.kind === responseKind && response.result === expectedResult &&
            canonicalValuesEqual(response.receipt, responseReceipt) &&
            response.ledger_seq === responseReceipt.ledger_seq &&
            canonicalValuesEqual(response.term_ids, responseReceipt.term_ids) &&
            (expectedStep !== "transfer_out" || canonicalValuesEqual(response.package, packageTerms));
          if (
            transfer.org_id !== request.orgId ||
            replay.request_sha256 !== requestHash || !sourceReceiptValid || !destinationReceiptValid ||
            !responseValid || !Array.isArray(sourceReceipt.term_ids) ||
            !Array.isArray(destinationReceipt.term_ids) ||
            sourceReceipt.term_ids.length !== (packageTerms as unknown[]).length ||
            destinationReceipt.term_ids.length !== (packageTerms as unknown[]).length
          ) {
            missingTransferReplay = true;
            break;
          }
        } catch {
          missingTransferReplay = true;
          break;
        }
        if (missingTransferReplay) break;
      }
      if (missingTransferReplay) {
        persistBlockedRecoveryMarker();
        return {
          kind: "rebuild_clinic_do",
          result: "blocked",
          blocked_reason: "transfer_replay_evidence_missing",
        };
      }
    }
    const sameRecovery = sameCandidate;

    const anchorSnapshot = JSON.parse(anchor.snapshot) as Record<
      string,
      unknown
    >;

    const ledgerQuery = `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
        operator_credential_id, operator_email, envelope_sha256, receipt, applied_at
      FROM grant_ledger WHERE installation_id = ?`;
    const [beforeResult, afterResult, voidResult, coverageResult, usageResult] = await Promise.all([
      request.db.prepare(`${ledgerQuery} AND applied_at <= ? ORDER BY applied_at ASC, grant_id ASC`)
        .bind(request.installationId, anchor.at).all<GrantLedgerRebuildRow>(),
      request.db.prepare(`${ledgerQuery} AND applied_at > ? ORDER BY applied_at ASC, grant_id ASC`)
        .bind(request.installationId, anchor.at).all<GrantLedgerRebuildRow>(),
      request.db.prepare(
        `SELECT v.grant_id, v.reason, v.source, v.evidence_sha256, v.at
         FROM grant_void v
         JOIN grant_ledger l ON l.grant_id = v.grant_id
         WHERE l.installation_id = ? AND l.org_id = ?
         ORDER BY v.at ASC, v.grant_id ASC`,
      ).bind(request.installationId, request.orgId).all<{ grant_id: string; reason: string; source: string; evidence_sha256: string; at: string }>(),
      request.db.prepare(
        `SELECT kind, snapshot, clinic_seq, at FROM coverage_event
         WHERE installation_id = ? AND clinic_seq > ? ORDER BY clinic_seq ASC`,
      ).bind(request.installationId, anchor.clinic_seq).all<{ kind: string; snapshot: string; clinic_seq: number; at: string }>(),
      request.db.prepare(
        `SELECT request_id, term_id, quota_weight, recorded_at FROM usage_event
         WHERE installation_id = ? AND recorded_at >= ? ORDER BY recorded_at ASC, request_id ASC`,
      ).bind(request.installationId, anchor.at).all<{ request_id: string; term_id: string; quota_weight: number; recorded_at: string }>(),
    ]);
    const beforeRows = beforeResult.results ?? [];
    const afterRows = afterResult.results ?? [];
    const allLedgerRows = [...beforeRows, ...afterRows];
    const capsules = new Map<string, Record<string, unknown>>();
    try {
      for (const row of allLedgerRows) {
        if (row.org_id !== request.orgId || row.installation_id !== request.installationId) {
          throw new Error(`grant_recovery_identity_conflict:${row.grant_id}`);
        }
        capsules.set(row.grant_id, await verifyGrantRecoveryCapsule(
          request.db, request.r2, row.grant_id, row, request.platformSigningKeyJson,
        ));
      }
    } catch (error) {
      const detail = error instanceof Error ? error.message : "grant_recovery_evidence_invalid";
      if (!/^(?:grant_recovery_|grant_void_recovery_)/u.test(detail)) throw error;
      persistBlockedRecoveryMarker();
      return { kind: "rebuild_clinic_do", result: "blocked", blocked_reason: detail };
    }
    const voidRows = voidResult.results ?? [];
    try {
      for (const row of voidRows) {
        const ledger = allLedgerRows.find((entry) => entry.grant_id === row.grant_id);
        if (ledger === undefined) throw new Error(`grant_void_recovery_ledger_missing:${row.grant_id}`);
        const key = `grant-ledger/${row.grant_id}.void.ndjson`;
        const object = await request.r2.get(key);
        if (object === null) throw new Error(`grant_void_recovery_evidence_missing:${row.grant_id}`);
        let proof: Record<string, unknown>;
        try {
          const lines = (await object.text()).trimEnd().split("\n");
          if (lines.length !== 1 || lines[0]!.length === 0) throw new Error("invalid_lines");
          proof = JSON.parse(lines[0]!) as Record<string, unknown>;
        } catch {
          throw new Error(`grant_void_recovery_evidence_invalid:${row.grant_id}`);
        }
        if (!canonicalValuesEqual(proof, {
          grant_id: row.grant_id,
          reason: row.reason,
          source: row.source,
          evidence_sha256: row.evidence_sha256,
          at: row.at,
          receipt: proof.receipt,
        }) || proof.receipt === null || typeof proof.receipt !== "object" || Array.isArray(proof.receipt)) {
          throw new Error(`grant_void_recovery_evidence_conflict:${row.grant_id}`);
        }
        const receipt = proof.receipt as Record<string, unknown>;
        let expectedEnvelopeHash = "";
        if (row.source === "reversal") {
          if (typeof receipt.reversal_id !== "string" || receipt.reversal_id.length === 0) {
            throw new Error(`grant_void_recovery_command_provenance_conflict:${row.grant_id}`);
          }
          const command = await request.db.prepare(
            `SELECT reversal_id, grant_id, request_sha256, request_body, state, receipt
             FROM reversal_command WHERE reversal_id = ?`,
          ).bind(receipt.reversal_id).first<{
            reversal_id: string; grant_id: string; request_sha256: string; request_body: string;
            state: string; receipt: string | null;
          }>();
          let commandBody: Record<string, unknown> | null = null;
          try {
            const parsed: unknown = command === null ? null : JSON.parse(command.request_body);
            if (isRecoveryRecord(parsed)) commandBody = parsed;
          } catch { /* handled by the provenance check below */ }
          if (command === null || commandBody === null || command.state !== "terminal" ||
              command.reversal_id !== receipt.reversal_id || command.grant_id !== row.grant_id ||
              command.request_sha256 !== receipt.envelope_sha256 ||
              await sha256Hex(canonicalize(commandBody)) !== command.request_sha256 ||
              commandBody.grant_id !== row.grant_id || commandBody.reversal_id !== receipt.reversal_id ||
              commandBody.reason !== row.reason || commandBody.evidence_sha256 !== row.evidence_sha256 ||
              command.receipt === null ||
              !canonicalValuesEqual(JSON.parse(command.receipt), receipt)) {
            throw new Error(`grant_void_recovery_command_provenance_conflict:${row.grant_id}`);
          }
          expectedEnvelopeHash = command.request_sha256;
        } else if (row.source !== "operator") {
          throw new Error(`grant_void_recovery_source_invalid:${row.grant_id}`);
        }
        if (
          receipt.installation_id !== request.installationId || receipt.org_id !== request.orgId ||
          receipt.applied_at !== row.at || receipt.envelope_sha256 !== expectedEnvelopeHash ||
          receipt.result !== "applied" || !Array.isArray(receipt.term_ids) ||
          (row.source === "operator" ? receipt.grant_id !== row.grant_id : typeof receipt.reversal_id !== "string")
        ) throw new Error(`grant_void_recovery_receipt_conflict:${row.grant_id}`);
        await verifyPlatformReceiptForRecovery(receipt, request.platformSigningKeyJson, row.grant_id);
      }
    } catch (error) {
      const detail = error instanceof Error ? error.message : "grant_void_recovery_evidence_invalid";
      persistBlockedRecoveryMarker();
      return {
        kind: "rebuild_clinic_do",
        result: "blocked",
        blocked_reason: detail,
      };
    }
    const coverageRows = coverageResult.results ?? [];
    const grantSnapshots = new Map<string, Record<string, unknown>>();
    for (const event of coverageRows) {
      if (event.kind !== "grant_applied") continue;
      const snapshot = JSON.parse(event.snapshot) as Record<string, unknown>;
      for (const grant of allLedgerRows) {
        if (!grantSnapshots.has(grant.grant_id) && snapshotTermsIncludeGrant(snapshot, grant.grant_id)) {
          grantSnapshots.set(grant.grant_id, snapshot);
        }
      }
    }

    storage.transactionSync(() => {
      wipeCoverageDoTables(storage);
      hydrateDoFromCoverageSnapshot(storage, anchorSnapshot, request.bindingEpoch);
      updateHot(storage, { reservations: "[]", reserved: 0 });
      for (const row of beforeRows) insertDoGrantRowFromLedger(storage, row, capsules.get(row.grant_id)!);
      for (const row of afterRows) {
        insertDoGrantRowFromLedger(storage, row, capsules.get(row.grant_id)!);
        const snapshot = grantSnapshots.get(row.grant_id);
        if (snapshot !== undefined) syncDoTermsAndHotFromCoverageSnapshot(storage, snapshot);
      }
      for (const event of coverageRows) {
        if (!REBUILD_COVERAGE_EVENT_KINDS.has(event.kind)) continue;
        const snapshot = JSON.parse(event.snapshot) as Record<string, unknown>;
        wipeCoverageDoTables(storage);
        hydrateDoFromCoverageSnapshot(storage, snapshot, request.bindingEpoch);
        updateHot(storage, { reservations: "[]", reserved: 0 });
        for (const row of allLedgerRows) insertDoGrantRowFromLedger(storage, row, capsules.get(row.grant_id)!);
      }
      for (const row of voidRows) applyGrantVoidRowToDo(storage, row);
      reapplyUsageEventsAfterSnapshot(
        storage,
        loadTerms(storage).map((term) => term.term_id),
        anchorSnapshot,
        anchor.at,
        usageResult.results ?? [],
      );
      sqlExec(storage,
        `UPDATE recovery_state SET status = 'building', updated_at = ${sqlString(new Date().toISOString())}
         WHERE singleton = 1 AND generation = ${sqlString(generation)}`,
      );
    });

    const recoveredAt = new Date().toISOString();
    applyDueBoundaries({
      storage,
      clockNowIso: recoveredAt,
      installationId: request.installationId,
      orgId: request.orgId,
      vendorContractVersion: request.vendorContractVersion,
      durationScale: request.durationScale,
    });
    await scheduleCoverageAlarm(state, storage, recoveredAt);

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

    if (!(await coverageMirrorMatchesSnapshot(request.db, request.installationId, rebuiltSnapshot))) {
      storage.transactionSync(() => sqlExec(storage,
        `UPDATE recovery_state SET status = 'blocked', updated_at = ${sqlString(new Date().toISOString())}
         WHERE singleton = 1 AND generation = ${sqlString(generation)}`,
      ));
      return { kind: "rebuild_clinic_do", result: "blocked", snapshot: rebuiltSnapshot };
    }

    storage.transactionSync(() => sqlExec(storage,
      `UPDATE recovery_state SET status = 'complete', updated_at = ${sqlString(new Date().toISOString())}
       WHERE singleton = 1 AND generation = ${sqlString(generation)}`,
    ));
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
  const normalizedMirror = normalizeCoverageSnapshotForMirrorCompare(mirrorSnapshot);
  const normalizedSnapshot = normalizeCoverageSnapshotForMirrorCompare(snapshot);
  const mirrorBytes = canonicalize(normalizedMirror);
  const snapshotBytes = canonicalize(normalizedSnapshot);
  if (
    mirrorBytes.length !== snapshotBytes.length ||
    mirrorBytes.some((byte, index) => byte !== snapshotBytes[index])
  ) {
    return false;
  }

  return true;
}

function normalizeCoverageSnapshotForMirrorCompare(
  snapshot: Record<string, unknown>,
): Record<string, unknown> {
  // Usage is replayed from the durable ledger after a DO rebuild. The
  // coverage mirror advances on entitlement coverage events, so it can
  // legitimately lag those usage-only updates. Compare the mirrored
  // entitlement state while leaving usage reconciliation to usage_event.
  const normalized = JSON.parse(JSON.stringify(snapshot)) as Record<
    string,
    unknown
  >;
  delete normalized.grace_base_used;

  const term = normalized.term;
  if (term !== null && typeof term === "object" && !Array.isArray(term)) {
    const termRecord = term as Record<string, unknown>;
    delete termRecord.used;
    delete termRecord.band;
  }

  const terms = normalized.terms;
  if (Array.isArray(terms)) {
    for (const entry of terms) {
      if (entry !== null && typeof entry === "object" && !Array.isArray(entry)) {
        const termRecord = entry as Record<string, unknown>;
        delete termRecord.used;
        delete termRecord.used_final;
      }
    }
  }

  return normalized;
}

export async function runRebuildClinicDo(
  env: {
    DB: D1Database;
    DO: DurableObjectNamespace;
    R2: R2Bucket;
    PLATFORM_SIGNING_KEY?: string;
    DURATION_SCALE?: string;
  },
  installationId: string,
  options?: { onMismatch: (installationId: string) => Promise<void> },
): Promise<RunRebuildClinicDoResult> {
  const bindings = await env.DB.prepare(
    `SELECT org_id, epoch AS binding_epoch FROM tenant_binding
     WHERE installation_id = ? AND status IN ('active', 'held_for_transfer')`,
  )
    .bind(installationId)
    .all<{ org_id: string; binding_epoch: number }>();
  if ((bindings.results ?? []).length === 0) {
    return { status: "not_found" };
  }
  if (bindings.results!.length !== 1) return { status: "blocked" };
  const binding = bindings.results![0]!;
  const anchor = await env.DB.prepare(
    `SELECT org_id, binding_epoch FROM coverage_event WHERE installation_id = ?
     ORDER BY clinic_seq DESC LIMIT 1`,
  ).bind(installationId).first<{ org_id: string; binding_epoch: number }>();
  if (
    anchor === null || anchor.org_id !== binding.org_id ||
    anchor.binding_epoch !== binding.binding_epoch
  ) {
    return { status: "blocked" };
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
  let body: RebuildClinicDoResponse | undefined;
  try {
    body = decodeDoResponse<RebuildClinicDoResponse>(
      await response.json(),
      CHANNEL_VERSIONS.platformDo,
    );
  } catch {
    return { status: "not_found" };
  }
  if (body === undefined || body.result !== "ok" || body.snapshot === undefined) {
    if (body?.result === "blocked") {
      return { status: "blocked", ...(body.blocked_reason ? { reason: body.blocked_reason } : {}) };
    }
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
  env: { DB: D1Database; R2: R2Bucket; PLATFORM_SIGNING_KEY?: string },
): Promise<{ grant_ledger: number; grant_void: number }> {
  const recovered: Array<{ key: string; row: Record<string, unknown>; isVoid: boolean }> = [];
  const recoveryCapsules = new Map<string, Record<string, unknown>>();
  const seenGrantIds = new Set<string>();
  let cursor: string | undefined;
  do {
    const listed = await env.R2.list({ prefix: "grant-ledger/", cursor });
    for (const object of listed.objects) {
      const key = object.key;
      if (/^grant-ledger\/[a-f0-9]{64}\.recovery-v1\.ndjson$/u.test(key)) continue;
      const match = /^grant-ledger\/([a-f0-9]{64})(\.void)?\.ndjson$/u.exec(key);
      if (match === null) {
        throw new Error(`grant_ledger_object_key_invalid:${key}`);
      }
      const stored = await env.R2.get(key);
      if (stored === null) {
        throw new Error(`grant_ledger_object_missing:${key}`);
      }
      const text = await stored.text();
      const lines = text.trimEnd().split("\n");
      if (lines.length !== 1 || lines[0]!.length === 0) {
        throw new Error(`grant_ledger_payload_lines_invalid:${key}`);
      }
      const parsed = JSON.parse(lines[0]!) as Record<string, unknown>;
      const grantId = match[1]!;
      const isVoid = match[2] !== undefined;
      if (parsed.grant_id !== grantId || seenGrantIds.has(`${grantId}:${isVoid}`)) {
        throw new Error(`grant_ledger_identity_conflict:${key}`);
      }
      seenGrantIds.add(`${grantId}:${isVoid}`);
      const expectedFields = isVoid
        ? ["grant_id", "reason", "source", "evidence_sha256", "at", "receipt"]
        : ["grant_id", "origin_grant_id", "org_id", "installation_id", "kind",
          "source_kind", "operator_credential_id", "operator_email", "envelope_sha256",
          "applied_at", "receipt"];
      const fields = Object.keys(parsed).sort();
      if (JSON.stringify(fields) !== JSON.stringify([...expectedFields].sort())) {
        throw new Error(`grant_ledger_schema_conflict:${key}`);
      }
      for (const field of expectedFields) {
        if (field !== "operator_email" && parsed[field] === null || parsed[field] === undefined) {
          throw new Error(`grant_ledger_field_missing:${key}:${field}`);
        }
      }
      if (isVoid) {
        if (
          typeof parsed.reason !== "string" || typeof parsed.source !== "string" ||
          typeof parsed.evidence_sha256 !== "string" ||
          !/^[a-f0-9]{64}$/u.test(parsed.evidence_sha256 as string) ||
          typeof parsed.at !== "string" || !Number.isFinite(Date.parse(parsed.at as string)) ||
          parsed.receipt === null || typeof parsed.receipt !== "object" || Array.isArray(parsed.receipt)
        ) {
          throw new Error(`grant_ledger_void_invalid:${key}`);
        }
        const voidReceipt = parsed.receipt as Record<string, unknown>;
        if (voidReceipt.grant_id !== grantId || voidReceipt.applied_at !== parsed.at) {
          throw new Error(`grant_ledger_void_receipt_conflict:${key}`);
        }
        await verifyPlatformReceiptForRecovery(voidReceipt, env.PLATFORM_SIGNING_KEY, grantId);
      } else {
        const receipt = parsed.receipt;
        if (
          typeof parsed.origin_grant_id !== "string" ||
          !/^[a-f0-9]{64}$/u.test(parsed.origin_grant_id) ||
          typeof parsed.org_id !== "string" || typeof parsed.installation_id !== "string" ||
          typeof parsed.kind !== "string" || typeof parsed.source_kind !== "string" ||
          typeof parsed.operator_credential_id !== "string" ||
          (parsed.operator_email !== null && typeof parsed.operator_email !== "string") ||
          typeof parsed.envelope_sha256 !== "string" ||
          !/^[a-f0-9]{64}$/u.test(parsed.envelope_sha256) ||
          typeof parsed.applied_at !== "string" || !Number.isFinite(Date.parse(parsed.applied_at)) ||
          receipt === null || typeof receipt !== "object" || Array.isArray(receipt)
        ) {
          throw new Error(`grant_ledger_row_invalid:${key}`);
        }
        const signed = receipt as Record<string, unknown>;
        if (
          signed.grant_id !== grantId || signed.org_id !== parsed.org_id ||
          signed.installation_id !== parsed.installation_id ||
          signed.envelope_sha256 !== parsed.envelope_sha256 ||
          signed.applied_at !== parsed.applied_at || typeof signed.kid !== "string" ||
          typeof signed.signature !== "string"
        ) {
          throw new Error(`grant_ledger_receipt_identity_conflict:${key}`);
        }
        recoveryCapsules.set(grantId, await verifyGrantRecoveryCapsule(
          env.DB,
          env.R2,
          grantId,
          parsed as unknown as GrantLedgerRebuildRow,
          env.PLATFORM_SIGNING_KEY,
        ));
      }
      recovered.push({ key, row: parsed, isVoid });
    }
    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor !== undefined);

  const stagedStatements: D1PreparedStatement[] = [];
  for (const item of recovered) {
    if (item.isVoid) {
      const row = item.row;
      const existing = await env.DB.prepare(
        `SELECT grant_id, reason, source, evidence_sha256, at FROM grant_void WHERE grant_id = ?`,
      ).bind(row.grant_id).first<Record<string, unknown>>();
      if (existing !== null && !canonicalValuesEqual(existing, {
        grant_id: row.grant_id, reason: row.reason, source: row.source,
        evidence_sha256: row.evidence_sha256, at: row.at,
      })) throw new Error(`grant_void_recovery_conflict:${item.key}`);
      if (existing === null) {
        stagedStatements.push(env.DB.prepare(
          `INSERT INTO grant_void (grant_id, reason, source, evidence_sha256, at)
           VALUES (?, ?, ?, ?, ?)`,
        ).bind(row.grant_id, row.reason, row.source, row.evidence_sha256, row.at));
      }
      continue;
    }
    const row = item.row;
    const capsule = recoveryCapsules.get(String(row.grant_id));
    if (capsule === undefined) throw new Error(`grant_recovery_capsule_required:${String(row.grant_id)}`);
    if (capsule.source_kind !== "transfer") {
    const existingClaim = await env.DB.prepare(
      `SELECT org_id, source_kind, envelope, envelope_sha256, installation_id,
              binding_epoch, route_generation, state, receipt, accepted_command,
              accepted_actor, signer_credential_id, assertion_sha256,
              override_assertion_sha256, accepted_contract_version,
              accepted_ceiling_policy_version, plan_snapshot, accepted_at, command_state,
              created_at, completed_at
       FROM grant_claim WHERE grant_id = ?`,
    ).bind(row.grant_id).first<Record<string, unknown>>();
    const expectedClaim = {
      org_id: capsule.org_id,
      source_kind: capsule.source_kind,
      envelope: capsule.envelope,
      envelope_sha256: capsule.envelope_sha256,
      installation_id: capsule.installation_id,
      binding_epoch: capsule.binding_epoch,
      route_generation: capsule.route_generation,
      state: "completed",
      receipt: capsule.receipt,
      accepted_command: capsule.accepted_command,
      accepted_actor: capsule.accepted_actor,
      signer_credential_id: capsule.signer_credential_id,
      assertion_sha256: capsule.assertion_sha256,
      override_assertion_sha256: capsule.override_assertion_sha256,
      accepted_contract_version: capsule.accepted_contract_version,
      accepted_ceiling_policy_version: capsule.accepted_ceiling_policy_version,
      plan_snapshot: typeof capsule.plan_snapshot === "string" ? JSON.parse(capsule.plan_snapshot) : capsule.plan_snapshot,
      accepted_at: capsule.accepted_at,
      created_at: capsule.created_at,
      completed_at: capsule.completed_at,
      command_state: capsule.accepted_command === null ? "none" : "completed",
    };
    const comparableClaim = existingClaim === null ? null : {
      ...existingClaim,
      envelope: typeof existingClaim.envelope === "string" ? JSON.parse(existingClaim.envelope) : existingClaim.envelope,
      receipt: typeof existingClaim.receipt === "string" ? JSON.parse(existingClaim.receipt) : existingClaim.receipt,
      plan_snapshot: typeof existingClaim.plan_snapshot === "string" ? JSON.parse(existingClaim.plan_snapshot) : existingClaim.plan_snapshot,
    };
    if (comparableClaim !== null && !canonicalValuesEqual(comparableClaim, expectedClaim)) {
      throw new Error(`grant_claim_recovery_conflict:${item.key}`);
    }
    if (existingClaim === null) {
      stagedStatements.push(env.DB.prepare(
        `INSERT INTO grant_claim (
           grant_id, org_id, source_kind, envelope, envelope_sha256, installation_id,
           binding_epoch, route_generation, state, receipt, created_at, completed_at,
           accepted_command, accepted_actor, signer_credential_id, assertion_sha256,
           override_assertion_sha256, accepted_contract_version,
           accepted_ceiling_policy_version, plan_snapshot, accepted_at, command_state
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'completed', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(
        row.grant_id, capsule.org_id, capsule.source_kind,
        new TextDecoder().decode(canonicalize(capsule.envelope)),
        capsule.envelope_sha256, capsule.installation_id, capsule.binding_epoch,
        capsule.route_generation, new TextDecoder().decode(canonicalize(capsule.receipt)),
        capsule.created_at, capsule.completed_at, capsule.accepted_command, capsule.accepted_actor,
        capsule.signer_credential_id, capsule.assertion_sha256,
        capsule.override_assertion_sha256, capsule.accepted_contract_version,
        capsule.accepted_ceiling_policy_version, capsule.plan_snapshot,
        capsule.accepted_at, capsule.accepted_command === null ? "none" : "completed",
      ));
    }
    const assertionClaims = [
      [capsule.assertion_sha256, capsule.signer_credential_id],
      [capsule.override_assertion_sha256, capsule.signer_credential_id],
    ] as const;
    for (const [challenge, credential] of assertionClaims) {
      if (typeof challenge !== "string" || challenge.length === 0 || typeof credential !== "string") continue;
      const existingAssertion = await env.DB.prepare(
        `SELECT credential_id FROM assertion_used WHERE challenge_sha256 = ?`,
      ).bind(challenge).first<{ credential_id: string }>();
      if (existingAssertion?.credential_id !== credential) {
        throw new Error(`grant_assertion_recovery_conflict:${item.key}`);
      }
    }
    const ceiling = capsule.ceiling_claim as Record<string, unknown> | null;
    if (ceiling !== null) {
      const existingCeiling = await env.DB.prepare(
        `SELECT grant_id, org_id, envelope_sha256, plan_id, plan_version,
                allowance_denominator, day_contribution, allowance_contribution,
                apply_per_grant_caps, source_reconciled, override_authorized,
                status, receipt, applied_at, created_at
         FROM complimentary_ceiling_claim WHERE grant_id = ?`,
      ).bind(row.grant_id).first<Record<string, unknown>>();
      const comparableCeiling = existingCeiling === null ? null : {
        ...existingCeiling,
        receipt: typeof existingCeiling.receipt === "string"
          ? JSON.parse(existingCeiling.receipt)
          : existingCeiling.receipt,
      };
      if (comparableCeiling !== null && !canonicalValuesEqual(comparableCeiling, ceiling)) {
        throw new Error(`grant_ceiling_recovery_conflict:${item.key}`);
      }
      if (existingCeiling === null) {
        stagedStatements.push(env.DB.prepare(
          `INSERT INTO complimentary_ceiling_claim (
             grant_id, org_id, envelope_sha256, plan_id, plan_version,
             allowance_denominator, day_contribution, allowance_contribution,
             apply_per_grant_caps, source_reconciled, override_authorized,
             status, receipt, applied_at, created_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).bind(
          ceiling.grant_id, ceiling.org_id, ceiling.envelope_sha256, ceiling.plan_id,
          ceiling.plan_version, ceiling.allowance_denominator, ceiling.day_contribution,
          ceiling.allowance_contribution, ceiling.apply_per_grant_caps,
          ceiling.source_reconciled, ceiling.override_authorized, ceiling.status,
          ceiling.receipt, ceiling.applied_at, ceiling.created_at,
        ));
      }
    }
    }
    const existing = await env.DB.prepare(
      `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
              operator_credential_id, operator_email, envelope_sha256, receipt, applied_at
       FROM grant_ledger WHERE grant_id = ?`,
    ).bind(row.grant_id).first<Record<string, unknown>>();
    const comparableExisting = existing === null ? null : {
      ...existing,
      receipt: typeof existing.receipt === "string" ? JSON.parse(existing.receipt) : existing.receipt,
    };
    if (comparableExisting !== null && !canonicalValuesEqual(comparableExisting, row)) {
      throw new Error(`grant_ledger_recovery_conflict:${item.key}`);
    }
    if (existing === null) {
      stagedStatements.push(env.DB.prepare(
        `INSERT INTO grant_ledger (
          grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
          operator_credential_id, operator_email, envelope_sha256, receipt, applied_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        row.grant_id, row.origin_grant_id, row.org_id, row.installation_id,
        row.kind, row.source_kind, row.operator_credential_id, row.operator_email,
        row.envelope_sha256, JSON.stringify(row.receipt), row.applied_at,
      ));
    }
  }
  // No writes occur until every recovery object and every existing-row
  // comparison has passed. D1 batch applies the staged inserts atomically;
  // unique-key races fail the batch instead of being silently ignored.
  if (stagedStatements.length > 0) await env.DB.batch(stagedStatements);
  return {
    grant_ledger: recovered.filter((item) => !item.isVoid).length,
    grant_void: recovered.filter((item) => item.isVoid).length,
  };
}

export type RefreshCoverageSnapshotRequest = {
  kind: "refresh_coverage_snapshot";
  installationId: string;
  orgId: string;
  bindingEpoch: number;
  vendorContractVersion: number;
  durationScale?: DurationScale;
  db: D1Database;
  r2: R2Bucket;
  nowIso: string;
};

export type RefreshCoverageSnapshotResponse = {
  kind: "refresh_coverage_snapshot";
  result: "ok" | "not_found" | "blocked";
  event_id?: string;
  shipped_alerts?: ShippedCoverageAlert[];
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

    const storedInstallationId = resolveInstallationIdFromStorage(storage);
    const storedOrgId = resolveOrgIdFromStorage(storage);
    const hot = loadHot(storage);
    if (
      storedInstallationId !== request.installationId ||
      storedOrgId !== request.orgId ||
      hot.binding_epoch !== request.bindingEpoch
    ) {
      return { kind: "refresh_coverage_snapshot", result: "blocked" };
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
    const shippedAlerts = await shipCoverageOutboxInLock(
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
      shipped_alerts: shippedAlerts,
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
): Promise<{ event_id: string } | "not_found" | "blocked"> {
  const bindings = await env.DB.prepare(
    `SELECT org_id, epoch FROM tenant_binding
     WHERE installation_id = ? AND status IN ('active', 'held_for_transfer')`,
  )
    .bind(installationId)
    .all<{ org_id: string; epoch: number }>();
  if ((bindings.results ?? []).length === 0) {
    return "not_found";
  }
  if (bindings.results!.length !== 1) return "blocked";
  const binding = bindings.results![0]!;

  const eventIdentity = await env.DB.prepare(
    `SELECT org_id, binding_epoch FROM coverage_event
     WHERE installation_id = ? ORDER BY clinic_seq DESC LIMIT 1`,
  ).bind(installationId).first<{ org_id: string; binding_epoch: number }>();
  if (
    eventIdentity !== null &&
    (eventIdentity.org_id !== binding.org_id || eventIdentity.binding_epoch !== binding.epoch)
  ) {
    return "blocked";
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
      bindingEpoch: binding.epoch,
      vendorContractVersion: CHANNEL_VERSIONS.platformDo,
      durationScale,
      nowIso,
    }),
  });
  if (!response.ok) {
    return "not_found";
  }
  let body: RefreshCoverageSnapshotResponse | undefined;
  try {
    body = decodeDoResponse<RefreshCoverageSnapshotResponse>(
      await response.json(),
      CHANNEL_VERSIONS.platformDo,
    );
  } catch {
    return "not_found";
  }
  if (body?.result === "blocked") {
    return "blocked";
  }
  if (body === undefined || body.result !== "ok" || body.event_id === undefined) {
    return "not_found";
  }
  return { event_id: body.event_id };
}
