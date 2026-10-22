import { sha256Hex } from "vendor-contracts";
import { clinicJsonResponse } from "./version.js";
import { prepareRaiseAlert } from "../alert/index.js";
import { storedOfferFault, type OfferCopy } from "../offers/copy.js";

export type OffersEnv = {
  DB: D1Database;
  R2: R2Bucket;
};

export type CatalogueOffer = {
  offer_id: string;
  version: number;
  plan_display_name: string;
  term_unit: string;
  term_count: number;
  price_minor: number;
  currency: string;
  allowance_credits: number;
  grace_days: number;
  copy: OfferCopy;
  terms: {
    version: number;
    text: string;
  };
};

type SellableRow = {
  offer_id: string;
  version: number;
  term_unit: string;
  term_count: number;
  price_minor: number;
  currency: string;
  allowance_credits: number;
  grace_days: number;
  copy: string;
};

async function currentTermsText(
  env: OffersEnv,
): Promise<{ version: number; text: string }> {
  const row = await env.DB.prepare(
    `SELECT terms_version, text_r2_key, text_sha256
     FROM terms_version
     WHERE terms_version = (SELECT MAX(terms_version) FROM terms_version)
       AND locale = ?`,
  )
    .bind("en")
    .first<{ terms_version: number; text_r2_key: string; text_sha256: string }>();
  if (!row) {
    throw new Error("current terms_version en not found");
  }
  const object = await env.R2.get(row.text_r2_key);
  if (!object) {
    throw new Error(`R2 object missing at ${row.text_r2_key}`);
  }
  const text = await object.text();
  // R8-PUB1 step 3: the stored digest must match the bytes served. A mismatch fails explicitly.
  const digest = await sha256Hex(new TextEncoder().encode(text));
  if (digest !== row.text_sha256) {
    throw new Error(
      `terms_hash_mismatch terms_version=${row.terms_version} key=${row.text_r2_key}`,
    );
  }
  return { version: row.terms_version, text };
}

export async function listOffers(env: OffersEnv): Promise<CatalogueOffer[]> {
  // R8-CONSOLE1 step 2: `reinstated` is the historical activation alias of `published`.
  const latestEvents = await env.DB.prepare(
    `SELECT oe.offer_id, oe.kind, oe.version, oe.at
     FROM offer_event oe
     INNER JOIN (
       SELECT offer_id, MAX(at) AS max_at
       FROM offer_event
       GROUP BY offer_id
     ) latest ON oe.offer_id = latest.offer_id AND oe.at = latest.max_at
     WHERE oe.kind IN ('published', 'reinstated')`,
  ).all<{ offer_id: string; kind: string; version: number; at: string }>();

  const sellableIds = latestEvents.results ?? [];
  const offers: CatalogueOffer[] = [];
  let currentTerms: { version: number; text: string } | null = null;

  for (const event of sellableIds) {
    const versionRow = await env.DB.prepare(
      `SELECT MAX(version) AS version
       FROM offer_event
       WHERE offer_id = ? AND kind IN ('published', 'reinstated')`,
    )
      .bind(event.offer_id)
      .first<{ version: number }>();
    const sellableVersion = versionRow?.version;
    if (sellableVersion === undefined || sellableVersion === null) {
      continue;
    }

    const row = await env.DB.prepare(
      `SELECT offer_id, version, term_unit, term_count, price_minor, currency,
              allowance_credits, grace_days, copy
       FROM offer_version
       WHERE offer_id = ? AND version = ?`,
    )
      .bind(event.offer_id, sellableVersion)
      .first<SellableRow>();
    if (!row) {
      continue;
    }

    // R8-CONSOLE5 step 2: a malformed stored offer is quarantined and alerted; the other valid
    // offers still load. Its copy is never repaired or invented.
    const fault = storedOfferFault(row);
    if (fault !== null) {
      await prepareRaiseAlert(
        env.DB,
        "offer_malformed",
        `offer_malformed:${row.offer_id}:${row.version}`,
        `offer ${row.offer_id} version ${row.version} malformed: ${fault}`,
      ).run();
      continue;
    }

    const copy = JSON.parse(row.copy) as OfferCopy;
    currentTerms ??= await currentTermsText(env);
    offers.push({
      offer_id: row.offer_id,
      version: row.version,
      plan_display_name: copy.en.name,
      term_unit: row.term_unit,
      term_count: row.term_count,
      price_minor: row.price_minor,
      currency: row.currency,
      allowance_credits: row.allowance_credits,
      grace_days: row.grace_days,
      copy,
      terms: currentTerms,
    });
  }

  offers.sort((a, b) => a.offer_id.localeCompare(b.offer_id));
  return offers;
}

export async function handleGetOffers(
  env: OffersEnv,
  contractVersion: number,
): Promise<Response> {
  const offers = await listOffers(env);
  return clinicJsonResponse(
    { contract_version: contractVersion, offers },
    200,
    contractVersion,
  );
}
