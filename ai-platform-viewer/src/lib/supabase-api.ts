import type { Stage2OperationId } from '@/catalog/stage-2-clinic-keypair'
import { buildRawRequest, buildRawResponse } from '@/lib/raw-http'
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

function flattenResponseBody(payload: unknown): FieldRow[] {
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
        if (dataName === 'public_jwk' && dataValue && typeof dataValue === 'object') {
          for (const [jwkName, jwkValue] of Object.entries(
            dataValue as Record<string, unknown>,
          )) {
            rows.push({
              name: `data.public_jwk.${jwkName}`,
              value:
                jwkValue === null || jwkValue === undefined
                  ? 'null'
                  : String(jwkValue),
              meaning: stage2FieldMeaning(`public_jwk.${jwkName}`),
            })
          }
          continue
        }

        rows.push({
          name: `data.${dataName}`,
          value:
            dataValue === null || dataValue === undefined
              ? 'null'
              : typeof dataValue === 'object'
                ? JSON.stringify(dataValue)
                : String(dataValue),
          meaning: stage2FieldMeaning(dataName),
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
            ? JSON.stringify(value)
            : String(value),
      meaning: stage2FieldMeaning(name),
    })
  }

  return rows.length > 0 ? rows : [{ name: '(empty)', value: '—' }]
}

function stage2FieldMeaning(name: string): string | undefined {
  switch (name) {
    case 'success':
      return 'PostgREST rpc_result success flag'
    case 'kid':
      return 'Key ID — copied to AAT header kid and platform installation_key.key_id'
    case 'installation_id':
      return 'Platform installation id; becomes AAT iss and enroll path parameter'
    case 'public_jwk.x':
      return 'Base64url raw public key — becomes platform enroll public_key'
    case 'public_jwk.kty':
      return 'JWK key type (OKP)'
    case 'public_jwk.crv':
      return 'Curve (Ed25519)'
    case 'public_jwk.kid':
      return 'JWK kid mirror of top-level kid'
    case 'error_code':
      return 'Machine-readable failure from rpc_result'
    case 'error_message':
      return 'Human-readable failure from rpc_result'
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

const RPC_BY_OPERATION: Record<Stage2OperationId, string> = {
  'enroll-keypair': 'enroll_installation_keypair',
  'rotate-installation-key': 'rotate_installation_key',
  'revoke-installation-key': 'revoke_installation_key',
  'get-availability': 'get_ai_availability',
}

function rpcBodyForOperation(
  operationId: Stage2OperationId,
  params?: Record<string, string>,
): Record<string, unknown> {
  if (operationId === 'revoke-installation-key') {
    return { p_kid: params?.p_kid ?? '' }
  }
  return {}
}

function requestBodyFields(
  operationId: Stage2OperationId,
  params?: Record<string, string>,
): FieldRow[] {
  if (operationId === 'revoke-installation-key') {
    return [
      {
        name: 'p_kid',
        value: params?.p_kid ?? '',
        meaning: 'installation_keys.kid to revoke',
      },
    ]
  }

  return [
    {
      name: '(body)',
      value: '{}',
      meaning: 'No RPC arguments for this call',
    },
  ]
}

export async function sendStage2SupabaseRequest(
  operationId: Stage2OperationId,
  adminCredentials: SupabaseAdminCredentials,
  params?: Record<string, string>,
): Promise<HttpExchange> {
  const config = await resolveSupabaseConfig(adminCredentials)
  const accessToken = await signInToSupabase(config)
  const rpcName = RPC_BY_OPERATION[operationId]
  const path = `/rest/v1/rpc/${rpcName}`
  const url = `${config.supabaseUrl}${path}`
  const sentAt = new Date().toISOString()
  const rpcBody = rpcBodyForOperation(operationId, params)

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
      body: requestBodyFields(operationId, params),
      raw: buildRawRequest('POST', url, requestHeaders, rpcBody),
    },
    response: {
      status: response.status,
      statusText: response.statusText,
      headers: Object.entries(responseHeaders).map(([name, value]) => ({
        name,
        value,
      })),
      body: flattenResponseBody(payload),
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
