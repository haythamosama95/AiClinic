"""Defense-in-depth validation and Command Protocol envelope assembly."""

from gateway.validation.envelope import assemble_envelope
from gateway.validation.schema_check import validate_command_schema
from gateway.validation.semantic import validate_semantics

__all__ = ["assemble_envelope", "validate_command_schema", "validate_semantics"]
