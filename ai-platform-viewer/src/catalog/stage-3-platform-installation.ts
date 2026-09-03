export type Stage3OperationId =
  | 'enroll'
  | 'rotate'
  | 'revoke-key'
  | 'suspend'
  | 'resume'
  | 'delete'
  | 'purge'
  | 'v1-request-probe'

export type Stage3Auth = 'operator' | 'aat'

export type Stage3BodyKind = 'enroll' | 'rotate' | 'revoke-key' | 'empty' | 'none'

export type Stage3ParamScope = 'path' | 'body' | 'header'

export interface Stage3ParamField {
  name: string
  scope: Stage3ParamScope
  hint?: string
  /** Prefill from clinic enrollment material when available */
  clinicKey?:
  | 'installation_id'
  | 'org_id'
  | 'display_name'
  | 'public_key'
  | 'kid'
  defaultValue?: string
  wide?: boolean
}

export interface Stage3OperationDefinition {
  id: Stage3OperationId
  title: string
  method: 'POST'
  pathSuffix: string
  auth: Stage3Auth
  bodyKind: Stage3BodyKind
  summary: string
  successNote: string
  destructive?: boolean
  failures: Array<{ status: number; error: string; trigger: string }>
  fields: Stage3ParamField[]
}

export const STAGE3_PARAM_FIELDS: Record<Stage3OperationId, Stage3ParamField[]> = {
  enroll: [
    {
      name: 'installation_id',
      scope: 'path',
      clinicKey: 'installation_id',
      hint: 'Canonical UUID — from Stage 2 enroll_installation_keypair',
      wide: true,
    },
    {
      name: 'org_id',
      scope: 'body',
      clinicKey: 'org_id',
      hint: 'Canonical UUID — clinic organizations.id',
      wide: true,
    },
    {
      name: 'display_name',
      scope: 'body',
      clinicKey: 'display_name',
      hint: 'Clinic org name',
    },
    { name: 'region', scope: 'body', defaultValue: 'local', hint: 'Billing region' },
    {
      name: 'plan',
      scope: 'body',
      defaultValue: 'standard',
      hint: 'starter | standard | professional | enterprise',
    },
    {
      name: 'public_key',
      scope: 'body',
      clinicKey: 'public_key',
      hint: 'Stage 2 public_jwk.x — base64url, 32-byte Ed25519 key',
      wide: true,
    },
    {
      name: 'algorithm',
      scope: 'body',
      defaultValue: 'EdDSA',
      hint: 'Must be EdDSA (clinic keystore pins Ed25519)',
    },
    {
      name: 'kid',
      scope: 'body',
      clinicKey: 'kid',
      hint: 'Canonical UUID — Stage 2 kid → installation_key.key_id',
      wide: true,
    },
  ],
  rotate: [
    {
      name: 'installation_id',
      scope: 'path',
      clinicKey: 'installation_id',
      hint: 'Must already exist from a prior enroll',
      wide: true,
    },
    {
      name: 'kid',
      scope: 'body',
      clinicKey: 'kid',
      hint: 'New kid from clinic rotate_installation_key()',
      wide: true,
    },
    {
      name: 'public_key',
      scope: 'body',
      clinicKey: 'public_key',
      hint: 'New public_jwk.x from clinic rotate RPC',
      wide: true,
    },
    {
      name: 'algorithm',
      scope: 'body',
      defaultValue: 'EdDSA',
      hint: 'Must be EdDSA (clinic keystore pins Ed25519)',
    },
  ],
  'revoke-key': [
    {
      name: 'installation_id',
      scope: 'path',
      clinicKey: 'installation_id',
      wide: true,
    },
    {
      name: 'kid',
      scope: 'body',
      clinicKey: 'kid',
      hint: 'installation_key.key_id to revoke',
      wide: true,
    },
  ],
  suspend: [
    {
      name: 'installation_id',
      scope: 'path',
      clinicKey: 'installation_id',
      wide: true,
    },
  ],
  resume: [
    {
      name: 'installation_id',
      scope: 'path',
      clinicKey: 'installation_id',
      wide: true,
    },
  ],
  delete: [
    {
      name: 'installation_id',
      scope: 'path',
      clinicKey: 'installation_id',
      wide: true,
    },
  ],
  purge: [
    {
      name: 'installation_id',
      scope: 'path',
      clinicKey: 'installation_id',
      wide: true,
    },
  ],
  'v1-request-probe': [
    {
      name: 'capability_id',
      scope: 'body',
      defaultValue: 'clinic.visit_summary',
      hint: 'Capability to invoke',
    },
    {
      name: 'user_intent',
      scope: 'body',
      defaultValue: 'probe enroll',
      hint: 'User intent string',
    },
    {
      name: 'context',
      scope: 'body',
      defaultValue: '{}',
      hint: 'JSON object',
      wide: true,
    },
    {
      name: 'x-idempotency-key',
      scope: 'header',
      defaultValue: '',
      hint: 'Leave blank to generate a UUID on send',
      wide: true,
    },
    {
      name: 'x-capability-version',
      scope: 'header',
      defaultValue: '1.0.0',
      hint: 'Required by adapter',
    },
  ],
}

