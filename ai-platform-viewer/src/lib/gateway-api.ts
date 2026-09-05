import type { FieldRow, HttpExchange } from '@/types'
import { buildRawRequest, buildRawResponse } from '@/lib/raw-http'
import { prettyJsonValue } from '@/lib/json-format'
import { ensurePlatformEnrollment } from '@/lib/platform-enroll'

const GATEWAY_PREFIX = '/gateway'

function maskBearer(token: string): string {
  if (!token) return '(not loaded — open Secrets)'
  if (token.length <= 12) return 'Bearer ••••••••'
  return `Bearer ${token.slice(0, 6)}…${token.slice(-4)}`
}

function maskAat(token: string): string {
  if (!token) return '(not minted — open Secrets)'
  if (token.length <= 12) return 'Bearer ••••••••'
  return `Bearer ${token.slice(0, 6)}…${token.slice(-4)}`
}

function headerRows(operatorBearer: string): FieldRow[] {
  return [
    {
      name: 'Authorization',
      value: maskBearer(operatorBearer),
      meaning: 'OPERATOR_BEARER_TOKEN from ai-platform/.dev.vars',
    },
    {
      name: 'Content-Type',
      value: 'application/json',
      meaning: 'JSON request body',
    },
  ]
}

function bodyVerRow(ver: string): FieldRow[] {
  return [
    {
      name: 'ver',
      value: ver,
      meaning: 'AAT version string; must match the JWT ver claim at verify time',
    },
  ]
}

function parseResponseBody(rawBody: string): FieldRow[] {
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
        meaning: responseFieldMeaning(name),
      })
    }

    return rows.length > 0 ? rows : [{ name: '(empty)', value: '—' }]
  } catch {
    return [{ name: 'body', value: rawBody || '(empty)' }]
  }
}

function responseFieldMeaning(name: string): string | undefined {
  switch (name) {
    case 'ver':
      return 'Accepted or retired AAT contract version'
    case 'retired_at':
      return 'ISO timestamp when this ver stopped accepting tokens'
    case 'error':
      return 'Machine-readable failure code from the gateway'
    case 'code':
      return 'Taxonomy error code when identity verify fails'
    default:
      return undefined
  }
}

export async function sendTokenContractRequest(
  path: '/control/token-contract/begin-rotation' | '/control/token-contract/retire',
  ver: string,
  operatorBearer: string,
): Promise<HttpExchange> {
  if (!operatorBearer) {
    throw new Error('Operator bearer not loaded. Open Secrets or check ai-platform/.dev.vars.')
  }

  const url = `${GATEWAY_PREFIX}${path}`
  const body = { ver: ver.trim() }
  const sentAt = new Date().toISOString()

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${operatorBearer}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })

  const rawBody = await response.text()
  const responseHeaders: Record<string, string> = {
    'content-type': response.headers.get('content-type') ?? '(none)',
  }
  const requestHeaders: Record<string, string> = {
    Authorization: `Bearer ${operatorBearer}`,
    'Content-Type': 'application/json',
  }

  return {
    request: {
      method: 'POST',
      url: `http://127.0.0.1:8787${path}`,
      headers: headerRows(operatorBearer),
      body: bodyVerRow(body.ver),
      raw: buildRawRequest('POST', `http://127.0.0.1:8787${path}`, requestHeaders, body),
    },
    response: {
      status: response.status,
      statusText: response.statusText,
      headers: [
        {
          name: 'content-type',
          value: responseHeaders['content-type'],
        },
      ],
      body: parseResponseBody(rawBody),
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

export async function sendCapabilitiesRequest(
  aat: string,
  operatorBearer: string,
): Promise<HttpExchange> {
  if (!aat) {
    throw new Error('Clinic AAT not loaded. Mint one from Secrets first.')
  }

  await ensurePlatformEnrollment(operatorBearer)

  const path = '/v1/capabilities'
  const url = `${GATEWAY_PREFIX}${path}`
  const sentAt = new Date().toISOString()

  const response = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${aat}`,
    },
  })

  const rawBody = await response.text()
  const responseHeaders: Record<string, string> = {
    'content-type': response.headers.get('content-type') ?? '(none)',
    'cache-control': response.headers.get('cache-control') ?? '(none)',
    etag: response.headers.get('etag') ?? '(none)',
  }
  const requestHeaders: Record<string, string> = {
    Authorization: `Bearer ${aat}`,
  }

  return {
    request: {
      method: 'GET',
      url: `http://127.0.0.1:8787${path}`,
      headers: [
        {
          name: 'Authorization',
          value: maskAat(aat),
          meaning: 'Clinic AAT minted from Supabase issue_ai_token',
        },
      ],
      body: [],
      raw: buildRawRequest('GET', `http://127.0.0.1:8787${path}`, requestHeaders),
    },
    response: {
      status: response.status,
      statusText: response.statusText,
      headers: Object.entries(responseHeaders).map(([name, value]) => ({
        name,
        value,
      })),
      body: parseResponseBody(rawBody),
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
