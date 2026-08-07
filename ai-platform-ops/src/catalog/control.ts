import type { EntityDef } from "./types";
import { parseJsonField, requireValue } from "./types";

function installationPath(id: string, action: string): string {
  return `/control/installations/${encodeURIComponent(id)}/${action}`;
}

function capabilityPath(
  capabilityId: string,
  version: string,
  action: string,
): string {
  return `/control/capabilities/${encodeURIComponent(capabilityId)}/versions/${encodeURIComponent(version)}/${action}`;
}

function routingPath(policyId: string, version: string, action: string): string {
  return `/control/routing-policies/${encodeURIComponent(policyId)}/versions/${encodeURIComponent(version)}/${action}`;
}

const installationIdField = {
  name: "installation_id",
  label: "installation_id",
  kind: "text" as const,
  required: true,
};

export const CONTROL_ENTITIES: EntityDef[] = [
  {
    id: "control.enroll",
    category: "control",
    title: "Enroll installation",
    description: "POST /control/installations/{id}/enroll",
    mode: "proxy",
    fields: [
      installationIdField,
      { name: "org_id", label: "org_id", kind: "text", required: true },
      {
        name: "display_name",
        label: "display_name",
        kind: "text",
        required: true,
      },
      { name: "region", label: "region", kind: "text", required: true },
      { name: "plan", label: "plan", kind: "text", required: true },
      {
        name: "public_key",
        label: "public_key",
        kind: "textarea",
        required: true,
      },
      {
        name: "algorithm",
        label: "algorithm",
        kind: "text",
        required: true,
        defaultValue: "EdDSA",
      },
      { name: "kid", label: "kid", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: installationPath(requireValue(values, "installation_id"), "enroll"),
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        org_id: requireValue(values, "org_id"),
        display_name: requireValue(values, "display_name"),
        region: requireValue(values, "region"),
        plan: requireValue(values, "plan"),
        public_key: requireValue(values, "public_key"),
        algorithm: requireValue(values, "algorithm"),
        kid: requireValue(values, "kid"),
      }),
    }),
  },
  {
    id: "control.rotate",
    category: "control",
    title: "Rotate key",
    description: "POST /control/installations/{id}/rotate",
    mode: "proxy",
    fields: [
      installationIdField,
      { name: "kid", label: "kid", kind: "text", required: true },
      {
        name: "public_key",
        label: "public_key",
        kind: "textarea",
        required: true,
      },
      {
        name: "algorithm",
        label: "algorithm",
        kind: "text",
        required: true,
        defaultValue: "EdDSA",
      },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: installationPath(requireValue(values, "installation_id"), "rotate"),
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        kid: requireValue(values, "kid"),
        public_key: requireValue(values, "public_key"),
        algorithm: requireValue(values, "algorithm"),
      }),
    }),
  },
  {
    id: "control.revoke-key",
    category: "control",
    title: "Revoke key",
    description: "POST /control/installations/{id}/revoke-key",
    mode: "proxy",
    dangerous: true,
    fields: [
      installationIdField,
      { name: "kid", label: "kid", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: installationPath(
        requireValue(values, "installation_id"),
        "revoke-key",
      ),
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ kid: requireValue(values, "kid") }),
    }),
  },
  {
    id: "control.suspend",
    category: "control",
    title: "Suspend installation",
    description: "POST /control/installations/{id}/suspend — AI denied until resume.",
    mode: "proxy",
    dangerous: true,
    fields: [installationIdField],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: installationPath(requireValue(values, "installation_id"), "suspend"),
      auth: "operator",
    }),
  },
  {
    id: "control.resume",
    category: "control",
    title: "Resume installation",
    description: "POST /control/installations/{id}/resume",
    mode: "proxy",
    fields: [installationIdField],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: installationPath(requireValue(values, "installation_id"), "resume"),
      auth: "operator",
    }),
  },
  {
    id: "control.entitle",
    category: "control",
    title: "Entitle installation",
    description:
      "POST /control/installations/{id}/entitle — activate pending entitlement economics and write capability_grant row(s) in one mutation. Rejects if not pending (409).",
    mode: "proxy",
    fields: [
      installationIdField,
      {
        name: "period_start",
        label: "period_start (ISO)",
        kind: "text",
        required: true,
        placeholder: "2026-08-01T00:00:00.000Z",
      },
      {
        name: "period_end",
        label: "period_end (ISO)",
        kind: "text",
        required: true,
        placeholder: "2026-09-01T00:00:00.000Z",
      },
      {
        name: "request_quota",
        label: "request_quota",
        kind: "number",
        required: true,
        defaultValue: 1000,
      },
      {
        name: "token_budget",
        label: "token_budget",
        kind: "number",
        required: true,
        defaultValue: 1_000_000,
      },
      {
        name: "cost_budget",
        label: "cost_budget",
        kind: "number",
        required: true,
        defaultValue: 100,
      },
      {
        name: "soft_threshold",
        label: "soft_threshold (0–1)",
        kind: "number",
        required: true,
        defaultValue: 0.8,
        help: "Fraction of budget; crossing selects degraded routing tier.",
      },
      {
        name: "allowed_capabilities",
        label: "allowed_capabilities (JSON string array)",
        kind: "json",
        required: true,
        defaultValue: '["clinic.visit_summary"]',
      },
      {
        name: "grants",
        label: "grants (JSON array)",
        kind: "json",
        required: true,
        defaultValue:
          '[{"capability_id":"clinic.visit_summary","capability_version":"1.0.0","scope":"installation"}]',
        help: 'Each grant: { capability_id, capability_version, scope?: "installation"|"plan" }',
      },
    ],
    buildRequest: (values) => {
      const request_quota = Number(requireValue(values, "request_quota"));
      const token_budget = Number(requireValue(values, "token_budget"));
      const cost_budget = Number(requireValue(values, "cost_budget"));
      const soft_threshold = Number(requireValue(values, "soft_threshold"));
      const allowed_capabilities = parseJsonField(
        requireValue(values, "allowed_capabilities"),
        "allowed_capabilities",
      );
      const grants = parseJsonField(requireValue(values, "grants"), "grants");
      return {
        mode: "proxy",
        method: "POST",
        path: installationPath(
          requireValue(values, "installation_id"),
          "entitle",
        ),
        auth: "operator",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          period_start: requireValue(values, "period_start"),
          period_end: requireValue(values, "period_end"),
          request_quota,
          token_budget,
          cost_budget,
          soft_threshold,
          allowed_capabilities,
          grants,
        }),
      };
    },
  },
  {
    id: "control.delete",
    category: "control",
    title: "Soft-delete installation",
    description: "POST /control/installations/{id}/delete",
    mode: "proxy",
    dangerous: true,
    fields: [installationIdField],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: installationPath(requireValue(values, "installation_id"), "delete"),
      auth: "operator",
    }),
  },
  {
    id: "control.purge",
    category: "control",
    title: "Purge installation",
    description:
      "POST /control/installations/{id}/purge — irreversible data wipe.",
    mode: "proxy",
    dangerous: true,
    fields: [installationIdField],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: installationPath(requireValue(values, "installation_id"), "purge"),
      auth: "operator",
    }),
  },
  {
    id: "control.token-begin-rotation",
    category: "control",
    title: "Token contract — begin rotation",
    description: "POST /control/token-contract/begin-rotation",
    mode: "proxy",
    fields: [
      { name: "ver", label: "ver", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: "/control/token-contract/begin-rotation",
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ver: requireValue(values, "ver") }),
    }),
  },
  {
    id: "control.token-retire",
    category: "control",
    title: "Token contract — retire ver",
    description: "POST /control/token-contract/retire",
    mode: "proxy",
    dangerous: true,
    fields: [
      { name: "ver", label: "ver", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: "/control/token-contract/retire",
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ver: requireValue(values, "ver") }),
    }),
  },
  {
    id: "control.capability-deprecate",
    category: "control",
    title: "Deprecate capability version",
    description:
      "POST /control/capabilities/{id}/versions/{ver}/deprecate — needs successor_id.",
    mode: "proxy",
    dangerous: true,
    fields: [
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
      },
      { name: "version", label: "version", kind: "text", required: true },
      {
        name: "successor_id",
        label: "successor_id",
        kind: "text",
        required: true,
      },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: capabilityPath(
        requireValue(values, "capability_id"),
        requireValue(values, "version"),
        "deprecate",
      ),
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        successor_id: requireValue(values, "successor_id"),
      }),
    }),
  },
  {
    id: "control.capability-retire",
    category: "control",
    title: "Retire capability version",
    description: "POST /control/capabilities/{id}/versions/{ver}/retire",
    mode: "proxy",
    dangerous: true,
    fields: [
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
      },
      { name: "version", label: "version", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: capabilityPath(
        requireValue(values, "capability_id"),
        requireValue(values, "version"),
        "retire",
      ),
      auth: "operator",
    }),
  },
  {
    id: "control.cohort-activate",
    category: "control",
    title: "Cohort activate",
    description:
      "POST /control/capabilities/{id}/versions/{ver}/activate",
    mode: "proxy",
    fields: [
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
      },
      { name: "version", label: "version", kind: "text", required: true },
      {
        name: "installation_ids",
        label: "installation_ids (JSON array)",
        kind: "json",
        required: true,
        defaultValue: "[]",
      },
      {
        name: "cohort_name",
        label: "cohort_name (optional)",
        kind: "text",
      },
    ],
    buildRequest: (values) => {
      const installation_ids = parseJsonField(
        requireValue(values, "installation_ids"),
        "installation_ids",
      );
      const body: Record<string, unknown> = { installation_ids };
      if (values.cohort_name?.trim()) {
        body.cohort_name = values.cohort_name.trim();
      }
      return {
        mode: "proxy",
        method: "POST",
        path: capabilityPath(
          requireValue(values, "capability_id"),
          requireValue(values, "version"),
          "activate",
        ),
        auth: "operator",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      };
    },
  },
  {
    id: "control.cohort-promote",
    category: "control",
    title: "Cohort promote",
    description:
      "POST /control/capabilities/{id}/versions/{ver}/promote — no body.",
    mode: "proxy",
    dangerous: true,
    fields: [
      {
        name: "capability_id",
        label: "capability_id",
        kind: "text",
        required: true,
      },
      { name: "version", label: "version", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: capabilityPath(
        requireValue(values, "capability_id"),
        requireValue(values, "version"),
        "promote",
      ),
      auth: "operator",
    }),
  },
  {
    id: "control.routing-publish",
    category: "control",
    title: "Routing policy — publish",
    description:
      "POST /control/routing-policies/{policyId}/versions/{version}/publish",
    mode: "proxy",
    fields: [
      { name: "policy_id", label: "policy_id", kind: "text", required: true },
      { name: "version", label: "version", kind: "text", required: true },
      {
        name: "document",
        label: "document (JSON object)",
        kind: "json",
        required: true,
        defaultValue: "{}",
      },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: routingPath(
        requireValue(values, "policy_id"),
        requireValue(values, "version"),
        "publish",
      ),
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        document: parseJsonField(
          requireValue(values, "document"),
          "document",
        ),
      }),
    }),
  },
  {
    id: "control.routing-canary",
    category: "control",
    title: "Routing policy — canary",
    description:
      "POST /control/routing-policies/{policyId}/versions/{version}/canary",
    mode: "proxy",
    fields: [
      { name: "policy_id", label: "policy_id", kind: "text", required: true },
      { name: "version", label: "version", kind: "text", required: true },
      {
        name: "installation_ids",
        label: "installation_ids (JSON array)",
        kind: "json",
        required: true,
        defaultValue: "[]",
      },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: routingPath(
        requireValue(values, "policy_id"),
        requireValue(values, "version"),
        "canary",
      ),
      auth: "operator",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        installation_ids: parseJsonField(
          requireValue(values, "installation_ids"),
          "installation_ids",
        ),
      }),
    }),
  },
  {
    id: "control.routing-promote",
    category: "control",
    title: "Routing policy — promote",
    description:
      "POST /control/routing-policies/{policyId}/versions/{version}/promote",
    mode: "proxy",
    dangerous: true,
    fields: [
      { name: "policy_id", label: "policy_id", kind: "text", required: true },
      { name: "version", label: "version", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: routingPath(
        requireValue(values, "policy_id"),
        requireValue(values, "version"),
        "promote",
      ),
      auth: "operator",
    }),
  },
  {
    id: "control.routing-rollback",
    category: "control",
    title: "Routing policy — rollback",
    description:
      "POST /control/routing-policies/{policyId}/versions/{version}/rollback",
    mode: "proxy",
    dangerous: true,
    fields: [
      { name: "policy_id", label: "policy_id", kind: "text", required: true },
      { name: "version", label: "version", kind: "text", required: true },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: routingPath(
        requireValue(values, "policy_id"),
        requireValue(values, "version"),
        "rollback",
      ),
      auth: "operator",
    }),
  },
  {
    id: "control.support-lookup",
    category: "control",
    title: "Support lookup",
    description:
      "POST /control/support/lookup?reference= — full request + attempts + R2 envelope.",
    mode: "proxy",
    fields: [
      {
        name: "reference",
        label: "reference",
        kind: "text",
        required: true,
      },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: `/control/support/lookup?reference=${encodeURIComponent(requireValue(values, "reference"))}`,
      auth: "operator",
    }),
  },
];