export const STAGE3_OPERATIONS: Stage3OperationDefinition[] = [
  {
    id: 'enroll',
    title: 'Enroll installation',
    method: 'POST',
    pathSuffix: '/enroll',
    auth: 'operator',
    bodyKind: 'enroll',
    fields: STAGE3_PARAM_FIELDS.enroll,
    summary:
      'Registers installation_id on the platform with the clinic public key specimen. Writes installation (active), installation_key, entitlement (pending, zero quotas), and control_audit. Returns platform_base_url echo only — no AI spend rights.',
    successNote:
      '200 — { platform_base_url }. D1 batch: installation + installation_key + entitlement(pending) + control_audit. No R2 writes.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid OPERATOR_BEARER_TOKEN' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not JSON' },
      { status: 400, error: 'invalid_payload', trigger: 'Required field empty, bad plan/algorithm, non-UUID ids, or invalid public_key' },
      { status: 409, error: 'already_enrolled', trigger: 'installation_id or org_id already exists' },
      { status: 409, error: 'duplicate_kid', trigger: 'kid UNIQUE violation on installation_key' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'rotate',
    title: 'Rotate platform key',
    method: 'POST',
    pathSuffix: '/rotate',
    auth: 'operator',
    bodyKind: 'rotate',
    fields: STAGE3_PARAM_FIELDS.rotate,
    summary:
      'Clinic first: rotate_installation_key() in Stage 2. Then register the new kid and public_key here. Additive — prior platform keys stay active until revoke-key.',
    successNote:
      '200 — {}. D1: INSERT new installation_key, control_audit action=rotate. Prior keys unchanged.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not JSON' },
      { status: 400, error: 'invalid_payload', trigger: 'Non-UUID kid, bad algorithm, or invalid public_key' },
      { status: 400, error: 'invalid_route', trigger: 'Malformed path' },
      { status: 404, error: 'installation_not_found', trigger: 'No installation row for path id' },
      { status: 409, error: 'illegal_lifecycle_transition', trigger: 'installation.status = deleted' },
      { status: 409, error: 'duplicate_kid', trigger: 'kid already in installation_key globally' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'revoke-key',
    title: 'Revoke platform key',
    method: 'POST',
    pathSuffix: '/revoke-key',
    auth: 'operator',
    bodyKind: 'revoke-key',
    fields: STAGE3_PARAM_FIELDS['revoke-key'],
    summary:
      'Retire one platform key by kid without adding a successor. AATs signed with that kid fail identity immediately. Other keys for the installation are untouched. Cannot revoke the sole remaining active key — rotate a replacement first.',
    successNote:
      '200 — {}. D1: installation_key.revoked_at = now, control_audit action=revoke-key.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 400, error: 'invalid_json', trigger: 'Body is not JSON' },
      { status: 400, error: 'invalid_payload', trigger: 'kid missing or empty' },
      { status: 404, error: 'installation_not_found', trigger: 'Unknown installation_id' },
      { status: 404, error: 'key_not_found', trigger: 'No key row for kid + installation' },
      { status: 409, error: 'illegal_lifecycle_transition', trigger: 'installation.status = deleted' },
      { status: 409, error: 'key_already_revoked', trigger: 'revoked_at already set on that key' },
      {
        status: 409,
        error: 'cannot_revoke_last_active_key',
        trigger: 'Revoke would leave zero active keys — rotate a replacement first',
      },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'suspend',
    title: 'Suspend installation',
    method: 'POST',
    pathSuffix: '/suspend',
    auth: 'operator',
    bodyKind: 'empty',
    fields: STAGE3_PARAM_FIELDS.suspend,
    summary:
      'Freeze the installation. Valid AATs are rejected at guard stage 2 with installation_suspended. Entitlement status is not changed.',
    successNote: '200 — {}. D1: installation.status = suspended, control_audit action=suspend.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 400, error: 'invalid_route', trigger: 'Malformed path' },
      { status: 404, error: 'installation_not_found', trigger: 'Unknown installation_id' },
      { status: 409, error: 'illegal_lifecycle_transition', trigger: 'Already suspended or deleted' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'resume',
    title: 'Resume installation',
    method: 'POST',
    pathSuffix: '/resume',
    auth: 'operator',
    bodyKind: 'empty',
    fields: STAGE3_PARAM_FIELDS.resume,
    summary:
      'Unfreeze a suspended installation. installation.status returns to active. Only valid when current status is suspended.',
    successNote: '200 — {}. D1: installation.status = active, control_audit action=resume.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 400, error: 'invalid_route', trigger: 'Malformed path' },
      { status: 404, error: 'installation_not_found', trigger: 'Unknown installation_id' },
      {
        status: 409,
        error: 'illegal_lifecycle_transition',
        trigger: 'Status is not suspended (e.g. active or deleted)',
      },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'delete',
    title: 'Delete installation',
    method: 'POST',
    pathSuffix: '/delete',
    auth: 'operator',
    bodyKind: 'empty',
    fields: STAGE3_PARAM_FIELDS.delete,
    summary:
      'Mark installation lifecycle-terminal (status = deleted). AATs fail identity with unauthenticated. Rows remain in D1 until purge.',
    successNote: '200 — {}. D1: installation.status = deleted, control_audit action=delete.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 400, error: 'invalid_route', trigger: 'Malformed path' },
      { status: 404, error: 'installation_not_found', trigger: 'Unknown installation_id' },
      { status: 409, error: 'illegal_lifecycle_transition', trigger: 'Already deleted' },
      { status: 500, error: 'storage_error', trigger: 'D1 batch failure' },
    ],
  },
  {
    id: 'purge',
    title: 'Purge installation',
    method: 'POST',
    pathSuffix: '/purge',
    auth: 'operator',
    bodyKind: 'empty',
    fields: STAGE3_PARAM_FIELDS.purge,
    summary:
      'Irreversibly remove this installation from D1 and R2 — identity, entitlement, grants, journal, ledger, and envelopes. Does not clear clinic Supabase keys.',
    successNote:
      '200 — {}. D1 + R2 deletes; control_audit action=purge_installation. Requires R2 binding.',
    destructive: true,
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or invalid operator bearer' },
      { status: 400, error: 'invalid_route', trigger: 'Malformed path' },
      { status: 500, error: 'missing_r2_binding', trigger: 'Worker env has no R2 bucket' },
      { status: 500, error: 'storage_error', trigger: 'D1 or R2 failure during purge' },
    ],
  },
  {
    id: 'v1-request-probe',
    title: 'Probe AI request (post-enroll)',
    method: 'POST',
    pathSuffix: '',
    auth: 'aat',
    bodyKind: 'none',
    fields: STAGE3_PARAM_FIELDS['v1-request-probe'],
    summary:
      'POST /v1/requests with a clinic AAT. After enroll but before entitle, identity may pass but entitlement fails with forbidden_capability (path ai_disabled). After suspend: installation_suspended. After delete or purge: unauthenticated.',
    successNote:
      '403 forbidden_capability / ai_disabled when enrolled but not entitled. 401 unauthenticated when platform has no file for this passport.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Before enroll, after delete/purge, or revoked kid' },
      {
        status: 403,
        error: 'forbidden_capability',
        trigger: 'Enrolled with pending entitlement — ai_disabled path',
      },
      {
        status: 403,
        error: 'installation_suspended',
        trigger: 'installation.status = suspended',
      },
    ],
  },
]
