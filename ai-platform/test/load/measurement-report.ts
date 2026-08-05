/**
 * Structured in-test measurement report for F5 load and cost tests.
 * Finite values only — no numeric ceilings for D1 headroom or DO throughput.
 */

export const CONCURRENCY_FIXTURE = 20;
/** Production-oriented design target ("tens of milliseconds"). */
export const GUARD_P95_PRODUCTION_TARGET_MS = 100;

/**
 * Workers-pool Miniflare fixture ceiling under concurrency. A single sequential
 * §6.1 guard on Miniflare is already ~300–400 ms; the concurrent N=20 run cannot
 * honestly use the production 100 ms target. Spec Kit Clarification Q3.
 */
export const GUARD_P95_CEILING_MS = 2000;

export type LoadMeasurementReport = {
  guard_p95_ms: number;
  guard_latencies_ms: number[];
  r2_class_a_ops_per_request: number;
  r2_class_a_ops_max_per_request: number;
  durable_object_requests_per_request: number;
  durable_object_requests_max_per_request: number;
  d1_hot_path_writes_per_request: number;
  d1_hot_path_writes_max_per_request: number;
  do_throughput_per_installation: number;
  concurrency: number;
  wall_clock_ms: number;
  request_count: number;
};

export function computeGuardP95(latenciesMs: number[]): number {
  if (latenciesMs.length === 0) return 0;
  const sorted = [...latenciesMs].sort((a, b) => a - b);
  const index = Math.ceil(0.95 * sorted.length) - 1;
  return sorted[Math.max(0, index)]!;
}

export function assertFiniteMeasurement(value: number): void {
  if (!Number.isFinite(value)) {
    throw new Error(`Expected finite measurement value, got ${String(value)}`);
  }
}

export function buildMeasurementReport(input: {
  guardLatenciesMs: number[];
  r2OpsTotal: number;
  r2OpsMaxPerRequest: number;
  doFetchesTotal: number;
  doFetchesMaxPerRequest: number;
  d1HotPathWritesTotal: number;
  d1HotPathWritesMaxPerRequest: number;
  doFetchesForPinnedInstallation: number;
  wallClockMs: number;
  pinnedInstallationDurationMs: number;
  observedConcurrency: number;
  requestCount: number;
}): LoadMeasurementReport {
  const pinnedSeconds =
    input.pinnedInstallationDurationMs > 0
      ? input.pinnedInstallationDurationMs / 1000
      : 0;
  const do_throughput_per_installation =
    pinnedSeconds > 0
      ? input.doFetchesForPinnedInstallation / pinnedSeconds
      : 0;
  const requestCount = input.requestCount;
  const per = (total: number) => (requestCount > 0 ? total / requestCount : 0);
  return {
    guard_p95_ms: computeGuardP95(input.guardLatenciesMs),
    guard_latencies_ms: [...input.guardLatenciesMs],
    r2_class_a_ops_per_request: per(input.r2OpsTotal),
    r2_class_a_ops_max_per_request: input.r2OpsMaxPerRequest,
    durable_object_requests_per_request: per(input.doFetchesTotal),
    durable_object_requests_max_per_request: input.doFetchesMaxPerRequest,
    d1_hot_path_writes_per_request: per(input.d1HotPathWritesTotal),
    d1_hot_path_writes_max_per_request: input.d1HotPathWritesMaxPerRequest,
    do_throughput_per_installation,
    concurrency: input.observedConcurrency,
    wall_clock_ms: input.wallClockMs,
    request_count: requestCount,
  };
}
