import { STAGE6_META, STAGE6_OPERATIONS } from '@/catalog/stage-6-mint-aat'
import { JourneyStagePage } from '@/components/JourneyStagePage'

export function Stage6MintAatPage() {
  return (
    <JourneyStagePage
      meta={STAGE6_META}
      operations={STAGE6_OPERATIONS}
      seedPanels={
        <div className="stage-page__seed stage-page__seed--mint">
          <p className="stage-page__seed-label">AAT session</p>
          <p className="operation-card__hint">
            A successful mint returns a compact JWS. Use <strong>Mint AAT</strong> in the header
            bar to load it into the Secrets session automatically (Stages 7–8 read that token), or
            send <code>issue_ai_token</code> below and copy the response token into Secrets
            manually. Seed <code>ai.aat.lifetime_minutes</code> is 15; the platform rejects{' '}
            <code>exp − iat &gt; 600</code> seconds independently.
          </p>
        </div>
      }
    />
  )
}
