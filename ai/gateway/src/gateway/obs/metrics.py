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


def record_request(method: str, endpoint: str, status: int) -> None:
    REQUESTS_TOTAL.labels(method=method, endpoint=endpoint, status=str(status)).inc()


def record_error(code: str) -> None:
    ERRORS_TOTAL.labels(code=code).inc()


def set_runner_health(runner_id: str, healthy: bool) -> None:
    RUNNER_HEALTH.labels(runner_id=runner_id).set(1 if healthy else 0)


def observe_runner_latency(runner_id: str, latency_s: float) -> None:
    RUNNER_LATENCY.labels(runner_id=runner_id).observe(latency_s)


def set_inflight(runner_id: str, count: int) -> None:
    INFLIGHT_REQUESTS.labels(runner_id=runner_id).set(count)


def metrics_payload() -> bytes:
    return generate_latest()
