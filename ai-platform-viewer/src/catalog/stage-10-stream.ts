import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import {
  VISIT_SUMMARY_CAPABILITY,
  VISIT_SUMMARY_INTENT,
  VISIT_SUMMARY_VERSION,
  buildVisitSummaryContextJson,
} from '@/catalog/stage-8-ingress'
import { visitSummaryPostFields } from '@/catalog/visit-summary-probe-fields'

const FAKE_PROVIDER_POLICY_JSON = `{
  "schema_version": 1,
  "policy_id": "standard",
  "policy_version": 91,
  "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
  "rules": [{
    "rule_id": "verify-fake",
    "match": {},
    "requires": { "structured_output": false, "min_context_window": 0, "languages": [] },
    "targets": [{
      "provider_id": "fake",
      "model_id": "fake-v1",
      "features": {
        "structured_output": true,
        "min_context_window": 128000,
        "languages": ["en"],
        "latency_class": "standard",
        "cost_class": "standard"
      },
      "max_attempts": 1,
      "timeout_ms": 30000
    }],
    "max_parallel_attempts": 99
  }],
  "overrides": []
}`

const VISIT_CONTEXT_PLACEHOLDER = buildVisitSummaryContextJson(
  '<match AAT org claim>',
  '<match AAT branch claim>',
)

export const STAGE10_META: JourneyStageMeta = {
  id: 'stage-10',
  navLabel: 'Stage 10',
  navNote: 'Accept, route, invoke, stream',
  eyebrow: 'Stage 10 · Accept, route, invoke, stream',
  title: 'From accepted to SSE terminal',
  lede:
    'After the guard passes, POST /v1/requests opens an SSE stream. accepted is the first frame; routing and provider invocation follow on the fresh path. Publish a fake-provider routing policy before the happy path so local dev does not need DeepSeek/Gemini API keys.',
  accentClass: 'stage-accent--stream',
  cardClass: 'operation-card--stream',
  buttonClass: 'stream-button',
}

export const STAGE10_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'stream-sse-happy',
    section: 'SSE accept',
    title: 'POST /v1/requests — visit summary happy path (SSE)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'sse',
    summary:
      'Full fresh path: accepted → text_delta → completed on the fake provider when routing policy version 91 is active. Save request_reference from the accepted frame for Stage 11.',
    successNote:
      '200 text/event-stream. First event: accepted with request_reference and trace_id. Terminal: completed with result.finalContent.text = "Fake adapter summary."',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Guard stage 2 failure' },
      { status: 200, error: 'failed (SSE)', trigger: 'Missing routing policy after accepted' },
    ],
    fields: visitSummaryPostFields({
      body: {
        capability_id: VISIT_SUMMARY_CAPABILITY,
        user_intent: VISIT_SUMMARY_INTENT,
        context: VISIT_CONTEXT_PLACEHOLDER,
      },
      headers: {
        'x-idempotency-key': 'idem-happy-1',
        'x-capability-version': VISIT_SUMMARY_VERSION,
        'x-trace-id': 'trace-happy-1',
      },
    }),
  },
  {
    id: 'stream-get-poll',
    section: 'GET poll',
    title: 'GET /v1/requests/{request_reference}',
    method: 'GET',
    path: '/v1/requests/{request_reference}',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'Poll terminal state after the SSE stream completes. Returns envelope result for Completed requests. Paste request_reference from the accepted SSE frame (XXXX-XXXX).',
    successNote:
      '200 with terminal payload when the journal row is Completed. 404 while still in-flight or unknown reference.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Invalid or missing AAT' },
      { status: 404, error: 'request_not_found', trigger: 'Unknown request_reference' },
    ],
    fields: [
      {
        name: 'request_reference',
        scope: 'path',
        defaultValue: '',
        hint: 'Copy from SSE accepted frame (e.g. W6GP-H3BT)',
        wide: true,
        required: true,
      },
    ],
  },
  {
    id: 'stream-routing-publish',
    section: 'Routing preload',
    title: 'Publish fake-provider routing policy',
    method: 'POST',
    path: '/control/routing-policies/publish',
    auth: 'operator',
    bodyKind: 'json',
    summary:
      'Loads routing policy into R2 and inserts a published D1 row. Identity from document.policy_id and document.policy_version. Visit summary manifest references routing/standard@v1 — config-cache serves the active row for policy_id=standard. Edit document to change targets.',
    successNote:
      '200 — {} or warnings. Policy published to control/routing-policy/standard/91.json (from document). Follow with promote to set status=active.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Invalid operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not valid JSON' },
      { status: 400, error: 'missing_document', trigger: 'document field absent from body' },
      {
        status: 400,
        error: 'invalid_policy_identity',
        trigger:
          'Missing/empty document.policy_id, or document.policy_version not an integer ≥ 1 (string "1" rejected)',
      },
      { status: 409, error: 'already_published', trigger: 'Version already exists' },
      { status: 500, error: 'storage_error', trigger: 'D1 or R2 failure' },
    ],
    fields: [
      {
        name: 'document',
        scope: 'body',
        json: true,
        defaultValue: FAKE_PROVIDER_POLICY_JSON,
        hint: 'Full routing policy document — fake provider needs no API keys; policy_version=91',
        wide: true,
      },
    ],
  },
  {
    id: 'stream-routing-promote',
    section: 'Routing preload',
    title: 'Promote routing policy to active',
    method: 'POST',
    path: '/control/routing-policies/{policy_id}/versions/{version}/promote',
    auth: 'operator',
    bodyKind: 'empty',
    summary:
      'Sets the published version to status=active so invoke loads it from D1+R2. Restart the Worker after promote if config-cache is warm on an old policy.',
    successNote:
      '200 — D1 routing_policy status=active, content_pointer=control/routing-policy/standard/{version}.json.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Invalid operator bearer' },
      { status: 404, error: 'policy_version_not_found', trigger: 'Publish first' },
      { status: 409, error: 'illegal_policy_transition', trigger: 'Version not in published state' },
    ],
    fields: [
      {
        name: 'policy_id',
        scope: 'path',
        defaultValue: 'standard',
        hint: 'Must match publish call',
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '91',
        hint: 'Version to promote',
      },
    ],
  },
]
