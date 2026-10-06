import {
  canonicalize,
  CHANNEL_VERSIONS,
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
  term_unit: string;
  term_count: number;
  charged_price_minor: number;
  currency: string;
  opened_with_coverage_through: string | null;
  coverage_source: string;
};

type CheckoutStatusRow = {
  state: string;
  last_event_at: string;
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
): Promise<BillingContactRow | null> {
  const row = await env.DB.prepare(
    `SELECT version, name, email, phone, contact_sha256, erased_at
     FROM billing_contact
     WHERE org_id = ?
     ORDER BY version DESC
     LIMIT 1`,
  )
    .bind(orgId)
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

async function hourlyCheckoutCount(
  env: CheckoutsEnv,
  orgId: string,
): Promise<number> {
  const nowMs = await clockNowMs(env);
  const hourAgo = new Date(nowMs - 60 * 60 * 1000).toISOString();
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS n
     FROM fact_log fl
     INNER JOIN checkout c ON c.checkout_id = fl.key
     WHERE fl."table" = 'checkout'
       AND c.org_id = ?
       AND fl.created_at > ?`,
  )
    .bind(orgId, hourAgo)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

async function loadExistingCheckout(
  env: CheckoutsEnv,
  orgId: string,
  clientRequestId: string,
): Promise<{ checkout: StoredCheckout; status: CheckoutStatusRow } | null> {
  const checkout = await env.DB.prepare(
    `SELECT checkout_id, reference, org_id, expires_at, offer_id, offer_version,
            term_unit, term_count, charged_price_minor, currency,
            opened_with_coverage_through, coverage_source
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
          : null;
      return decisionFromSnapshot(snapshot, "live", projectedStart);
    }
  } catch {
    // Fall through to coverage_view.
  }
  const viewSnapshot = await loadCoverageViewSnapshot(env, orgId);
  return decisionFromSnapshot(viewSnapshot, "view", null);
}

