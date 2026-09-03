import { useCallback, useEffect, useState } from 'react'
import { fetchClinicEnrollmentMaterial } from '@/lib/dev-api'
import type { ClinicEnrollmentMaterial } from '@/types'

export type ClinicMaterialStatus = 'loading' | 'ready' | 'missing' | 'error'

export interface ClinicEnrollmentMaterialState {
  material: ClinicEnrollmentMaterial | null
  status: ClinicMaterialStatus
  error: string | null
  reload: () => Promise<void>
}

/** Stable key so form defaults re-sync when Supabase key material changes. */
export function clinicMaterialFingerprint(
  material: ClinicEnrollmentMaterial | null,
): string {
  if (!material) {
    return ''
  }

  return [
    material.installation_id,
    material.kid,
    material.public_key,
    material.org_id,
    material.branch_id,
    material.display_name,
    material.aat_ver,
  ].join('|')
}

export function useClinicEnrollmentMaterial(): ClinicEnrollmentMaterialState {
  const [material, setMaterial] = useState<ClinicEnrollmentMaterial | null>(null)
  const [status, setStatus] = useState<ClinicMaterialStatus>('loading')
  const [error, setError] = useState<string | null>(null)

  const reload = useCallback(async () => {
    setStatus('loading')
    setError(null)

    try {
      const next = await fetchClinicEnrollmentMaterial()
      setMaterial(next)
      setStatus(next ? 'ready' : 'missing')
    } catch (loadError) {
      setMaterial(null)
      setStatus('error')
      setError(
        loadError instanceof Error
          ? loadError.message
          : 'Could not load clinic enrollment material',
      )
    }
  }, [])

  useEffect(() => {
    void reload()
  }, [reload])

  return { material, status, error, reload }
}
