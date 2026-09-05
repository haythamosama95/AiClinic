import { STAGE5_META, STAGE5_OPERATIONS } from '@/catalog/stage-5-routing-policy'
import { JourneyStagePage } from '@/components/JourneyStagePage'

export function Stage5RoutingPage() {
  return (
    <JourneyStagePage
      meta={STAGE5_META}
      operations={STAGE5_OPERATIONS}
      seedPanels={
        <div className="stage-page__seed stage-page__seed--routing">
          <p className="stage-page__seed-label">Manifest link (visit summary)</p>
          <dl className="stage-page__seed-grid">
            <div>
              <dt>routingPolicyRef</dt>
              <dd>
                <code>routing/standard</code>
              </dd>
            </div>
            <div>
              <dt>R2 content_pointer</dt>
              <dd>
                <code>control/routing-policy/standard/1.json</code>
              </dd>
            </div>
            <div>
              <dt>lifecycle</dt>
              <dd>published → canary → active → superseded</dd>
            </div>
            <div>
              <dt>publish default</dt>
              <dd>platform-default/1.json</dd>
            </div>
            <div>
              <dt>served when</dt>
              <dd>status active or canary (for listed ids)</dd>
            </div>
            <div>
              <dt>not served</dt>
              <dd>published only — promote required</dd>
            </div>
          </dl>
        </div>
      }
    />
  )
}
