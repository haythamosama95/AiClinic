import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdPaid,
  humanRef,
  sha256Hex,
  ulid,
} from "vendor-contracts";
import type { BillingClaims } from "./auth.js";
import { clinicErrorResponse, clinicJsonResponse } from "./version.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { PAYMOB_PROVIDER_ID, providerForId } from "../provider/registry.js";

const CHECKOUT_EXPIRES_MINUTES = 30;
const CHECKOUT_EXPIRES_S = 1800;
const HOURLY_CHECKOUT_LIMIT = 10;

export type CheckoutsEnv = ClockEnv & {
  DB: D1Database;
  BILLING_HOST: string;
  PAYMOB_BASE_URL: string;
  PAYMOB_SECRET_KEY: string;
  PAYMOB_PUBLIC_KEY: string;
  PAYMOB_CARD_INTEGRATION_ID: string;
  PLATFORM: {
    getCoverage(args: Record<string, unknown>): Promise<Record<string, unknown>>;
  };
};

type CheckoutRequestBody = {
  client_request_id: string;
  offer_id: string;
  offer_version: number;
  terms_version: number;
};

type OfferVersionRow = {
  offer_id: string;
  version: number;
  plan_id: string;
  plan_version: number;
  term_unit: string;
  term_count: number;
  price_minor: number;
  currency: string;
  allowance_credits: number;
  grace_days: number;
  grace_cap_rule: string;
  copy: string;
  terms_version: number;
  contract_version: number;
};

type BillingContactRow = {
  version: number;
  name: string;
  email: string;
  phone: string;
  contact_sha256: string;
  erased_at: string | null;
};

type StoredCheckout = {
  checkout_id: string;
  reference: string;
  org_id: string;
  expires_at: string;
  offer_id: string;
  offer_version: number;
  terms_version: number;
  billing_contact_version: number;
  term_unit: string;
  term_count: number;
  charged_price_minor: number;
  currency: string;
  opened_with_coverage_through: string | null;
  coverage_source: string;
  coverage_starts: "now" | "after_current" | null;
  projected_start: string | null;
  contract_version: number;
};

type CheckoutStatusRow = {
  state: string;
  last_event_at: string;
};

type IntentionAttemptRow = {
  attempt_no: number;
  state: "pending" | "created" | "abandoned_unconfirmed";
  lease_token: string;
  lease_until: string;
  special_reference: string;
  started_at: string;
};

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function parsePostBody(body: unknown): CheckoutRequestBody | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return null;
  }
  const record = body as Record<string, unknown>;
  const clientRequestId = record.client_request_id;
  const offerId = record.offer_id;
  const offerVersion = record.offer_version;
  const termsVersion = record.terms_version;
  if (!isNonEmptyString(clientRequestId) || !isNonEmptyString(offerId)) {
    return null;
  }
  if (!Number.isInteger(offerVersion) || !Number.isInteger(termsVersion)) {
    return null;
  }
  return {
    client_request_id: clientRequestId,
    offer_id: offerId,
    offer_version: offerVersion as number,
    terms_version: termsVersion as number,
  };
}

function offerItemName(copyJson: string): string {
  try {
    const copy = JSON.parse(copyJson) as { en?: { name?: string } };
    return copy.en?.name ?? "Clinic subscription";
  } catch {
    return "Clinic subscription";
  }
}

function paymobReturnUrl(env: CheckoutsEnv): string {
  return `https://${env.BILLING_HOST}/return/paymob?v=${CHANNEL_VERSIONS.paymobReturn}`;
}

function paymobNotifyUrl(env: CheckoutsEnv): string {
  return `https://${env.BILLING_HOST}/notify/paymob`;
}