async function appendCheckoutFact(
  env: CheckoutsEnv,
  canonicalRow: Record<string, unknown>,
  checkoutId: string,
  createdAt: string,
): Promise<void> {
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.prepare(
    `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
  )
    .bind("checkout", checkoutId, rowSha256, createdAt)
    .run();
}

async function appendCheckoutEvent(
  env: CheckoutsEnv,
  row: {
    checkout_id: string;
    kind: string;
    source: string;
    ref: string;
    actor: string;
    at: string;
    contract_version: number;
  },
  createdAt: string,
): Promise<void> {
  const canonicalRow = {
    checkout_id: row.checkout_id,
    kind: row.kind,
    source: row.source,
    ref: row.ref,
    actor: row.actor,
    at: row.at,
    contract_version: row.contract_version,
  };
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO checkout_event (
         checkout_id, kind, source, ref, actor, at, contract_version
       ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      row.checkout_id,
      row.kind,
      row.source,
      row.ref,
      row.actor,
      row.at,
      row.contract_version,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind(
      "checkout_event",
      `${row.checkout_id}:${row.kind}:${row.at}`,
      rowSha256,
      createdAt,
    ),
  ]);
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

async function rebuildRedirect(
  env: CheckoutsEnv,
  checkoutId: string,
  reference: string,
  expiresAt: string,
  offer: OfferVersionRow,
  contact: BillingContactRow,
): Promise<{ ok: true; redirect_url: string; expires_at: string } | { ok: false }> {
  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return { ok: false };
  }
  const result = await provider.createCheckout({
    checkout_id: checkoutId,
    reference,
    amount_minor: offer.price_minor,
    currency: offer.currency,
    item_name: offerItemName(offer.copy),
    payer: {
      name: contact.name,
      email: contact.email,
      phone: contact.phone,
    },
    expires_in_s: CHECKOUT_EXPIRES_S,
    return_url: paymobReturnUrl(env),
    notify_url: paymobNotifyUrl(env),
  });
  if (!result.ok) {
    return { ok: false };
  }
  return { ok: true, redirect_url: result.redirect_url, expires_at: result.expires_at };
}

async function handleExistingCheckout(
  env: CheckoutsEnv,
  contractVersion: number,
  existing: { checkout: StoredCheckout; status: CheckoutStatusRow },
  offer: OfferVersionRow,
  contact: BillingContactRow,
): Promise<Response> {
  const { checkout, status } = existing;
  if (status.state === "open_failed") {
    return clinicErrorResponse(
      "provider_unavailable",
      503,
      contractVersion,
      { checkout_id: checkout.checkout_id },
    );
  }
  const rebuilt = await rebuildRedirect(
    env,
    checkout.checkout_id,
    checkout.reference,
    checkout.expires_at,
    offer,
    contact,
  );
  if (!rebuilt.ok) {
    return clinicErrorResponse(
      "provider_unavailable",
      503,
      contractVersion,
      { checkout_id: checkout.checkout_id },
    );
  }
  const coverage = await resolveCoverage(env, checkout.org_id);
  return clinicJsonResponse(
    successResponseBody(
      contractVersion,
      checkout.checkout_id,
      checkout.reference,
      rebuilt.redirect_url,
      checkout.expires_at,
      coverage,
    ),
    201,
    contractVersion,
  );
}

export async function handlePostCheckout(
  request: Request,
  env: CheckoutsEnv,
  claims: BillingClaims,
  contractVersion: number,
): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return clinicErrorResponse("invalid_request", 422, contractVersion);
  }

  const parsed = parsePostBody(body);
  if (parsed === null) {
    return clinicErrorResponse("invalid_request", 422, contractVersion);
  }

  const orgId = claims.org;

  const existing = await loadExistingCheckout(
    env,
    orgId,
    parsed.client_request_id,
  );
  if (existing !== null) {
    const offer = await loadOfferVersion(
      env,
      existing.checkout.offer_id,
      existing.checkout.offer_version,
    );
    const contact = await loadBillingContact(env, orgId);
    if (offer === null || contact === null) {
      return clinicErrorResponse("not_found", 404, contractVersion);
    }
    return handleExistingCheckout(env, contractVersion, existing, offer, contact);
  }

  if ((await hourlyCheckoutCount(env, orgId)) >= HOURLY_CHECKOUT_LIMIT) {
    return clinicErrorResponse("rate_limited", 429, contractVersion);
  }

  const contact = await loadBillingContact(env, orgId);
  if (contact === null) {
    return clinicErrorResponse("billing_contact_required", 409, contractVersion);
  }

  const currentTerms = await maxTermsVersion(env);
  if (currentTerms === null || parsed.terms_version !== currentTerms) {
    return clinicErrorResponse("terms_not_accepted", 409, contractVersion);
  }

  const sellableVersion = await sellableOfferVersion(env, parsed.offer_id);
  if (sellableVersion === null || parsed.offer_version !== sellableVersion) {
    return clinicErrorResponse("offer_unavailable", 409, contractVersion, {
      current_version: sellableVersion,
    });
  }

  const offer = await loadOfferVersion(env, parsed.offer_id, parsed.offer_version);
  if (offer === null) {
    return clinicErrorResponse("offer_unavailable", 409, contractVersion, {
      current_version: sellableVersion,
    });
  }

  const coverage = await resolveCoverage(env, orgId);
  const checkoutId = await newCheckoutId(env);
  const reference = humanRef("CK", checkoutId);
  const expiresAt = new Date(
    (await clockNowMs(env)) + CHECKOUT_EXPIRES_MINUTES * 60_000,
  ).toISOString();
  const createdAt = await clockNowIso(env);

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return clinicErrorResponse("provider_unavailable", 503, contractVersion);
  }

  const providerResult = await provider.createCheckout({
    checkout_id: checkoutId,
    reference,
    amount_minor: offer.price_minor,
    currency: offer.currency,
    item_name: offerItemName(offer.copy),
    payer: {
      name: contact.name,
      email: contact.email,
      phone: contact.phone,
    },
    expires_in_s: CHECKOUT_EXPIRES_S,
    return_url: paymobReturnUrl(env),
    notify_url: paymobNotifyUrl(env),
  });

  const canonicalCheckout = {
    checkout_id: checkoutId,
    reference,
    org_id: orgId,
    created_by_sub: claims.sub,
    billing_token_jti: claims.jti,
    client_request_id: parsed.client_request_id,
    offer_id: offer.offer_id,
    offer_version: offer.version,
    plan_id: offer.plan_id,
    plan_version: offer.plan_version,
    term_unit: offer.term_unit,
    term_count: offer.term_count,
    allowance_credits: offer.allowance_credits,
    grace_days: offer.grace_days,
    grace_cap_rule: offer.grace_cap_rule,
    list_price_minor: offer.price_minor,
    charged_price_minor: offer.price_minor,
    adjustment_id: null,
    currency: offer.currency,
    terms_version: offer.terms_version,
    billing_contact_version: contact.version,
    billing_contact_sha256: contact.contact_sha256,
    opened_with_coverage_through: coverage.opened_with_coverage_through,
    coverage_source: coverage.coverage_source,
    provider_id: PAYMOB_PROVIDER_ID,
    initiator: "payer",
    expires_at: expiresAt,
    contract_version: contractVersion,
  };

  if (!providerResult.ok) {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO checkout (
           checkout_id, reference, org_id, created_by_sub, billing_token_jti,
           client_request_id, offer_id, offer_version, plan_id, plan_version,
           term_unit, term_count, allowance_credits, grace_days, grace_cap_rule,
           list_price_minor, charged_price_minor, adjustment_id, currency,
           terms_version, billing_contact_version, billing_contact_sha256,
           opened_with_coverage_through, coverage_source, provider_id, initiator,
           expires_at, contract_version
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        checkoutId,
        reference,
        orgId,
        claims.sub,
        claims.jti,
        parsed.client_request_id,
        offer.offer_id,
        offer.version,
        offer.plan_id,
        offer.plan_version,
        offer.term_unit,
        offer.term_count,
        offer.allowance_credits,
        offer.grace_days,
        offer.grace_cap_rule,
        offer.price_minor,
        offer.price_minor,
        null,
        offer.currency,
        offer.terms_version,
        contact.version,
        contact.contact_sha256,
        coverage.opened_with_coverage_through,
        coverage.coverage_source,
        PAYMOB_PROVIDER_ID,
        "payer",
        expiresAt,
        contractVersion,
      ),
      env.DB.prepare(
        `INSERT INTO checkout_status (checkout_id, state, last_event_at)
         VALUES (?, 'open_failed', ?)`,
      ).bind(checkoutId, createdAt),
    ]);
    await appendCheckoutFact(env, canonicalCheckout, checkoutId, createdAt);
    await appendCheckoutEvent(
      env,
      {
        checkout_id: checkoutId,
        kind: "open_failed",
        source: "system",
        ref: reference,
        actor: claims.sub,
        at: createdAt,
        contract_version: contractVersion,
      },
      createdAt,
    );
    return clinicErrorResponse("provider_unavailable", 503, contractVersion, {
      checkout_id: checkoutId,
    });
  }

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO checkout (
         checkout_id, reference, org_id, created_by_sub, billing_token_jti,
         client_request_id, offer_id, offer_version, plan_id, plan_version,
         term_unit, term_count, allowance_credits, grace_days, grace_cap_rule,
         list_price_minor, charged_price_minor, adjustment_id, currency,
         terms_version, billing_contact_version, billing_contact_sha256,
         opened_with_coverage_through, coverage_source, provider_id, initiator,
         expires_at, contract_version
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      checkoutId,
      reference,
      orgId,
      claims.sub,
      claims.jti,
      parsed.client_request_id,
      offer.offer_id,
      offer.version,
      offer.plan_id,
      offer.plan_version,
      offer.term_unit,
      offer.term_count,
      offer.allowance_credits,
      offer.grace_days,
      offer.grace_cap_rule,
      offer.price_minor,
      offer.price_minor,
      null,
      offer.currency,
      offer.terms_version,
      contact.version,
      contact.contact_sha256,
      coverage.opened_with_coverage_through,
      coverage.coverage_source,
      PAYMOB_PROVIDER_ID,
      "payer",
      expiresAt,
      contractVersion,
    ),
    env.DB.prepare(
      `INSERT INTO checkout_status (checkout_id, state, last_event_at)
       VALUES (?, 'open', ?)`,
    ).bind(checkoutId, createdAt),
  ]);
  await appendCheckoutFact(env, canonicalCheckout, checkoutId, createdAt);
  await appendCheckoutEvent(
    env,
    {
      checkout_id: checkoutId,
      kind: "opened",
      source: "system",
      ref: reference,
      actor: claims.sub,
      at: createdAt,
      contract_version: contractVersion,
    },
    createdAt,
  );

  return clinicJsonResponse(
    successResponseBody(
      contractVersion,
      checkoutId,
      reference,
      providerResult.redirect_url,
      expiresAt,
      coverage,
    ),
    201,
    contractVersion,
  );
}

function shownState(state: string): string | null {
  if (state === "open") {
    return "Waiting";
  }
  if (state === "open_failed") {
    return "Abandoned";
  }
  return null;
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
  const display = shownState(row.state);
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
