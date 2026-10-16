import type { FieldRow } from '@/types'
import { JsonBlock } from '@/components/JsonBlock'
import { SseBlock } from '@/components/SseBlock'
import { isJsonText } from '@/lib/json-format'
import { isSseText } from '@/lib/sse-format'

interface FieldListProps {
  rows: FieldRow[]
  keyPrefix?: string
}

export function FieldList({ rows, keyPrefix = 'field' }: FieldListProps) {
  return (
    <dl className="field-table__list">
      {rows.map((row) => (
        <div key={`${keyPrefix}-${row.name}`} className="field-table__row">
          <dt>{row.name}</dt>
          <dd>
            {isSseText(row.value) ? (
              <SseBlock value={row.value} />
            ) : isJsonText(row.value) ? (
              <JsonBlock value={row.value} />
            ) : (
              <code>{row.value}</code>
            )}
            {row.meaning ? (
              <span className="field-table__meaning">{row.meaning}</span>
            ) : null}
          </dd>
        </div>
      ))}
    </dl>
  )
}

interface FieldTableProps {
  title: string
  rows: FieldRow[]
  emptyLabel?: string
}

export function FieldTable({ title, rows, emptyLabel = 'No fields' }: FieldTableProps) {
  return (
    <div className="field-table">
      <h4 className="field-table__title">{title}</h4>
      {rows.length === 0 ? (
        <p className="field-table__empty">{emptyLabel}</p>
      ) : (
        <FieldList rows={rows} keyPrefix={title} />
      )}
    </div>
  )
}
