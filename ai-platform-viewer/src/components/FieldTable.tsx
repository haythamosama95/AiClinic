import type { FieldRow } from '@/types'

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
        <dl className="field-table__list">
          {rows.map((row) => (
            <div key={`${title}-${row.name}`} className="field-table__row">
              <dt>{row.name}</dt>
              <dd>
                <code>{row.value}</code>
                {row.meaning ? (
                  <span className="field-table__meaning">{row.meaning}</span>
                ) : null}
              </dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  )
}
