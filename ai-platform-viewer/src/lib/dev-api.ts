import type { ClinicEnrollmentMaterial, DevConfig, HttpExchange, ResetResult } from '@/types'

async function fetchInspectExchange(url: string): Promise<HttpExchange> {
  const response = await fetch(url)
  const payload = (await response.json()) as HttpExchange & { error?: string }
  if (!response.ok) {
    throw new Error(payload.error ?? 'Invoice inspect failed')
  }
  return payload
}

export async function loadDevConfig(): Promise<DevConfig> {
  const response = await fetch('/api/dev/config')
  if (!response.ok) {
    throw new Error('Could not load operator credentials from ai-platform/.dev.vars')
  }
  return response.json() as Promise<DevConfig>
}

export async function ensureViewerAatLifetime(): Promise<void> {
  const response = await fetch('/api/dev/ensure-aat-lifetime', { method: 'POST' })
  if (!response.ok) {
    const payload = (await response.json()) as { error?: string }
    throw new Error(payload.error ?? 'Could not set clinic AAT lifetime for viewer mint')
  }
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

export async function resetInstallations(): Promise<ResetResult> {
  const response = await fetch('/api/dev/reset-installations', { method: 'POST' })
  const payload = (await response.json()) as ResetResult & { error?: string }
  if (!response.ok) {
    throw new Error(payload.error ?? 'Installation reset failed')
  }
  return payload
}

export async function fetchIssuedInvoices(): Promise<HttpExchange> {
  return fetchInspectExchange('/api/dev/invoices')
}

export async function fetchInvoiceDetail(
  installationId: string,
  period: string,
): Promise<HttpExchange> {
  const query = new URLSearchParams({
    installation_id: installationId,
    period,
  })
  return fetchInspectExchange(`/api/dev/invoices/detail?${query.toString()}`)
}
