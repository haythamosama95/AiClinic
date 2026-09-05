import { prettyJsonText } from '@/lib/json-format'
import { isSseText, prettySseText } from '@/lib/sse-format'

export function buildRawRequest(
  method: string,
  url: string,
  headers: Record<string, string>,
  body?: Record<string, unknown>,
): string {
  const headerLines = Object.entries(headers).map(
    ([name, value]) => `${name}: ${value}`,
  )
  const lines = [`${method} ${url}`, ...headerLines, '']
  if (body !== undefined) {
    lines.push(JSON.stringify(body, null, 2))
  }
  return lines.join('\n')
}

export function buildRawResponse(
  status: number,
  statusText: string,
  headers: Record<string, string>,
  rawBody: string,
): string {
  const headerLines = Object.entries(headers).map(
    ([name, value]) => `${name}: ${value}`,
  )
  const formattedBody = isSseText(rawBody) ? prettySseText(rawBody) : prettyJsonText(rawBody)

  return [
    `HTTP/1.1 ${status} ${statusText}`,
    ...headerLines,
    '',
    formattedBody,
  ].join('\n')
}
