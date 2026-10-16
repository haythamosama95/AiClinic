import { STAGE10_META, STAGE10_OPERATIONS } from '@/catalog/stage-10-stream'
import { JourneyStagePage } from '@/components/JourneyStagePage'

export function Stage10StreamPage() {
  return (
    <JourneyStagePage
      meta={STAGE10_META}
      operations={STAGE10_OPERATIONS}
      seedPanels={
        <div className="stage-page__seed stage-page__seed--stream">
          <p className="stage-page__seed-label">Recommended order</p>
          <ol className="stage-page__seed-list">
            <li>
              Publish + promote fake routing policy (version 91) if local D1 has no
              active policy.
            </li>
            <li>
              Mint clinician AAT with <code>ai.visit_summary</code> scope and matching{' '}
              <code>context.org</code> / <code>context.branch</code>.
            </li>
            <li>Send SSE happy path — save <code>request_reference</code> from accepted.</li>
            <li>GET poll — inspect terminal state in Stage 11.</li>
          </ol>
        </div>
      }
    />
  )
}
