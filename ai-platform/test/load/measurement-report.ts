/**
 * Structured in-test measurement report for F5 load and cost tests.
 * Finite values only — no numeric ceilings for D1 headroom or DO throughput.
 */

export const CONCURRENCY_FIXTURE = 20;
export const GUARD_P95_CEILING_MS = 100;

export type LoadMeasurementReport = {
  guard_p95_ms: number;
  guard_latencies_ms: number[];
  r2_class_a_ops_per_request: number;
  durable_object_requests_per_request: number;
  d1_hot_path_writes_per_request: number;
  do_throughput_per_installation: number;
  concurrency: number;
  request_count: number;
};

export function computeGuardP95(latenciesMs: number[]): number {
  if (latenciesMs.length === 0) {
    return 0;
  }
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
  doFetchesTotal: number;
  d1HotPathWritesTotal: number;
  requestCount: number;
  concurrency: number;
}): LoadMeasurementReport {
  const { guardLatenciesMs, r2OpsTotal, doFetchesTotal, d1HotPathWritesTotal, requestCount, concurrency } =
    input;

  const guard_p95_ms = computeGuardP95(guardLatenciesMs);

  return {
    guard_p95_ms,
    guard_latencies_ms: [...guardLatenciesMs],
    r2_class_a_ops_per_request: requestCount > 0 ? r2OpsTotal / requestCount : 0,
    durable_object_requests_per_request: requestCount > 0 ? doFetchesTotal / requestCount : 0,
    d1_hot_path_writes_per_request: requestCount > 0 ? d1HotPathWritesTotal / requestCount : 0,
    do_throughput_per_installation: requestCount > 0 ? doFetchesTotal / requestCount : 0,
    concurrency,
    request_count: requestCount,
  };
}
