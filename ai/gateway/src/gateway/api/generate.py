"""AI generation endpoint — scheduling proposals (non-streaming US1 + streaming US2 + pipeline US3)."""

from __future__ import annotations

import asyncio
import re
import time
from collections.abc import AsyncIterator
from datetime import datetime
from enum import Enum
from typing import Annotated, Any, Self
from uuid import UUID

import httpx
from ai_common.verbose_logging import get_logger, log_request_v2
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from gateway.agents.base import Agent
from gateway.agents.scheduling import get_scheduling_agent
from gateway.agents.scheduling.normalize import normalize_scheduling_envelope
from gateway.api.errors import ErrorCode, GatewayError, envelope_dict, error_response
from gateway.api.sse import format_event
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.obs.logging import log_generation_record, log_record
from gateway.obs.metrics import record_ai_request
from gateway.pipeline.cancel import log_cancelled
from gateway.pipeline.queue import GenerationQueue
from gateway.pipeline.retry import RetryContext, execute_with_retry, should_retry
from gateway.pipeline.timeout import (
    FirstTokenTimeout,
    TimeoutSettings,
    stream_with_first_token_timeout,
)
from gateway.routing.registry import RunnerRegistry, RunnerRegistryEntry
from gateway.routing.selector import SelectorState, select_runner_with_swap
from gateway.runners.openai_client import (
    GenerationResult,
    GrammarStreamSession,
    chat_completion_grammar,
    chat_completion_grammar_stream,
)
from gateway.validation.envelope import assemble_envelope
from gateway.validation.schema_check import validate_command_schema, validate_envelope_schema
from gateway.validation.semantic import validate_semantics

router = APIRouter(prefix="/v1", tags=["generate"])

MAX_PROMPT_BYTES = 8192
_CONTROL_CHAR_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
UNSUPPORTED_TASK_MESSAGE = "Only task='command' is supported in this deployment phase."


def strip_control_characters(value: str) -> str:
    """Remove C0 control characters except tab, LF, and CR."""
    return _CONTROL_CHAR_RE.sub("", value)


def sanitize_context_strings(context: dict[str, Any]) -> dict[str, Any]:
    """Strip control characters from every string value in context."""
    sanitized: dict[str, Any] = {}
    for key, value in context.items():
        if isinstance(value, str):
            sanitized[key] = strip_control_characters(value)
        elif isinstance(value, dict):
            sanitized[key] = sanitize_context_strings(value)
        elif isinstance(value, list):
            sanitized[key] = [
                strip_control_characters(item)
                if isinstance(item, str)
                else sanitize_context_strings(item)
                if isinstance(item, dict)
                else item
                for item in value
            ]
        else:
            sanitized[key] = value
    return sanitized


CAPABILITY_CLASS = "command"
REQUIRED_CAPABILITIES: list[str] = []

_selector_state = SelectorState()
vlog = get_logger(__name__)


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


class GenerationContext(BaseModel):
    """Caller-supplied scheduling context. ``now`` anchors relative date semantics."""

    model_config = ConfigDict(extra="allow")

    now: str

    @field_validator("now")
    @classmethod
    def validate_now(cls, value: str) -> str:
        cleaned = strip_control_characters(value)
        if not cleaned:
            raise ValueError("context.now must not be empty")
        try:
            parsed = datetime.fromisoformat(cleaned)
        except ValueError as exc:
            raise ValueError("context.now must be a valid ISO-8601 timestamp") from exc
        if parsed.tzinfo is None:
            raise ValueError("context.now must include a timezone offset")
        return cleaned


class GenerateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    task: GenerateTask
    prompt: str
    context: GenerationContext
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
        return strip_control_characters(value)

    @model_validator(mode="after")
    def sanitize_context(self) -> Self:
        ctx_dict = sanitize_context_strings(self.context.model_dump())
        object.__setattr__(self, "context", GenerationContext.model_validate(ctx_dict))
        return self

    def context_dict(self) -> dict[str, Any]:
        return self.context.model_dump()


