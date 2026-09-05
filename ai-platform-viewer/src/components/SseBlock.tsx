import { useMemo } from 'react'
import { isSseText, prettySseText } from '@/lib/sse-format'

interface SseBlockProps {
  value: string
  className?: string
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}

function highlightSse(text: string): string {
  const escaped = escapeHtml(text)

  return escaped.replace(
    /("(\\u[a-fA-F0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?|^event:.*$|^data:$)/gm,
    (match) => {
      if (match.startsWith('event:')) {
        return `<span class="sse-block__event">${match}</span>`
      }
      if (match === 'data:') {
        return `<span class="sse-block__label">${match}</span>`
      }

      let className = 'json-block__number'
      if (/^"/.test(match)) {
        className = /:$/.test(match) ? 'json-block__key' : 'json-block__string'
      } else if (/true|false/.test(match)) {
        className = 'json-block__boolean'
      } else if (/null/.test(match)) {
        className = 'json-block__null'
      }
      return `<span class="${className}">${match}</span>`
    },
  )
}

export function SseBlock({ value, className }: SseBlockProps) {
  const formatted = useMemo(() => {
    if (!isSseText(value)) {
      return value
    }
    return prettySseText(value)
  }, [value])

  const highlighted = useMemo(() => highlightSse(formatted), [formatted])

  if (!isSseText(value)) {
    return <code className={className}>{value}</code>
  }

  return (
    <pre className={`sse-block json-block${className ? ` ${className}` : ''}`}>
      <code dangerouslySetInnerHTML={{ __html: highlighted }} />
    </pre>
  )
}
