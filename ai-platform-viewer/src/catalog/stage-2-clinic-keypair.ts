export type Stage2OperationId = 'enroll-keypair' | 'get-availability'

export interface Stage2OperationDefinition {
  id: Stage2OperationId
  title: string
  rpcName: string
  path: string
  summary: string
  authHint: string
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
        error: 'SINGLE_INSTALLATION_VIOLATION',
        trigger: 'Second distinct installation_id on installation_keys',
      },
    ],
  },
  {
    id: 'get-availability',
    title: 'Get AI availability',
    rpcName: 'get_ai_availability',
    path: '/rest/v1/rpc/get_ai_availability',
    summary:
      'Reads ai_internal.app_settings key ai.availability. Flutter uses this clinic-local switch to show or hide AI UI without probing Cloudflare on every launch.',
    authHint: 'Any authenticated staff session — admin credentials from Secrets',
    successNote:
      '200 — { enrolled, platform_base_url }. Default after reset: enrolled=false, platform_base_url=null.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Missing or invalid Supabase session' },
    ],
  },
]
