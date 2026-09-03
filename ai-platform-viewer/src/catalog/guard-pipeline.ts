import type { NavSection } from '@/types'

export type GuardStageNumber = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10

export type JourneyPrerequisite = {
  stage: Exclude<NavSection, 'secrets' | 'stage-9' | 'stage-10' | 'stage-11' | 'stage-12'>
  label: string
  how: string
}

export type GuardError = {
  code: string
  http: number
  trigger: string
  paths?: string[]
}

export type GuardPipelineStage = {
  guardStage: GuardStageNumber
  name: string
  shortName: string
  module: string
  check: string
  skippedOnIdempotent?: boolean
  prerequisites: JourneyPrerequisite[]
  errors: GuardError[]
}

/** Ten sequential guard checkpoints — sourced from `runGuard()` in ai-platform/src/pipeline/index.ts */
export const GUARD_PIPELINE_STAGES: GuardPipelineStage[] = [
  {
    guardStage: 1,
    name: 'Ingress size + JSON',
    shortName: 'Ingress',
    module: 'pipeline/index.ts · adapter.ts',
    check: 'Body ≤ 1 MiB UTF-8; plain-object JSON parse. Extracts user_intent, context, and conversational fields.',
    prerequisites: [
      {
        stage: 'stage-0',
        label: 'Stage 0 — Platform boot',
        how: 'Worker serves POST /v1/requests with INGRESS_BODY_SIZE_LIMIT bound.',
      },
      {
        stage: 'stage-8',
        label: 'Stage 8 — Request ingress',
        how: 'Client sends a valid JSON object with required headers (x-idempotency-key, x-capability-version). Adapter may reject before guard for missing headers or non-object JSON.',
      },
    ],
    errors: [
      {
        code: 'request_too_large',
        http: 413,
        trigger: 'bodyText exceeds 1 MiB UTF-8',
      },
      {
        code: 'internal_error',
        http: 500,
        trigger: 'bodyText is not a plain JSON object (parseAdapterRequestBody returns null)',
      },
    ],
  },
  {
    guardStage: 2,
    name: 'Identity (AAT)',
    shortName: 'Identity',
    module: 'identity/index.ts',
    check: 'Verify Ed25519 JWS: claims, signature, installation + installation_key rows, token contract ver, installation status.',
    prerequisites: [
      {
        stage: 'stage-0',
        label: 'Stage 0 — Platform boot',
        how: 'TokenVerifier and D1 reader bindings available.',
      },
      {
        stage: 'stage-1',
        label: 'Stage 1 — Token contract',
        how: 'D1 token_contract row accepted; payload ver must match.',
      },
      {
        stage: 'stage-2',
        label: 'Stage 2 — Clinic keypair',
        how: 'Clinic holds the private key that signed the AAT.',
      },
      {
        stage: 'stage-3',
        label: 'Stage 3 — Platform installation',
        how: 'Enroll creates D1 installation + installation_key; suspend sets installation_suspended.',
      },
      {
        stage: 'stage-6',
        label: 'Stage 6 — Mint AAT',
        how: 'issue_ai_token() mints a valid clinic AAT with org, branch, scopes, and role claims.',
      },
    ],
    errors: [
      {
        code: 'unauthenticated',
        http: 401,
        trigger: 'Missing token, malformed JWS, bad signature, expired claims, missing installation/key, or retired token contract',
      },
      {
        code: 'installation_suspended',
        http: 403,
        trigger: 'installation.status is suspended (Stage 3 lifecycle)',
      },
    ],
  },
  {
    guardStage: 3,
    name: 'Entitlement + kill switches',
    shortName: 'Entitlement',
    module: 'entitlement/index.ts',
    check: 'Active entitlement, plan tier, allowed_capabilities, per-capability grants, and D1 kill_switch rows.',
    prerequisites: [
      {
        stage: 'stage-4',
        label: 'Stage 4 — Entitlement',
        how: 'Entitle sets status=active, plan tier, allowed_capabilities, and installation or plan grants matching capability@version.',
      },
    ],
    errors: [
      {
        code: 'forbidden_capability',
        http: 403,
        trigger: 'Entitlement or grant check failed',
        paths: [
          'ai_disabled — entitlement.status ≠ active',
          'plan_tier — plan below minimumPlanTier',
          'capability_not_granted — missing from allowed_capabilities or grant revoked/version_mismatch',
        ],
      },
      {
        code: 'capability_disabled',
        http: 503,
        trigger: 'Active D1 kill_switch row',
        paths: [
          'kill_switch_global',
          'kill_switch_capability',
          'kill_switch_installation',
          'kill_switch_provider',
        ],
      },
    ],
  },
  {
    guardStage: 4,
    name: 'Rate limits',
    shortName: 'Rate limit',
    module: 'rate-limit/index.ts',
    check: 'Three Cloudflare Rate Limit bindings: per installation, per installation+actor, per installation+capability.',
    prerequisites: [
      {
        stage: 'stage-0',
        label: 'Stage 0 — Platform boot',
        how: 'RATE_LIMITER_INSTALLATION, RATE_LIMITER_ACTOR, and RATE_LIMITER_CAPABILITY bindings configured in wrangler.toml.',
      },
    ],
    errors: [
      {
        code: 'rate_limited',
        http: 429,
        trigger: 'Any binding returns success=false; response includes retry_after (binding hint or 60s default)',
      },
    ],
  },
  {
    guardStage: 5,
    name: 'Capability resolve',
    shortName: 'Capability',
    module: 'capability/index.ts',
    check: 'In-memory manifest registry lookup, lifecycle overlay, plan allowance (scope, role, grants), capability-level kill switches.',
    prerequisites: [
      {
        stage: 'stage-0',
        label: 'Stage 0 — Platform boot',
        how: 'Published manifests loaded into capabilityRegistry at Worker boot.',
      },
      {
        stage: 'stage-4',
        label: 'Stage 4 — Entitlement',
        how: 'Grants and plan tier satisfy manifest.Access (re-checked at resolve).',
      },
      {
        stage: 'stage-6',
        label: 'Stage 6 — Mint AAT',
        how: 'AAT role and scopes satisfy manifest.Access.requiredCapabilityScope and allowedStaffRoles.',
      },
    ],
    errors: [
      {
        code: 'capability_unknown',
        http: 404,
        trigger: 'No manifest for capability_id@x-capability-version in registry',
      },
      {
        code: 'capability_retired',
        http: 404,
        trigger: 'Effective lifecycle state is retired',
      },
      {
        code: 'forbidden_capability',
        http: 403,
        trigger: 'Plan allowance failed: inactive entitlement, plan tier, missing grant, scope, or role',
      },
      {
        code: 'capability_disabled',
        http: 503,
        trigger: 'Capability-level kill switch active at resolve (provider kills surface as killedProviderIds, not this code)',
      },
    ],
  },
  {
    guardStage: 6,
    name: 'Context validate',
    shortName: 'Context',
    module: 'context/validator.ts',
    check: 'Required manifest context keys, tenant bind (org/branch vs AAT), shape/maxSize, conversational transcript budget.',
    prerequisites: [
      {
        stage: 'stage-6',
        label: 'Stage 6 — Mint AAT',
        how: 'principal.organizationId and principal.branchId must match context.org and context.branch.',
      },
      {
        stage: 'stage-8',
        label: 'Stage 8 — Request ingress',
        how: 'Client supplies visit context keys required by the manifest (e.g. visit.chief_complaint@v1).',
      },
    ],
    errors: [
      {
        code: 'context_required',
        http: 422,
        trigger: 'Required manifest context key absent (missing_keys not exposed on live HTTP)',
      },
      {
        code: 'context_invalid',
        http: 422,
        trigger: 'Tenant bind mismatch, shape violation, or maxSize exceeded',
      },
      {
        code: 'conversation_budget_exhausted',
        http: 409,
        trigger: 'Conversational mode: transcript turn budget exhausted',
      },
      {
        code: 'internal_error',
        http: 500,
        trigger: 'Unexpected validation failure path',
      },
    ],
  },
  {
    guardStage: 7,
    name: 'Cost pre-flight',
    shortName: 'Preflight',
    module: 'context/preflight.ts',
    check: 'Token estimate from context + user_intent + transcript + prompt scaffold vs manifest maxInputTokens and perRequestTokenCeiling.',
    prerequisites: [
      {
        stage: 'stage-0',
        label: 'Stage 0 — Platform boot',
        how: 'Bundled manifest economics (maxInputTokens, perRequestTokenCeiling) and prompt scaffold byte length available.',
      },
    ],
    errors: [
      {
        code: 'request_too_large',
        http: 413,
        trigger: 'Estimated input tokens exceed manifest ceiling',
      },
    ],
  },
  {
    guardStage: 8,
    name: 'Admission (Quota DO)',
    shortName: 'Admission',
    module: 'admission/index.ts',
    check: 'One Quota DO round trip: idempotency, JTI replay guard, request/token/cost quota, grace admission when DO unavailable.',
    prerequisites: [
      {
        stage: 'stage-4',
        label: 'Stage 4 — Entitlement',
        how: 'request_quota, token_budget, and cost_budget > 0; zero quotas with active entitlement yield quota_exhausted here, not at stage 3.',
      },
    ],
    errors: [
      {
        code: 'unauthenticated',
        http: 401,
        trigger: 'JTI replay after prior admit (DO outcome replay)',
      },
      {
        code: 'quota_exhausted',
        http: 429,
        trigger: 'Quota DO refusal or concurrency_exhausted (mapped to quota_exhausted)',
      },
      {
        code: 'rate_limited',
        http: 429,
        trigger: 'Grace admission cap exceeded while Quota DO is unavailable',
      },
      {
        code: 'internal_error',
        http: 500,
        trigger: 'Unexpected DO outcome or transport failure after grace exhausted',
      },
    ],
  },
  {
    guardStage: 9,
    name: 'Journal INSERT',
    shortName: 'Journal',
    module: 'journal/index.ts',
    check: 'INSERT ai_request row (state=Accepted). Conversational legs require conversation_id and turn_ordinal.',
    skippedOnIdempotent: true,
    prerequisites: [
      {
        stage: 'stage-0',
        label: 'Stage 0 — Platform boot',
        how: 'D1 ai_request table and journal bindings available.',
      },
      {
        stage: 'stage-8',
        label: 'Stages 1–8 pass',
        how: 'Fresh admission path only — idempotent replay skips this stage.',
      },
    ],
    errors: [
      {
        code: 'context_invalid',
        http: 422,
        trigger: 'Conversational manifest but missing conversation_id or turn_ordinal on wire',
      },
      {
        code: 'internal_error',
        http: 500,
        trigger: 'D1 INSERT failure; admission reservation released',
      },
    ],
  },
  {
    guardStage: 10,
    name: 'Prompt compose',
    shortName: 'Compose',
    module: 'prompt/composer.ts',
    check: 'Build CanonicalRequest from manifest, filtered context, and user_intent. Success boundary → SSE accepted.',
    skippedOnIdempotent: true,
    prerequisites: [
      {
        stage: 'stage-0',
        label: 'Stage 0 — Platform boot',
        how: 'Lazy prompt registry loads system instruction artifacts.',
      },
      {
        stage: 'stage-8',
        label: 'Stages 1–8 pass',
        how: 'Fresh path only. Routing (Stage 5 viewer) is not required until post-accepted stream (Stage 10 viewer).',
      },
    ],
    errors: [
      {
        code: 'internal_error',
        http: 500,
        trigger: 'composeRequest failed; ai_request.state updated to Failed',
      },
    ],
  },
]