async function newCheckoutId(env: CheckoutsEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

async function sellableOfferVersion(
  env: CheckoutsEnv,
  offerId: string,
): Promise<number | null> {
  const latest = await env.DB.prepare(
    `SELECT oe.kind
     FROM offer_event oe
     INNER JOIN (
       SELECT offer_id, MAX(at) AS max_at
       FROM offer_event
       WHERE offer_id = ?
       GROUP BY offer_id
     ) latest ON oe.offer_id = latest.offer_id AND oe.at = latest.max_at
     WHERE oe.offer_id = ?`,
  )
    .bind(offerId, offerId)
    .first<{ kind: string }>();
  if (latest?.kind !== "published") {
    return null;
  }
  const row = await env.DB.prepare(
    `SELECT MAX(version) AS version
     FROM offer_event
     WHERE offer_id = ? AND kind = 'published'`,
  )
    .bind(offerId)
    .first<{ version: number | null }>();
  return row?.version ?? null;
}

async function maxTermsVersion(env: CheckoutsEnv): Promise<number | null> {
  const row = await env.DB.prepare(
    `SELECT MAX(terms_version) AS terms_version FROM terms_version`,
  ).first<{ terms_version: number | null }>();
  return row?.terms_version ?? null;
}

async function loadBillingContact(
  env: CheckoutsEnv,
  orgId: string,
  version?: number,
): Promise<BillingContactRow | null> {
  const row = await env.DB.prepare(
    `SELECT version, name, email, phone, contact_sha256, erased_at
     FROM billing_contact
     WHERE org_id = ? AND (? IS NULL OR version = ?)
     ORDER BY version DESC
     LIMIT 1`,
  )
    .bind(orgId, version ?? null, version ?? null)
    .first<BillingContactRow>();
  if (row === null || row.erased_at !== null) {
    return null;
  }
  return row;
}

async function loadOfferVersion(
  env: CheckoutsEnv,
  offerId: string,
  version: number,
): Promise<OfferVersionRow | null> {
  return env.DB.prepare(
    `SELECT offer_id, version, plan_id, plan_version, term_unit, term_count,
            price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
            copy, terms_version, contract_version
     FROM offer_version
     WHERE offer_id = ? AND version = ?`,
  )
    .bind(offerId, version)
    .first<OfferVersionRow>();
}

async function loadExistingCheckout(
  env: CheckoutsEnv,
  orgId: string,
  clientRequestId: string,
): Promise<{ checkout: StoredCheckout; status: CheckoutStatusRow } | null> {
  const checkout = await env.DB.prepare(
    `SELECT checkout_id, reference, org_id, expires_at, offer_id, offer_version,
            terms_version, billing_contact_version,
            term_unit, term_count, charged_price_minor, currency,
            opened_with_coverage_through, coverage_source, coverage_starts,
            projected_start, contract_version
     FROM checkout
     WHERE org_id = ? AND client_request_id = ?`,
  )
    .bind(orgId, clientRequestId)
    .first<StoredCheckout>();
  if (checkout === null) {
    return null;
  }
  const status = await env.DB.prepare(
    `SELECT state, last_event_at FROM checkout_status WHERE checkout_id = ?`,
  )
    .bind(checkout.checkout_id)
    .first<CheckoutStatusRow>();
  if (status === null) {
    return null;
  }
  return { checkout, status };
}

async function latestAttempt(
  env: CheckoutsEnv,
  checkoutId: string,
): Promise<IntentionAttemptRow | null> {
  return env.DB.prepare(
    `SELECT attempt_no, state, lease_token, lease_until, special_reference, started_at
     FROM paymob_intention_attempt
     WHERE checkout_id = ? ORDER BY attempt_no DESC LIMIT 1`,
  )
    .bind(checkoutId)
    .first<IntentionAttemptRow>();
}

type CoverageDecision = {
  starts: "now" | "after_current";
  projected_start?: string;
  opened_with_coverage_through: string | null;
  coverage_source: "live" | "view";
};

type CoverageSnapshot = {
  state?: string;
  coverage_through?: string;
};

function parseCoverageSnapshot(value: unknown): CoverageSnapshot | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  return value as CoverageSnapshot;
}

async function loadCoverageViewSnapshot(
  env: CheckoutsEnv,
  orgId: string,
): Promise<CoverageSnapshot | null> {
  const row = await env.DB.prepare(
    `SELECT snapshot FROM coverage_view WHERE org_id = ?`,
  )
    .bind(orgId)
    .first<{ snapshot: string }>();
  if (row === null) {
    return null;
  }
  try {
    return parseCoverageSnapshot(JSON.parse(row.snapshot));
  } catch {
    return null;
  }
}

function decisionFromSnapshot(
  snapshot: CoverageSnapshot | null,
  source: "live" | "view",
  projectedStart?: string | null,
): CoverageDecision {
  if (snapshot?.state === "active" && typeof snapshot.coverage_through === "string") {
    const decision: CoverageDecision = {
      starts: "after_current",
      opened_with_coverage_through: snapshot.coverage_through,
      coverage_source: source,
    };
    if (typeof projectedStart === "string") {
      decision.projected_start = projectedStart;
    }
    return decision;
  }
  const through =
    typeof snapshot?.coverage_through === "string"
      ? snapshot.coverage_through
      : null;
  return {
    starts: "now",
    opened_with_coverage_through: through,
    coverage_source: source,
  };
}

async function resolveCoverage(
  env: CheckoutsEnv,
  orgId: string,
): Promise<CoverageDecision> {
  try {
    const envelope = await env.PLATFORM.getCoverage({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      org_id: orgId,
    });
    if (envelope.result === "ok" && typeof envelope.detail === "string") {
      const detail = JSON.parse(envelope.detail) as {
        snapshot?: unknown;
        coverage_through?: unknown;
      };
      const snapshot = parseCoverageSnapshot(detail.snapshot);
      const projectedStart =
        typeof detail.coverage_through === "string"
          ? detail.coverage_through
          : typeof snapshot?.coverage_through === "string"
            ? snapshot.coverage_through
            : null;
      return decisionFromSnapshot(snapshot, "live", projectedStart);
    }
  } catch {
    // Fall through to coverage_view.
  }
  const viewSnapshot = await loadCoverageViewSnapshot(env, orgId);
  const projectedStart =
    typeof viewSnapshot?.coverage_through === "string"
      ? viewSnapshot.coverage_through
      : null;
  return decisionFromSnapshot(viewSnapshot, "view", projectedStart);
}

function successResponseBody(
  contractVersion: number,
  checkoutId: string,
  reference: string,
  redirectUrl: string,
  expiresAt: string,
  coverage: CoverageDecision,
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    contract_version: contractVersion,
    checkout_id: checkoutId,
    reference,
    redirect_url: redirectUrl,
    expires_at: expiresAt,
    starts: coverage.starts,
  };
  if (coverage.starts === "after_current" && coverage.projected_start) {
    body.projected_start = coverage.projected_start;
  }
  return body;
}

function coverageFromStoredCheckout(checkout: StoredCheckout): CoverageDecision {
  if (checkout.coverage_starts === "after_current") {
    return {
      starts: "after_current",
      ...(typeof checkout.projected_start === "string"
        ? { projected_start: checkout.projected_start }
        : {}),
      opened_with_coverage_through: checkout.opened_with_coverage_through,
      coverage_source:
        checkout.coverage_source === "view" ? "view" : "live",
    };
  }
  return {
    starts: "now",
    // Legacy records have no recorded decision. Do not infer after_current
    // from a coverage end that may have belonged to a non-active snapshot.
    opened_with_coverage_through: checkout.opened_with_coverage_through,
    coverage_source:
      checkout.coverage_source === "view" ? "view" : "live",
  };
}

