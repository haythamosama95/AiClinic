"""AI generation endpoint — validation + dispatch skeleton (no inference yet)."""

from __future__ import annotations

from enum import Enum
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator

from gateway.api.errors import ErrorCode, error_response
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity

router = APIRouter(prefix="/v1", tags=["generate"])

MAX_PROMPT_BYTES = 8192
NOT_IMPLEMENTED_MESSAGE = "AI generation is not available in this deployment phase."


class GenerateTask(str, Enum):
    COMMAND = "command"
    PLAN = "plan"
    TEXT = "text"
    CLINICAL_NOTE = "clinical_note"
    ANALYTICS = "analytics"


class PlanMode(str, Enum):
    SINGLE = "single"
    MULTI = "multi"


class GenerateOptions(BaseModel):
    model_config = ConfigDict(extra="ignore")

    stream: bool = False
    confidence_hint: bool = True
    plan_mode: PlanMode = PlanMode.SINGLE


class GenerateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    task: GenerateTask
    prompt: str
    context: dict[str, Any] | None = None
    conversation_id: UUID | None = None
    turn: int | None = Field(default=None, ge=0)
    options: GenerateOptions = Field(default_factory=GenerateOptions)

    @field_validator("prompt")
    @classmethod
    def validate_prompt(cls, value: str) -> str:
        encoded = value.encode("utf-8")
        if not encoded:
            raise ValueError("prompt must not be empty")
        if len(encoded) > MAX_PROMPT_BYTES:
            raise ValueError(f"prompt must be at most {MAX_PROMPT_BYTES} bytes")
        return value


@router.post("/ai/generate")
async def post_generate(
    request: Request,
    body: GenerateRequest,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
    """Validate generation requests; inference not yet implemented."""
    request_id = getattr(request.state, "request_id", "unknown")
    config = request.app.state.config
    options = body.options

    if options.stream and config.streaming_enabled:
        return error_response(
            ErrorCode.NOT_IMPLEMENTED,
            NOT_IMPLEMENTED_MESSAGE,
            request_id,
        )

    return error_response(
        ErrorCode.NOT_IMPLEMENTED,
        NOT_IMPLEMENTED_MESSAGE,
        request_id,
    )
