import type {
  JourneyAuth,
  JourneyOperationDefinition,
  JourneyParamField,
} from '@/catalog/journey-types'
import { buildVisitSummaryContextJson } from '@/catalog/stage-8-ingress'
import { buildRawRequest, buildRawResponse } from '@/lib/raw-http'
import { prettyJsonValue } from '@/lib/json-format'
import { isSseText, parseSseResponseBody } from '@/lib/sse-format'
import { sendStage2SupabaseRequest, sendSupabaseRpcRequest } from '@/lib/supabase-api'
import type { ClinicEnrollmentMaterial, FieldRow, HttpExchange } from '@/types'
import type { Stage2OperationId } from '@/catalog/stage-2-clinic-keypair'

const GATEWAY_PREFIX = '/gateway'
const GATEWAY_ORIGIN = 'http://127.0.0.1:8787'

function maskBearer(token: string, emptyLabel: string): string {
  if (!token) return emptyLabel
  if (token.length <= 12) return 'Bearer ••••••••'
  return `Bearer ${token.slice(0, 6)}…${token.slice(-4)}`
}

function fieldMeaning(field: JourneyParamField): string | undefined {
  return field.hint
}

function parseResponseBody(rawBody: string): FieldRow[] {
  if (isSseText(rawBody)) {
    return parseSseResponseBody(rawBody)
  }

  try {
    const parsed = JSON.parse(rawBody) as Record<string, unknown>
    const rows: FieldRow[] = []

    for (const [name, value] of Object.entries(parsed)) {
      rows.push({
        name,
        value:
          value === null || value === undefined
            ? 'null'
            : typeof value === 'object'
              ? prettyJsonValue(value)
              : String(value),
      })
    }

    return rows.length > 0 ? rows : [{ name: '(empty)', value: rawBody || '—' }]
  } catch {
    return [{ name: 'body', value: rawBody || '(empty)' }]
  }
}

export function buildJourneyDefaultParams(
  fields: JourneyParamField[],
  material?: ClinicEnrollmentMaterial | null,
): Record<string, string> {
  const values: Record<string, string> = {}

  for (const field of fields) {
    if (
      field.name === 'context' &&
      field.json &&
      material?.org_id &&
      material.branch_id
    ) {
      values[field.name] = buildVisitSummaryContextJson(
        material.org_id,
        material.branch_id,
      )
    } else if (field.clinicKey && material?.[field.clinicKey]) {
      if (field.json && field.name === 'installation_ids') {
        values[field.name] = JSON.stringify([material[field.clinicKey]])
      } else {
        values[field.name] = material[field.clinicKey]
      }
    } else if (field.defaultValue !== undefined) {
      values[field.name] = field.defaultValue
    } else {
      values[field.name] = ''
    }
  }

  return values
}

export function journeyUsesClinicMaterial(fields: JourneyParamField[]): boolean {
  return fields.some((field) => field.clinicKey !== undefined)
}

export function validateJourneyParams(
  fields: JourneyParamField[],
  params: Record<string, string>,
): string | null {
  for (const field of fields) {
    if (field.required === false) {
      continue
    }
    if (field.name === 'x-idempotency-key' && !params[field.name]?.trim()) {
      continue
    }

    const value = params[field.name]?.trim() ?? ''
    if (!value) {
      return `${field.name} is required`
    }

    if (field.json) {
      try {
        JSON.parse(value)
      } catch {
        return `${field.name} must be valid JSON`
      }
    }
  }

  return null
}

function resolvePath(template: string, params: Record<string, string>): string {
  return template.replace(/\{([^}]+)\}/g, (_, key: string) => {
    const value = params[key]?.trim()
    if (!value) {
      throw new Error(`${key} is required for this path`)
    }
    return encodeURIComponent(value)
  })
}

function buildQueryString(
  fields: JourneyParamField[],
  params: Record<string, string>,
): string {
  const parts: string[] = []

  for (const field of fields) {
    if (field.scope !== 'query') {
      continue
    }
    const value = params[field.name]?.trim()
    if (value) {
      parts.push(`${encodeURIComponent(field.name)}=${encodeURIComponent(value)}`)
    }
  }

  return parts.length > 0 ? `?${parts.join('&')}` : ''
}

