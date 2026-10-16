import type { ProviderPort } from "./port.js";
import {
  createPaymobAdapter,
  PAYMOB_ADAPTER_VERSION,
  parseStoredPaymobNotification,
  type PaymobAdapterEnv,
} from "./paymob/adapter.js";

export const PAYMOB_PROVIDER_ID = "paymob";

export type ProviderRegistryEnv = PaymobAdapterEnv;

// Domain services depend on the provider boundary, not the adapter module.
export { PAYMOB_ADAPTER_VERSION, parseStoredPaymobNotification };

export function providerForId(
  env: ProviderRegistryEnv,
  providerId: string,
): ProviderPort | null {
  if (providerId === PAYMOB_PROVIDER_ID) {
    return createPaymobAdapter(env);
  }
  return null;
}
