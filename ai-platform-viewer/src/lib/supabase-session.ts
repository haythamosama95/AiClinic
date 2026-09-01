import { loadDevConfig } from '@/lib/dev-api'
import { resolveSupabaseAdminFromDevConfig, resolveSupabaseAdminFromEnv } from '@/lib/supabase-admin'
import type { SupabaseAdminCredentials } from '@/types'

export interface SupabaseSessionConfig {
  supabaseUrl: string
  anonKey: string
  bootstrapUsername: string
  bootstrapPassword: string
}

export async function resolveSupabaseConfig(
  adminCredentials?: SupabaseAdminCredentials,
): Promise<SupabaseSessionConfig> {
  const fromEnv = {
    supabaseUrl: import.meta.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321',
    anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY || '',
  }

  const adminFromEnv = resolveSupabaseAdminFromEnv()
  const admin = adminCredentials ?? {
    username: adminFromEnv.username,
    password: adminFromEnv.password,
  }

  if (fromEnv.anonKey) {
    return {
      supabaseUrl: fromEnv.supabaseUrl,
      anonKey: fromEnv.anonKey,
      bootstrapUsername: admin.username,
      bootstrapPassword: admin.password,
    }
  }

  const devConfig = await loadDevConfig()
  const anonKey = devConfig.supabaseAnonKey
  if (!anonKey) {
    throw new Error(
      'No Supabase anon key found. Set VITE_SUPABASE_ANON_KEY in .env.local or create backend/local/.env from backend/local/.env.example.',
    )
  }

  const adminFromDev = resolveSupabaseAdminFromDevConfig(devConfig)

  return {
    supabaseUrl: devConfig.supabaseUrl || fromEnv.supabaseUrl,
    anonKey,
    bootstrapUsername: adminCredentials?.username ?? adminFromDev.username,
    bootstrapPassword: adminCredentials?.password ?? adminFromDev.password,
  }
}

export async function signInToSupabase(
  config: SupabaseSessionConfig,
): Promise<string> {
  const authResponse = await fetch(
    `${config.supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        apikey: config.anonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: config.bootstrapUsername,
        password: config.bootstrapPassword,
      }),
    },
  )

  const authPayload = (await authResponse.json()) as {
    access_token?: string
    error_description?: string
    msg?: string
  }

  if (!authResponse.ok || !authPayload.access_token) {
    throw new Error(
      authPayload.error_description ??
      authPayload.msg ??
      'Supabase sign-in failed',
    )
  }

  return authPayload.access_token
}

export async function callSupabaseRpc(
  config: SupabaseSessionConfig,
  accessToken: string,
  rpcName: string,
  body: unknown = {},
): Promise<{ response: Response; payload: unknown; rawBody: string }> {
  const response = await fetch(`${config.supabaseUrl}/rest/v1/rpc/${rpcName}`, {
    method: 'POST',
    headers: {
      apikey: config.anonKey,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })

  const rawBody = await response.text()
  let payload: unknown = rawBody

  if (rawBody) {
    try {
      payload = JSON.parse(rawBody) as unknown
    } catch {
      payload = rawBody
    }
  }

  return { response, payload, rawBody }
}
