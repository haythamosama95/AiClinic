export type RunPeriodCloseInput = {
  db: D1Database;
  period: string;
};

/**
 * M1 interim: period-close issues no invoices until M2 owns purchase-proof /
 * paid-amount pricing (FR-017). Do not reintroduce credits×price here.
 */
export async function runPeriodClose(
  _input: RunPeriodCloseInput,
): Promise<void> {
  // no-op until M2
}