def _adjust_in_flight(registry: RunnerRegistry, runner_id: str, delta: int) -> None:
    entry = registry.get(runner_id)
    if entry is None:
        return
    registry.update_entry(runner_id, in_flight=max(0, entry.in_flight + delta))


async def _select_generation_runner(
    registry: RunnerRegistry,
    config,
    request_id: str,
    *,
    http_client: httpx.AsyncClient | None = None,
) -> tuple[RunnerRegistryEntry, Any]:
    vlog.v0("Selecting runner for generation", request_id=request_id)
    runner_entry = await select_runner_with_swap(
        registry,
        required_capabilities=REQUIRED_CAPABILITIES,
        round_robin_state=_selector_state,
        config=config,
        request_id=request_id,
        client=http_client,
    )

    loaded = runner_entry.loaded_model
    if loaded is None:
        raise GatewayError(
            ErrorCode.AI_NO_CAPACITY,
            "selected runner has no loaded model",
            request_id,
        )
    vlog.v1(
        "Selected runner for generation",
        request_id=request_id,
        runner_id=runner_entry.id,
        model=loaded.name,
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
    vlog.v0("Building command envelope from model output", request_id=request_id)
    parsed = normalize_scheduling_envelope(parsed)
    command_type = str(parsed.get("command_type", ""))
    vlog.v1("Parsing model output for envelope", request_id=request_id, command_type=command_type)

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
    envelope = assemble_envelope(
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
    vlog.v0("Built command envelope from model output", request_id=request_id, command_type=command_type)
    return envelope


def _log_success(
    *,
    request_id: str,
    agent_name: str,
    model: str,
    digest: str,
    queue_wait_seconds: float,
    total_seconds: float,
    prompt_tokens: int,
    completion_tokens: int,
    first_token_seconds: float | None,
    caller: CallerIdentity,
    runner_id: str,
    log_verbatim: bool,
    retried: bool,
    prompt: str,
    context: dict[str, Any],
) -> None:
    log_generation_record(
        request_id=request_id,
        endpoint="/v1/ai/generate",
        outcome="ok",
        agent=agent_name,
        model=model,
        digest=digest,
        queue_wait_seconds=queue_wait_seconds,
        total_seconds=total_seconds,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        retried=retried,
        verbatim=log_verbatim,
        caller_staff_id=caller.staff_id,
        runner_id=runner_id,
        first_token_seconds=first_token_seconds,
        prompt=prompt,
        context=context,
    )
    record_ai_request("command", "ok")


def _log_failure(
    *,
    request_id: str,
    outcome: str,
    error_code: str,
    caller: CallerIdentity,
    runner_id: str | None = None,
    queue_wait_seconds: float = 0.0,
    total_seconds: float | None = None,
    retried: bool = False,
) -> None:
    log_record(
        request_id=request_id,
        endpoint="/v1/ai/generate",
        outcome=outcome,
        error_code=error_code,
        caller_staff_id=caller.staff_id,
        runner_id=runner_id,
        queue_wait_seconds=queue_wait_seconds,
        total_seconds=total_seconds,
        retried=retried,
    )
    record_ai_request("command", outcome)


def _error_event_payload(exc: GatewayError, request_id: str) -> dict[str, Any]:
    return envelope_dict(exc.code.value, exc.message, exc.request_id or request_id)


async def _run_non_streaming_generation(
    *,
    runner: RunnerRegistryEntry,
    loaded,
    messages: list[dict[str, str]],
    format_schema: dict[str, Any],
    settings: TimeoutSettings,
    request_id: str,
    config,
    registry: RunnerRegistry,
    http: httpx.AsyncClient,
) -> GenerationResult:
    vlog.v0(
        "Running non-streaming generation on runner",
        request_id=request_id,
        runner_id=runner.id,
        model=loaded.name,
    )
    _adjust_in_flight(registry, runner.id, 1)
    try:
        async def _call_runner() -> GenerationResult:
            try:
                return await chat_completion_grammar(
                    runner.base_url,
                    model=loaded.name,
                    digest=loaded.digest,
                    messages=messages,
                    format_schema=format_schema,
                    timeout_s=float(config.timeout_total_s),
                    client=http,
                )
            except ValueError as exc:
                raise GatewayError(
                    ErrorCode.AI_UNUSABLE,
                    f"runner generation failed: {exc}",
                    request_id,
                ) from exc

        try:
            result = await asyncio.wait_for(
                _call_runner(),
                timeout=settings.first_token_s,
            )
            vlog.v1(
                "Non-streaming generation completed",
                request_id=request_id,
                runner_id=runner.id,
                prompt_tokens=result.prompt_tokens,
                completion_tokens=result.completion_tokens,
            )
            return result
        except TimeoutError as exc:
            vlog.v0("Non-streaming generation timed out waiting for first token", request_id=request_id, runner_id=runner.id)
            raise FirstTokenTimeout(request_id) from exc
    finally:
        _adjust_in_flight(registry, runner.id, -1)


async def _generate_command_non_streaming(
    *,
    request: Request,
    body: GenerateRequest,
    caller: CallerIdentity,
    request_id: str,
) -> JSONResponse:
    vlog.v0("Starting non-streaming command generation", request_id=request_id)
    config = request.app.state.config
    registry: RunnerRegistry = request.app.state.registry
    queue: GenerationQueue = request.app.state.generation_queue
    agent = get_scheduling_agent()
    context = body.context_dict()
    settings = TimeoutSettings.from_config(config)

    async with queue.acquire(
        capability=CAPABILITY_CLASS,
        request_id=request_id,
        caller_staff_id=caller.staff_id,
    ) as slot:
        started = time.perf_counter()
        retried = False
        runner_entry: RunnerRegistryEntry | None = None

        try:
            messages = agent.compose_chat_messages(body.prompt, context)
            format_schema = agent.grammar.to_ollama_format(agent.envelope_schema())

            async with httpx.AsyncClient() as http:
                runner_entry, loaded = await _select_generation_runner(
                    registry, config, request_id, http_client=http
                )

                retry_ctx = RetryContext(request_id=request_id)

                async def call_runner(runner: RunnerRegistryEntry) -> GenerationResult:
                    nonlocal runner_entry, loaded
                    runner_entry = runner
                    loaded = runner.loaded_model
                    if loaded is None:
                        raise GatewayError(
                            ErrorCode.AI_NO_CAPACITY,
                            "selected runner has no loaded model",
                            request_id,
                        )
                    return await _run_non_streaming_generation(
                        runner=runner,
                        loaded=loaded,
                        messages=messages,
                        format_schema=format_schema,
                        settings=settings,
                        request_id=request_id,
                        config=config,
                        registry=registry,
                        http=http,
                    )

                generation, runner_entry, retried = await execute_with_retry(
                    call_runner,
                    initial_runner=runner_entry,
                    all_entries=registry.snapshot(),
                    required_capabilities=REQUIRED_CAPABILITIES,
                    ctx=retry_ctx,
                    caller_staff_id=caller.staff_id,
                )

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
                queue_wait_seconds=slot.queue_wait_seconds,
                total_seconds=total_seconds,
                prompt_tokens=generation.prompt_tokens,
                completion_tokens=generation.completion_tokens,
                first_token_seconds=generation.first_token_seconds,
                caller=caller,
                runner_id=runner_entry.id,
                log_verbatim=config.log_verbatim,
                retried=retried,
                prompt=body.prompt,
                context=context,
            )

            vlog.v0(
                "Non-streaming command generation succeeded",
                request_id=request_id,
                runner_id=runner_entry.id,
                command_type=envelope.get("command_type"),
            )
            return JSONResponse(status_code=200, content=envelope)
        except asyncio.CancelledError:
            vlog.v0("Non-streaming command generation cancelled", request_id=request_id)
            log_cancelled(
                request_id=request_id,
                caller_staff_id=caller.staff_id,
                runner_id=runner_entry.id if runner_entry else None,
                agent=agent.name,
                queue_wait_seconds=slot.queue_wait_seconds,
                total_seconds=time.perf_counter() - started,
            )
            record_ai_request("command", "cancelled")
            raise
        except GatewayError as exc:
            vlog.v0(
                "Non-streaming command generation failed",
                request_id=request_id,
                error_code=exc.code.value,
            )
            _log_failure(
                request_id=request_id,
                outcome="error",
                error_code=exc.code.value,
                caller=caller,
                runner_id=runner_entry.id if runner_entry else None,
                queue_wait_seconds=slot.queue_wait_seconds,
                total_seconds=time.perf_counter() - started,
                retried=retried,
            )
            raise


async def _generate_command_streaming(
    *,
    request: Request,
    body: GenerateRequest,
    caller: CallerIdentity,
    request_id: str,
) -> StreamingResponse:
    vlog.v0("Starting streaming command generation", request_id=request_id)
    config = request.app.state.config
    registry: RunnerRegistry = request.app.state.registry
    queue: GenerationQueue = request.app.state.generation_queue
    agent = get_scheduling_agent()
    context = body.context_dict()
    settings = TimeoutSettings.from_config(config)

    async def event_generator() -> AsyncIterator[str]:
        vlog.v2("Starting SSE event generator", request_id=request_id)
        terminal_emitted = False
        runner_entry: RunnerRegistryEntry | None = None
        started = time.perf_counter()
        retried = False
        partial_stream_sent = False

        try:
            async with queue.acquire(
                capability=CAPABILITY_CLASS,
                request_id=request_id,
                caller_staff_id=caller.staff_id,
            ) as slot:
                messages = agent.compose_chat_messages(body.prompt, context)
                format_schema = agent.grammar.to_ollama_format(agent.envelope_schema())

                async with httpx.AsyncClient() as http:
                    runner_entry, loaded = await _select_generation_runner(
                        registry, config, request_id, http_client=http
                    )

                    session: GrammarStreamSession | None = None
                    in_command_body = False
                    client_bytes_sent = False
                    retry_ctx = RetryContext(request_id=request_id)
                    current_runner = runner_entry
                    current_loaded = loaded

                    for attempt in range(2):
                        vlog.v2(
                            "Streaming generation attempt",
                            request_id=request_id,
                            attempt=attempt,
                            runner_id=current_runner.id,
                        )
                        try:
                            _adjust_in_flight(registry, current_runner.id, 1)
                            try:
                                stream = chat_completion_grammar_stream(
                                    current_runner.base_url,
                                    model=current_loaded.name,
                                    digest=current_loaded.digest,
                                    messages=messages,
                                    format_schema=format_schema,
                                    timeout_s=float(config.timeout_total_s),
                                    client=http,
                                )
                                timed_stream = stream_with_first_token_timeout(
                                    stream,
                                    settings=settings,
                                    runner_status=current_runner.status,
                                    request_id=request_id,
                                )

                                async for delta, active_session in timed_stream:
                                    session = active_session
                                    chunk = delta.content
                                    vlog.v2(
                                        "Received streaming delta from runner",
                                        request_id=request_id,
                                        chunk_len=len(chunk) if chunk else 0,
                                        in_command_body=in_command_body,
                                    )
                                    if chunk:
                                        partial_stream_sent = True
                                        retry_ctx = RetryContext(
                                            request_id=request_id,
                                            partial_stream_sent=True,
                                            retried=retried,
                                        )
                                    if in_command_body or not chunk:
                                        continue
                                    brace = chunk.find("{")
                                    if brace == -1:
                                        yield format_event("summary", {"delta": chunk})
                                        client_bytes_sent = True
                                    else:
                                        prefix = chunk[:brace]
                                        if prefix:
                                            yield format_event("summary", {"delta": prefix})
                                            client_bytes_sent = True
                                        in_command_body = True
                            finally:
                                _adjust_in_flight(registry, current_runner.id, -1)
                            break
                        except BaseException as exc:
                            if session is not None and session.content:
                                partial_stream_sent = True
                                retry_ctx = RetryContext(
                                    request_id=request_id,
                                    partial_stream_sent=True,
                                    retried=retried,
                                )
                            if client_bytes_sent:
                                partial_stream_sent = True
                                retry_ctx = RetryContext(
                                    request_id=request_id,
                                    partial_stream_sent=True,
                                    retried=retried,
                                )
                            if (
                                attempt == 0
                                and should_retry(retry_ctx, exc)
                                and not partial_stream_sent
                            ):
                                vlog.v1(
                                    "Retrying streaming generation on alternate runner",
                                    request_id=request_id,
                                    failed_runner_id=current_runner.id,
                                )
                                from gateway.pipeline.retry import select_retry_runner

                                retry_runner = select_retry_runner(
                                    registry.snapshot(),
                                    failed_runner_id=current_runner.id,
                                    required_capabilities=REQUIRED_CAPABILITIES,
                                )
                                if retry_runner is None:
                                    raise
                                retried = True
                                current_runner = retry_runner
                                current_loaded = retry_runner.loaded_model
                                if current_loaded is None:
                                    raise GatewayError(
                                        ErrorCode.AI_NO_CAPACITY,
                                        "retry runner has no loaded model",
                                        request_id,
                                    ) from exc
                                runner_entry = current_runner
                                in_command_body = False
                                session = None
                                continue
                            raise

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
                        queue_wait_seconds=slot.queue_wait_seconds,
                        total_seconds=total_seconds,
                        prompt_tokens=session.prompt_tokens,
                        completion_tokens=session.completion_tokens,
                        first_token_seconds=session.first_token_seconds,
                        caller=caller,
                        runner_id=runner_entry.id,
                        log_verbatim=config.log_verbatim,
                        retried=retried,
                        prompt=body.prompt,
                        context=context,
                    )

                    vlog.v0(
                        "Streaming command generation succeeded",
                        request_id=request_id,
                        runner_id=runner_entry.id,
                        command_type=envelope.get("command_type"),
                    )
                    yield format_event("final", envelope)
                    terminal_emitted = True
        except asyncio.CancelledError:
            vlog.v0("Streaming command generation cancelled", request_id=request_id)
            log_cancelled(
                request_id=request_id,
                caller_staff_id=caller.staff_id,
                runner_id=runner_entry.id if runner_entry else None,
                agent=agent.name,
                queue_wait_seconds=0.0,
                total_seconds=time.perf_counter() - started,
            )
            record_ai_request("command", "cancelled")
            raise
        except GatewayError as exc:
            vlog.v0(
                "Streaming command generation failed",
                request_id=request_id,
                error_code=exc.code.value,
            )
            if not terminal_emitted:
                yield format_event("error", _error_event_payload(exc, request_id))
                terminal_emitted = True
            _log_failure(
                request_id=request_id,
                outcome="error",
                error_code=exc.code.value,
                caller=caller,
                runner_id=runner_entry.id if runner_entry else None,
                total_seconds=time.perf_counter() - started,
                retried=retried,
            )
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
    vlog.v0(
        "Received AI generation request",
        request_id=request_id,
        task=body.task.value,
        stream=options.stream,
        caller_staff_id=caller.staff_id,
    )
    vlog.v1(
        "AI generation request details",
        request_id=request_id,
        prompt=body.prompt,
        context=body.context_dict(),
        conversation_id=str(body.conversation_id) if body.conversation_id else None,
    )
    log_request_v2(
        vlog,
        "Received generation",
        body.model_dump(mode="json"),
        request_id=request_id,
    )

    if body.task != GenerateTask.COMMAND:
        vlog.v0("Rejected unsupported generation task", request_id=request_id, task=body.task.value)
        return error_response(
            ErrorCode.NOT_IMPLEMENTED,
            UNSUPPORTED_TASK_MESSAGE,
            request_id,
        )

    if options.stream and config.streaming_enabled:
        vlog.v1("Routing generation request to streaming handler", request_id=request_id)
        return await _generate_command_streaming(
            request=request,
            body=body,
            caller=caller,
            request_id=request_id,
        )

    vlog.v1("Routing generation request to non-streaming handler", request_id=request_id)
    return await _generate_command_non_streaming(
        request=request,
        body=body,
        caller=caller,
        request_id=request_id,
    )
