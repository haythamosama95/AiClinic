export function prettyJsonValue(value: unknown): string {
  return JSON.stringify(value, null, 2)
}

export function prettyJsonText(raw: string): string {
  try {
    return prettyJsonValue(JSON.parse(raw) as unknown)
  } catch {
    return raw
  }
}

export function isJsonText(value: string): boolean {
  const trimmed = value.trim()
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    return false
  }
  try {
    JSON.parse(trimmed)
    return true
  } catch {
    return false
  }
}
