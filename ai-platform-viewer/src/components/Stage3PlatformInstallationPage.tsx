import { useState } from 'react'
import { STAGE3_OPERATIONS } from '@/catalog/stage-3-platform-installation'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { PlatformOperationCard } from '@/components/PlatformOperationCard'
import { useClinicEnrollmentMaterial } from '@/hooks/useClinicEnrollmentMaterial'
import { resetInstallations } from '@/lib/dev-api'

export function Stage3PlatformInstallationPage() {
  const {
    material: clinicMaterial,
    status: clinicMaterialStatus,
    error: clinicMaterialError,
    reload: reloadClinicMaterial,
  } = useClinicEnrollmentMaterial()
  const [resetOpen, setResetOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  async function handleResetInstallations() {
    setBusy(true)
    setStatusMessage(null)
    setErrorMessage(null)
    try {
      const result = await resetInstallations()
      await reloadClinicMaterial()
      setStatusMessage(result.steps.join(' · '))
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : 'Installation reset failed',
      )
    } finally {
      setBusy(false)
      setResetOpen(false)
    }
  }

  return (
    <section className="stage-page stage-page--platform">
      <header className="stage-page__intro">
        <div className="stage-page__intro-row">
          <div>
            <p className="stage-page__eyebrow stage-page__eyebrow--platform">
              Stage 3 · Platform installation enrollment
            </p>
            <h2>Passport office registers the airline</h2>
          </div>
          <button
            type="button"
            className="danger-button danger-button--compact"
            onClick={() => setResetOpen(true)}
            disabled={busy}
          >
            Reset installations
          </button>
        </div>
        <p className="stage-page__lede">
          The control-plane caller files the clinic&apos;s public key specimen on
          Cloudflare D1. <code>installation_id</code> comes from Stage 2 — the
          platform never mints or discovers it. Enroll returns only{' '}
          <code>platform_base_url</code>; entitlement stays{' '}
          <code>pending</code> with zero quotas until Stage 4. After enroll,
          operators can rotate, revoke-key, suspend, resume, delete, or purge.
          Staff AATs are never accepted on <code>/control/*</code>.
        </p>
      </header>

      {statusMessage ? (
        <div className="status-banner status-banner--ok" role="status">
          {statusMessage}
        </div>
      ) : null}
      {errorMessage ? (
        <div className="status-banner status-banner--error" role="alert">
          {errorMessage}
        </div>
      ) : null}

      <div className="stage-page__seed stage-page__seed--platform">
        <p className="stage-page__seed-label">Clinic defaults (Supabase)</p>
        {clinicMaterialStatus === 'loading' ? (
          <p className="operation-card__hint">Loading installation key from Postgres…</p>
        ) : clinicMaterialError ? (
          <p className="operation-card__hint" role="alert">
            {clinicMaterialError}
          </p>
        ) : clinicMaterial ? (
          <dl className="stage-page__seed-grid">
            <div>
              <dt>installation_id</dt>
              <dd>
                <code>{clinicMaterial.installation_id}</code>
              </dd>
            </div>
            <div>
              <dt>kid</dt>
              <dd>
                <code>{clinicMaterial.kid}</code>
              </dd>
            </div>
            <div>
              <dt>org_id</dt>
              <dd>
                <code>{clinicMaterial.org_id}</code>
              </dd>
            </div>
            <div>
              <dt>display_name</dt>
              <dd>{clinicMaterial.display_name}</dd>
            </div>
            <div>
              <dt>public_key</dt>
              <dd>
                <code>{clinicMaterial.public_key}</code>
              </dd>
            </div>
            <div>
              <dt>ai.aat.ver</dt>
              <dd>
                <code>{clinicMaterial.aat_ver}</code>
              </dd>
            </div>
          </dl>
        ) : (
          <p className="operation-card__hint">
            No active clinic key in Supabase — run Stage 2{' '}
            <code>enroll_installation_keypair</code> first.
          </p>
        )}
      </div>

      <div className="stage-page__seed stage-page__seed--platform">
        <p className="stage-page__seed-label">D1 state after first enroll</p>
        <dl className="stage-page__seed-grid">
          <div>
            <dt>installation.status</dt>
            <dd>active</dd>
          </div>
          <div>
            <dt>entitlement.status</dt>
            <dd>pending</dd>
          </div>
          <div>
            <dt>request_quota</dt>
            <dd>0</dd>
          </div>
          <div>
            <dt>allowed_capabilities</dt>
            <dd>[]</dd>
          </div>
          <div>
            <dt>control_audit.action</dt>
            <dd>enroll</dd>
          </div>
          <div>
            <dt>R2 writes</dt>
            <dd>none</dd>
          </div>
        </dl>
      </div>

      <div className="stage-page__operations">
        {STAGE3_OPERATIONS.map((operation) => (
          <PlatformOperationCard
            key={operation.id}
            operation={operation}
            clinicMaterial={clinicMaterial}
            clinicMaterialLoading={clinicMaterialStatus === 'loading'}
            clinicMaterialError={clinicMaterialError}
            onReloadClinicDefaults={() => {
              void reloadClinicMaterial()
            }}
          />
        ))}
      </div>

      <ConfirmDialog
        open={resetOpen}
        title="Reset all platform installations?"
        description="This deletes every installation from local D1 (installation, installation_key, entitlement, journal, ledger, grants, audit, counters) and removes local R2 request envelopes. Token contract, kill switch, routing policy, and clinic Supabase keys are left unchanged."
        confirmLabel="Reset installations"
        busy={busy}
        onConfirm={() => {
          void handleResetInstallations()
        }}
        onCancel={() => setResetOpen(false)}
      />
    </section>
  )
}