function buildJsonBody(
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
      body[field.name] = JSON.parse(raw) as unknown
    } else if (
      raw === 'true' ||
      raw === 'false' ||
      (!Number.isNaN(Number(raw)) && raw !== '' && !field.name.includes('id'))
    ) {
      if (raw === 'true' || raw === 'false') {
        body[field.name] = raw === 'true'
      } else if (/^-?\d+(\.\d+)?$/.test(raw)) {
        body[field.name] = raw.includes('.') ? Number(raw) : Number(raw)
      } else {
        body[field.name] = raw
      }
    } else {
      body[field.name] = raw
    }
  }

  return body
}

function authHeaderRows(auth: JourneyAuth, operatorBearer: string, aat: string): FieldRow[] {
  switch (auth) {
    case 'operator':
      return [
        {
          name: 'Authorization',
          value: maskBearer(operatorBearer, '(not loaded — open Secrets)'),
          meaning: 'OPERATOR_BEARER_TOKEN from ai-platform/.dev.vars',
        },
      ]
    case 'aat':
      return [
        {
          name: 'Authorization',
          value: maskBearer(aat, '(not minted — open Secrets)'),
          meaning: 'Clinic AAT from issue_ai_token',
        },
      ]
    default:
      return []
  }
}

function buildRequestHeaders(
  operation: JourneyOperationDefinition,
  params: Record<string, string>,
  operatorBearer: string,
  aat: string,
): Record<string, string> {
  const headers: Record<string, string> = {}

  switch (operation.auth) {
    case 'operator':
      headers.Authorization = `Bearer ${operatorBearer}`
      break
    case 'aat':
      headers.Authorization = `Bearer ${aat}`
      break
    default:
      break
  }

  if (
    operation.bodyKind === 'json' ||
    operation.bodyKind === 'empty' ||
    operation.bodyKind === 'sse'
  ) {
    headers['Content-Type'] = 'application/json'
  }

  for (const field of operation.fields) {
    if (field.scope !== 'header') {
      continue
    }
    const value = params[field.name]?.trim()
    if (value) {
      headers[field.name] = value
    }
  }

  if (
    operation.method === 'POST' &&
    operation.fields.some((field) => field.name === 'x-idempotency-key') &&
    !headers['x-idempotency-key']
  ) {
    headers['x-idempotency-key'] = crypto.randomUUID()
  }

  return headers
}

