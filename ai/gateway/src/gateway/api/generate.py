"""AI generation endpoint — non-streaming scheduling proposals (US1)."""

from __future__ import annotations

import time
from enum import Enum
from typing import Annotated, Any
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator

from gateway.agents.scheduling import get_scheduling_agent
from gateway.api.errors import ErrorCode, GatewayError, error_response
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.obs.logging import log_generation_record
from gateway.routing.registry import RunnerRegistry
from gateway.routing.selector import SelectorState, select_runner
from gateway.runners.openai_client import chat_completion_grammar
from gateway.validation.envelope import assemble_envelope
from gateway.validation.schema_check import validate_command_schema, validate_envelope_schema
from gateway.validation.semantic import validate_semantics

router = APIRouter(prefix="/v1", tags=["generate"])

MAX_PROMPT_BYTES = 8192
STREAMING_NOT_IMPLEMENTED_MESSAGE = (
    "SSE streaming generation is not available in this deployment phase."
)
UNSUPPORTED_TASK_MESSAGE = "Only task='command' is supported in this deployment phase."

_selector_state = SelectorState()


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


def _adjust_in_flight(registry: RunnerRegistry, runner_id: str, delta: int) -> None:
    entry = registry.get(runner_id)
    if entry is None:
        return
    registry.update_entry(runner_id, in_flight=max(0, entry.in_flight + delta))


async def _generate_command_non_streaming(
    *,
    request: Request,
    body: GenerateRequest,
    caller: CallerIdentity,
    request_id: str,
) -> JSONResponse:
    config = request.app.state.config
    registry: RunnerRegistry = request.app.state.registry
    agent = get_scheduling_agent()
    context = body.context or {}

    runner_entry = select_runner(
        registry,
        required_capabilities=[],
        round_robin_state=_selector_state,
    )
    if runner_entry is None:
        raise GatewayError(
            ErrorCode.AI_NO_CAPACITY,
            "no healthy runner available for generation",
            request_id,
        )

    loaded = runner_entry.loaded_model
    if loaded is None:
        raise GatewayError(
            ErrorCode.AI_NO_CAPACITY,
            "selected runner has no loaded model",
            request_id,
        )

    messages = [
        {"role": "system", "content": agent.system_prompt},
        {"role": "user", "content": agent.build_user_message(body.prompt, context)},
    ]
    format_schema = agent.grammar.to_ollama_format(agent.envelope_schema())

    started = time.perf_counter()
    _adjust_in_flight(registry, runner_entry.id, 1)
    try:
        async with httpx.AsyncClient() as http:
            generation = await chat_completion_grammar(
                runner_entry.base_url,
                model=loaded.name,
                digest=loaded.digest,
                messages=messages,
                format_schema=format_schema,
                timeout_s=float(config.timeout_total_s),
                client=http,
            )
    except (httpx.HTTPError, ValueError) as exc:
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"runner generation failed: {exc}",
            request_id,
        ) from exc
    finally:
        _adjust_in_flight(registry, runner_entry.id, -1)

    parsed = generation.parsed
    command_type = str(parsed.get("command_type", ""))

    validate_envelope_schema(
        payload=parsed,
        schema=agent.envelope_schema(),
        request_id=request_id,
    )

    params = parsed.get("params", {})
    if not isinstance(params, dict):
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            "params must be an object",
            request_id,
        )

    command_schema = agent.command_schemas.get(command_type)
    if command_schema is None:
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"unknown command_type {command_type!r}",
            request_id,
        )

    validate_command_schema(
        command_type=command_type,
        payload=params,
        schema=command_schema,
        request_id=request_id,
    )
    validate_semantics(
        agent=agent,
        command_type=command_type,
        parsed=parsed,
        context=context,
        request_id=request_id,
    )

    requires_resolution = parsed.get("requires_resolution", {})
    if not isinstance(requires_resolution, dict):
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            "requires_resolution must be an object",
            request_id,
        )

    warnings_raw = parsed.get("warnings", [])
    warnings: list[dict[str, str]] = []
    if isinstance(warnings_raw, list):
        for item in warnings_raw:
            if isinstance(item, dict) and "code" in item and "message" in item:
                warnings.append(
                    {"code": str(item["code"]), "message": str(item["message"])}
                )

    confidence = float(parsed.get("confidence", 0.0))
    envelope = assemble_envelope(
        command_type=command_type,
        confidence=confidence,
        display_summary=str(parsed.get("display_summary", "")),
        params=params,
        requires_resolution={
            str(key): str(value) for key, value in requires_resolution.items()
        },
        warnings=warnings,
        confidence_threshold=config.confidence_threshold,
    )

    total_seconds = time.perf_counter() - started
    log_generation_record(
        request_id=request_id,
        endpoint="/v1/ai/generate",
        outcome="ok",
        agent=agent.name,
        model=generation.model,
        digest=generation.digest,
        queue_wait_seconds=0.0,
        total_seconds=total_seconds,
        prompt_tokens=generation.prompt_tokens,
        completion_tokens=generation.completion_tokens,
        retried=False,
        verbatim=config.log_verbatim,
        caller_staff_id=caller.staff_id,
        runner_id=runner_entry.id,
        first_token_seconds=generation.first_token_seconds,
    )

    return JSONResponse(status_code=200, content=envelope)


@router.post("/ai/generate")
async def post_generate(
    request: Request,
    body: GenerateRequest,
    caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
    """Generate a scheduling command proposal (non-streaming US1 path)."""
    request_id = getattr(request.state, "request_id", "unknown")
    config = request.app.state.config
    options = body.options

    if body.task != GenerateTask.COMMAND:
        return error_response(
            ErrorCode.NOT_IMPLEMENTED,
            UNSUPPORTED_TASK_MESSAGE,
            request_id,
        )

    if options.stream and config.streaming_enabled:
        return error_response(
            ErrorCode.NOT_IMPLEMENTED,
            STREAMING_NOT_IMPLEMENTED_MESSAGE,
            request_id,
        )

    return await _generate_command_non_streaming(
        request=request,
        body=body,
        caller=caller,
        request_id=request_id,
    )
