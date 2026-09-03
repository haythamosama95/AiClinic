import type {
  Stage3OperationId,
  Stage3ParamField,
} from '@/catalog/stage-3-platform-installation'
import { STAGE3_PARAM_FIELDS } from '@/catalog/stage-3-platform-installation'
import { buildRawRequest, buildRawResponse } from '@/lib/raw-http'
import type { ClinicEnrollmentMaterial, FieldRow, HttpExchange } from '@/types'

const GATEWAY_PREFIX = '/gateway'
const GATEWAY_ORIGIN = 'http://127.0.0.1:8787'

function maskBearer(token: string, emptyLabel: string): string {
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
              ? JSON.stringify(value)
              : String(value),
        meaning: responseFieldMeaning(name),
      })
    }

    return rows.length > 0 ? rows : [{ name: '(empty)', value: '{}' }]
  } catch {
    return [{ name: 'body', value: rawBody || '(empty)' }]
  }
}

function responseFieldMeaning(name: string): string | undefined {
  switch (name) {
    case 'platform_base_url':
      return 'Worker origin echo — store in clinic ai.availability (not written by platform)'
    case 'error':
      return 'Machine-readable control-plane failure code'
    case 'code':
      return 'Taxonomy error code from /v1/* guard'
    case 'path':
      return 'Guard rejection path (e.g. ai_disabled, installation_suspended)'
    default:
      return undefined
  }
}

function fieldMeaning(field: Stage3ParamField): string | undefined {
  return field.hint
}

function operatorHeaderRows(operatorBearer: string): FieldRow[] {
  return [
    {
      name: 'Authorization',
      value: maskBearer(operatorBearer, '(not loaded — open Secrets)'),
      meaning: 'OPERATOR_BEARER_TOKEN from ai-platform/.dev.vars',
    },
    {
      name: 'Content-Type',
      value: 'application/json',
      meaning: 'JSON request body',
    },
  ]
}

function installationPath(installationId: string, suffix: string): string {
  return `/control/installations/${installationId}${suffix}`
}

function pathSuffixForOperation(operationId: Stage3OperationId): string {
  switch (operationId) {
    case 'enroll':
      return '/enroll'
    case 'rotate':
      return '/rotate'
    case 'revoke-key':
      return '/revoke-key'
    case 'suspend':
      return '/suspend'
    case 'resume':
      return '/resume'
    case 'delete':
      return '/delete'
    case 'purge':
      return '/purge'
    default:
      return ''
  }
}

export function stage3UsesClinicMaterial(operationId: Stage3OperationId): boolean {
  return STAGE3_PARAM_FIELDS[operationId].some((field) => field.clinicKey !== undefined)
}

export function buildStage3DefaultParams(
  operationId: Stage3OperationId,
  material?: ClinicEnrollmentMaterial | null,
): Record<string, string> {
  const values: Record<string, string> = {}

  for (const field of STAGE3_PARAM_FIELDS[operationId]) {
    if (field.clinicKey && material?.[field.clinicKey]) {
      values[field.name] = material[field.clinicKey]
    } else if (field.defaultValue !== undefined) {
      values[field.name] = field.defaultValue
    } else {
      values[field.name] = ''
    }
  }

  return values
}

export function validateStage3Params(
  operationId: Stage3OperationId,
  params: Record<string, string>,
): string | null {
  for (const field of STAGE3_PARAM_FIELDS[operationId]) {
    if (field.name === 'x-idempotency-key') {
      continue
    }

    const value = params[field.name]?.trim() ?? ''
    if (!value) {
      return `${field.name} is required`
    }
  }

  if (operationId === 'v1-request-probe') {
    const context = params.context?.trim() ?? ''
    try {
      const parsed = JSON.parse(context) as unknown
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return 'context must be a JSON object'
      }
    } catch {
      return 'context must be valid JSON'
    }
  }

  return null
}

