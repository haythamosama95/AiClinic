import { STAGE4_META, STAGE4_OPERATIONS } from '@/catalog/stage-4-entitlement'
import { JourneyStagePage } from '@/components/JourneyStagePage'
import { useClinicEnrollmentMaterial } from '@/hooks/useClinicEnrollmentMaterial'

export function Stage4EntitlementPage() {
  const {
    material: clinicMaterial,
    status: clinicMaterialStatus,
    error: clinicMaterialError,
  } = useClinicEnrollmentMaterial()

  return (
    <JourneyStagePage
      meta={STAGE4_META}
      operations={STAGE4_OPERATIONS}
      syncAction={{
        label: 'Sync installation from Supabase',
        title: 'Reload installation_id from clinic Postgres?',
        description:
          'Re-fetches the active installation_id from ai_internal.installation_keys in local Supabase and reapplies it to every entitle and cohort field on this page that uses clinic defaults. Does not change D1 entitlement rows — only viewer form prefill.',
        confirmLabel: 'Sync defaults',
        onConfirm: async () => {
          if (!clinicMaterial?.installation_id) {
            throw new Error(
              'No active installation key in Supabase — run Stage 2 enroll_installation_keypair first.',
            )
          }
          return `Synced installation_id ${clinicMaterial.installation_id} from clinic Postgres.`
        },
      }}
      seedPanels={
        <>
          <div className="stage-page__seed stage-page__seed--entitlement">
            <p className="stage-page__seed-label">
              Pending entitlement sentinel (after Stage 3 enroll)
            </p>
            <dl className="stage-page__seed-grid">
              <div>
                <dt>entitlement.status</dt>
                <dd>pending</dd>
              </div>
              <div>
                <dt>request_quota</dt>
                <dd>0</dd>
              </div>
              <div>
                <dt>token_budget</dt>
                <dd>0</dd>
              </div>
              <div>
                <dt>cost_budget</dt>
                <dd>0</dd>
              </div>
              <div>
                <dt>allowed_capabilities</dt>
                <dd>[]</dd>
              </div>
              <div>
                <dt>soft_threshold</dt>
                <dd>0</dd>
              </div>
              <div>
                <dt>capability_grant rows</dt>
                <dd>0</dd>
              </div>
              <div>
                <dt>period_start</dt>
                <dd>= period_end (placeholders)</dd>
              </div>
              <div>
                <dt>installation.status</dt>
                <dd>active</dd>
              </div>
            </dl>
          </div>
          <div className="stage-page__seed stage-page__seed--entitlement">
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
                  <dt>plan hint</dt>
                  <dd>≥ standard for visit_summary</dd>
                </div>
                <div>
                  <dt>entitle</dt>
                  <dd>one-shot while pending</dd>
                </div>
              </dl>
            ) : (
              <p className="operation-card__hint">
                No active clinic key — run Stage 2 enroll_installation_keypair, then Stage 3
                enroll.
              </p>
            )}
          </div>
        </>
      }
    />
  )
}
