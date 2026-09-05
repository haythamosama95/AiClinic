import { STAGE8_META, STAGE8_OPERATIONS } from '@/catalog/stage-8-ingress'
import { JourneyStagePage } from '@/components/JourneyStagePage'
import { useClinicEnrollmentMaterial } from '@/hooks/useClinicEnrollmentMaterial'

export function Stage8IngressPage() {
  const {
    material: clinicMaterial,
    status: clinicMaterialStatus,
    error: clinicMaterialError,
  } = useClinicEnrollmentMaterial()

  return (
    <JourneyStagePage
      meta={STAGE8_META}
      operations={STAGE8_OPERATIONS}
      mintAatBeforeEachRequest
      syncAction={{
        label: 'Sync clinic context',
        title: 'Reload org/branch into context defaults?',
        description:
          'Re-fetches org_id and the bootstrap admin primary branch_id from Supabase Postgres and reapplies them to ingress context JSON fields on this page.',
        confirmLabel: 'Sync defaults',
        onConfirm: async () => {
          if (!clinicMaterial?.org_id || !clinicMaterial.branch_id) {
            throw new Error(
              'Could not resolve org_id and branch_id from clinic Postgres — run Stage 2 enroll first.',
            )
          }
          return `Synced context.org=${clinicMaterial.org_id} and context.branch=${clinicMaterial.branch_id}.`
        },
      }}
      seedPanels={
        <>
          <div className="stage-page__seed stage-page__seed--ingress">
            <p className="stage-page__seed-label">Required headers</p>
            <dl className="stage-page__seed-grid">
              <div>
                <dt>Authorization</dt>
                <dd>Bearer AAT (Secrets session)</dd>
              </div>
              <div>
                <dt>x-idempotency-key</dt>
                <dd>required — non-empty after trim</dd>
              </div>
              <div>
                <dt>x-capability-version</dt>
                <dd>required — e.g. 1.0.0</dd>
              </div>
              <div>
                <dt>x-trace-id</dt>
                <dd>optional — ULID if omitted</dd>
              </div>
              <div>
                <dt>Content-Type</dt>
                <dd>application/json</dd>
              </div>
              <div>
                <dt>response</dt>
                <dd>SSE when guard accepts</dd>
              </div>
            </dl>
          </div>

          <div className="stage-page__seed stage-page__seed--ingress">
            <p className="stage-page__seed-label">Clinic tenant defaults (Supabase)</p>
            {clinicMaterialStatus === 'loading' ? (
              <p className="operation-card__hint">Loading org/branch from Postgres…</p>
            ) : clinicMaterialError ? (
              <p className="operation-card__hint" role="alert">
                {clinicMaterialError}
              </p>
            ) : clinicMaterial ? (
              <dl className="stage-page__seed-grid">
                <div>
                  <dt>context.org</dt>
                  <dd>
                    <code>{clinicMaterial.org_id}</code>
                  </dd>
                </div>
                <div>
                  <dt>context.branch</dt>
                  <dd>
                    <code>{clinicMaterial.branch_id}</code>
                  </dd>
                </div>
                <div>
                  <dt>visit.chief_complaint@v1</dt>
                  <dd>from get_visit_chief_complaint or inline</dd>
                </div>
              </dl>
            ) : (
              <p className="operation-card__hint">
                No clinic key in Supabase — run Stage 2 enroll_installation_keypair first.
              </p>
            )}
          </div>
        </>
      }
    />
  )
}
