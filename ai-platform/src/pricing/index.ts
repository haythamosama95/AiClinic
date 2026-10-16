/**
 * Post-response ledger pricing. Money is computed here from provider-reported
 * tokens and never enters the preflight (§13.6.2). The versioned table lives
 * next to the routing-policy fixture under `control/` and is bundled — not a
 * new store and not client-visible.
 */
import platformPricingArtifact from "../../control/pricing/platform-default/1.json";
import type { CanonicalResult } from "../contracts/canonical";

export const TOKENS_PER_PRICE_UNIT = 1_000;
const COST_DECIMAL_PLACES = 6;

export type ModelRates = {
  input_per_1k: number;
  output_per_1k: number;
};

export type PlatformPricingTable = {
  schema_version: number;
  pricing_id: string;
  pricing_version: number;
  unit: "per_1k_tokens";
  models: Record<string, ModelRates>;
  default: ModelRates;
};

export type PriceUsageInput = {
  modelId: string;
  inputTokens: number;
  outputTokens: number;
};

function isFiniteNonNegative(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function parseRates(raw: unknown, label: string): ModelRates {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error(`Invalid pricing rates for ${label}`);
  }
  const input = (raw as { input_per_1k?: unknown }).input_per_1k;
  const output = (raw as { output_per_1k?: unknown }).output_per_1k;
  if (!isFiniteNonNegative(input) || !isFiniteNonNegative(output)) {
    throw new Error(`Invalid pricing rates for ${label}`);
  }
  return { input_per_1k: input, output_per_1k: output };
}

function parsePricingTable(raw: unknown): PlatformPricingTable {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("Invalid platform pricing artifact");
  }
  const document = raw as {
    schema_version?: unknown;
    pricing_id?: unknown;
    pricing_version?: unknown;
    unit?: unknown;
    models?: unknown;
    default?: unknown;
  };
  if (
    document.schema_version !== 1 ||
    typeof document.pricing_id !== "string" ||
    document.pricing_id.length === 0 ||
    document.pricing_version !== 1 ||
    document.unit !== "per_1k_tokens" ||
    document.models === null ||
    typeof document.models !== "object" ||
    Array.isArray(document.models)
  ) {
    throw new Error("Invalid platform pricing artifact");
  }
  const models: Record<string, ModelRates> = {};
  for (const [modelId, rates] of Object.entries(document.models)) {
    models[modelId] = parseRates(rates, modelId);
  }
  return {
    schema_version: 1,
    pricing_id: document.pricing_id,
    pricing_version: 1,
    unit: "per_1k_tokens",
    models,
    default: parseRates(document.default, "default"),
  };
}

/** Versioned platform price table (control/pricing/platform-default/1.json). */
export const PLATFORM_PRICING_TABLE: PlatformPricingTable = parsePricingTable(
  platformPricingArtifact,
);

export function ratesForModel(modelId: string): ModelRates {
  return PLATFORM_PRICING_TABLE.models[modelId] ?? PLATFORM_PRICING_TABLE.default;
}

export function roundLedgerCost(value: number): number {
  const scale = 10 ** COST_DECIMAL_PLACES;
  return Math.round(value * scale) / scale;
}

function nonNegativeTokens(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return value;
}

/**
 * Shared ledger cost: provider-reported tokens × per-1K model rates.
 * Used by attempt rows, usage_event, and cancel credits when usage exists.
 */
export function priceUsage(input: PriceUsageInput): number {
  const rates = ratesForModel(input.modelId);
  const inputTokens = nonNegativeTokens(input.inputTokens);
  const outputTokens = nonNegativeTokens(input.outputTokens);
  return roundLedgerCost(
    (inputTokens / TOKENS_PER_PRICE_UNIT) * rates.input_per_1k +
      (outputTokens / TOKENS_PER_PRICE_UNIT) * rates.output_per_1k,
  );
}

export function ledgerUsageFromProvider(
  result: Pick<CanonicalResult, "usage" | "providerModel">,
): { tokens: number; cost: number } {
  const inputTokens = nonNegativeTokens(result.usage.input);
  const outputTokens = nonNegativeTokens(result.usage.output);
  return {
    tokens: inputTokens + outputTokens,
    cost: priceUsage({
      modelId: result.providerModel.model,
      inputTokens,
      outputTokens,
    }),
  };
}

/**
 * Named char-based fallback when the provider has not reported usage.
 * Treats streamed characters as output tokens and prices them with
 * {@link priceUsage} — not a third anonymous 0.001 formula.
 */
export function estimateUsageFromStreamedChars(
  streamedChars: number,
  modelId: string,
): { tokens: number; cost: number } {
  const tokens = nonNegativeTokens(streamedChars);
  return {
    tokens,
    cost: priceUsage({
      modelId,
      inputTokens: 0,
      outputTokens: tokens,
    }),
  };
}
