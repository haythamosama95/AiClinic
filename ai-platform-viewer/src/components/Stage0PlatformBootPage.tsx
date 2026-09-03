import { STAGE0_META, STAGE0_OPERATIONS } from '@/catalog/stage-0-platform-boot'
import { JourneyStagePage } from '@/components/JourneyStagePage'
import { useSession } from '@/context/SessionContext'

export function Stage0PlatformBootPage() {
  const { resetAll } = useSession()

  return (
    <JourneyStagePage
      meta={STAGE0_META}
      operations={STAGE0_OPERATIONS}
      seedPanels={
        <>
          <div className="stage-page__seed stage-page__seed--boot">
            <p className="stage-page__seed-label">Expected GET /health body (local dev)</p>
            <dl className="stage-page__seed-grid">
              <div>
                <dt>build</dt>
                <dd>
                  <code>local</code>
                </dd>
              </div>
              <div>
                <dt>environment</dt>
                <dd>
                  <code>development</code>
                </dd>
              </div>
              <div>
                <dt>auth</dt>
                <dd>none</dd>
              </div>
            </dl>
          </div>
          <div className="stage-page__seed stage-page__seed--boot">
            <p className="stage-page__seed-label">D1 seed after migrations</p>
            <dl className="stage-page__seed-grid">
              <div>
                <dt>token_contract.ver</dt>
                <dd>1</dd>
              </div>
              <div>
                <dt>retired_at</dt>
                <dd>null</dd>
              </div>
              <div>
                <dt>changed_by</dt>
                <dd>seed</dd>
              </div>
              <div>
                <dt>installation rows</dt>
                <dd>0</dd>
              </div>
              <div>
                <dt>routing_policy rows</dt>
                <dd>0</dd>
              </div>
              <div>
                <dt>wrangler crons</dt>
                <dd>
                  <code>0 3 * * *</code>, <code>0 4 * * *</code>
                </dd>
              </div>
              <div>
                <dt>CONFIG_CACHE_TTL_MS</dt>
                <dd>
                  <code>30000</code> (wrangler <code>[vars]</code>)
                </dd>
              </div>
            </dl>
          </div>
          <div className="stage-page__seed stage-page__seed--boot">
            <p className="stage-page__seed-label">Platform reset (viewer sync — not HTTP)</p>
            <p className="operation-card__hint">
              Use <strong>Reset platform</strong> above or the header Reset button. Calls{' '}
              <code>resetPlatform()</code>: wipes D1 business rows, restores token_contract seed,
              clears R2 envelopes, re-mints clinic AAT. Leaves routing_policy and clinic
              Supabase keys unchanged unless you reset installations separately (Stage 3).
            </p>
          </div>
        </>
      }
      syncAction={{
        label: 'Reset platform',
        title: 'Reset entire local platform?',
        description:
          'Wipes D1 business rows, restores the token_contract seed, clears R2 envelopes, and re-mints a clinic AAT. Same as the header Reset — not an HTTP route on the gateway.',
        confirmLabel: 'Reset platform',
        onConfirm: async () => {
          await resetAll()
          return ''
        },
      }}
    />
  )
}
