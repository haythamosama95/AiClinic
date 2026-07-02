"""Prometheus /metrics endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Response

from gateway.obs.metrics import metrics_payload

router = APIRouter()


@router.get("/metrics")
async def get_metrics() -> Response:
    return Response(
        content=metrics_payload(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )
