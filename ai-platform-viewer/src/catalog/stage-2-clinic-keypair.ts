export type Stage2OperationId =
  | 'enroll-keypair'
  | 'rotate-installation-key'
  | 'revoke-installation-key'
  | 'get-availability'

export interface Stage2OperationDefinition {
  id: Stage2OperationId
  title: string
  rpcName: string
  path: string
  summary: string
  authHint: string
  paramName?: string
  paramHint?: string
  successNote: string
  failures: Array<{ status: number; error: string; trigger: string }>
}

export const STAGE2_OPERATIONS: Stage2OperationDefinition[] = [
  {
    id: 'enroll-keypair',
    title: 'Enroll installation keypair',
    rpcName: 'enroll_installation_keypair',
    path: '/rest/v1/rpc/enroll_installation_keypair',
    summary:
      'Mints an Ed25519 keypair inside clinic Postgres. The private key never leaves Supabase; the response carries kid, installation_id, and public_jwk.x for the later platform enroll call.',
    authHint: 'Owner or administrator session — admin credentials from Secrets',
    successNote:
      '200 — rpc_result with data.kid, data.installation_id, data.public_jwk. Writes ai_internal.installation_keys.',
    failures: [
      { status: 200, error: 'FORBIDDEN', trigger: 'Caller is not owner or administrator' },
      {
        status: 200,
        error: 'ALREADY_ENROLLED',
        trigger: 'Active installation key already exists — use rotate_installation_key',
      },
      {
        status: 200,
        error: 'SINGLE_INSTALLATION_VIOLATION',
        trigger: 'Second distinct installation_id on installation_keys',
      },
    ],
  },
  {
    id: 'rotate-installation-key',
    title: 'Rotate installation key',
    rpcName: 'rotate_installation_key',
    path: '/rest/v1/rpc/rotate_installation_key',
    summary:
      'Adds a new signing key for the clinic’s existing installation_id. Production rotation path — same installation_id, new kid and public_jwk. Previous key rows stay active until revoked.',
    authHint: 'Owner or administrator session — admin credentials from Secrets',
    successNote:
      '200 — rpc_result with data.kid, data.installation_id, data.public_jwk (same shape as enroll). Requires at least one active key row.',
    failures: [
      { status: 200, error: 'FORBIDDEN', trigger: 'Caller is not owner or administrator' },
      {
        status: 200,
        error: 'INSTALLATION_NOT_ENROLLED',
        trigger: 'No active installation_keys row — enroll first',
      },
    ],
  },
  {
    id: 'revoke-installation-key',
    title: 'Revoke installation key',
    rpcName: 'revoke_installation_key',
    path: '/rest/v1/rpc/revoke_installation_key',
    summary:
      'Marks one key row as revoked by kid. Tokens signed with that kid must not verify afterward. Idempotent when the key is already revoked.',
    authHint: 'Owner or administrator session — admin credentials from Secrets',
    paramName: 'p_kid',
    paramHint: 'installation_keys.kid from a prior enroll or rotate response',
    successNote:
      '200 — rpc_result with data.kid and data.revoked_at. Does not delete the row.',
    failures: [
      { status: 200, error: 'FORBIDDEN', trigger: 'Caller is not owner or administrator' },
      { status: 200, error: 'INVALID_INPUT', trigger: 'p_kid is null or blank after trim' },
      { status: 200, error: 'KEY_NOT_FOUND', trigger: 'No non-deleted row with that kid' },
    ],
  },
  {
    id: 'get-availability',
    title: 'Get AI availability',
    rpcName: 'get_ai_availability',
    path: '/rest/v1/rpc/get_ai_availability',
    summary:
      'Read-only clinic switch from ai_internal.app_settings key ai.availability. Returns plain jsonb (not rpc_result). Flutter uses this to show or hide AI UI without probing Cloudflare on every launch.',
    authHint: 'Any authenticated staff session — admin credentials from Secrets',
    successNote:
      '200 — { enrolled, platform_base_url }. Default after reset: enrolled=false, platform_base_url=null.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Missing or invalid Supabase session (anon has no GRANT)' },
    ],
  },
]
