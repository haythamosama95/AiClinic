import { clinicJsonResponse } from "./version.js";

export type OffersEnv = {
  DB: D1Database;
  R2: R2Bucket;
};

type LocalizedCopy = {
  name: string;
  summary: string;
};

type OfferCopy = {
  en: LocalizedCopy;
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
  terms_version: number;
};

function parseCopy(copyJson: string): OfferCopy {
  const parsed = JSON.parse(copyJson) as OfferCopy;
  return parsed;
}

async function termsText(
  env: OffersEnv,
  termsVersion: number,
): Promise<{ version: number; text: string }> {
  const row = await env.DB.prepare(
    `SELECT terms_version, text_r2_key
     FROM terms_version
     WHERE terms_version = ? AND locale = ?`,
  )
    .bind(termsVersion, "en")
    .first<{ terms_version: number; text_r2_key: string }>();
  if (!row) {
    throw new Error(`terms_version ${termsVersion} en not found`);
  }
  const object = await env.R2.get(row.text_r2_key);
  if (!object) {
    throw new Error(`R2 object missing at ${row.text_r2_key}`);
  }
  const text = await object.text();
  return { version: row.terms_version, text };
}

export async function listOffers(env: OffersEnv): Promise<CatalogueOffer[]> {
  const latestEvents = await env.DB.prepare(
    `SELECT oe.offer_id, oe.kind, oe.version, oe.at
     FROM offer_event oe
     INNER JOIN (
       SELECT offer_id, MAX(at) AS max_at
       FROM offer_event
       GROUP BY offer_id
     ) latest ON oe.offer_id = latest.offer_id AND oe.at = latest.max_at
     WHERE oe.kind = 'published'`,
  ).all<{ offer_id: string; kind: string; version: number; at: string }>();

  const sellableIds = latestEvents.results ?? [];
  const offers: CatalogueOffer[] = [];

  for (const event of sellableIds) {
    const versionRow = await env.DB.prepare(
      `SELECT MAX(version) AS version
       FROM offer_event
       WHERE offer_id = ? AND kind = 'published'`,
    )
      .bind(event.offer_id)
      .first<{ version: number }>();
    const sellableVersion = versionRow?.version;
    if (sellableVersion === undefined || sellableVersion === null) {
      continue;
    }

    const row = await env.DB.prepare(
      `SELECT offer_id, version, term_unit, term_count, price_minor, currency,
              allowance_credits, grace_days, copy, terms_version
       FROM offer_version
       WHERE offer_id = ? AND version = ?`,
    )
      .bind(event.offer_id, sellableVersion)
      .first<SellableRow>();
    if (!row) {
      continue;
    }

    const copy = parseCopy(row.copy);
    const terms = await termsText(env, row.terms_version);
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
      terms,
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
