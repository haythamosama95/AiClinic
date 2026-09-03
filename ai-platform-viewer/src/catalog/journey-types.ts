import type { ClinicEnrollmentMaterial } from '@/types'

export type ParamScope = 'path' | 'body' | 'header' | 'query'

export type JourneyAuth = 'operator' | 'aat' | 'supabase-admin' | 'none'

export type JourneyBodyKind = 'json' | 'empty' | 'none' | 'sse'

export type ClinicMaterialKey = keyof ClinicEnrollmentMaterial

export interface JourneyParamField {
  name: string
  scope: ParamScope
  hint?: string
  defaultValue?: string
  wide?: boolean
  clinicKey?: ClinicMaterialKey
  required?: boolean
  json?: boolean
  jsonRows?: number
}

export interface JourneyOperationDefinition {
  id: string
  section: string
  title: string
  method: 'GET' | 'POST' | 'RPC'
  path: string
  auth: JourneyAuth
  bodyKind: JourneyBodyKind
  summary: string
  successNote: string
  destructive?: boolean
  failures: Array<{ status: number; error: string; trigger: string }>
  fields: JourneyParamField[]
  rpcName?: string
}

export interface JourneyStageMeta {
  id: string
  navLabel: string
  navNote: string
  eyebrow: string
  title: string
  lede: string
  accentClass: string
  cardClass: string
  buttonClass: string
}
