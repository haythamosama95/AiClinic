import { sha256Hex } from "vendor-contracts";

const PAYOUT_REVERSAL_REF_DOMAIN = "abo:paymob:payout-reversal-ref:v1";

/**
 * R9-AO2: opaque, adapter-owned identity of a Paymob refund or chargeback transaction. The same
 * function derives the value stored from a payout CSV line (`transaction_id`) and the value stored
 * from a provider-recorded reversal (`provider_txn_id`), so both sides compare for equality only.
 */
export function paymobReversalRef(providerTxnId: string): Promise<string> {
  return sha256Hex(new TextEncoder().encode(`${PAYOUT_REVERSAL_REF_DOMAIN}:${providerTxnId}`));
}
