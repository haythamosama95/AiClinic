export type NavSection =
  | 'stage-0'
  | 'stage-1'
  | 'stage-2'
  | 'stage-3'
  | 'stage-4'
  | 'stage-5'
  | 'stage-6'
  | 'stage-7'
  | 'stage-8'
  | 'stage-9'
  | 'stage-10'
  | 'stage-11'
  | 'stage-12'
  | 'guard-pipeline'
  | 'plans'
  | 'usage'
  | 'invoices'
  | 'stage-x'
  | 'secrets'

export interface DevConfig {
  operatorBearerToken: string
  devVarsPath: string
  supabaseUrl: string
  supabaseAnonKey: string
  backendEnvPath: string
  bootstrapAdminUsername: string
  bootstrapAdminPassword: string
  bootstrapAdminSource: string
}

export interface SupabaseAdminCredentials {
  username: string
  password: string
}

export interface ResetResult {
  steps: string[]
}

export interface ResetError {
  error: string
}

export interface ClinicEnrollmentMaterial {
  installation_id: string
  kid: string
  public_key: string
  org_id: string
  branch_id: string
  display_name: string
  aat_ver: string
}

export interface FieldRow {
  name: string
  value: string
  meaning?: string
}

export interface HttpExchange {
  request: {
    method: string
    url: string
    headers: FieldRow[]
    body: FieldRow[]
    raw: string
  }
  response: {
    status: number
    statusText: string
    headers: FieldRow[]
    body: FieldRow[]
    /** Shown above the payload — e.g. request_reference from SSE accepted. */
    pinned?: FieldRow[]
    rawBody: string
    raw: string
  }
  sentAt: string
}