async function handleExistingCheckout(
  env: CheckoutsEnv,
  contractVersion: number,
  existing: { checkout: StoredCheckout; status: CheckoutStatusRow },
): Promise<Response> {
  const { checkout, status } = existing;
  if (status.state !== "open" && status.state !== "open_failed") {
    return clinicErrorResponse(
      "provider_unavailable",
      503,
      contractVersion,
      { checkout_id: checkout.checkout_id },
    );
  }
  if (Date.parse(checkout.expires_at) <= await clockNowMs(env)) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const attempt = await latestAttempt(env, checkout.checkout_id);
  if (attempt === null || attempt.state !== "created") {
    return clinicErrorResponse(
      "provider_unavailable",
      503,
      contractVersion,
      { checkout_id: checkout.checkout_id },
    );
  }
  const stillOpen = await env.DB.prepare(
    `SELECT 1 AS ready FROM checkout_status
     WHERE checkout_id = ? AND state IN ('open', 'open_failed')`,
  ).bind(checkout.checkout_id).first<{ ready: number }>();
  if (stillOpen === null) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  const intention = await provider?.createCheckout({
    checkout_id: checkout.checkout_id,
    attempt_no: attempt.attempt_no,
    lease_token: attempt.lease_token,
    reference: checkout.reference,
    amount_minor: checkout.charged_price_minor,
    currency: checkout.currency,
    item_name: "Clinic subscription",
    payer: { name: "", email: "", phone: "" },
    expires_in_s: CHECKOUT_EXPIRES_S,
    return_url: paymobReturnUrl(env),
    notify_url: paymobNotifyUrl(env),
  });
  if (intention?.ok !== true) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion, {
      checkout_id: checkout.checkout_id,
    });
  }
  if (Date.parse(checkout.expires_at) <= await clockNowMs(env)) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const statusAfterProvider = await env.DB.prepare(
    `SELECT 1 AS ready FROM checkout_status
     WHERE checkout_id = ? AND state IN ('open', 'open_failed')`,
  ).bind(checkout.checkout_id).first<{ ready: number }>();
  if (statusAfterProvider === null) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const coverage = coverageFromStoredCheckout(checkout);
  return clinicJsonResponse(
    successResponseBody(
      contractVersion,
      checkout.checkout_id,
      checkout.reference,
      intention.redirect_url,
      checkout.expires_at,
      coverage,
    ),
    201,
    contractVersion,
  );
}

async function factLogInsert(
  env: CheckoutsEnv,
  table: string,
  key: string,
  canonicalRow: Record<string, unknown>,
  createdAt: string,
  guardSql: string,
  guardBindings: unknown[],
): Promise<D1PreparedStatement> {
  const rowJson = new TextDecoder().decode(canonicalize(canonicalRow));
  const rowHash = await sha256Hex(canonicalize(canonicalRow));
  return env.DB.prepare(
    `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
     SELECT ?, ?, ?, ?, ? WHERE ${guardSql}`,
  ).bind(table, key, rowHash, rowJson, createdAt, ...guardBindings);
}

