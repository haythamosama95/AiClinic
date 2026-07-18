"""Typed error envelope and FastAPI exception handlers."""

from __future__ import annotations

from enum import Enum
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException

from gateway.obs.metrics import record_ai_error, record_error


class ErrorCode(str, Enum):
    BAD_REQUEST = "bad_request"
    UNAUTHENTICATED = "unauthenticated"
    FORBIDDEN = "forbidden"
    NOT_IMPLEMENTED = "not_implemented"
    RATE_LIMITED = "rate_limited"
    AI_UNUSABLE = "ai_unusable"
    AI_BUSY = "ai_busy"
    AI_NO_CAPACITY = "ai_no_capacity"
    AI_TIMEOUT = "ai_timeout"


ERROR_STATUS_MAP: dict[ErrorCode, int] = {
    ErrorCode.BAD_REQUEST: 400,
    ErrorCode.UNAUTHENTICATED: 401,
    ErrorCode.FORBIDDEN: 403,
    ErrorCode.NOT_IMPLEMENTED: 501,
    ErrorCode.RATE_LIMITED: 429,
    ErrorCode.AI_UNUSABLE: 422,
    ErrorCode.AI_BUSY: 503,
    ErrorCode.AI_NO_CAPACITY: 503,
    ErrorCode.AI_TIMEOUT: 504,
}

_AI_ERROR_CODES = frozenset(
    {
        ErrorCode.AI_UNUSABLE,
        ErrorCode.AI_BUSY,
        ErrorCode.AI_NO_CAPACITY,
        ErrorCode.AI_TIMEOUT,
    }
)


class ErrorBody(BaseModel):
    code: str
    message: str
    request_id: str


class ErrorEnvelope(BaseModel):
    error: ErrorBody


class GatewayError(Exception):
    """Application-level error with a stable machine-readable code."""

    def __init__(
        self,
        code: ErrorCode,
        message: str,
        request_id: str | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        self.code = code
        self.message = message
        self.request_id = request_id
        self.headers = headers
        super().__init__(message)


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "unknown")


def _record_error_metrics(code: ErrorCode) -> None:
    record_error(code.value)
    if code in _AI_ERROR_CODES:
        record_ai_error(code.value)


def error_response(
    code: ErrorCode,
    message: str,
    request_id: str,
    *,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    status = ERROR_STATUS_MAP[code]
    _record_error_metrics(code)
    body = ErrorEnvelope(
        error=ErrorBody(code=code.value, message=message, request_id=request_id)
    )
    return JSONResponse(
        status_code=status,
        content=body.model_dump(),
        headers=headers or {},
    )


def error_response_with_headers(
    code: ErrorCode,
    message: str,
    request_id: str,
    headers: dict[str, str],
) -> JSONResponse:
    """Build an error response with optional HTTP headers (e.g. Retry-After on ai_busy)."""
    return error_response(code, message, request_id, headers=headers)


def _http_error_code(exc: StarletteHTTPException) -> ErrorCode:
    if exc.status_code == 401:
        return ErrorCode.UNAUTHENTICATED
    if exc.status_code == 403:
        return ErrorCode.FORBIDDEN
    if exc.status_code == 422:
        return ErrorCode.AI_UNUSABLE
    if exc.status_code == 429:
        return ErrorCode.RATE_LIMITED
    if exc.status_code == 503:
        if exc.headers and "Retry-After" in exc.headers:
            return ErrorCode.AI_BUSY
        return ErrorCode.AI_NO_CAPACITY
    if exc.status_code == 504:
        return ErrorCode.AI_TIMEOUT
    if exc.status_code == 501:
        return ErrorCode.NOT_IMPLEMENTED
    return ErrorCode.BAD_REQUEST


def install_exception_handlers(app: FastAPI) -> None:
    """Register uniform error handlers on the FastAPI app."""

    @app.exception_handler(GatewayError)
    async def gateway_error_handler(request: Request, exc: GatewayError) -> JSONResponse:
        rid = exc.request_id or _request_id(request)
        return error_response(exc.code, exc.message, rid, headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        return error_response(
            ErrorCode.BAD_REQUEST,
            "Request validation failed",
            _request_id(request),
        )

    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(
        request: Request, exc: StarletteHTTPException
    ) -> JSONResponse:
        code = _http_error_code(exc)
        detail = exc.detail if isinstance(exc.detail, str) else "Request failed"
        return error_response(
            code,
            detail,
            _request_id(request),
            headers=dict(exc.headers) if exc.headers else None,
        )


def raise_gateway_error(
    code: ErrorCode,
    message: str,
    request: Request | None = None,
    *,
    headers: dict[str, str] | None = None,
) -> None:
    """Convenience helper to raise a GatewayError with request context."""
    rid = _request_id(request) if request else None
    raise GatewayError(code, message, rid, headers=headers)


def envelope_dict(code: str, message: str, request_id: str) -> dict[str, Any]:
    """Build a raw error envelope dict (for tests)."""
    return {"error": {"code": code, "message": message, "request_id": request_id}}
