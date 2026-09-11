import type { JourneyOperationDefinition, JourneyParamField } from '@/catalog/journey-types'

const PLAN_BODY_FIELDS: JourneyParamField[] = [
  {
    name: 'name',
    scope: 'body',
    hint: 'Unique plan name',
    required: true,
    wide: true,
  },
  {
    name: 'credit_budget',
    scope: 'body',
    defaultValue: '1000',
    hint: 'Integer ≥ 0 — credit budget for the plan',
  },
  {
    name: 'request_quota',
    scope: 'body',
    defaultValue: '500',
    hint: 'Integer ≥ 0 — max AI requests in billing period',
  },
  {
    name: 'max_cost_class',
    scope: 'body',
    defaultValue: 'standard',
    hint: 'Routing cost class ceiling',
  },
  {
    name: 'soft_threshold',
    scope: 'body',
    defaultValue: '0.8',
    hint: 'Fraction ∈ [0, 1] — soft budget threshold',
  },
  {
    name: 'allowed_capabilities',
    scope: 'body',
    json: true,
    defaultValue: '["clinic.visit_summary"]',
    hint: 'JSON string array of capability ids',
    wide: true,
  },
  {
    name: 'status',
    scope: 'body',
    defaultValue: 'active',
    hint: 'Plan status (e.g. active)',
  },
]

export const COMMERCIAL_PLAN_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'plan-create',
    section: 'Plan catalogue',
    title: 'POST /control/plans/create',
    method: 'POST',
    path: '/control/plans/create',
    auth: 'operator',
    bodyKind: 'json',
    fields: PLAN_BODY_FIELDS,
    summary:
      'Create a plan row in G1 plan catalogue. Operator bearer required — missing credentials return frozen B2 401 {"error":"unauthorized"} in the raw panel.',
    successNote: '200 — plan created. control_audit records the mutation.',
    failures: [
      {
        status: 401,
        error: 'unauthorized',
        trigger: 'Missing or invalid OPERATOR_BEARER_TOKEN',
      },
      { status: 400, error: 'invalid_payload', trigger: 'Malformed plan body' },
    ],
  },
  {
    id: 'plan-update',
    section: 'Plan catalogue',
    title: 'POST /control/plans/{name}/update',
    method: 'POST',
    path: '/control/plans/{name}/update',
    auth: 'operator',
    bodyKind: 'json',
    fields: PLAN_BODY_FIELDS,
    summary: 'Update an existing plan by name. Same frozen plan columns as create.',
    successNote: '200 — plan updated.',
    failures: [
      {
        status: 401,
        error: 'unauthorized',
        trigger: 'Missing or invalid OPERATOR_BEARER_TOKEN',
      },
      { status: 404, error: 'not_found', trigger: 'Unknown plan name' },
    ],
  },
  {
    id: 'plan-delete',
    section: 'Plan catalogue',
    title: 'POST /control/plans/{name}/delete',
    method: 'POST',
    path: '/control/plans/{name}/delete',
    auth: 'operator',
    bodyKind: 'empty',
    fields: [
      {
        name: 'name',
        scope: 'path',
        hint: 'Plan name to delete',
        required: true,
        wide: true,
      },
    ],
    summary: 'Delete a plan by name. Body is {}.',
    successNote: '200 — plan deleted.',
    destructive: true,
    failures: [
      {
        status: 401,
        error: 'unauthorized',
        trigger: 'Missing or invalid OPERATOR_BEARER_TOKEN',
      },
      { status: 404, error: 'not_found', trigger: 'Unknown plan name' },
    ],
  },
]
