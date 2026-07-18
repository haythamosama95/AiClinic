"""Prometheus metrics collectors for the AI Gateway."""

from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram, generate_latest

REQUESTS_TOTAL = Counter(
    "gateway_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)

ERRORS_TOTAL = Counter(
    "gateway_errors_total",
    "Total errors by code",
    ["code"],
)

RUNNER_HEALTH = Gauge(
    "gateway_runner_health",
    "Runner health status (1=healthy, 0=unhealthy)",
    ["runner_id"],
)

RUNNER_LATENCY = Histogram(
    "gateway_runner_poll_latency_seconds",
    "Runner health poll latency",
    ["runner_id"],
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0),
)

INFLIGHT_REQUESTS = Gauge(
    "gateway_inflight_requests",
    "Current in-flight requests",
    ["runner_id"],
)

AI_REQUESTS_TOTAL = Counter(
    "ai_requests_total",
    "Total AI generation requests",
    ["task", "outcome"],
)

AI_ERRORS_TOTAL = Counter(
    "ai_errors_total",
    "Total AI-layer errors by code",
    ["code"],
)

AI_QUEUE_DEPTH = Gauge(
    "ai_queue_depth",
    "Current queue depth per capability class",
    ["capability"],
)

AI_FIRST_TOKEN_SECONDS = Histogram(
    "ai_first_token_seconds",
    "Time to first token from runner",
    ["runner"],
    buckets=(0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0),
)

AI_TOTAL_SECONDS = Histogram(
    "ai_total_seconds",
    "End-to-end AI generation latency",
    ["runner", "task"],
    buckets=(0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 45.0, 60.0, 120.0),
)

AI_INFLIGHT = Gauge(
    "ai_inflight",
    "Current in-flight AI requests per capability",
    ["capability"],
)

AI_TOKENS_PER_SEC = Histogram(
    "ai_tokens_per_sec",
    "Token throughput during generation",
    ["runner", "task"],
    buckets=(1.0, 5.0, 10.0, 25.0, 50.0, 100.0, 200.0, 500.0),
)

AI_MODEL_SWAPS_TOTAL = Counter(
    "ai_model_swaps_total",
    "Auto-triggered model swap attempts",
    ["runner", "outcome"],
)


def record_request(method: str, endpoint: str, status: int) -> None:
    REQUESTS_TOTAL.labels(method=method, endpoint=endpoint, status=str(status)).inc()


def record_error(code: str) -> None:
    ERRORS_TOTAL.labels(code=code).inc()


def record_ai_error(code: str) -> None:
    AI_ERRORS_TOTAL.labels(code=code).inc()


def record_ai_request(task: str, outcome: str) -> None:
    AI_REQUESTS_TOTAL.labels(task=task, outcome=outcome).inc()


def set_ai_queue_depth(capability: str, depth: int) -> None:
    AI_QUEUE_DEPTH.labels(capability=capability).set(depth)


def observe_ai_first_token_seconds(runner: str, seconds: float) -> None:
    AI_FIRST_TOKEN_SECONDS.labels(runner=runner).observe(seconds)


def observe_ai_total_seconds(runner: str, task: str, seconds: float) -> None:
    AI_TOTAL_SECONDS.labels(runner=runner, task=task).observe(seconds)


def set_ai_inflight(capability: str, count: int) -> None:
    AI_INFLIGHT.labels(capability=capability).set(count)


def observe_ai_tokens_per_sec(runner: str, task: str, tokens_per_sec: float) -> None:
    AI_TOKENS_PER_SEC.labels(runner=runner, task=task).observe(tokens_per_sec)


def record_ai_model_swap(runner: str, outcome: str) -> None:
    AI_MODEL_SWAPS_TOTAL.labels(runner=runner, outcome=outcome).inc()


def set_runner_health(runner_id: str, healthy: bool) -> None:
    RUNNER_HEALTH.labels(runner_id=runner_id).set(1 if healthy else 0)


def observe_runner_latency(runner_id: str, latency_s: float) -> None:
    RUNNER_LATENCY.labels(runner_id=runner_id).observe(latency_s)


def set_inflight(runner_id: str, count: int) -> None:
    INFLIGHT_REQUESTS.labels(runner_id=runner_id).set(count)


def metrics_payload() -> bytes:
    return generate_latest()
