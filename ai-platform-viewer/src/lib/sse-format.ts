import type { FieldRow } from '@/types'
import { prettyJsonText } from '@/lib/json-format'

export function isSseText(text: string): boolean {
  const trimmed = text.trim()
  return /^event:\s/m.test(trimmed) && /^data:\s/m.test(trimmed)
}

function parseSseBlock(block: string): { event: string; data: string } | null {
  const trimmed = block.trim()
  if (!trimmed || trimmed.startsWith('…')) {
    return null
  }

  let event = ''
  let data = ''

  for (const line of trimmed.split('\n')) {
    if (line.startsWith('event:')) {
      event = line.slice('event:'.length).trim()
    } else if (line.startsWith('data:')) {
      data = line.slice('data:'.length).trim()
    }
  }

  if (!event) {
    return null
  }

  return { event, data }
}

export function prettySseText(text: string): string {
  const blocks = text.split(/\n\n+/)
  const formatted: string[] = []

  for (const block of blocks) {
    const trimmed = block.trim()
    if (!trimmed) {
      continue
    }
    if (trimmed.startsWith('…')) {
      formatted.push(trimmed)
      continue
    }

    const parsed = parseSseBlock(trimmed)
    if (!parsed) {
      formatted.push(trimmed)
      continue
    }

    if (parsed.data) {
      formatted.push(`event: ${parsed.event}\ndata:\n${prettyJsonText(parsed.data)}`)
    } else {
      formatted.push(`event: ${parsed.event}`)
    }
  }

  return formatted.join('\n\n')
}

export function parseSseResponseBody(text: string): FieldRow[] {
  const blocks = text.split(/\n\n+/).filter((block) => block.trim().length > 0)
  const rows: FieldRow[] = []

  for (const block of blocks) {
    const trimmed = block.trim()
    if (trimmed.startsWith('…')) {
      rows.push({ name: 'stream', value: trimmed, meaning: 'Truncated SSE preview' })
      continue
    }

    const parsed = parseSseBlock(trimmed)
    if (!parsed) {
      continue
    }

    rows.push({
      name: parsed.event,
      value: parsed.data ? prettyJsonText(parsed.data) : '(no data)',
      meaning: 'SSE event frame',
    })
  }

  return rows.length > 0
    ? rows
    : [{ name: 'body', value: prettySseText(text) || '(empty)' }]
}
