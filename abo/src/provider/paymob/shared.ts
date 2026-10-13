/**
 * Paymob shared surface (G6 import boundary).
 *
 * Modules outside `provider/` import this module — never `adapter.ts` or
 * `client.ts`. Only `adapter.ts` may import `client.ts`.
 */
import type { ClockEnv } from "../../clock.js";

export type PaymobClientEnv = {
  PAYMOB_BASE_URL: string;
  PAYMOB_SECRET_KEY: string;
  PAYMOB_API_KEY?: string;
  PAYMOB_CARD_INTEGRATION_ID: string;
  TEST_CLOCK?: string;
  PAYMOB_STUB?: Fetcher;
};

export type PaymobAdapterEnv = PaymobClientEnv &
  ClockEnv & {
    DB: D1Database;
    R2: R2Bucket;
    BILLING_HOST: string;
    PAYMOB_PUBLIC_KEY: string;
    PAYMOB_HMAC_SECRET: string;
  };

export const PAYMOB_ADAPTER_VERSION = 1;

/**
 * `parseStoredPaymobNotification` needs the adapter's HMAC verification and
 * notification pipeline, so it stays implemented in `adapter.ts`; this module
 * is the boundary-legal import surface for non-provider consumers.
 */
export { parseStoredPaymobNotification } from "./adapter.js";