export async function sendStage3Request(
  operationId: Stage3OperationId,
  operatorBearer: string,
  aat: string,
  params: Record<string, string>,
): Promise<HttpExchange> {
  const validationError = validateStage3Params(operationId, params)
  if (validationError) {
    throw new Error(validationError)
  }

  const fields = STAGE3_PARAM_FIELDS[operationId]
  const sentAt = new Date().toISOString()

  if (operationId === 'v1-request-probe') {
    if (!aat) {
      throw new Error('Clinic AAT not loaded. Mint one from Secrets first.')
    }

    const path = '/v1/requests'
    const idempotencyKey =
      params['x-idempotency-key']?.trim() || crypto.randomUUID()
    const capabilityVersion = params['x-capability-version']?.trim() || '1.0.0'
    const context = JSON.parse(params.context.trim()) as Record<string, unknown>
    const body = {
      capability_id: params.capability_id.trim(),
      user_intent: params.user_intent.trim(),
      context,
    }
    const requestHeaders: Record<string, string> = {
      Authorization: `Bearer ${aat}`,
      'Content-Type': 'application/json',
      'x-idempotency-key': idempotencyKey,
      'x-capability-version': capabilityVersion,
    }

    const response = await fetch(`${GATEWAY_PREFIX}${path}`, {
      method: 'POST',
      headers: requestHeaders,
      body: JSON.stringify(body),
    })

    const rawBody = await response.text()
    const responseHeaders: Record<string, string> = {
      'content-type': response.headers.get('content-type') ?? '(none)',
    }

    const bodyRows: FieldRow[] = fields
      .filter((field) => field.scope === 'body')
      .map((field) => ({
        name: field.name,
        value: params[field.name],
        meaning: fieldMeaning(field),
      }))

    const headerRows: FieldRow[] = [
      {
        name: 'Authorization',
        value: maskBearer(aat, '(not minted)'),
        meaning: 'Clinic AAT from issue_ai_token',
      },
      { name: 'Content-Type', value: 'application/json' },
      {
        name: 'x-idempotency-key',
        value: idempotencyKey,
        meaning: fields.find((field) => field.name === 'x-idempotency-key')?.hint,
      },
      {
        name: 'x-capability-version',
        value: capabilityVersion,
        meaning: fields.find((field) => field.name === 'x-capability-version')?.hint,
      },
    ]

    return {
      request: {
        method: 'POST',
        url: `${GATEWAY_ORIGIN}${path}`,
        headers: headerRows,
        body: bodyRows,
        raw: buildRawRequest('POST', `${GATEWAY_ORIGIN}${path}`, requestHeaders, body),
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

  if (!operatorBearer) {
    throw new Error('Operator bearer not loaded. Open Secrets or check ai-platform/.dev.vars.')
  }

  const installationId = params.installation_id.trim()
  const suffix = pathSuffixForOperation(operationId)
  const path = installationPath(installationId, suffix)

  const body: Record<string, unknown> = {}
  for (const field of fields) {
    if (field.scope === 'body') {
      body[field.name] = params[field.name].trim()
    }
  }

  const requestHeaders: Record<string, string> = {
    Authorization: `Bearer ${operatorBearer}`,
    'Content-Type': 'application/json',
  }

  const response = await fetch(`${GATEWAY_PREFIX}${path}`, {
    method: 'POST',
    headers: requestHeaders,
    body: JSON.stringify(body),
  })

  const rawBody = await response.text()
  const responseHeaders: Record<string, string> = {
    'content-type': response.headers.get('content-type') ?? '(none)',
  }

  const displayPath = path.replace(installationId, '{installation_id}')
  const bodyRows: FieldRow[] =
    Object.keys(body).length > 0
      ? fields
        .filter((field) => field.scope === 'body')
        .map((field) => ({
          name: field.name,
          value: String(body[field.name]),
          meaning: fieldMeaning(field),
        }))
      : [{ name: '(body)', value: '{}', meaning: 'Empty JSON object' }]

  return {
    request: {
      method: 'POST',
      url: `${GATEWAY_ORIGIN}${path}`,
      headers: [
        ...operatorHeaderRows(operatorBearer),
        {
          name: 'installation_id',
          value: installationId,
          meaning: 'Path parameter — from Stage 2 RPC, editable above',
        },
      ],
      body: bodyRows,
      raw: buildRawRequest('POST', `${GATEWAY_ORIGIN}${displayPath}`, requestHeaders, body),
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
