import { useMemo } from 'react'
import { isJsonText, prettyJsonText } from '@/lib/json-format'

interface JsonBlockProps {
  value: string
  className?: string
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}

function highlightJson(json: string): string {
  const escaped = escapeHtml(json)

  return escaped.replace(
    /("(\\u[a-fA-F0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
    (match) => {
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

export function JsonBlock({ value, className }: JsonBlockProps) {
  const formatted = useMemo(() => {
    if (!isJsonText(value)) {
      return value
    }
    return prettyJsonText(value)
  }, [value])

  const highlighted = useMemo(() => highlightJson(formatted), [formatted])

  if (!isJsonText(value)) {
    return <code className={className}>{value}</code>
  }

  return (
    <pre className={`json-block${className ? ` ${className}` : ''}`}>
      <code dangerouslySetInnerHTML={{ __html: highlighted }} />
    </pre>
  )
}
