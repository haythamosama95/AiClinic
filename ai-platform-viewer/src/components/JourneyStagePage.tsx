import { useState, type ReactNode } from 'react'
import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import {
  CommandCard,
  CommandDeck,
  CommandDeckSection,
  journeyAuthLabel,
  journeyCommandTone,
  StagePage,
  StagePageIntro,
} from '@/components/containers'
import {
  JourneyCommandPanel,
  journeyCommandFieldCount,
  journeyCommandPath,
} from '@/components/JourneyCommandPanel'
import { useClinicEnrollmentMaterial } from '@/hooks/useClinicEnrollmentMaterial'
import { useSession } from '@/context/SessionContext'

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
  deckEyebrow?: string
  deckLede?: string
  /** Mint a fresh clinic AAT before each AAT-authenticated gateway request. */
  mintAatBeforeEachRequest?: boolean
}

export function JourneyStagePage({
  meta,
  operations,
  seedPanels,
  syncAction,
  deckEyebrow = 'Commands',
  deckLede = 'Pick a command on the left — its request panel opens on the right.',
  mintAatBeforeEachRequest = false,
}: JourneyStagePageProps) {
  const {
    material: clinicMaterial,
    status: clinicMaterialStatus,
    error: clinicMaterialError,
    reload: reloadClinicMaterial,
  } = useClinicEnrollmentMaterial()
  const { notifySuccess, notifyError } = useSession()
  const [syncOpen, setSyncOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [selectedCommand, setSelectedCommand] = useState<string | null>(null)

  const sections = [...new Set(operations.map((operation) => operation.section))]
  const selectedOperation =
    operations.find((operation) => operation.id === selectedCommand) ?? null

  function selectCommand(id: string) {
    setSelectedCommand((current) => (current === id ? null : id))
  }

  async function handleSync() {
    if (!syncAction) {
      return
    }
    setBusy(true)
    try {
      const message = await syncAction.onConfirm()
      await reloadClinicMaterial()
      if (message) {
        notifySuccess(message)
      }
    } catch (error) {
      notifyError(error instanceof Error ? error.message : 'Sync action failed')
    } finally {
      setBusy(false)
      setSyncOpen(false)
    }
  }

  return (
    <StagePage accentClass={meta.accentClass}>
      <StagePageIntro
        eyebrow={meta.eyebrow}
        eyebrowClass={meta.accentClass}
        title={meta.title}
        lede={meta.lede}
        details={seedPanels}
        action={
          syncAction ? (
            <button
              type="button"
              className="danger-button danger-button--compact"
              onClick={() => setSyncOpen(true)}
              disabled={busy}
            >
              {syncAction.label}
            </button>
          ) : undefined
        }
      />

      {sections.length > 0 ? (
        <CommandDeck
          eyebrow={deckEyebrow}
          lede={deckLede}
          ariaLabel={`${meta.title} commands`}
          panel={
            selectedOperation ? (
              <JourneyCommandPanel
                key={selectedOperation.id}
                operation={selectedOperation}
                clinicMaterial={clinicMaterial}
                clinicMaterialLoading={clinicMaterialStatus === 'loading'}
                clinicMaterialError={clinicMaterialError}
                onReloadClinicDefaults={() => {
                  void reloadClinicMaterial()
                }}
                onClose={() => setSelectedCommand(null)}
                buttonClass={meta.buttonClass}
                mintAatBeforeEachRequest={mintAatBeforeEachRequest}
              />
            ) : null
          }
        >
          {sections.flatMap((section) => [
            <CommandDeckSection key={`${section}-label`} title={section} />,
            ...operations
              .filter((operation) => operation.section === section)
              .map((operation) => (
                <CommandCard
                  key={operation.id}
                  method={operation.method === 'RPC' ? 'RPC' : operation.method}
                  title={operation.title}
                  path={journeyCommandPath(operation)}
                  authLabel={journeyAuthLabel(operation.auth)}
                  fieldCount={journeyCommandFieldCount(operation)}
                  tone={journeyCommandTone(operation)}
                  destructive={operation.destructive}
                  selected={selectedCommand === operation.id}
                  onSelect={() => selectCommand(operation.id)}
                />
              )),
          ])}
        </CommandDeck>
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
    </StagePage>
  )
}
