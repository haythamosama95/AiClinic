"""Prometheus /metrics endpoint."""

from __future__ import annotations

from ai_common.verbose_logging import get_logger
from fastapi import APIRouter, Response

from gateway.obs.metrics import metrics_payload

router = APIRouter()

vlog = get_logger(__name__)


@router.get("/metrics")
async def get_metrics() -> Response:
    vlog.v0("Serving Prometheus metrics")
    payload = metrics_payload()
    vlog.v1("Prometheus metrics served", payload_bytes=len(payload))
    return Response(
        content=payload,
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )
