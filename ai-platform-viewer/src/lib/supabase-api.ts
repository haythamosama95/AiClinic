import type { JourneyParamField } from '@/catalog/journey-types'
import type { Stage2OperationId } from '@/catalog/stage-2-clinic-keypair'
import { STAGE2_OPERATIONS } from '@/catalog/stage-2-clinic-keypair'
import { buildRawRequest, buildRawResponse } from '@/lib/raw-http'
import { prettyJsonValue } from '@/lib/json-format'
import {
  callSupabaseRpc,
  resolveSupabaseConfig,
  signInToSupabase,
} from '@/lib/supabase-session'
import type { FieldRow, HttpExchange, SupabaseAdminCredentials } from '@/types'

function maskToken(token: string, emptyLabel: string): string {
  if (!token) return emptyLabel
  if (token.length <= 12) return '••••••••'
  return `${token.slice(0, 6)}…${token.slice(-4)}`
}

function maskApiKey(key: string): string {
  if (!key) return '(not loaded — check backend/local/.env)'
  if (key.length <= 12) return '••••••••'
  return `${key.slice(0, 6)}…${key.slice(-4)}`
}

function flattenRpcResponseBody(payload: unknown, rpcName: string): FieldRow[] {
  if (rpcName === 'issue_ai_token') {
    if (typeof payload === 'string') {
      const segments = payload.split('.')
      return [
        { name: 'token', value: payload, meaning: 'Compact JWS — use as Bearer AAT' },
        {
          name: 'segments',
          value: String(segments.length),
          meaning: 'header.payload.signature',
        },
      ]
    }
  }

  if (payload === null || payload === undefined) {
    return [{ name: '(empty)', value: '—' }]
  }

  if (typeof payload === 'string') {
    return [{ name: 'body', value: payload || '(empty)' }]
  }

  if (typeof payload !== 'object') {
    return [{ name: 'body', value: String(payload) }]
  }

  const rows: FieldRow[] = []

  for (const [name, value] of Object.entries(payload as Record<string, unknown>)) {
    if (name === 'data' && value && typeof value === 'object' && !Array.isArray(value)) {
      for (const [dataName, dataValue] of Object.entries(
        value as Record<string, unknown>,
      )) {
        rows.push({
          name: `data.${dataName}`,
          value:
            dataValue === null || dataValue === undefined
              ? 'null'
              : typeof dataValue === 'object'
                ? prettyJsonValue(dataValue)
                : String(dataValue),
          meaning: rpcFieldMeaning(dataName),
        })
      }
      continue
    }

    rows.push({
      name,
      value:
        value === null || value === undefined
          ? 'null'
          : typeof value === 'object'
            ? prettyJsonValue(value)
            : String(value),
      meaning: rpcFieldMeaning(name),
    })
  }

  return rows.length > 0 ? rows : [{ name: '(empty)', value: '—' }]
}

function rpcFieldMeaning(name: string): string | undefined {
  switch (name) {
    case 'success':
      return 'PostgREST rpc_result success flag'
    case 'kid':
      return 'Key ID — copied to AAT header kid and platform installation_key.key_id'
    case 'installation_id':
      return 'Platform installation id; becomes AAT iss and enroll path parameter'
    case 'public_jwk.x':
      return 'Base64url raw public key — becomes platform enroll public_key'
    case 'error_code':
      return 'Machine-readable failure from rpc_result'
    case 'error_message':
      return 'Human-readable failure from rpc_result'
    case 'visit_id':
      return 'Echo of p_visit_id'
    case 'complaint':
      return 'Chief complaint for visit.chief_complaint@v1 context key'
    case 'recorded_at':
      return 'ISO-8601 UTC instant from note created_at'
    case 'enrolled':
      return 'Clinic-local switch — Flutter hides or shows AI UI from this flag'
    case 'platform_base_url':
      return 'Gateway base URL written after platform enroll (manual today)'
    case 'revoked_at':
      return 'Timestamp when revocation took effect'
    default:
      return undefined
  }
}