async function appendAttemptCheckoutEvent(args: {
  env: CheckoutsEnv;
  checkout: StoredCheckout;
  attemptNo: number;
  kind: "opened" | "open_failed";
  actor: string;
  contractVersion: number;
  at: string;
  expectedState: "pending" | "abandoned_unconfirmed";
}): Promise<void> {
  const { env, checkout, attemptNo, kind, actor, contractVersion, at, expectedState } = args;
  const event = {
    checkout_id: checkout.checkout_id, kind, source: "system",
    ref: checkout.reference, actor, at, contract_version: contractVersion,
  };
  const guard = `EXISTS (SELECT 1 FROM paymob_intention_attempt
    WHERE checkout_id = ? AND attempt_no = ? AND state = ?)
    AND NOT EXISTS (SELECT 1 FROM paymob_intention_attempt newer
      WHERE newer.checkout_id = ? AND newer.attempt_no > ?)
    AND EXISTS (SELECT 1 FROM checkout c
      INNER JOIN checkout_status s ON s.checkout_id = c.checkout_id
      WHERE c.checkout_id = ? AND c.expires_at > ?
        AND s.state IN ('open', 'open_failed'))`;
  const atBindings = [
    checkout.checkout_id, attemptNo, expectedState,
    checkout.checkout_id, attemptNo,
    checkout.checkout_id, at,
  ];
  const guardBindings = atBindings;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO checkout_event (checkout_id, kind, source, ref, actor, at, contract_version)
       SELECT ?, ?, 'system', ?, ?, ?, ?
       WHERE ${guard}
       ON CONFLICT(checkout_id, kind, at) DO NOTHING`,
    ).bind(checkout.checkout_id, kind, checkout.reference, actor, at,
      contractVersion, ...guardBindings),
    env.DB.prepare(
      `UPDATE checkout_status SET state = ?, last_event_at = ?
       WHERE checkout_id = ? AND state IN ('open', 'open_failed')
         AND EXISTS (SELECT 1 FROM checkout c
           WHERE c.checkout_id = checkout_status.checkout_id AND c.expires_at > ?)
         AND EXISTS (SELECT 1 FROM paymob_intention_attempt
           WHERE checkout_id = ? AND attempt_no = ? AND state = ?)
         AND NOT EXISTS (SELECT 1 FROM paymob_intention_attempt newer
           WHERE newer.checkout_id = checkout_status.checkout_id AND newer.attempt_no > ?)`,
    ).bind(kind === "opened" ? "open" : "open_failed", at,
      checkout.checkout_id, at, checkout.checkout_id, attemptNo, expectedState,
      attemptNo),
    await factLogInsert(env, "checkout_event",
      `${checkout.checkout_id}:${kind}:${at}`, event, at,
      `EXISTS (SELECT 1 FROM checkout_event WHERE checkout_id = ? AND kind = ? AND at = ?)
       AND ${guard}`,
      [checkout.checkout_id, kind, at, ...guardBindings]),
  ]);
}

function checkoutInsertBindings(args: {
  checkoutId: string;
  reference: string;
  orgId: string;
  claims: BillingClaims;
  request: CheckoutRequestBody;
  offer: OfferVersionRow;
  contact: BillingContactRow;
  coverage: CoverageDecision;
  expiresAt: string;
  createdAt: string;
  termsVersion: number;
  contractVersion: number;
}): unknown[] {
  const { checkoutId, reference, orgId, claims, request, offer, contact, coverage,
    expiresAt, createdAt, termsVersion, contractVersion } = args;
  return [
    checkoutId, reference, orgId, claims.sub, claims.jti, request.client_request_id,
    offer.offer_id, offer.version, offer.plan_id, offer.plan_version, offer.term_unit,
    offer.term_count, offer.allowance_credits, offer.grace_days, offer.grace_cap_rule,
    offer.price_minor, offer.price_minor, null, offer.currency, termsVersion,
    contact.version, contact.contact_sha256, coverage.opened_with_coverage_through,
    coverage.coverage_source, coverage.starts,
    coverage.starts === "after_current"
      ? coverage.projected_start ?? coverage.opened_with_coverage_through
      : null,
    PAYMOB_PROVIDER_ID, "payer", expiresAt, contractVersion,
    createdAt,
  ];
}

async function reserveFirstCheckout(args: {
  env: CheckoutsEnv;
  checkoutId: string;
  reference: string;
  orgId: string;
  claims: BillingClaims;
  request: CheckoutRequestBody;
  offer: OfferVersionRow;
  contact: BillingContactRow;
  coverage: CoverageDecision;
  expiresAt: string;
  createdAt: string;
  termsVersion: number;
  contractVersion: number;
  leaseToken: string;
  leaseUntil: string;
}): Promise<boolean> {
  const { env, checkoutId, reference, orgId, claims, request, offer, contact,
    coverage, expiresAt, createdAt, termsVersion, contractVersion, leaseToken,
    leaseUntil } = args;
  const canonicalCheckout = {
    checkout_id: checkoutId, reference, org_id: orgId, created_by_sub: claims.sub,
    billing_token_jti: claims.jti, client_request_id: request.client_request_id,
    offer_id: offer.offer_id, offer_version: offer.version, plan_id: offer.plan_id,
    plan_version: offer.plan_version, term_unit: offer.term_unit,
    term_count: offer.term_count, allowance_credits: offer.allowance_credits,
    grace_days: offer.grace_days, grace_cap_rule: offer.grace_cap_rule,
    list_price_minor: offer.price_minor, charged_price_minor: offer.price_minor,
    adjustment_id: null, currency: offer.currency, terms_version: termsVersion,
    billing_contact_version: contact.version,
    billing_contact_sha256: contact.contact_sha256,
    opened_with_coverage_through: coverage.opened_with_coverage_through,
    coverage_source: coverage.coverage_source,
    coverage_starts: coverage.starts,
    projected_start: coverage.starts === "after_current"
      ? coverage.projected_start ?? coverage.opened_with_coverage_through
      : null,
    provider_id: PAYMOB_PROVIDER_ID,
    initiator: "payer", expires_at: expiresAt, contract_version: contractVersion,
    created_at: createdAt,
  };
  const openedEvent = {
    checkout_id: checkoutId, kind: "opened", source: "system", ref: reference,
    actor: claims.sub, at: createdAt, contract_version: contractVersion,
  };
  const pendingAttempt = {
    event_key: `${checkoutId}:1:pending:${createdAt}`,
    checkout_id: checkoutId, attempt_no: 1, state: "pending", lease_token: leaseToken,
    lease_until: leaseUntil, special_reference: `${reference}-1`, intention_id: null,
    order_id: null, expires_at: null,
    started_at: createdAt, finished_at: null, event_at: createdAt,
  };
  const hourAgo = new Date(Date.parse(createdAt) - 60 * 60 * 1000).toISOString();
  const insertCheckout = env.DB.prepare(
    `INSERT INTO checkout (
       checkout_id, reference, org_id, created_by_sub, billing_token_jti,
       client_request_id, offer_id, offer_version, plan_id, plan_version,
       term_unit, term_count, allowance_credits, grace_days, grace_cap_rule,
       list_price_minor, charged_price_minor, adjustment_id, currency,
       terms_version, billing_contact_version, billing_contact_sha256,
       opened_with_coverage_through, coverage_source, coverage_starts, projected_start,
       provider_id, initiator, expires_at, contract_version, created_at
     ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
              ?, ?, ?, ?, ?, ?, ?, ?, ?
       WHERE (SELECT MAX(terms_version) FROM terms_version) = ?
         AND (SELECT COUNT(*) FROM checkout
              WHERE org_id = ? AND created_at > ?) < ?
       ON CONFLICT(org_id, client_request_id) DO NOTHING`,
  ).bind(
    ...checkoutInsertBindings({ checkoutId, reference, orgId, claims,
      request, offer, contact, coverage, expiresAt, createdAt, termsVersion,
      contractVersion }),
    termsVersion, orgId, hourAgo, HOURLY_CHECKOUT_LIMIT,
  );
  const guard = `EXISTS (SELECT 1 FROM checkout WHERE checkout_id = ? AND org_id = ? AND client_request_id = ?)`;
  const guardBindings = [checkoutId, orgId, request.client_request_id];
  const attemptJson = new TextDecoder().decode(canonicalize(pendingAttempt));
  const attemptHash = await sha256Hex(canonicalize(pendingAttempt));
  const results = await env.DB.batch([
    insertCheckout,
    env.DB.prepare(
      `INSERT INTO checkout_status (checkout_id, state, last_event_at)
       SELECT ?, 'open', ? WHERE EXISTS (SELECT 1 FROM checkout WHERE checkout_id = ?)
       ON CONFLICT(checkout_id) DO NOTHING`,
    ).bind(checkoutId, createdAt, checkoutId),
    env.DB.prepare(
      `INSERT INTO checkout_event (checkout_id, kind, source, ref, actor, at, contract_version)
       SELECT ?, 'opened', 'system', ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM checkout WHERE checkout_id = ?)
       ON CONFLICT(checkout_id, kind, at) DO NOTHING`,
    ).bind(checkoutId, reference, claims.sub, createdAt, contractVersion, checkoutId),
    await factLogInsert(env, "checkout", checkoutId, canonicalCheckout, createdAt,
      guard, guardBindings),
    await factLogInsert(env, "checkout_event", `${checkoutId}:opened:${createdAt}`,
      openedEvent, createdAt, guard, guardBindings),
    env.DB.prepare(
      `INSERT INTO paymob_intention_attempt (
         checkout_id, attempt_no, state, lease_token, lease_until,
         special_reference, started_at
       ) SELECT ?, 1, 'pending', ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM checkout WHERE checkout_id = ?)
       ON CONFLICT(checkout_id, attempt_no) DO NOTHING`,
    ).bind(checkoutId, leaseToken, leaseUntil, `${reference}-1`, createdAt, checkoutId),
    env.DB.prepare(
      `INSERT INTO paymob_intention_attempt_event (
         event_key, checkout_id, attempt_no, state, lease_token, lease_until,
         special_reference, intention_id, order_id, client_secret, expires_at,
         started_at, finished_at, event_at
       ) SELECT ?, ?, 1, 'pending', ?, ?, ?, NULL, NULL, NULL, NULL, ?, NULL, ?
       WHERE EXISTS (SELECT 1 FROM paymob_intention_attempt
                     WHERE checkout_id = ? AND attempt_no = 1 AND lease_token = ?)
       ON CONFLICT(event_key) DO NOTHING`,
    ).bind(pendingAttempt.event_key, checkoutId, leaseToken, leaseUntil,
      `${reference}-1`, createdAt, createdAt, checkoutId, leaseToken),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
       SELECT 'paymob_intention_attempt_event', ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM paymob_intention_attempt_event WHERE event_key = ?)`,
    ).bind(pendingAttempt.event_key, attemptHash, attemptJson, createdAt,
      pendingAttempt.event_key),
  ]);
  return (results[0]?.meta.changes ?? 0) === 1;
}

