import type { ProviderPort } from "./port.js";
import { createPaymobAdapter, type PaymobAdapterEnv } from "./paymob/adapter.js";

export const PAYMOB_PROVIDER_ID = "paymob";

export type ProviderRegistryEnv = PaymobAdapterEnv;

export function providerForId(
  env: ProviderRegistryEnv,
  providerId: string,
): ProviderPort | null {
  if (providerId === PAYMOB_PROVIDER_ID) {
    return createPaymobAdapter(env);
  }
  return null;
}