function buildRpcBody(
  fields: JourneyParamField[],
  params: Record<string, string>,
): Record<string, unknown> {
  const body: Record<string, unknown> = {}

  for (const field of fields) {
    if (field.scope !== 'body') {
      continue
    }

    const raw = params[field.name]?.trim() ?? ''
    if (!raw && field.required === false) {
      continue
    }

    if (field.json) {
      const parsed = JSON.parse(raw) as unknown
      if (field.name === 'p_scopes' && Array.isArray(parsed) && parsed.length === 0) {
        continue
      }
      body[field.name] = parsed
    } else if (field.name === 'p_visit_id') {
      body[field.name] = raw
    } else {
      body[field.name] = raw
    }
  }

  return body
}

function rpcRequestBodyFields(
  fields: JourneyParamField[],
  params: Record<string, string>,
  rpcBody: Record<string, unknown>,
): FieldRow[] {
  const bodyFields = fields.filter((field) => field.scope === 'body')
  if (bodyFields.length === 0) {
    return [{ name: '(body)', value: '{}', meaning: 'No RPC arguments for this call' }]
  }

  return bodyFields.map((field) => ({
    name: field.name,
    value:
      rpcBody[field.name] !== undefined
        ? field.json
          ? JSON.stringify(rpcBody[field.name])
          : String(rpcBody[field.name])
        : params[field.name] ?? '',
    meaning: field.hint,
  }))
}

export interface SupabaseRpcRequest {
  rpcName: string
  fields: JourneyParamField[]
  params?: Record<string, string>
}

export async function sendSupabaseRpcRequest(
  request: SupabaseRpcRequest,
  adminCredentials: SupabaseAdminCredentials,
): Promise<HttpExchange> {
  const config = await resolveSupabaseConfig(adminCredentials)
  const accessToken = await signInToSupabase(config)
  const { rpcName, fields, params } = request
  const path = `/rest/v1/rpc/${rpcName}`
  const url = `${config.supabaseUrl}${path}`
  const sentAt = new Date().toISOString()
  const rpcBody = buildRpcBody(fields, params ?? {})

  const { response, payload, rawBody } = await callSupabaseRpc(
    config,
    accessToken,
    rpcName,
    rpcBody,
  )

  const requestHeaders: Record<string, string> = {
    apikey: config.anonKey,
    Authorization: `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  }
  const responseHeaders: Record<string, string> = {
    'content-type': response.headers.get('content-type') ?? '(none)',
  }

  return {
    request: {
      method: 'POST',
      url,
      headers: [
        {
          name: 'apikey',
          value: maskApiKey(config.anonKey),
          meaning: 'SUPABASE_ANON_KEY from backend/local/.env',
        },
        {
          name: 'Authorization',
          value: `Bearer ${maskToken(accessToken, '(sign-in failed)')}`,
          meaning: 'Authenticated clinic session from Secrets admin credentials',
        },
        {
          name: 'Content-Type',
          value: 'application/json',
          meaning: 'PostgREST RPC call',
        },
      ],
      body: rpcRequestBodyFields(fields, params ?? {}, rpcBody),
      raw: buildRawRequest('POST', url, requestHeaders, rpcBody),
    },
    response: {
      status: response.status,
      statusText: response.statusText,
      headers: Object.entries(responseHeaders).map(([name, value]) => ({
        name,
        value,
      })),
      body: flattenRpcResponseBody(payload, rpcName),
      rawBody,
      raw: buildRawResponse(
        response.status,
        response.statusText,
        responseHeaders,
        rawBody,
      ),
    },
    sentAt,
  }
}

export async function sendStage2SupabaseRequest(
  operationId: Stage2OperationId,
  adminCredentials: SupabaseAdminCredentials,
  params?: Record<string, string>,
): Promise<HttpExchange> {
  const operation = STAGE2_OPERATIONS.find((item) => item.id === operationId)
  if (!operation) {
    throw new Error(`Unknown Stage 2 operation: ${operationId}`)
  }

  const fields: JourneyParamField[] =
    operation.paramName !== undefined
      ? [
          {
            name: operation.paramName,
            scope: 'body',
            hint: operation.paramHint,
          },
        ]
      : []

  return sendSupabaseRpcRequest(
    {
      rpcName: operation.rpcName,
      fields,
      params,
    },
    adminCredentials,
  )
}
