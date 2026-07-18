"""JSON Schema to Ollama ``format`` and GBNF grammar mapping."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from gateway.agents.scheduling.schemas import JSON_SCHEMA_DRAFT


class SchedulingGrammarMapper:
    """Maps scheduling JSON schemas to Ollama ``format`` and GBNF equivalents."""

    def to_ollama_format(self, schema: dict[str, Any]) -> dict[str, Any]:
        """Return the JSON schema for Ollama's ``format`` parameter."""
        formatted = deepcopy(schema)
        formatted["$schema"] = JSON_SCHEMA_DRAFT
        return formatted

    def to_gbnf(self, schema: dict[str, Any]) -> str:
        """Return an equivalent GBNF grammar string for ``llama-server``."""
        return to_gbnf(schema)


def to_ollama_format(schema: dict[str, Any]) -> dict[str, Any]:
    """Return the JSON schema for Ollama's ``format`` parameter."""
    return SchedulingGrammarMapper().to_ollama_format(schema)


def to_gbnf(schema: dict[str, Any]) -> str:
    """Translate a JSON schema to an equivalent GBNF string (llama-server alternative).

    Minimal translator for tests — supports objects, required string fields, enums,
    and const values used by the scheduling envelope schema.
    """
    lines: list[str] = ["root ::= ws object ws", "ws ::= [ \\t\\n\\r]*"]

    def _rule_name(ref: str) -> str:
        return ref.rsplit("/", 1)[-1].replace("_params", "_rule")

    defs = schema.get("$defs", {})

    def _object_rule(name: str, spec: dict[str, Any]) -> list[str]:
        props = spec.get("properties", {})
        required = spec.get("required", list(props.keys()))
        parts: list[str] = []
        for idx, field in enumerate(required):
            prop_spec = props[field]
            if "$ref" in prop_spec:
                ref_rule = _rule_name(prop_spec["$ref"])
                segment = f'"{field}" ws ":" ws {ref_rule}'
            elif prop_spec.get("type") == "string":
                segment = f'"{field}" ws ":" ws string-value'
            elif prop_spec.get("type") == "number":
                segment = f'"{field}" ws ":" ws number-value'
            elif prop_spec.get("type") == "boolean":
                segment = f'"{field}" ws ":" ws boolean-value'
            elif prop_spec.get("type") == "object":
                segment = f'"{field}" ws ":" ws object'
            elif prop_spec.get("type") == "array":
                segment = f'"{field}" ws ":" ws array'
            else:
                segment = f'"{field}" ws ":" ws value'
            if idx < len(required) - 1:
                segment += ' ws "," ws'
            parts.append(segment)
        inner = ' ws "{" ws ' + " ws ".join(parts) + ' ws "}" ws'
        return [f"object ::= {inner}" if name == "object" else f"{name} ::= {inner}"]

    for def_name, def_spec in defs.items():
        rule = _rule_name(f"#/$defs/{def_name}")
        lines.extend(_object_rule(rule, def_spec))

    lines.extend(_object_rule("object", schema))
    lines.extend(
        [
            'string-value ::= ws "\\"" [^\\"]* "\\"" ws',
            'number-value ::= ws [0-9]+ ( "." [0-9]+ )? ws',
            'boolean-value ::= ws "true" ws | ws "false" ws',
            'array ::= ws "[" ws ( object ( ws "," ws object )* )? ws "]" ws',
            "value ::= string-value | number-value | boolean-value | object | array",
        ]
    )
    return "\n".join(lines)