export async function sendJourneyRequest(
  operation: JourneyOperationDefinition,
  params: Record<string, string>,
  credentials: {
    operatorBearer: string
    aat: string
    supabaseAdmin?: { username: string; password: string }
  },
): Promise<HttpExchange> {
  if (operation.method === 'RPC') {
    if (!credentials.supabaseAdmin) {
      throw new Error('Supabase admin credentials not loaded.')
    }
    if (!operation.rpcName) {
      throw new Error('RPC operation is missing rpcName.')
    }

    if (operation.id.startsWith('stage2-')) {
      const rpcParams: Record<string, string> = {}
      for (const field of operation.fields) {
        if (field.scope !== 'body') {
          continue
        }
        const value = params[field.name]?.trim()
        if (value) {
          rpcParams[field.name] = value
        }
      }
      return sendStage2SupabaseRequest(
        operation.id.replace(/^stage2-/, '') as Stage2OperationId,
        credentials.supabaseAdmin,
        Object.keys(rpcParams).length > 0 ? rpcParams : undefined,
      )
    }

    return sendSupabaseRpcRequest(
      {
        rpcName: operation.rpcName,
        fields: operation.fields,
        params,
      },
      credentials.supabaseAdmin,
    )
  }

  const validationError = validateJourneyParams(operation.fields, params)
  if (validationError) {
    throw new Error(validationError)
  }

  if (operation.auth === 'operator' && !credentials.operatorBearer) {
    throw new Error('Operator bearer not loaded. Open Secrets or check ai-platform/.dev.vars.')
  }
  if (operation.auth === 'aat' && !credentials.aat) {
    throw new Error('Clinic AAT not loaded. Mint one from Secrets first.')
  }

  const querySuffix = buildQueryString(operation.fields, params)
  const pathWithQuery = resolvePath(operation.path, params) + querySuffix
  const url = `${GATEWAY_PREFIX}${pathWithQuery}`
  const displayPath = querySuffix ? `${operation.path}${querySuffix}` : operation.path
  const sentAt = new Date().toISOString()
  const requestHeaders = buildRequestHeaders(
    operation,
    params,
    credentials.operatorBearer,
    credentials.aat,
  )

  let body: Record<string, unknown> | undefined
  if (operation.bodyKind === 'json' || operation.bodyKind === 'sse') {
    body = buildJsonBody(operation.fields, params)
  } else if (operation.bodyKind === 'empty') {
    body = {}
  }

  const fetchInit: RequestInit = {
    method: operation.method,
    headers: requestHeaders,
  }
  if (body !== undefined) {
    fetchInit.body = JSON.stringify(body)
  }

  const response = await fetch(url, fetchInit)
  let rawBody = await response.text()

  if (operation.bodyKind === 'sse' && response.ok) {
    const lines = rawBody.split('\n').filter((line) => line.trim())
    const preview = lines.slice(0, 12).join('\n')
    rawBody = lines.length > 12 ? `${preview}\n… (${lines.length} SSE lines total)` : preview
  }

  const responseHeaders: Record<string, string> = {}
  response.headers.forEach((value, name) => {
    responseHeaders[name] = value
  })

  const bodyRows: FieldRow[] =
    body && Object.keys(body).length > 0
      ? operation.fields
        .filter((field) => field.scope === 'body')
        .map((field) => ({
          name: field.name,
          value:
            field.json && body![field.name] !== undefined
              ? JSON.stringify(body![field.name])
              : String(body![field.name] ?? ''),
          meaning: fieldMeaning(field),
        }))
      : operation.bodyKind === 'empty'
        ? [{ name: '(body)', value: '{}', meaning: 'Empty JSON object' }]
        : []

  const headerRows: FieldRow[] = [
    ...authHeaderRows(operation.auth, credentials.operatorBearer, credentials.aat),
    ...operation.fields
      .filter((field) => field.scope === 'header')
      .map((field) => ({
        name: field.name,
        value: requestHeaders[field.name] ?? params[field.name] ?? '',
        meaning: fieldMeaning(field),
      })),
    ...operation.fields
      .filter((field) => field.scope === 'query')
      .map((field) => ({
        name: field.name,
        value: params[field.name] ?? '',
        meaning: fieldMeaning(field),
      })),
  ]

  if (
    operation.bodyKind === 'json' ||
    operation.bodyKind === 'empty' ||
    operation.bodyKind === 'sse'
  ) {
    if (!headerRows.some((row) => row.name === 'Content-Type')) {
      headerRows.push({ name: 'Content-Type', value: 'application/json' })
    }
  }

  const rawRequestHeaders = { ...requestHeaders }
  if (operation.auth === 'operator') {
    rawRequestHeaders.Authorization = `Bearer ${credentials.operatorBearer}`
  } else if (operation.auth === 'aat') {
    rawRequestHeaders.Authorization = `Bearer ${credentials.aat}`
  }

  return {
    request: {
      method: operation.method,
      url: `${GATEWAY_ORIGIN}${pathWithQuery}`,
      headers: headerRows,
      body: bodyRows,
      raw: buildRawRequest(
        operation.method,
        `${GATEWAY_ORIGIN}${displayPath}`,
        rawRequestHeaders,
        body,
      ),
    },
    response: {
      status: response.status,
      statusText: response.statusText,
      headers: Object.entries(responseHeaders).map(([name, value]) => ({ name, value })),
      body: parseResponseBody(rawBody),
      rawBody,
      raw: buildRawResponse(response.status, response.statusText, responseHeaders, rawBody),
    },
    sentAt,
  }
}
