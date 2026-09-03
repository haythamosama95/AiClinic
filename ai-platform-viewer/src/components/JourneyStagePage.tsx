import { useState, type ReactNode } from 'react'
import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { JourneyOperationCard } from '@/components/JourneyOperationCard'
import { useClinicEnrollmentMaterial } from '@/hooks/useClinicEnrollmentMaterial'

interface SyncAction {
  label: string
  title: string
  description: string
  confirmLabel: string
  onConfirm: () => Promise<string>
}

interface JourneyStagePageProps {
  meta: JourneyStageMeta
  operations: JourneyOperationDefinition[]
  seedPanels?: ReactNode
  syncAction?: SyncAction
}

export function JourneyStagePage({
  meta,
  operations,
  seedPanels,
  syncAction,
}: JourneyStagePageProps) {
  const {
    material: clinicMaterial,
    status: clinicMaterialStatus,
    error: clinicMaterialError,
    reload: reloadClinicMaterial,
  } = useClinicEnrollmentMaterial()
  const [syncOpen, setSyncOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  const sections = [...new Set(operations.map((operation) => operation.section))]

  async function handleSync() {
    if (!syncAction) {
      return
    }
    setBusy(true)
    setStatusMessage(null)
    setErrorMessage(null)
    try {
      const message = await syncAction.onConfirm()
      await reloadClinicMaterial()
      setStatusMessage(message)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Sync action failed')
    } finally {
      setBusy(false)
      setSyncOpen(false)
    }
  }

  return (
    <section className={`stage-page ${meta.accentClass}`}>
      <header className="stage-page__intro">
        <div className="stage-page__intro-row">
          <div>
            <p className={`stage-page__eyebrow ${meta.accentClass}`}>{meta.eyebrow}</p>
            <h2>{meta.title}</h2>
          </div>
          {syncAction ? (
            <button
              type="button"
              className="danger-button danger-button--compact"
              onClick={() => setSyncOpen(true)}
              disabled={busy}
            >
              {syncAction.label}
            </button>
          ) : null}
        </div>
        <p className="stage-page__lede">{meta.lede}</p>
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

      {seedPanels}

      {sections.length > 0 ? (
        sections.map((section) => (
          <div key={section} className="stage-page__section">
            <h3 className="stage-page__section-title">{section}</h3>
            <div className="stage-page__operations">
              {operations
                .filter((operation) => operation.section === section)
                .map((operation) => (
                  <JourneyOperationCard
                    key={operation.id}
                    operation={operation}
                    clinicMaterial={clinicMaterial}
                    clinicMaterialLoading={clinicMaterialStatus === 'loading'}
                    clinicMaterialError={clinicMaterialError}
                    onReloadClinicDefaults={() => {
                      void reloadClinicMaterial()
                    }}
                    accentClass={meta.accentClass}
                    cardClass={meta.cardClass}
                    buttonClass={meta.buttonClass}
                  />
                ))}
            </div>
          </div>
        ))
      ) : (
        <p className="operation-card__hint">
          Operations for this stage are not wired in the viewer yet.
        </p>
      )}

      {syncAction ? (
        <ConfirmDialog
          open={syncOpen}
          title={syncAction.title}
          description={syncAction.description}
          confirmLabel={syncAction.confirmLabel}
          busy={busy}
          onConfirm={() => {
            void handleSync()
          }}
          onCancel={() => setSyncOpen(false)}
        />
      ) : null}
    </section>
  )
}
