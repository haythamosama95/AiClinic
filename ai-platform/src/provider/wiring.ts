import { DeepSeekAdapter, type DeepSeekAdapterOptions } from "./deepseek";
import { GeminiAdapter, type GeminiAdapterOptions } from "./gemini";
import type { ProviderPort } from "./port";

export type ProviderWiringOptions = DeepSeekAdapterOptions | GeminiAdapterOptions;

const PROVIDER_CONSTRUCTORS = {
  deepseek: DeepSeekAdapter,
  gemini: GeminiAdapter,
} as const;

export type WiredProviderId = keyof typeof PROVIDER_CONSTRUCTORS;

export function createProviderAdapter(
  providerId: WiredProviderId,
  options: ProviderWiringOptions,
): ProviderPort {
  const AdapterClass = PROVIDER_CONSTRUCTORS[providerId];
  return new AdapterClass(options as DeepSeekAdapterOptions & GeminiAdapterOptions);
}

export function listWiredProviderIds(): WiredProviderId[] {
  return Object.keys(PROVIDER_CONSTRUCTORS) as WiredProviderId[];
}
