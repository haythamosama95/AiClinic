import type { EntityDef } from "./types";
import { parseJsonField, requireValue } from "./types";

export const CLINIC_ENTITIES: EntityDef[] = [
  {
    id: "clinic.health",
    category: "clinic",
    title: "Health",
    description: "GET /health — build + environment identity.",
    mode: "proxy",
    fields: [],
    buildRequest: () => ({
      mode: "proxy",
      method: "GET",
      path: "/health",
      auth: "none",
    }),
  },
  {
    id: "clinic.decode-aat",
    category: "clinic",
    title: "Decode AAT claims",
    description:
      "Local JWS payload decode (iss, aud, sub, org, branch, role, scopes, jti, ver, kid). Does not verify signature.",
    mode: "local",
    fields: [
      {
        name: "aat",
        label: "AAT",
        kind: "password",
        required: true,
        fromConnection: "aat",
        help: "Uses connection strip AAT when blank.",
      },
    ],
    buildRequest: (values) => ({
      mode: "local",
      handler: "decode-aat",
      input: { aat: values.aat?.trim() ?? "" },
    }),
  },
  {
    id: "clinic.get-request",
    category: "clinic",
    title: "Get request",
    description: "GET /v1/requests/{reference} with AAT.",
    mode: "proxy",
    fields: [
      {
        name: "reference",
        label: "Request reference",
        kind: "text",
        required: true,
        placeholder: "req_…",
      },
      {
        name: "aat",
        label: "AAT override",
        kind: "password",
        fromConnection: "aat",
        help: "Blank → connection strip AAT.",
      },
    ],
    buildRequest: (values) => {
      const reference = encodeURIComponent(requireValue(values, "reference"));
      return {
        mode: "proxy",
        method: "GET",
        path: `/v1/requests/${reference}`,
        auth: "aat",
        headers: values.aat?.trim()
          ? { "x-ops-aat-override": values.aat.trim() }
          : undefined,
      };
    },
  },
  {
    id: "clinic.submit",
    category: "clinic",
    title: "Submit request (SSE)",
    description:
      "POST /v1/requests — live Worker orchestrator (guard → admit → journal → stream → credit). Streams SSE to one terminal event.",
    mode: "proxy",
    fields: [
      {
        name: "idempotency_key",
        label: "x-idempotency-key",
        kind: "text",
        required: true,
      },
      {
        name: "capability_version_header",
        label: "x-capability-version",
        kind: "text",
        required: true,
        placeholder: "1.0.0",
      },
      {
        name: "trace_id",
        label: "x-trace-id (optional)",
        kind: "text",
      },
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
        defaultValue: "clinic.visit_summary",
      },
      {
        name: "capability_version",
        label: "capability_version (body)",
        kind: "text",
        required: true,
        defaultValue: "1.0.0",
      },
      {
        name: "user_intent",
        label: "user_intent",
        kind: "textarea",
        required: true,
      },
      {
        name: "context",
        label: "context (JSON object)",
        kind: "json",
        defaultValue: "{}",
      },
      {
        name: "conversation_id",
        label: "conversation_id (optional)",
        kind: "text",
      },
      {
        name: "turn_ordinal",
        label: "turn_ordinal (optional)",
        kind: "number",
      },
      {
        name: "transcript",
        label: "transcript (JSON, optional)",
        kind: "json",
        placeholder: "[]",
      },
      {
        name: "aat",
        label: "AAT override",
        kind: "password",
        fromConnection: "aat",
      },
    ],
    buildRequest: (values) => {
      const body: Record<string, unknown> = {
        capability_id: requireValue(values, "capability_id"),
        capability_version: requireValue(values, "capability_version"),
        user_intent: requireValue(values, "user_intent"),
      };
      const context = parseJsonField(values.context ?? "", "context");
      if (context !== undefined) body.context = context;
      if (values.conversation_id?.trim()) {
        body.conversation_id = values.conversation_id.trim();
      }
      if (values.turn_ordinal?.trim()) {
        body.turn_ordinal = Number(values.turn_ordinal);
      }
      const transcript = parseJsonField(values.transcript ?? "", "transcript");
      if (transcript !== undefined) body.transcript = transcript;

      const headers: Record<string, string> = {
        "content-type": "application/json",
        "x-idempotency-key": requireValue(values, "idempotency_key"),
        "x-capability-version": requireValue(
          values,
          "capability_version_header",
        ),
      };
      if (values.trace_id?.trim()) {
        headers["x-trace-id"] = values.trace_id.trim();
      }
      if (values.aat?.trim()) {
        headers["x-ops-aat-override"] = values.aat.trim();
      }

      return {
        mode: "proxy",
        method: "POST",
        path: "/v1/requests",
        auth: "aat",
        headers,
        body: JSON.stringify(body),
      };
    },
  },
  {
    id: "clinic.discovery",
    category: "clinic",
    title: "Capability discovery",
    description:
      "GET /v1/capabilities — AAT-authenticated discovery of granted active/deprecated manifests. Supports If-None-Match → 304.",
    mode: "proxy",
    fields: [
      {
        name: "if_none_match",
        label: "If-None-Match (optional ETag)",
        kind: "text",
        placeholder: '"abc…"',
        help: "Quoted ETag from a prior discovery response for conditional revalidation.",
      },
      {
        name: "aat",
        label: "AAT override",
        kind: "password",
        fromConnection: "aat",
        help: "Blank → connection strip AAT.",
      },
    ],
    buildRequest: (values) => {
      const headers: Record<string, string> = {};
      if (values.if_none_match?.trim()) {
        headers["if-none-match"] = values.if_none_match.trim();
      }
      if (values.aat?.trim()) {
        headers["x-ops-aat-override"] = values.aat.trim();
      }
      return {
        mode: "proxy",
        method: "GET",
        path: "/v1/capabilities",
        auth: "aat",
        headers: Object.keys(headers).length > 0 ? headers : undefined,
      };
    },
  },
];
