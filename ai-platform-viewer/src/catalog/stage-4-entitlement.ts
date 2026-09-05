import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import { visitSummaryPostFields } from '@/catalog/visit-summary-probe-fields'

export const STAGE4_META: JourneyStageMeta = {
  id: 'stage-4',
  navLabel: 'Stage 4',
  navNote: 'Entitlement & grants',
  eyebrow: 'Stage 4 · Entitlement and capability grants',
  title: 'The ticket office opens',
  lede:
    'After Stage 3 enroll leaves entitlement pending with zero quotas, the control-plane caller entitles the installation (one-shot), then manages capability cohorts (activate, promote) and version lifecycle (deprecate, retire). Runtime POST /v1/requests probes guard stage 3 while pending vs active. GET …/quota inspects the live Quota DO snapshot and remaining budget.',
  accentClass: 'stage-accent--entitlement',
  cardClass: 'operation-card--entitlement',
  buttonClass: 'entitlement-button',
}

const ENTITLE_GRANTS_DEFAULT = JSON.stringify([
  {
    capability_id: 'clinic.visit_summary',
    capability_version: '1.0.0',
    scope: 'installation',
  },
])

export const STAGE4_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'entitle',
    section: 'Entitle installation',
    title: 'POST …/entitle',
    method: 'POST',
    path: '/control/installations/{installation_id}/entitle',
    auth: 'operator',
    bodyKind: 'json',
    fields: [
      {
        name: 'installation_id',
        scope: 'path',
        clinicKey: 'installation_id',
        hint: 'From Stage 2 enroll_installation_keypair',
        wide: true,
      },
      {
        name: 'period_start',
        scope: 'body',
        defaultValue: '2026-08-01T00:00:00.000Z',
        hint: 'ISO-8601 UTC instant — must be < period_end',
        wide: true,
      },
      {
        name: 'period_end',
        scope: 'body',
        defaultValue: '2026-09-01T00:00:00.000Z',
        hint: 'ISO-8601 UTC instant — must be > period_start',
        wide: true,
      },
      {
        name: 'request_quota',
        scope: 'body',
        defaultValue: '1000',
        hint: 'Integer ≥ 0 — max AI requests in billing period',
      },
      {
        name: 'token_budget',
        scope: 'body',
        defaultValue: '500000',
        hint: 'Integer ≥ 0 — max provider tokens in period',
      },
      {
        name: 'cost_budget',
        scope: 'body',
        defaultValue: '50.0',
        hint: 'Finite number ≥ 0 — max platform currency spend',
      },
      {
        name: 'soft_threshold',
        scope: 'body',
        defaultValue: '0.8',
        hint: 'Fraction ∈ [0, 1] — degrade routing when any budget ratio crosses threshold',
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
        name: 'grants',
        scope: 'body',
        json: true,
        defaultValue: ENTITLE_GRANTS_DEFAULT,
        hint: 'Non-empty JSON array — capability_id, capability_version, optional scope (installation | plan)',
        wide: true,
      },
    ],
    summary:
      'Turn on spend rights: billing period, quotas, allowed_capabilities, and capability_grant rows. One-shot — only works when entitlement.status is pending.',
    successNote:
      '200 — { installation_id, status: "active" }. D1: UPDATE entitlement, INSERT capability_grant per grant, control_audit action=entitle.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong OPERATOR_BEARER_TOKEN' },
      { status: 404, error: 'installation_not_found', trigger: 'No installation row' },
      { status: 404, error: 'entitlement_not_found', trigger: 'No entitlement row' },
      { status: 409, error: 'not_pending', trigger: 'entitlement.status !== pending' },
      {
        status: 400,
        error: 'invalid_payload',
        trigger: 'Bad numbers, empty grants, bad scope, non-ISO periods, or period_start >= period_end',
      },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'entitlement-probe',
    section: 'Runtime entitlement probe',
    title: 'POST /v1/requests (entitlement guard)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    fields: visitSummaryPostFields(),
    summary:
      'Probe guard stage 3 via runtime ingress. While entitlement is pending: 403 forbidden_capability (ai_disabled). After entitle with active status: passes stage 3 (may still fail later on Access role/scope).',
    successNote:
      '403 forbidden_capability while pending. After entitle + cache refresh (restart or 30s): stage 3 ok; visit-summary may still 403 on Access fields.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Missing or invalid AAT' },
      {
        status: 403,
        error: 'forbidden_capability',
        trigger: 'Pending entitlement, plan_tier, capability_not_granted, or Access role/scope',
      },
      { status: 503, error: 'capability_disabled', trigger: 'Active kill_switch row' },
    ],
  },
  {
    id: 'cohort-activate',
    section: 'Cohort activate',
    title: 'POST …/activate',
    method: 'POST',
    path: '/control/capabilities/{capability_id}/versions/{version}/activate',
    auth: 'operator',
    bodyKind: 'json',
    fields: [
      {
        name: 'capability_id',
        scope: 'path',
        defaultValue: 'clinic.visit_summary',
        hint: 'Capability id',
        wide: true,
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '1.0.0',
        hint: 'Capability build version',
      },
      {
        name: 'installation_ids',
        scope: 'body',
        json: true,
        defaultValue: '[]',
        clinicKey: 'installation_id',
        hint: 'Non-empty JSON array of installation ids — prefill wraps clinic installation_id',
        wide: true,
      },
      {
        name: 'cohort_name',
        scope: 'body',
        defaultValue: 'pilot-clinics',
        hint: 'Optional operator label for audit target',
        required: false,
      },
    ],
    summary:
      'Give a named cohort a specific capability build version. Installations not in the list keep their existing grant version.',
    successNote:
      '200 — {}. D1: UPDATE or INSERT capability_grant per id, control_audit action=cohort_activate.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not valid JSON' },
      { status: 400, error: 'missing_installation_ids', trigger: 'installation_ids missing, not array, or empty' },
      { status: 404, error: 'capability_not_found', trigger: 'capability_id@version not in Worker registry' },
      { status: 404, error: 'installation_not_found', trigger: 'Any listed installation id has no row' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'cohort-promote',
    section: 'Cohort promote',
    title: 'POST …/promote',
    method: 'POST',
    path: '/control/capabilities/{capability_id}/versions/{version}/promote',
    auth: 'operator',
    bodyKind: 'empty',
    fields: [
      {
        name: 'capability_id',
        scope: 'path',
        defaultValue: 'clinic.visit_summary',
        hint: 'Capability id',
        wide: true,
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '1.0.0',
        hint: 'Target version for all entitled installations',
      },
    ],
    summary:
      'End a staged split — every entitled installation (active + allowed_capabilities contains id) receives this version. Plan-scoped grants updated or created.',
    successNote: '200 — {}. D1: UPDATE all live grants, upsert missing grants, control_audit action=cohort_promote.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 404, error: 'capability_not_found', trigger: 'capability_id@version not in registry' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'deprecate',
    section: 'Deprecate capability version',
    title: 'POST …/deprecate',
    method: 'POST',
    path: '/control/capabilities/{capability_id}/versions/{version}/deprecate',
    auth: 'operator',
    bodyKind: 'json',
    fields: [
      {
        name: 'capability_id',
        scope: 'path',
        defaultValue: 'clinic.visit_summary',
        wide: true,
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '1.0.0',
      },
      {
        name: 'successor_id',
        scope: 'body',
        defaultValue: 'clinic.visit_summary',
        hint: 'Successor capability id — must be known to in-memory registry',
        wide: true,
      },
    ],
    summary:
      'Mark a capability version deprecated with a announced successor. Global overlay on capability_grant — version stays servable until retire after 90-day overlap.',
    successNote:
      '200 — {}. D1: INSERT global overlay lifecycle_state=deprecated, retire_after = deprecated_at + 90d, control_audit action=deprecate.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not valid JSON' },
      { status: 400, error: 'missing_successor_id', trigger: 'Empty or missing successor_id' },
      { status: 400, error: 'unknown_successor', trigger: 'successor_id not in registry' },
      { status: 404, error: 'capability_not_found', trigger: 'capability_id@version not in registry' },
      { status: 409, error: 'already_retired', trigger: 'Latest global overlay is retired' },
      { status: 409, error: 'already_deprecated', trigger: 'Already deprecated with different successor_id' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'retire',
    section: 'Retire capability version',
    title: 'POST …/retire',
    method: 'POST',
    path: '/control/capabilities/{capability_id}/versions/{version}/retire',
    auth: 'operator',
    bodyKind: 'empty',
    fields: [
      {
        name: 'capability_id',
        scope: 'path',
        defaultValue: 'clinic.visit_summary',
        wide: true,
      },
      {
        name: 'version',
        scope: 'path',
        defaultValue: '1.0.0',
      },
    ],
    summary:
      'Permanently retire a deprecated capability version after the overlap window. resolve() then returns capability_retired; discover() omits the version.',
    successNote: '200 — {}. D1: INSERT global overlay lifecycle_state=retired, control_audit action=retire.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not valid JSON (if body sent)' },
      { status: 400, error: 'not_deprecated', trigger: 'No prior global deprecated overlay with successor' },
      { status: 400, error: 'overlap_window_active', trigger: 'Current time < retire_after' },
      { status: 404, error: 'capability_not_found', trigger: 'capability_id@version not in registry' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'quota-inspect',
    section: 'Quota inspection',
    title: 'GET …/quota',
    method: 'GET',
    path: '/control/installations/{installation_id}/quota',
    auth: 'operator',
    bodyKind: 'none',
    fields: [
      {
        name: 'installation_id',
        scope: 'path',
        clinicKey: 'installation_id',
        hint: 'From Stage 2 enroll_installation_keypair',
        wide: true,
      },
      {
        name: 'verbose',
        scope: 'query',
        required: false,
        defaultValue: '',
        hint: 'Set to true to include full idempotency / JTI replay / admitted / credited maps (500-entry cap per map)',
      },
    ],
    summary:
      'Read-only live snapshot of the installation\'s Quota DO (GatewayObject): period counters, in-flight admissions, idempotency and JTI replay state, joined with D1 entitlement limits to compute remaining budget.',
    successNote:
      '200 — period_counters, entitlement, remaining (limit − used), and entry counts. DO state reflects the 2h ephemeral sweep; nothing is persisted by this call.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong OPERATOR_BEARER_TOKEN' },
      { status: 404, error: 'installation_not_found', trigger: 'No installation row' },
      { status: 405, error: 'method_not_allowed', trigger: 'Non-GET method on this route' },
      {
        status: 503,
        error: 'quota_do_unavailable',
        trigger: 'Quota DO unreachable — same condition that triggers grace admission on POST /v1/requests',
      },
    ],
  },
]
