import type { FieldRow, HttpExchange } from '@/types'
import { buildRawRequest, buildRawResponse } from '@/lib/raw-http'
import { prettyJsonValue } from '@/lib/json-format'
import {
  type IssuerKeyMaterial,
  type IssuerTokenClaims,
  issuerContractVersionHeader,
  mintIssuerToken,
} from '@/lib/issuer-token'

const GATEWAY_PREFIX = '/gateway'
const GATEWAY_ORIGIN = 'http://127.0.0.1:8787'

function gatewayFetchUrl(pathWithQuery: string): string {
  if (typeof window === 'undefined') {
    return `${GATEWAY_ORIGIN}${pathWithQuery}`
  }
  return `${GATEWAY_PREFIX}${pathWithQuery}`
}

function maskToken(token: string, emptyLabel: string): string {
  if (!token) return emptyLabel
  if (token.length <= 12) return 'Bearer ••••••••'
  return `Bearer ${token.slice(0, 6)}…${token.slice(-4)}`
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

export async function sendCapabilitiesRequest(
  issuerKey: IssuerKeyMaterial,
  claims: IssuerTokenClaims = {},
): Promise<HttpExchange> {
  const token = await mintIssuerToken(issuerKey, claims)
  const path = '/v1/capabilities'
  const url = gatewayFetchUrl(path)
  const sentAt = new Date().toISOString()
  const contractVersion = issuerContractVersionHeader()

  const response = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${token}`,
      'Aip-Contract-Version': contractVersion,
    },
  })

  const rawBody = await response.text()
  const responseHeaders: Record<string, string> = {
    'content-type': response.headers.get('content-type') ?? '(none)',
    'cache-control': response.headers.get('cache-control') ?? '(none)',
    etag: response.headers.get('etag') ?? '(none)',
  }
  const requestHeaders: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    'Aip-Contract-Version': contractVersion,
  }

  return {
    request: {
      method: 'GET',
      url: `${GATEWAY_ORIGIN}${path}`,
      headers: [
        {
          name: 'Authorization',
          value: maskToken(token, '(issuer token not minted)'),
          meaning: 'Issuer token signed by the test issuer key',
        },
        {
          name: 'Aip-Contract-Version',
          value: contractVersion,
          meaning: 'Clinic contract version accepted by the platform',
        },
      ],
      body: [],
      raw: buildRawRequest('GET', `${GATEWAY_ORIGIN}${path}`, requestHeaders),
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
