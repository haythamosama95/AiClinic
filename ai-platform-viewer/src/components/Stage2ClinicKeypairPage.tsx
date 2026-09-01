import { STAGE2_OPERATIONS } from '@/catalog/stage-2-clinic-keypair'
import { SupabaseOperationCard } from '@/components/SupabaseOperationCard'

export function Stage2ClinicKeypairPage() {
  return (
    <section className="stage-page stage-page--clinic">
      <header className="stage-page__intro">
        <p className="stage-page__eyebrow stage-page__eyebrow--clinic">
          Stage 2 · Clinic keypair enrollment
        </p>
        <h2>Signing stamp in clinic Postgres</h2>
        <p className="stage-page__lede">
          The clinic mints its Ed25519 keypair inside Supabase. The private key
          never leaves the database — only the <code>kid</code>,{' '}
          <code>installation_id</code>, and <code>public_jwk.x</code> travel to
          the platform enroll call in Stage 3. These RPCs run against local
          PostgREST, not the Cloudflare gateway.
        </p>
      </header>

      <div className="stage-page__seed stage-page__seed--clinic">
        <p className="stage-page__seed-label">Default availability (after reset)</p>
        <dl className="stage-page__seed-grid">
          <div>
            <dt>enrolled</dt>
            <dd>false</dd>
          </div>
          <div>
            <dt>platform_base_url</dt>
            <dd>null</dd>
          </div>
          <div>
            <dt>private key</dt>
            <dd>stays in Postgres</dd>
          </div>
        </dl>
      </div>

      <div className="stage-page__operations">
        {STAGE2_OPERATIONS.map((operation) => (
          <SupabaseOperationCard key={operation.id} operation={operation} />
        ))}
      </div>
    </section>
  )
}
