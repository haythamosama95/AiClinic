import path from 'node:path'
import { spawn } from 'node:child_process'
import type { HttpExchange } from '../src/types.ts'

function buildRawResponse(
  status: number,
  statusText: string,
  headers: Record<string, string>,
  rawBody: string,
): string {
  const headerLines = Object.entries(headers).map(
    ([name, value]) => `${name}: ${value}`,
  )
  return [`HTTP/1.1 ${status} ${statusText}`, ...headerLines, '', rawBody].join('\n')
}

const AI_PLATFORM_DIR = path.resolve(import.meta.dirname, '../../ai-platform')

const INVOICE_LIST_SQL = `
SELECT installation_id, period, credits_consumed, credit_price_version, total, status, issued_at
  FROM invoice
 ORDER BY issued_at DESC
`.trim()

function escapeSqlLiteral(value: string): string {
  return value.replace(/'/g, "''")
}

function buildInvoiceDetailSql(installationId: string, period: string): string {
  const installation = escapeSqlLiteral(installationId)
  const periodLiteral = escapeSqlLiteral(period)

  return `
SELECT rollup_id, dimensions, request_count, quota_weight, tokens, cost
  FROM usage_rollup
 WHERE json_extract(dimensions, '$.installation_id') = '${installation}'
   AND json_extract(dimensions, '$.period') = '${periodLiteral}';

SELECT ue.request_id, ar.request_reference
  FROM usage_event ue
  JOIN ai_request ar ON ar.request_id = ue.request_id
 WHERE ue.installation_id = '${installation}'
   AND ue.period = '${periodLiteral}'
   AND ue.request_id IS NOT NULL
 ORDER BY ar.request_reference;
`.trim()
}

function runCommand(
  command: string,
  args: string[],
  cwd: string,
): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      shell: false,
      env: process.env,
    })
    let stdout = ''
    let stderr = ''

    child.stdout.on('data', (chunk: Buffer) => {
      stdout += chunk.toString()
    })
    child.stderr.on('data', (chunk: Buffer) => {
      stderr += chunk.toString()
    })
    child.on('error', reject)
    child.on('close', (code) => resolve({ stdout, stderr, code }))
  })
}

async function executeD1Statements(
  sql: string,
): Promise<Array<Record<string, unknown>>> {
  const result = await runCommand(
    'npx',
    [
      'wrangler',
      'd1',
      'execute',
      'ai-platform-development',
      '--local',
      '--env',
      'development',
      '--command',
      sql,
      '--json',
    ],
    AI_PLATFORM_DIR,
  )

  if (result.code !== 0) {
    throw new Error(result.stderr || result.stdout || 'D1 inspect failed')
  }

  const trimmed = result.stdout.trim()
  if (!trimmed) {
    return []
  }

  const parsed = JSON.parse(trimmed) as
    | { error?: { text?: string } }
    | Array<{ results?: Array<Record<string, unknown>>; success?: boolean }>

  if (!Array.isArray(parsed)) {
    if (parsed.error?.text) {
      throw new Error(parsed.error.text)
    }
    throw new Error('Unexpected D1 inspect response')
  }

  const rows: Array<Record<string, unknown>> = []
  for (const entry of parsed) {
    if (entry.results) {
      rows.push(...entry.results)
    }
  }
  return rows
}

function wrapSqlExchange(
  sql: string,
  responseBody: unknown,
  url: string,
): HttpExchange {
  const rawBody = JSON.stringify(responseBody, null, 2)
  const responseHeaders = { 'Content-Type': 'application/json' }

  return {
    request: {
      method: 'SQL',
      url,
      headers: [],
      body: [],
      raw: sql,
    },
    response: {
      status: 200,
      statusText: 'OK',
      headers: Object.entries(responseHeaders).map(([name, value]) => ({
        name,
        value,
      })),
      body: [],
      rawBody,
      raw: buildRawResponse(200, 'OK', responseHeaders, rawBody),
    },
    sentAt: new Date().toISOString(),
  }
}

export async function listIssuedInvoices(): Promise<HttpExchange> {
  const rows = await executeD1Statements(INVOICE_LIST_SQL)
  return wrapSqlExchange(INVOICE_LIST_SQL, rows, 'd1://invoice/list')
}

export async function fetchInvoiceDetailEvidence(
  installationId: string,
  period: string,
): Promise<HttpExchange> {
  const sql = buildInvoiceDetailSql(installationId, period)
  const statements = sql
    .split(';')
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0)

  const rollupLines =
    statements[0] ? await executeD1Statements(`${statements[0]};`) : []
  const traces =
    statements[1] ? await executeD1Statements(`${statements[1]};`) : []

  const payload = {
    rollup_lines: rollupLines,
    traces,
  }

  return wrapSqlExchange(
    sql,
    payload,
    `d1://invoice/detail?installation_id=${encodeURIComponent(installationId)}&period=${encodeURIComponent(period)}`,
  )
}
