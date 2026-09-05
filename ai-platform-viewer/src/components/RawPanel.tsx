import { isJsonText } from '@/lib/json-format'
import { JsonBlock } from '@/components/JsonBlock'

interface RawPanelProps {
  title: string
  value: string
}

function splitRawHttp(value: string): { headers: string; body: string } {
  const separator = value.indexOf('\n\n')
  if (separator === -1) {
    return { headers: value, body: '' }
  }
  return {
    headers: value.slice(0, separator),
    body: value.slice(separator + 2),
  }
}

export function RawPanel({ title, value }: RawPanelProps) {
  const { headers, body } = splitRawHttp(value)
  const bodyIsJson = body.length > 0 && isJsonText(body)

  return (
    <div className="raw-panel">
      <h4 className="raw-panel__title">{title}</h4>
      {bodyIsJson ? (
        <div className="raw-panel__split">
          <pre className="raw-panel__headers" aria-label={`${title} headers`}>
            {headers}
          </pre>
          <JsonBlock value={body} className="raw-panel__json" />
        </div>
      ) : (
        <textarea
          className="raw-panel__output"
          readOnly
          spellCheck={false}
          value={value}
          aria-label={`${title} raw`}
        />
      )}
    </div>
  )
}
