import { useState } from 'react'
import type { HttpExchange } from '@/types'
import { InspectorPane } from '@/components/InspectorPane'
import { RawPanel } from '@/components/RawPanel'

interface RequestInspectorProps {
  exchange: HttpExchange
}

export function RequestInspector({ exchange }: RequestInspectorProps) {
  const { request, response, sentAt } = exchange
  const ok = response.status >= 200 && response.status < 300
  const [showRaw, setShowRaw] = useState(false)

  return (
    <div className="request-inspector">
      <div className="request-inspector__meta">
        <span className="request-inspector__time">Sent {sentAt}</span>
        <div className="request-inspector__tools">
          <span
            className={`request-inspector__status${ok ? ' request-inspector__status--ok' : ' request-inspector__status--err'}`}
          >
            {response.status} {response.statusText}
          </span>
          <button
            type="button"
            className={`ghost-button ghost-button--compact${showRaw ? ' ghost-button--active' : ''}`}
            aria-pressed={showRaw}
            onClick={() => setShowRaw((value) => !value)}
          >
            Raw
          </button>
        </div>
      </div>

      <div className="request-inspector__panes">
        <section className="inspector-pane">
          {showRaw ? (
            <RawPanel title="Request" value={request.raw} />
          ) : (
            <InspectorPane
              title="Request"
              metadataRows={[
                { name: 'method', value: request.method, meaning: 'HTTP verb' },
                { name: 'url', value: request.url, meaning: 'Gateway control route' },
                ...request.headers,
              ]}
              platformRows={request.body.map((row) => ({
                ...row,
                name: `body.${row.name}`,
              }))}
            />
          )}
        </section>

        <section className="inspector-pane">
          {showRaw ? (
            <RawPanel title="Response" value={response.raw} />
          ) : (
            <InspectorPane
              title="Response"
              metadataRows={response.headers}
              pinnedRows={[
                {
                  name: 'status',
                  value: String(response.status),
                  meaning: response.statusText,
                },
                ...(response.pinned ?? []),
              ]}
              platformRows={response.body.map((row) => ({
                ...row,
                name: row.name === 'body' ? row.name : `body.${row.name}`,
              }))}
            />
          )}
        </section>
      </div>
    </div>
  )
}
