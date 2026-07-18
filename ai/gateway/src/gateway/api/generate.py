"""AI generation endpoint — scheduling proposals (non-streaming US1 + streaming US2)."""

from __future__ import annotations

import time
from collections.abc import AsyncIterator
from enum import Enum
from typing import Annotated, Any
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator

from gateway.agents.base import Agent
from gateway.agents.scheduling import get_scheduling_agent
from gateway.api.errors import ErrorCode, GatewayError, envelope_dict, error_response
from gateway.api.sse import format_event
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.obs.logging import log_generation_record
from gateway.routing.registry import RunnerRegistry
from gateway.routing.selector import SelectorState, select_runner
from gateway.runners.openai_client import (
    GrammarStreamSession,
    chat_completion_grammar,
    chat_completion_grammar_stream,
)
from gateway.validation.envelope import assemble_envelope
from gateway.validation.schema_check import validate_command_schema, validate_envelope_schema
from gateway.validation.semantic import validate_semantics

router = APIRouter(prefix="/v1", tags=["generate"])

MAX_PROMPT_BYTES = 8192
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


def _select_generation_runner(
    registry: RunnerRegistry,
    request_id: str,
):
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
    return runner_entry, loaded


def _normalize_warnings(parsed: dict[str, Any]) -> list[dict[str, str]]:
    warnings_raw = parsed.get("warnings", [])
    warnings: list[dict[str, str]] = []
    if isinstance(warnings_raw, list):
        for item in warnings_raw:
            if isinstance(item, dict) and "code" in item and "message" in item:
                warnings.append(
                    {"code": str(item["code"]), "message": str(item["message"])}
                )
    return warnings


def _build_envelope_from_parsed(
    *,
    agent: Agent,
    parsed: dict[str, Any],
    context: dict[str, Any],
    request_id: str,
    confidence_threshold: float,
) -> dict[str, Any]:
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

    confidence = float(parsed.get("confidence", 0.0))
    return assemble_envelope(
        command_type=command_type,
        confidence=confidence,
        display_summary=str(parsed.get("display_summary", "")),
        params=params,
        requires_resolution={
            str(key): str(value) for key, value in requires_resolution.items()
        },
        warnings=_normalize_warnings(parsed),
        confidence_threshold=confidence_threshold,
    )


def _log_success(
    *,
    request_id: str,
    agent_name: str,
    model: str,
    digest: str,
    total_seconds: float,
    prompt_tokens: int,
    completion_tokens: int,
    first_token_seconds: float | None,
    caller: CallerIdentity,
    runner_id: str,
    log_verbatim: bool,
) -> None:
    log_generation_record(
        request_id=request_id,
        endpoint="/v1/ai/generate",
        outcome="ok",
        agent=agent_name,
        model=model,
        digest=digest,
        queue_wait_seconds=0.0,
        total_seconds=total_seconds,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        retried=False,
        verbatim=log_verbatim,
        caller_staff_id=caller.staff_id,
        runner_id=runner_id,
        first_token_seconds=first_token_seconds,
    )


def _error_event_payload(exc: GatewayError, request_id: str) -> dict[str, Any]:
    return envelope_dict(exc.code.value, exc.message, exc.request_id or request_id)


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

    runner_entry, loaded = _select_generation_runner(registry, request_id)

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

    envelope = _build_envelope_from_parsed(
        agent=agent,
        parsed=generation.parsed,
        context=context,
        request_id=request_id,
        confidence_threshold=config.confidence_threshold,
    )

    total_seconds = time.perf_counter() - started
    _log_success(
        request_id=request_id,
        agent_name=agent.name,
        model=generation.model,
        digest=generation.digest,
        total_seconds=total_seconds,
        prompt_tokens=generation.prompt_tokens,
        completion_tokens=generation.completion_tokens,
        first_token_seconds=generation.first_token_seconds,
        caller=caller,
        runner_id=runner_entry.id,
        log_verbatim=config.log_verbatim,
    )

    return JSONResponse(status_code=200, content=envelope)


