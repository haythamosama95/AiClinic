function prettyJson(raw: string): string {
  try {
    return JSON.stringify(JSON.parse(raw) as unknown, null, 2)
  } catch {
    return raw
  }
}

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
  return [
    `HTTP/1.1 ${status} ${statusText}`,
    ...headerLines,
    '',
    prettyJson(rawBody),
  ].join('\n')
}
