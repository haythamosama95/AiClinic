import type { DevConfig, SupabaseAdminCredentials } from '@/types'

export function resolveSupabaseAdminFromEnv(): SupabaseAdminCredentials & {
  source: string
} {
  return {
    username: import.meta.env.VITE_BOOTSTRAP_ADMIN_USERNAME || 'admin',
    password: import.meta.env.VITE_BOOTSTRAP_ADMIN_PASSWORD || 'admin',
    source: '.env.local',
  }
}

export function resolveSupabaseAdminFromDevConfig(
  devConfig: DevConfig,
): SupabaseAdminCredentials & { source: string } {
  if (import.meta.env.VITE_SUPABASE_ANON_KEY) {
    return resolveSupabaseAdminFromEnv()
  }

  return {
    username: devConfig.bootstrapAdminUsername,
    password: devConfig.bootstrapAdminPassword,
    source: devConfig.bootstrapAdminSource,
  }
}