async def _generate_command_streaming(
    *,
    request: Request,
    body: GenerateRequest,
    caller: CallerIdentity,
    request_id: str,
) -> StreamingResponse:
    config = request.app.state.config
    registry: RunnerRegistry = request.app.state.registry
    agent = get_scheduling_agent()
    context = body.context or {}

    async def event_generator() -> AsyncIterator[str]:
        terminal_emitted = False
        runner_entry = None
        started = time.perf_counter()

        try:
            runner_entry, loaded = _select_generation_runner(registry, request_id)
            messages = [
                {"role": "system", "content": agent.system_prompt},
                {"role": "user", "content": agent.build_user_message(body.prompt, context)},
            ]
            format_schema = agent.grammar.to_ollama_format(agent.envelope_schema())
            session: GrammarStreamSession | None = None
            in_command_body = False

            _adjust_in_flight(registry, runner_entry.id, 1)
            try:
                async with httpx.AsyncClient() as http:
                    async for delta, session in chat_completion_grammar_stream(
                        runner_entry.base_url,
                        model=loaded.name,
                        digest=loaded.digest,
                        messages=messages,
                        format_schema=format_schema,
                        timeout_s=float(config.timeout_total_s),
                        client=http,
                    ):
                        chunk = delta.content
                        if in_command_body or not chunk:
                            continue
                        brace = chunk.find("{")
                        if brace == -1:
                            yield format_event("summary", {"delta": chunk})
                        else:
                            prefix = chunk[:brace]
                            if prefix:
                                yield format_event("summary", {"delta": prefix})
                            in_command_body = True
            except (httpx.HTTPError, ValueError) as exc:
                raise GatewayError(
                    ErrorCode.AI_UNUSABLE,
                    f"runner generation failed: {exc}",
                    request_id,
                ) from exc
            finally:
                _adjust_in_flight(registry, runner_entry.id, -1)

            if session is None:
                raise GatewayError(
                    ErrorCode.AI_UNUSABLE,
                    "runner stream produced no command body",
                    request_id,
                )

            try:
                parsed = session.parsed_json_matching_schema(format_schema)
            except ValueError as exc:
                raise GatewayError(
                    ErrorCode.AI_UNUSABLE,
                    f"runner stream produced no valid command body: {exc}",
                    request_id,
                ) from exc

            envelope = _build_envelope_from_parsed(
                agent=agent,
                parsed=parsed,
                context=context,
                request_id=request_id,
                confidence_threshold=config.confidence_threshold,
            )

            total_seconds = time.perf_counter() - started
            _log_success(
                request_id=request_id,
                agent_name=agent.name,
                model=session.model,
                digest=session.digest,
                total_seconds=total_seconds,
                prompt_tokens=session.prompt_tokens,
                completion_tokens=session.completion_tokens,
                first_token_seconds=session.first_token_seconds,
                caller=caller,
                runner_id=runner_entry.id,
                log_verbatim=config.log_verbatim,
            )

            yield format_event("final", envelope)
            terminal_emitted = True
        except GatewayError as exc:
            if not terminal_emitted:
                yield format_event("error", _error_event_payload(exc, request_id))
                terminal_emitted = True
        except Exception as exc:
            if not terminal_emitted:
                wrapped = GatewayError(
                    ErrorCode.AI_UNUSABLE,
                    f"runner generation failed: {exc}",
                    request_id,
                )
                yield format_event("error", _error_event_payload(wrapped, request_id))
                terminal_emitted = True

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        status_code=200,
    )


@router.post("/ai/generate", response_model=None)
async def post_generate(
    request: Request,
    body: GenerateRequest,
    caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse | StreamingResponse:
    """Generate a scheduling command proposal (non-streaming or SSE streaming)."""
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
        return await _generate_command_streaming(
            request=request,
            body=body,
            caller=caller,
            request_id=request_id,
        )

    return await _generate_command_non_streaming(
        request=request,
        body=body,
        caller=caller,
        request_id=request_id,
    )
