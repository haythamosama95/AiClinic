import type { ClinicEnrollmentMaterial, DevConfig, ResetResult } from '@/types'

export async function loadDevConfig(): Promise<DevConfig> {
  const response = await fetch('/api/dev/config')
  if (!response.ok) {
    throw new Error('Could not load operator credentials from ai-platform/.dev.vars')
  }
  return response.json() as Promise<DevConfig>
}

export async function fetchClinicEnrollmentMaterial(): Promise<ClinicEnrollmentMaterial | null> {
  const response = await fetch('/api/dev/clinic-enrollment-material')
  if (response.status === 404) {
    return null
  }
  if (!response.ok) {
    const payload = (await response.json()) as { error?: string }
    throw new Error(payload.error ?? 'Could not load clinic enrollment material')
  }
  return response.json() as Promise<ClinicEnrollmentMaterial>
}

export async function resetPlatform(): Promise<ResetResult> {
  const response = await fetch('/api/dev/reset', { method: 'POST' })
  const payload = (await response.json()) as ResetResult & { error?: string }
  if (!response.ok) {
    throw new Error(payload.error ?? 'Platform reset failed')
  }
  return payload
}
