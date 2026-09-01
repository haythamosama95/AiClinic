import { STAGE1_OPERATIONS } from '@/catalog/stage-1-token-contract'
import { OperationCard } from '@/components/OperationCard'

export function Stage1TokenContractPage() {
  return (
    <section className="stage-page">
      <header className="stage-page__intro">
        <p className="stage-page__eyebrow">Stage 1 · Token contract baseline</p>
        <h2>Accepted AAT versions</h2>
        <p className="stage-page__lede">
          The platform keeps a list of accepted AAT <code>ver</code> claims in D1{' '}
          <code>token_contract</code>. Use these control routes to open a rotation
          window or retire an old booklet edition, then probe <code>GET /v1/capabilities</code>{' '}
          with a minted AAT. Clinic <code>ai.aat.ver</code> must be accepted on{' '}
          <code>token_contract</code> — mint syncs that automatically.
        </p>
      </header>

      <div className="stage-page__seed">
        <p className="stage-page__seed-label">Seed row (after reset)</p>
        <dl className="stage-page__seed-grid">
          <div>
            <dt>ver</dt>
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
        </dl>
      </div>

      <div className="stage-page__operations">
        {STAGE1_OPERATIONS.map((operation) => (
          <OperationCard key={operation.id} operation={operation} />
        ))}
      </div>
    </section>
  )
}
