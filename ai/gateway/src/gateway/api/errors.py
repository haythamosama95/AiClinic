"""Typed error envelope and FastAPI exception handlers."""

from __future__ import annotations

from enum import Enum
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException


class ErrorCode(str, Enum):
    BAD_REQUEST = "bad_request"
    UNAUTHENTICATED = "unauthenticated"
    FORBIDDEN = "forbidden"
    NOT_IMPLEMENTED = "not_implemented"
    RATE_LIMITED = "rate_limited"
    AI_NO_CAPACITY = "ai_no_capacity"
    AI_TIMEOUT = "ai_timeout"


ERROR_STATUS_MAP: dict[ErrorCode, int] = {
    ErrorCode.BAD_REQUEST: 400,
    ErrorCode.UNAUTHENTICATED: 401,
    ErrorCode.FORBIDDEN: 403,
    ErrorCode.NOT_IMPLEMENTED: 501,
    ErrorCode.RATE_LIMITED: 429,
    ErrorCode.AI_NO_CAPACITY: 503,
    ErrorCode.AI_TIMEOUT: 504,
}


class ErrorBody(BaseModel):
    code: str
    message: str
    request_id: str


class ErrorEnvelope(BaseModel):
    error: ErrorBody


class GatewayError(Exception):
    """Application-level error with a stable machine-readable code."""

    def __init__(self, code: ErrorCode, message: str, request_id: str | None = None) -> None:
        self.code = code
        self.message = message
        self.request_id = request_id
        super().__init__(message)


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "unknown")


def error_response(code: ErrorCode, message: str, request_id: str) -> JSONResponse:
    status = ERROR_STATUS_MAP[code]
    body = ErrorEnvelope(
        error=ErrorBody(code=code.value, message=message, request_id=request_id)
    )
    return JSONResponse(status_code=status, content=body.model_dump())


def install_exception_handlers(app: FastAPI) -> None:
    """Register uniform error handlers on the FastAPI app."""

    @app.exception_handler(GatewayError)
    async def gateway_error_handler(request: Request, exc: GatewayError) -> JSONResponse:
        rid = exc.request_id or _request_id(request)
        return error_response(exc.code, exc.message, rid)

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
        if exc.status_code == 401:
            code = ErrorCode.UNAUTHENTICATED
        elif exc.status_code == 403:
            code = ErrorCode.FORBIDDEN
        elif exc.status_code == 429:
            code = ErrorCode.RATE_LIMITED
        elif exc.status_code == 503:
            code = ErrorCode.AI_NO_CAPACITY
        elif exc.status_code == 504:
            code = ErrorCode.AI_TIMEOUT
        elif exc.status_code == 501:
            code = ErrorCode.NOT_IMPLEMENTED
        else:
            code = ErrorCode.BAD_REQUEST
        detail = exc.detail if isinstance(exc.detail, str) else "Request failed"
        return error_response(code, detail, _request_id(request))


def raise_gateway_error(
    code: ErrorCode,
    message: str,
    request: Request | None = None,
) -> None:
    """Convenience helper to raise a GatewayError with request context."""
    rid = _request_id(request) if request else None
    raise GatewayError(code, message, rid)


def envelope_dict(code: str, message: str, request_id: str) -> dict[str, Any]:
    """Build a raw error envelope dict (for tests)."""
    return {"error": {"code": code, "message": message, "request_id": request_id}}
