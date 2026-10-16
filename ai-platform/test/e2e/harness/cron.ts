import { emptyExecutionContext, env } from "./env";

/**
 * Invoke the worker `scheduled` handler directly (Register 5 #44).
 * Production crons: `0 3 * * *` (retention) and `0 4 * * *` (rollup).
 *
 * Pass `runtimeEnv` to inject a wrapped D1/DO (Register 5 #28 mid-tick faults).
 * `SELF.scheduled` is not exposed by this pool version.
 */
export async function invokeCron(
  cron: string,
  runtimeEnv: typeof env = env,
  scheduledTime: number = Date.now(),
): Promise<void> {
  const workerModule = await import("../../../src/worker");
  await workerModule.default.scheduled(
    {
      cron,
      scheduledTime,
      noRetry() {},
    },
    runtimeEnv as never,
    emptyExecutionContext(),
  );
}

export const CRON_RETENTION = "0 3 * * *";
export const CRON_ROLLUP = "0 4 * * *";
