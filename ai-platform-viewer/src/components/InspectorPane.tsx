import { useId, useState } from 'react'
import type { FieldRow } from '@/types'
import { FieldList } from '@/components/FieldTable'

interface InspectorPaneProps {
  title: string
  metadataRows: FieldRow[]
  platformRows: FieldRow[]
  pinnedRows?: FieldRow[]
  emptyLabel?: string
}

export function InspectorPane({
  title,
  metadataRows,
  platformRows,
  pinnedRows = [],
  emptyLabel = 'No fields',
}: InspectorPaneProps) {
  const [metadataOpen, setMetadataOpen] = useState(false)
  const metadataId = useId()
  const metadataCount = metadataRows.length
  const hasMetadata = metadataCount > 0
  const hasPlatform = platformRows.length > 0
  const hasPinned = pinnedRows.length > 0

  return (
    <div className="inspector-pane-content">
      <h4 className="field-table__title">{title}</h4>

      {hasMetadata ? (
        <div className="inspector-pane-content__metadata">
          <button
            type="button"
            className="inspector-pane-content__metadata-toggle"
            aria-expanded={metadataOpen}
            aria-controls={metadataId}
            onClick={() => setMetadataOpen((open) => !open)}
          >
            <span className="inspector-pane-content__metadata-chevron" aria-hidden="true" />
            <span className="inspector-pane-content__metadata-label">Metadata</span>
            <span className="inspector-pane-content__metadata-count">
              {metadataCount} {metadataCount === 1 ? 'field' : 'fields'}
            </span>
          </button>

          {metadataOpen ? (
            <div id={metadataId} className="inspector-pane-content__metadata-body">
              <FieldList rows={metadataRows} />
            </div>
          ) : null}
        </div>
      ) : null}

      {hasPinned ? (
        <div className="inspector-pane-content__pinned">
          <FieldList rows={pinnedRows} />
        </div>
      ) : null}

      {hasPlatform ? (
        <div className="inspector-pane-content__platform">
          {hasMetadata || hasPinned ? (
            <p className="inspector-pane-content__platform-label">Payload</p>
          ) : null}
          <FieldList rows={platformRows} />
        </div>
      ) : !hasMetadata && !hasPinned ? (
        <p className="field-table__empty">{emptyLabel}</p>
      ) : null}
    </div>
  )
}
