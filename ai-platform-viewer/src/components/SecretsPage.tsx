import { CredentialField } from '@/components/CredentialField'
import { useSession } from '@/context/SessionContext'

export function SecretsPage() {
  const {
    operatorBearer,
    operatorSource,
    supabaseAdminUsername,
    supabaseAdminPassword,
    supabaseAdminSource,
    supabaseAdminUsernameRevealed,
    supabaseAdminPasswordRevealed,
    setSupabaseAdminUsernameRevealed,
    setSupabaseAdminPasswordRevealed,
    aat,
    operatorRevealed,
    aatRevealed,
    setOperatorRevealed,
    setAatRevealed,
    busyAction,
    mintAat,
  } = useSession()

  return (
    <section className="secrets-page">
      <header className="secrets-page__intro">
        <p className="secrets-page__eyebrow">Local credentials</p>
        <h2>Secrets</h2>
        <p className="secrets-page__lede">
          Operator bearer authorizes control-plane routes. Supabase admin signs
          into clinic PostgREST for RPC calls and AAT mint. Clinic AAT
          authorizes gateway requests after mint.
        </p>
      </header>

      <div className="secrets-page__grid">
        <article className="secrets-card">
          <div className="secrets-card__head">
            <div>
              <p className="secrets-card__kind">Control plane</p>
              <h3>Operator bearer</h3>
            </div>
            <span className="secrets-card__source">
              {operatorSource ? 'ai-platform/.dev.vars' : 'Missing .dev.vars'}
            </span>
          </div>
          <CredentialField
            id="operator-bearer"
            label="Bearer token"
            value={operatorBearer}
            revealed={operatorRevealed}
            onToggleReveal={() => setOperatorRevealed(!operatorRevealed)}
            placeholder="Start wrangler dev or add OPERATOR_BEARER_TOKEN to .dev.vars"
            rows={2}
          />
        </article>

        <article className="secrets-card secrets-card--clinic">
          <div className="secrets-card__head">
            <div>
              <p className="secrets-card__kind">Clinic database</p>
              <h3>Supabase admin</h3>
            </div>
            <span className="secrets-card__source">
              {supabaseAdminSource || 'Not loaded'}
            </span>
          </div>
          <CredentialField
            id="supabase-admin-username"
            label="Admin email"
            hint="Signs into /auth/v1/token for PostgREST RPCs"
            value={supabaseAdminUsername}
            revealed={supabaseAdminUsernameRevealed}
            onToggleReveal={() =>
              setSupabaseAdminUsernameRevealed(!supabaseAdminUsernameRevealed)
            }
            placeholder="Set VITE_BOOTSTRAP_ADMIN_USERNAME in .env.local"
            rows={1}
          />
          <CredentialField
            id="supabase-admin-password"
            label="Admin password"
            value={supabaseAdminPassword}
            revealed={supabaseAdminPasswordRevealed}
            onToggleReveal={() =>
              setSupabaseAdminPasswordRevealed(!supabaseAdminPasswordRevealed)
            }
            placeholder="Set VITE_BOOTSTRAP_ADMIN_PASSWORD in .env.local"
            rows={1}
          />
        </article>

        <article className="secrets-card">
          <div className="secrets-card__head">
            <div>
              <p className="secrets-card__kind">Clinic trust</p>
              <h3>Clinic AAT</h3>
            </div>
            <button
              type="button"
              className="ghost-button ghost-button--compact"
              onClick={() => void mintAat()}
              disabled={busyAction !== null}
            >
              {busyAction === 'mint' ? 'Minting…' : 'Mint AAT'}
            </button>
          </div>
          <CredentialField
            id="clinic-aat"
            label="Signed token"
            hint={
              aat
                ? 'Minted from Supabase (5-minute lifetime)'
                : 'Auto-mints on load and after reset (5-minute lifetime)'
            }
            value={aat}
            revealed={aatRevealed}
            onToggleReveal={() => setAatRevealed(!aatRevealed)}
            placeholder="Mint an AAT to populate this field"
            rows={4}
          />
        </article>
      </div>
    </section>
  )
}
