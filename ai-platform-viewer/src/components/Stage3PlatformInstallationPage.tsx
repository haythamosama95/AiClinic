import { useState } from 'react'
import type { Stage3OperationId } from '@/catalog/stage-3-platform-installation'
import { STAGE3_OPERATIONS } from '@/catalog/stage-3-platform-installation'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import {
  CommandCard,
  CommandDeck,
  StagePage,
  StagePageIntro,
  StagePageSeed,
  stage3CommandTone,
} from '@/components/containers'
import {
  Stage3CommandPanel,
  stage3AuthLabel,
  stage3PathDisplay,
} from '@/components/Stage3CommandPanel'
import { useClinicEnrollmentMaterial } from '@/hooks/useClinicEnrollmentMaterial'
import { useSession } from '@/context/SessionContext'
import { resetInstallations } from '@/lib/dev-api'

export function Stage3PlatformInstallationPage() {
  const {
    material: clinicMaterial,
    status: clinicMaterialStatus,
    error: clinicMaterialError,
    reload: reloadClinicMaterial,
  } = useClinicEnrollmentMaterial()
  const { notifySuccess, notifyError } = useSession()
  const [resetOpen, setResetOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [selectedCommand, setSelectedCommand] = useState<Stage3OperationId | null>(
    null,
  )

  const selectedOperation =
    STAGE3_OPERATIONS.find((operation) => operation.id === selectedCommand) ?? null

  function selectCommand(id: Stage3OperationId) {
    setSelectedCommand((current) => (current === id ? null : id))
  }

  async function handleResetInstallations() {
    setBusy(true)
    try {
      const result = await resetInstallations()
      await reloadClinicMaterial()
      notifySuccess(result.steps.join(' · '))
    } catch (error) {
      notifyError(
        error instanceof Error ? error.message : 'Installation reset failed',
      )
    } finally {
      setBusy(false)
      setResetOpen(false)
    }
  }

  return (
    <StagePage accentClass="stage-page--platform">
      <StagePageIntro
        eyebrow="Stage 3 · Platform installation enrollment"
        eyebrowClass="stage-page__eyebrow--platform"
        title="Passport office registers the airline"
        lede={
          <>
            The control-plane caller files the clinic&apos;s public key specimen on
            Cloudflare D1. <code>installation_id</code> comes from Stage 2 — the
            platform never mints or discovers it. Enroll returns only{' '}
            <code>platform_base_url</code>; entitlement stays{' '}
            <code>pending</code> with zero quotas until Stage 4. After enroll,
            operators can rotate, revoke-key, suspend, resume, delete, or purge.
            Staff AATs are never accepted on <code>/control/*</code>.
          </>
        }
        details={
          <>
            <StagePageSeed label="Clinic defaults (Supabase)" variant="platform">
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
            </StagePageSeed>

            <StagePageSeed label="D1 state after first enroll" variant="platform">
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
            </StagePageSeed>
          </>
        }
        action={
          <button
            type="button"
            className="danger-button danger-button--compact"
            onClick={() => setResetOpen(true)}
            disabled={busy}
          >
            Reset installations
          </button>
        }
      />

      <CommandDeck
        eyebrow="Control commands"
        lede="Pick a command on the left — its request panel opens on the right."
        ariaLabel="Control plane commands"
        panel={
          selectedOperation ? (
            <Stage3CommandPanel
              key={selectedOperation.id}
              operation={selectedOperation}
              clinicMaterial={clinicMaterial}
              clinicMaterialLoading={clinicMaterialStatus === 'loading'}
              clinicMaterialError={clinicMaterialError}
              onReloadClinicDefaults={() => {
                void reloadClinicMaterial()
              }}
              onClose={() => setSelectedCommand(null)}
            />
          ) : null
        }
      >
        {STAGE3_OPERATIONS.map((operation) => (
          <CommandCard
            key={operation.id}
            method={operation.method}
            title={operation.title}
            path={stage3PathDisplay(operation)}
            authLabel={stage3AuthLabel(operation)}
            fieldCount={operation.fields.length}
            tone={stage3CommandTone(operation)}
            destructive={operation.destructive}
            selected={selectedCommand === operation.id}
            onSelect={() => selectCommand(operation.id)}
          />
        ))}
      </CommandDeck>

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
    </StagePage>
  )
}
