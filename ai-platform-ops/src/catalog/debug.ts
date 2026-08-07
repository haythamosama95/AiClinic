import type { EntityDef } from "./types";
import { parseJsonField, requireValue } from "./types";

export const DEBUG_ENTITIES: EntityDef[] = [
  {
    id: "debug.compose",
    category: "debug",
    title: "Compose preview",
    description:
      "composeRequest — capability id/version + context → canonical request preview (local).",
    mode: "local",
    fields: [
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
        defaultValue: "clinic.visit_summary",
      },
      {
        name: "capability_version",
        label: "capability_version",
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
        name: "filtered_context",
        label: "filtered_context (JSON object)",
        kind: "json",
        required: true,
        defaultValue: "{}",
      },
      {
        name: "request_reference",
        label: "request_reference",
        kind: "text",
        required: true,
      },
      {
        name: "installation_id",
        label: "principal.installation_id",
        kind: "text",
        required: true,
      },
      {
        name: "org_id",
        label: "principal.org",
        kind: "text",
        required: true,
      },
      {
        name: "branch_id",
        label: "principal.branch",
        kind: "text",
        required: true,
      },
      {
        name: "actor_id",
        label: "principal.sub",
        kind: "text",
        required: true,
      },
      {
        name: "role",
        label: "principal.role",
        kind: "text",
        required: true,
        defaultValue: "clinician",
      },
      {
        name: "stream_flag",
        label: "stream_flag",
        kind: "checkbox",
        defaultValue: true,
      },
      {
        name: "transcript",
        label: "transcript (JSON, optional)",
        kind: "json",
      },
    ],
    buildRequest: (values) => ({
      mode: "local",
      handler: "compose",
      input: {
        capability_id: requireValue(values, "capability_id"),
        capability_version: requireValue(values, "capability_version"),
        user_intent: requireValue(values, "user_intent"),
        filtered_context:
          parseJsonField(
            requireValue(values, "filtered_context"),
            "filtered_context",
          ) ?? {},
        request_reference: requireValue(values, "request_reference"),
        principal: {
          installationId: requireValue(values, "installation_id"),
          orgId: requireValue(values, "org_id"),
          branchId: requireValue(values, "branch_id"),
          actorId: requireValue(values, "actor_id"),
          role: requireValue(values, "role"),
        },
        stream_flag: values.stream_flag === "true",
        transcript: parseJsonField(values.transcript ?? "", "transcript"),
      },
    }),
  },
  {
    id: "debug.context-validate",
    category: "debug",
    title: "Context validate",
    description: "validateContext / validateKey against published shapes.",
    mode: "local",
    fields: [
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
        defaultValue: "clinic.visit_summary",
      },
      {
        name: "capability_version",
        label: "capability_version",
        kind: "text",
        required: true,
        defaultValue: "1.0.0",
      },
      {
        name: "context",
        label: "context (JSON object)",
        kind: "json",
        required: true,
        defaultValue: "{}",
      },
      {
        name: "key",
        label: "single key to validate (optional)",
        kind: "text",
        help: "If set, also runs validateKey on this key.",
      },
    ],
    buildRequest: (values) => ({
      mode: "local",
      handler: "context-validate",
      input: {
        capability_id: requireValue(values, "capability_id"),
        capability_version: requireValue(values, "capability_version"),
        context:
          parseJsonField(requireValue(values, "context"), "context") ?? {},
        key: values.key?.trim() || undefined,
      },
    }),
  },
  {
    id: "debug.route-dry-run",
    category: "debug",
    title: "Route dry-run",
    description: "selectCandidateChain dry-run from policy document + match inputs.",
    mode: "local",
    fields: [
      {
        name: "policy_document",
        label: "policy_document (JSON)",
        kind: "json",
        required: true,
        defaultValue: "{}",
      },
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
      },
      {
        name: "installation_id",
        label: "installation_id",
        kind: "text",
        required: true,
      },
      {
        name: "cost_class",
        label: "cost_class",
        kind: "text",
        defaultValue: "standard",
      },
      {
        name: "tier",
        label: "tier",
        kind: "select",
        options: [
          { value: "standard", label: "standard" },
          { value: "degraded", label: "degraded" },
        ],
        defaultValue: "standard",
      },
      {
        name: "language",
        label: "language",
        kind: "text",
        defaultValue: "en",
      },
      {
        name: "latency_class",
        label: "latency_class",
        kind: "text",
        defaultValue: "standard",
      },
    ],
    buildRequest: (values) => ({
      mode: "local",
      handler: "route-dry-run",
      input: {
        policy_document:
          parseJsonField(
            requireValue(values, "policy_document"),
            "policy_document",
          ) ?? {},
        capability_id: requireValue(values, "capability_id"),
        installation_id: requireValue(values, "installation_id"),
        cost_class: values.cost_class?.trim() || "standard",
        tier: values.tier?.trim() || "standard",
        language: values.language?.trim() || "en",
        latency_class: values.latency_class?.trim() || "standard",
      },
    }),
  },
  {
    id: "debug.taxonomy",
    category: "debug",
    title: "Taxonomy browser",
    description: "List ALL_TAXONOMY_CODES or look up one code → status / retryable.",
    mode: "local",
    fields: [
      {
        name: "code",
        label: "code (optional — blank lists all)",
        kind: "text",
        placeholder: "quota_exhausted",
      },
    ],
    buildRequest: (values) => ({
      mode: "local",
      handler: "taxonomy",
      input: { code: values.code?.trim() || undefined },
    }),
  },
  {
    id: "debug.reference",
    category: "debug",
    title: "Request reference",
    description: "generateRequestReference / normalizeRequestReference.",
    mode: "local",
    fields: [
      {
        name: "action",
        label: "action",
        kind: "select",
        required: true,
        options: [
          { value: "generate", label: "generate" },
          { value: "normalize", label: "normalize" },
        ],
        defaultValue: "generate",
      },
      {
        name: "reference",
        label: "reference (for normalize)",
        kind: "text",
      },
    ],
    buildRequest: (values) => ({
      mode: "local",
      handler: "reference",
      input: {
        action: requireValue(values, "action"),
        reference: values.reference?.trim() || undefined,
      },
    }),
  },
  {
    id: "debug.canonical-lint",
    category: "debug",
    title: "Canonical encode lint",
    description:
      "assertNoProviderShapedFieldNames / encodeCanonicalRequest on supplied JSON.",
    mode: "local",
    fields: [
      {
        name: "request",
        label: "canonical-ish request (JSON)",
        kind: "json",
        required: true,
        defaultValue: "{}",
      },
    ],
    buildRequest: (values) => ({
      mode: "local",
      handler: "canonical-lint",
      input: {
        request:
          parseJsonField(requireValue(values, "request"), "request") ?? {},
      },
    }),
  },
];
