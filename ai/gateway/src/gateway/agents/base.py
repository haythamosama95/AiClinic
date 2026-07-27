"""Agent interface for prompt, grammar, schema, and semantic validation."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Mapping
from typing import Any, Protocol, runtime_checkable


@runtime_checkable
class GrammarMapper(Protocol):
    """Maps command JSON schemas to runner-specific constrained-decoding formats."""

    def to_ollama_format(self, schema: dict[str, Any]) -> dict[str, Any]:
        """Return the JSON schema for Ollama's ``format`` parameter."""
        ...

    def to_gbnf(self, schema: dict[str, Any]) -> str:
        """Return an equivalent GBNF grammar string (llama-server alternative)."""
        ...


@runtime_checkable
class SemanticValidator(Protocol):
    """Per-command semantic checks beyond structural schema validation."""

    def validate(self, parsed: dict[str, Any], *, context: dict[str, Any]) -> None:
        """Raise ``GatewayError`` (``ai_unusable``) when validation fails."""
        ...


class Agent(ABC):
    """Scheduling and future agents implement this contract."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Stable agent identifier (e.g. ``scheduling``)."""

    @property
    @abstractmethod
    def system_prompt(self) -> str:
        """Immutable server-side instruction region (no request-derived content)."""

    @property
    @abstractmethod
    def grammar(self) -> GrammarMapper:
        """Grammar mapping for constrained decoding."""

    @property
    @abstractmethod
    def command_schemas(self) -> Mapping[str, dict[str, Any]]:
        """Per-command JSON Schema (Draft 2020-12) keyed by ``command_type``."""

    @property
    @abstractmethod
    def command_catalog(self) -> frozenset[str]:
        """Registered ``command_type`` values this agent may emit."""

    @property
    @abstractmethod
    def semantic_validators(self) -> Mapping[str, SemanticValidator]:
        """Per-command semantic validators keyed by ``command_type``."""

    def envelope_schema(self) -> dict[str, Any]:
        """Top-level scheduling envelope schema sent to the runner ``format`` field."""
        raise NotImplementedError