async function reserveNextAttempt(args: {
  env: CheckoutsEnv;
  checkout: StoredCheckout;
  previous: IntentionAttemptRow;
  createdAt: string;
  leaseToken: string;
  leaseUntil: string;
}): Promise<IntentionAttemptRow | null> {
  const { env, checkout, previous, createdAt, leaseToken, leaseUntil } = args;
  const attemptNo = previous.attempt_no + 1;
  const specialReference = `${checkout.reference}-${attemptNo}`;
  const canonicalAttempt = {
    event_key: `${checkout.checkout_id}:${attemptNo}:pending:${createdAt}`,
    checkout_id: checkout.checkout_id, attempt_no: attemptNo, state: "pending",
    lease_token: leaseToken, lease_until: leaseUntil, special_reference: specialReference,
    intention_id: null, order_id: null, expires_at: null,
    started_at: createdAt, finished_at: null, event_at: createdAt,
  };
  const rowJson = new TextDecoder().decode(canonicalize(canonicalAttempt));
  const rowHash = await sha256Hex(canonicalize(canonicalAttempt));
  const abandonedPrevious = {
    event_key: `${checkout.checkout_id}:${previous.attempt_no}:abandoned_unconfirmed:${createdAt}`,
    checkout_id: checkout.checkout_id,
    attempt_no: previous.attempt_no,
    state: "abandoned_unconfirmed",
    lease_token: previous.lease_token,
    lease_until: previous.lease_until,
    special_reference: previous.special_reference,
    intention_id: null,
    order_id: null,
    expires_at: null,
    started_at: previous.started_at,
    finished_at: createdAt,
    event_at: createdAt,
  };
  const abandonedJson = new TextDecoder().decode(canonicalize(abandonedPrevious));
  const abandonedHash = await sha256Hex(canonicalize(abandonedPrevious));
  const openedEvent = {
    checkout_id: checkout.checkout_id, kind: "opened", source: "system",
    ref: checkout.reference, actor: "system", at: createdAt,
    contract_version: checkout.contract_version,
  };
  const priorExpired = previous.state === "abandoned_unconfirmed" ||
    (previous.state === "pending" && Date.parse(previous.lease_until) <= Date.parse(createdAt));
  if (!priorExpired) return null;
  const retryableCheckout = `EXISTS (
    SELECT 1 FROM checkout c
    INNER JOIN checkout_status s ON s.checkout_id = c.checkout_id
    WHERE c.checkout_id = ? AND c.expires_at > ?
      AND s.state IN ('open', 'open_failed')
  )`;
  const retryableBindings = [checkout.checkout_id, createdAt];
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE paymob_intention_attempt SET state = 'abandoned_unconfirmed', finished_at = ?
       WHERE checkout_id = ? AND attempt_no = ? AND state = 'pending' AND lease_until <= ?
         AND ${retryableCheckout}`,
    ).bind(createdAt, checkout.checkout_id, previous.attempt_no, createdAt,
      ...retryableBindings),
    env.DB.prepare(
      `INSERT INTO paymob_intention_attempt_event (
         event_key, checkout_id, attempt_no, state, lease_token, lease_until,
         special_reference, intention_id, order_id, client_secret, expires_at,
         started_at, finished_at, event_at
       ) SELECT ?, ?, ?, 'abandoned_unconfirmed', ?, ?, ?, NULL, NULL, NULL, NULL, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM paymob_intention_attempt
         WHERE checkout_id = ? AND attempt_no = ? AND state = 'abandoned_unconfirmed'
           AND finished_at = ?) AND ${retryableCheckout}
       ON CONFLICT(event_key) DO NOTHING`,
    ).bind(abandonedPrevious.event_key, checkout.checkout_id, previous.attempt_no,
      previous.lease_token, previous.lease_until, previous.special_reference,
      previous.started_at, createdAt, createdAt, checkout.checkout_id,
      previous.attempt_no, createdAt, ...retryableBindings),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
       SELECT 'paymob_intention_attempt_event', ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM paymob_intention_attempt_event WHERE event_key = ?)
         AND ${retryableCheckout}`,
    ).bind(abandonedPrevious.event_key, abandonedHash, abandonedJson, createdAt,
      abandonedPrevious.event_key, ...retryableBindings),
    env.DB.prepare(
      `INSERT INTO paymob_intention_attempt (
         checkout_id, attempt_no, state, lease_token, lease_until, special_reference, started_at
       ) SELECT ?, ?, 'pending', ?, ?, ?, ?
       WHERE EXISTS (
         SELECT 1 FROM paymob_intention_attempt
         WHERE checkout_id = ? AND attempt_no = ? AND state = 'abandoned_unconfirmed'
       ) AND ${retryableCheckout}
       ON CONFLICT(checkout_id, attempt_no) DO NOTHING`,
    ).bind(checkout.checkout_id, attemptNo, leaseToken, leaseUntil, specialReference,
      createdAt, checkout.checkout_id, previous.attempt_no, ...retryableBindings),
    env.DB.prepare(
      `INSERT INTO paymob_intention_attempt_event (
         event_key, checkout_id, attempt_no, state, lease_token, lease_until,
         special_reference, intention_id, order_id, client_secret, expires_at,
         started_at, finished_at, event_at
       ) SELECT ?, ?, ?, 'pending', ?, ?, ?, NULL, NULL, NULL, NULL, ?, NULL, ?
       WHERE EXISTS (SELECT 1 FROM paymob_intention_attempt
                     WHERE checkout_id = ? AND attempt_no = ? AND lease_token = ?)
         AND ${retryableCheckout}
       ON CONFLICT(event_key) DO NOTHING`,
    ).bind(canonicalAttempt.event_key, checkout.checkout_id, attemptNo, leaseToken,
      leaseUntil, specialReference, createdAt, createdAt, checkout.checkout_id,
      attemptNo, leaseToken, ...retryableBindings),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
       SELECT 'paymob_intention_attempt_event', ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM paymob_intention_attempt_event WHERE event_key = ?)
         AND ${retryableCheckout}`,
    ).bind(canonicalAttempt.event_key, rowHash, rowJson, createdAt,
      canonicalAttempt.event_key, ...retryableBindings),
    env.DB.prepare(
      `INSERT INTO checkout_event (checkout_id, kind, source, ref, actor, at, contract_version)
       SELECT ?, 'opened', 'system', ?, 'system', ?, ?
       WHERE EXISTS (SELECT 1 FROM paymob_intention_attempt
                     WHERE checkout_id = ? AND attempt_no = ? AND lease_token = ?)
         AND ${retryableCheckout}
       ON CONFLICT(checkout_id, kind, at) DO NOTHING`,
    ).bind(checkout.checkout_id, checkout.reference, createdAt, checkout.contract_version,
      checkout.checkout_id, attemptNo, leaseToken, ...retryableBindings),
    await factLogInsert(env, "checkout_event",
      `${checkout.checkout_id}:opened:${createdAt}`, openedEvent, createdAt,
      `EXISTS (SELECT 1 FROM paymob_intention_attempt
        WHERE checkout_id = ? AND attempt_no = ? AND lease_token = ?)
        AND ${retryableCheckout}`,
      [checkout.checkout_id, attemptNo, leaseToken, ...retryableBindings]),
    env.DB.prepare(
      `UPDATE checkout_status SET state = 'open', last_event_at = ?
       WHERE checkout_id = ? AND state IN ('open', 'open_failed')
         AND EXISTS (SELECT 1 FROM checkout c
           WHERE c.checkout_id = checkout_status.checkout_id AND c.expires_at > ?)
         AND EXISTS (
         SELECT 1 FROM paymob_intention_attempt
         WHERE checkout_id = ? AND attempt_no = ? AND lease_token = ?
       )`,
    ).bind(createdAt, checkout.checkout_id, createdAt, checkout.checkout_id, attemptNo,
      leaseToken),
  ]);
  return env.DB.prepare(
    `SELECT attempt_no, state, lease_token, lease_until FROM paymob_intention_attempt
     WHERE checkout_id = ? AND attempt_no = ? AND lease_token = ?`,
  ).bind(checkout.checkout_id, attemptNo, leaseToken).first<IntentionAttemptRow>();
}

async function provideCheckoutRedirect(args: {
  env: CheckoutsEnv;
  checkout: StoredCheckout;
  attempt: IntentionAttemptRow;
  contact: BillingContactRow;
  offer: OfferVersionRow;
  contractVersion: number;
  coverage: CoverageDecision;
  actor: string;
}): Promise<Response> {
  const { env, checkout, attempt, contact, offer, contractVersion, coverage, actor } = args;
  if (attempt.state !== "pending" && attempt.state !== "created") {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const nowMs = await clockNowMs(env);
  if (Date.parse(checkout.expires_at) <= nowMs) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const stillOpen = await env.DB.prepare(
    `SELECT 1 AS ready FROM checkout c
     INNER JOIN checkout_status s ON s.checkout_id = c.checkout_id
     WHERE c.checkout_id = ? AND c.expires_at > ?
       AND s.state IN ('open', 'open_failed')`,
  ).bind(checkout.checkout_id, new Date(nowMs).toISOString()).first<{ ready: number }>();
  if (stillOpen === null) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const expiresInS = Math.max(1, Math.floor((Date.parse(checkout.expires_at) - nowMs) / 1000));
  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const result = await provider.createCheckout({
    checkout_id: checkout.checkout_id, attempt_no: attempt.attempt_no,
    lease_token: attempt.lease_token, reference: checkout.reference,
    amount_minor: checkout.charged_price_minor, currency: checkout.currency,
    item_name: offerItemName(offer.copy),
    payer: { name: contact.name, email: contact.email, phone: contact.phone },
    expires_in_s: expiresInS, return_url: paymobReturnUrl(env),
    notify_url: paymobNotifyUrl(env),
  });
  if (!result.ok) {
    await appendAttemptCheckoutEvent({ env, checkout, attemptNo: attempt.attempt_no,
      kind: "open_failed", actor, contractVersion,
      at: await clockNowIso(env), expectedState: "abandoned_unconfirmed" });
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const responseNow = await clockNowMs(env);
  if (Date.parse(checkout.expires_at) <= responseNow) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  const statusAfterProvider = await env.DB.prepare(
    `SELECT 1 AS ready FROM checkout_status
     WHERE checkout_id = ? AND state IN ('open', 'open_failed')`,
  ).bind(checkout.checkout_id).first<{ ready: number }>();
  if (statusAfterProvider === null) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkout.checkout_id });
  }
  return clinicJsonResponse(successResponseBody(contractVersion, checkout.checkout_id,
    checkout.reference, result.redirect_url, checkout.expires_at, coverage), 201, contractVersion);
}

export async function handlePostCheckout(
  request: Request,
  env: CheckoutsEnv,
  claims: BillingClaims,
  contractVersion: number,
): Promise<Response> {
  let body: unknown;
  try { body = await request.json(); } catch {
    return clinicErrorResponse("invalid_request", 422, contractVersion);
  }
  const parsed = parsePostBody(body);
  if (parsed === null) return clinicErrorResponse("invalid_request", 422, contractVersion);
  const orgId = claims.org;

  let existing = await loadExistingCheckout(env, orgId, parsed.client_request_id);
  if (existing !== null) {
    if (existing.checkout.offer_id !== parsed.offer_id ||
        existing.checkout.offer_version !== parsed.offer_version ||
        existing.checkout.terms_version !== parsed.terms_version) {
      return clinicErrorResponse("idempotency_conflict", 409, contractVersion);
    }
    if ((existing.status.state === "open" || existing.status.state === "open_failed") &&
        Date.parse(existing.checkout.expires_at) > await clockNowMs(env)) {
      const attempt = await latestAttempt(env, existing.checkout.checkout_id);
      if (attempt?.state === "created") {
        const contact = await loadBillingContact(env, orgId,
          existing.checkout.billing_contact_version);
        const offer = await loadOfferVersion(env, existing.checkout.offer_id,
          existing.checkout.offer_version);
        if (contact && offer) return provideCheckoutRedirect({ env, checkout: existing.checkout,
          attempt, contact, offer, contractVersion,
          coverage: coverageFromStoredCheckout(existing.checkout), actor: claims.sub });
      }
      if (attempt?.state === "abandoned_unconfirmed" || attempt?.state === "pending") {
        const now = await clockNowIso(env);
        const token = crypto.randomUUID();
        const next = await reserveNextAttempt({ env, checkout: existing.checkout,
          previous: attempt, createdAt: now, leaseToken: token,
          leaseUntil: new Date(Date.parse(now) + 2 * 60_000).toISOString() });
        if (next !== null) {
          const contact = await loadBillingContact(env, orgId,
            existing.checkout.billing_contact_version);
          const offer = await loadOfferVersion(env, existing.checkout.offer_id,
            existing.checkout.offer_version);
          if (contact && offer) return provideCheckoutRedirect({ env,
            checkout: existing.checkout, attempt: next, contact, offer,
            contractVersion, coverage: coverageFromStoredCheckout(existing.checkout),
            actor: claims.sub });
        }
      }
    }
    return handleExistingCheckout(env, contractVersion, existing);
  }

  const contact = await loadBillingContact(env, orgId);
  if (contact === null) return clinicErrorResponse("billing_contact_required", 409, contractVersion);
  const currentTerms = await maxTermsVersion(env);
  if (currentTerms === null || parsed.terms_version !== currentTerms) {
    return clinicErrorResponse("terms_not_accepted", 409, contractVersion);
  }
  const sellableVersion = await sellableOfferVersion(env, parsed.offer_id);
  if (sellableVersion === null || parsed.offer_version !== sellableVersion) {
    return clinicErrorResponse("offer_unavailable", 409, contractVersion, { current_version: sellableVersion });
  }
  const offer = await loadOfferVersion(env, parsed.offer_id, parsed.offer_version);
  if (offer === null) return clinicErrorResponse("offer_unavailable", 409, contractVersion,
    { current_version: sellableVersion });

  const coverage = await resolveCoverage(env, orgId);
  const checkoutId = await newCheckoutId(env);
  const reference = humanRef("CK", checkoutId);
  const createdAt = await clockNowIso(env);
  const expiresAt = new Date(Date.parse(createdAt) + CHECKOUT_EXPIRES_MINUTES * 60_000).toISOString();
  const leaseToken = crypto.randomUUID();
  const leaseUntil = new Date(Date.parse(createdAt) + 2 * 60_000).toISOString();
  const inserted = await reserveFirstCheckout({ env, checkoutId, reference, orgId, claims,
    request: parsed, offer, contact, coverage, expiresAt, createdAt,
    termsVersion: currentTerms, contractVersion, leaseToken, leaseUntil });
  if (!inserted) {
    existing = await loadExistingCheckout(env, orgId, parsed.client_request_id);
    if (existing !== null) {
      if (existing.checkout.offer_id !== parsed.offer_id ||
          existing.checkout.offer_version !== parsed.offer_version ||
          existing.checkout.terms_version !== parsed.terms_version) {
        return clinicErrorResponse("idempotency_conflict", 409, contractVersion);
      }
      return handleExistingCheckout(env, contractVersion, existing);
    }
    const currentAfterRace = await maxTermsVersion(env);
    if (currentAfterRace !== currentTerms) {
      return clinicErrorResponse("terms_not_accepted", 409, contractVersion);
    }
    return clinicErrorResponse("rate_limited", 429, contractVersion);
  }

  const reserved = await loadExistingCheckout(env, orgId, parsed.client_request_id);
  const attempt = await latestAttempt(env, checkoutId);
  if (reserved === null || attempt === null) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion,
      { checkout_id: checkoutId });
  }
  return provideCheckoutRedirect({ env, checkout: reserved.checkout, attempt,
    contact, offer, contractVersion, coverage, actor: claims.sub });
}

function shownStateForOpenStates(state: string): string | null {
  if (state === "open") {
    return "Waiting";
  }
  if (
    state === "open_failed" ||
    state === "expired" ||
    state === "cancelled"
  ) {
    return "Abandoned";
  }
  return null;
}

async function shownStateForPaidCheckout(
  env: CheckoutsEnv,
  checkoutId: string,
): Promise<string | null> {
  const payment = await env.DB.prepare(
    `SELECT payment_id FROM payment WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ payment_id: string }>();
  if (payment === null) {
    return null;
  }
  const grantId = await grantIdPaid(payment.payment_id);
  const outcome = await env.DB.prepare(
    `SELECT result FROM grant_outcome WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first<{ result: string }>();
  const grantApplied =
    outcome?.result === "applied" || outcome?.result === "already_applied";
  if (grantApplied) {
    return "Active";
  }
  return "Paid";
}

async function checkoutReadObject(
  env: CheckoutsEnv,
  checkoutId: string,
  contractVersion: number,
): Promise<Record<string, unknown> | null> {
  const row = await env.DB.prepare(
    `SELECT c.reference, c.offer_id, c.offer_version, c.term_unit, c.term_count,
            c.charged_price_minor, c.currency, s.state, s.last_event_at
     FROM checkout c
     INNER JOIN checkout_status s ON s.checkout_id = c.checkout_id
     WHERE c.checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{
      reference: string;
      offer_id: string;
      offer_version: number;
      term_unit: string;
      term_count: number;
      charged_price_minor: number;
      currency: string;
      state: string;
      last_event_at: string;
    }>();
  if (row === null) {
    return null;
  }
  let display = shownStateForOpenStates(row.state);
  if (
    display === null &&
    (row.state === "paid" || row.state === "paid_late")
  ) {
    display = await shownStateForPaidCheckout(env, checkoutId);
  }
  if (display === null) {
    return null;
  }
  return {
    contract_version: contractVersion,
    reference: row.reference,
    shown_state: display,
    offer: {
      offer_id: row.offer_id,
      version: row.offer_version,
      term_unit: row.term_unit,
      term_count: row.term_count,
      charged_price_minor: row.charged_price_minor,
      currency: row.currency,
    },
    payment_reference: null,
    term_ref: null,
    updated_at: row.last_event_at,
  };
}

