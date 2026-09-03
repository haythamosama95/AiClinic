import type { JourneyAuth } from '@/catalog/journey-types'

export function journeyAuthLabel(auth: JourneyAuth): string {
  switch (auth) {
    case 'operator':
      return 'Operator bearer'
    case 'aat':
      return 'Clinic AAT'
    case 'supabase-admin':
      return 'Supabase admin'
    default:
      return 'No auth'
  }
}

export function journeyAuthLine(auth: JourneyAuth, authReady: boolean): string {
  const base = (() => {
    switch (auth) {
      case 'operator':
        return 'Operator bearer from Secrets'
      case 'aat':
        return 'Clinic AAT from Secrets'
      case 'supabase-admin':
        return 'Supabase admin session from Secrets'
      default:
        return 'No auth required'
    }
  })()

  return authReady ? base : `${base} — load credentials first`
}
