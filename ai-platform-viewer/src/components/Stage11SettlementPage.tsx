import { STAGE11_META, STAGE11_OPERATIONS } from '@/catalog/stage-11-settlement'
import { JourneyStagePage } from '@/components/JourneyStagePage'

export function Stage11SettlementPage() {
  return (
    <JourneyStagePage
      meta={STAGE11_META}
      operations={STAGE11_OPERATIONS}
      seedPanels={
        <div className="stage-page__seed stage-page__seed--settlement">
          <p className="stage-page__seed-label">Prerequisites</p>
          <dl className="stage-page__seed-grid">
            <div>
              <dt>request_reference</dt>
              <dd>
                Copy from Stage 10 SSE <code>accepted</code> frame (XXXX-XXXX)
              </dd>
            </div>
            <div>
              <dt>request_id (RID)</dt>
              <dd>Only in D1 — not in SSE; use wrangler to join journal tables</dd>
            </div>
            <div>
              <dt>payload_pointer</dt>
              <dd>
                <code>request/&lt;request_id&gt;/envelope</code> after settlement
              </dd>
            </div>
          </dl>
        </div>
      }
    />
  )
}
