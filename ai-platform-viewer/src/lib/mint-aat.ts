import {
  callSupabaseRpc,
  resolveSupabaseConfig,
  signInToSupabase,
  type SupabaseSessionConfig,
} from '@/lib/supabase-session'
import { ensurePlatformEnrollment } from '@/lib/platform-enroll'
import type { SupabaseAdminCredentials } from '@/types'

export interface MintAatResult {
  token: string
  aatVer: string
}

type RpcResult = {
  success?: boolean
  data?: {
    installation_id?: string
    kid?: string
    public_jwk?: { x?: string }
  }
  error_code?: string
  error_message?: string
}

async function ensureClinicKeypair(
  config: SupabaseSessionConfig,
  accessToken: string,
): Promise<void> {
  const { payload } = await callSupabaseRpc(
    config,
    accessToken,
    'enroll_installation_keypair',
  )

  const result = payload as RpcResult

  if (result.success === false) {
    throw new Error(
      result.error_message ??
      result.error_code ??
      'enroll_installation_keypair failed',
    )
  }
}

async function issueAat(
  config: SupabaseSessionConfig,
  accessToken: string,
): Promise<string> {
  try {
    const { response, payload } = await callSupabaseRpc(
      config,
      accessToken,
      'issue_ai_token',
    )
    if (!response.ok) {
      throw new Error(
        typeof payload === 'string'
          ? payload
          : ((payload as { message?: string }).message ?? 'issue_ai_token failed'),
      )
    }
    if (typeof payload !== 'string' || payload.length === 0) {
      throw new Error('issue_ai_token returned an empty token')
    }
    return payload
  } catch (error) {
    const message = error instanceof Error ? error.message : ''
    if (!message.includes('INSTALLATION_NOT_ENROLLED')) {
      throw error
    }
    await ensureClinicKeypair(config, accessToken)
    const { response, payload } = await callSupabaseRpc(
      config,
      accessToken,
      'issue_ai_token',
    )
    if (!response.ok) {
      throw new Error(
        typeof payload === 'string'
          ? payload
          : ((payload as { message?: string }).message ?? 'issue_ai_token failed'),
      )
    }
    if (typeof payload !== 'string' || payload.length === 0) {
      throw new Error('issue_ai_token returned an empty token')
    }
    return payload
  }
}

export async function mintAatFromSupabase(
  operatorBearer: string,
  adminCredentials: SupabaseAdminCredentials,
): Promise<MintAatResult> {
  const config = await resolveSupabaseConfig(adminCredentials)
  const accessToken = await signInToSupabase(config)
  const token = await issueAat(config, accessToken)
  const aatVer = await ensurePlatformEnrollment(operatorBearer)
  return { token, aatVer }
}