export async function handleGetCheckout(
  env: CheckoutsEnv,
  orgId: string,
  checkoutId: string,
  contractVersion: number,
): Promise<Response> {
  const owner = await env.DB.prepare(
    `SELECT org_id FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ org_id: string }>();
  if (owner === null || owner.org_id !== orgId) {
    return clinicErrorResponse("not_found", 404, contractVersion);
  }
  const body = await checkoutReadObject(env, checkoutId, contractVersion);
  if (body === null) {
    return clinicErrorResponse("not_found", 404, contractVersion);
  }
  return clinicJsonResponse(body, 200, contractVersion);
}

export async function handleListOpenCheckouts(
  env: CheckoutsEnv,
  orgId: string,
  contractVersion: number,
): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT c.checkout_id
     FROM checkout c
     INNER JOIN checkout_status s ON s.checkout_id = c.checkout_id
     WHERE c.org_id = ?
       AND s.state IN ('open', 'paid', 'paid_late')`,
  )
    .bind(orgId)
    .all<{ checkout_id: string }>();

  const checkouts: Record<string, unknown>[] = [];
  for (const row of rows.results ?? []) {
    const item = await checkoutReadObject(env, row.checkout_id, contractVersion);
    if (item !== null) {
      checkouts.push(item);
    }
  }

  return clinicJsonResponse(
    { contract_version: contractVersion, checkouts },
    200,
    contractVersion,
  );
}
