import { canonicalize, sha256Hex } from "vendor-contracts";
import { clockNowIso, type ClockEnv } from "../clock.js";

export type AppendEnv = ClockEnv & {
  DB: D1Database;
};

export type FactLogEnv = {
  DB: D1Database;
};

const textDecoder = new TextDecoder();

export async function insertFactLog(
  env: FactLogEnv,
  table: string,
  key: string,
  canonicalRow: Record<string, unknown>,
  createdAt: string,
): Promise<D1PreparedStatement> {
  const rowJsonBytes = canonicalize(canonicalRow);
  const rowJson = textDecoder.decode(rowJsonBytes);
  const rowSha256 = await sha256Hex(rowJsonBytes);
  return env.DB.prepare(
    `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at) VALUES (?, ?, ?, ?, ?)`,
  ).bind(table, key, rowSha256, rowJson, createdAt);
}

export type OfferRow = {
  offer_id: string;
  code: string;
  contract_version: number;
};

type FixtureTermsVersion = {
  terms_version: number;
  locale: string;
  text_r2_key: string;
  text: string;
  text_sha256: string;
  published_by: string;
  contract_version: number;
};

type FixtureOfferVersion = {
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
  copy: Record<string, { name: string; summary: string }>;
  terms_version: number;
  published_by: string;
  assertion_sha256: string;
  contract_version: number;
};

type FixtureOfferEvent = {
  offer_id: string;
  kind: string;
  version: number;
  actor: string;
  at: string;
  contract_version: number;
};

type OffersFixture = {
  terms_versions?: FixtureTermsVersion[];
  offers?: OfferRow[];
  offer_versions?: FixtureOfferVersion[];
  offer_events?: FixtureOfferEvent[];
};

type HarnessAppendEnv = AppendEnv & {
  R2: R2Bucket;
};

const dynamicImport = new Function(
  "specifier",
  "return import(specifier)",
) as (specifier: string) => Promise<{ env: HarnessAppendEnv }>;

async function resolveHarnessEnv(): Promise<HarnessAppendEnv> {
  const mod = await dynamicImport("cloudflare:test");
  return mod.env;
}

async function appendOfferRow(env: AppendEnv, row: OfferRow): Promise<void> {
  const canonicalRow = {
    offer_id: row.offer_id,
    code: row.code,
    contract_version: row.contract_version,
  };
  const createdAt = await clockNowIso(env);
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO offer (offer_id, code, contract_version) VALUES (?, ?, ?)`,
    ).bind(row.offer_id, row.code, row.contract_version),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind("offer", row.offer_id, rowSha256, createdAt),
  ]);
}

export async function appendOffer(
  envOrRow: AppendEnv | OfferRow,
  maybeRow?: OfferRow,
): Promise<void> {
  if (maybeRow === undefined) {
    const env = await resolveHarnessEnv();
    return appendOfferRow(env, envOrRow as OfferRow);
  }
  return appendOfferRow(envOrRow as AppendEnv, maybeRow);
}

async function appendTermsVersion(
  env: AppendEnv,
  row: FixtureTermsVersion,
): Promise<void> {
  const canonicalRow = {
    terms_version: row.terms_version,
    locale: row.locale,
    text_r2_key: row.text_r2_key,
    text_sha256: row.text_sha256,
    published_by: row.published_by,
    contract_version: row.contract_version,
  };
  const createdAt = await clockNowIso(env);
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO terms_version (
        terms_version, locale, text_r2_key, text_sha256, published_by, contract_version
      ) VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(
      row.terms_version,
      row.locale,
      row.text_r2_key,
      row.text_sha256,
      row.published_by,
      row.contract_version,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind(
      "terms_version",
      `${row.terms_version}:${row.locale}`,
      rowSha256,
      createdAt,
    ),
  ]);
}

async function appendOfferVersion(
  env: AppendEnv,
  row: FixtureOfferVersion,
): Promise<void> {
  const copyJson = JSON.stringify(row.copy);
  const canonicalRow = {
    offer_id: row.offer_id,
    version: row.version,
    plan_id: row.plan_id,
    plan_version: row.plan_version,
    term_unit: row.term_unit,
    term_count: row.term_count,
    price_minor: row.price_minor,
    currency: row.currency,
    allowance_credits: row.allowance_credits,
    grace_days: row.grace_days,
    grace_cap_rule: row.grace_cap_rule,
    copy: copyJson,
    terms_version: row.terms_version,
    published_by: row.published_by,
    assertion_sha256: row.assertion_sha256,
    contract_version: row.contract_version,
  };
  const createdAt = await clockNowIso(env);
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO offer_version (
        offer_id, version, plan_id, plan_version, term_unit, term_count, price_minor,
        currency, allowance_credits, grace_days, grace_cap_rule, copy, terms_version,
        published_by, assertion_sha256, contract_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      row.offer_id,
      row.version,
      row.plan_id,
      row.plan_version,
      row.term_unit,
      row.term_count,
      row.price_minor,
      row.currency,
      row.allowance_credits,
      row.grace_days,
      row.grace_cap_rule,
      copyJson,
      row.terms_version,
      row.published_by,
      row.assertion_sha256,
      row.contract_version,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind(
      "offer_version",
      `${row.offer_id}:${row.version}`,
      rowSha256,
      createdAt,
    ),
  ]);
}

async function appendOfferEvent(
  env: AppendEnv,
  row: FixtureOfferEvent,
): Promise<void> {
  const canonicalRow = {
    offer_id: row.offer_id,
    kind: row.kind,
    version: row.version,
    actor: row.actor,
    at: row.at,
    contract_version: row.contract_version,
  };
  const createdAt = await clockNowIso(env);
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO offer_event (
        offer_id, kind, version, actor, at, contract_version
      ) VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(
      row.offer_id,
      row.kind,
      row.version,
      row.actor,
      row.at,
      row.contract_version,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind(
      "offer_event",
      `${row.offer_id}:${row.kind}:${row.version}:${row.at}`,
      rowSha256,
      createdAt,
    ),
  ]);
}

export async function loadOffersFixture(fixture: unknown): Promise<void> {
  const data = fixture as OffersFixture;
  const env = await resolveHarnessEnv();

  for (const terms of data.terms_versions ?? []) {
    await env.R2.put(terms.text_r2_key, terms.text);
    await appendTermsVersion(env, terms);
  }

  for (const offer of data.offers ?? []) {
    await appendOfferRow(env, offer);
  }

  for (const version of data.offer_versions ?? []) {
    await appendOfferVersion(env, version);
  }

  for (const event of data.offer_events ?? []) {
    await appendOfferEvent(env, event);
  }
}
