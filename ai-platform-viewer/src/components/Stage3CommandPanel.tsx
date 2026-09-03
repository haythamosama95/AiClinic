import { useEffect, useState } from 'react'
import type { Stage3OperationDefinition } from '@/catalog/stage-3-platform-installation'
import { RequestInspector } from '@/components/RequestInspector'
import {
  CommandPanel,
  CommandPanelField,
  CommandPanelFields,
  stage3CommandTone,
} from '@/components/containers'
import { clinicMaterialFingerprint } from '@/hooks/useClinicEnrollmentMaterial'
import { useSession } from '@/context/SessionContext'
import {
  buildStage3DefaultParams,
  sendStage3Request,
  stage3UsesClinicMaterial,
} from '@/lib/platform-installation-api'
import type { ClinicEnrollmentMaterial, HttpExchange } from '@/types'

interface Stage3CommandPanelProps {
  operation: Stage3OperationDefinition
  clinicMaterial: ClinicEnrollmentMaterial | null
  clinicMaterialLoading: boolean
  clinicMaterialError: string | null
  onReloadClinicDefaults: () => void
  onClose: () => void
}

export function Stage3CommandPanel({
  operation,
  clinicMaterial,
  clinicMaterialLoading,
  clinicMaterialError,
  onReloadClinicDefaults,
  onClose,
}: Stage3CommandPanelProps) {
  const { operatorBearer, aat } = useSession()
  const needsClinicMaterial = stage3UsesClinicMaterial(operation.id)
  const materialFingerprint = clinicMaterialFingerprint(clinicMaterial)
  const [params, setParams] = useState<Record<string, string>>(() =>
    buildStage3DefaultParams(operation.id, clinicMaterial),
  )
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [inspectorOpen, setInspectorOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  useEffect(() => {
    setParams(buildStage3DefaultParams(operation.id, clinicMaterial))
    setExchange(null)
    setInspectorOpen(false)
    setSendError(null)
  }, [operation.id, clinicMaterial, materialFingerprint])

  const authReady =
    operation.auth === 'operator' ? Boolean(operatorBearer) : Boolean(aat)

  const clinicDefaultsReady =
    !needsClinicMaterial || (!clinicMaterialLoading && clinicMaterial !== null)

  const prefillNote = (() => {
    if (!needsClinicMaterial) {
      return null
    }
    if (clinicMaterialLoading) {
      return 'Loading clinic defaults from Postgres…'
    }
    if (clinicMaterialError) {
      return `Could not load clinic defaults — ${clinicMaterialError}`
    }
    if (!clinicMaterial) {
      return 'No clinic key found in Supabase — run Stage 2 enroll_installation_keypair first.'
    }
    return `Defaults synced from clinic Postgres (installation_id ${clinicMaterial.installation_id}, kid ${clinicMaterial.kid}).`
  })()

  const pathDisplay =
    operation.id === 'v1-request-probe'
      ? '/v1/requests'
      : `/control/installations/{installation_id}${operation.pathSuffix}`

  const authLine = [
    operation.auth === 'operator'
      ? 'Operator bearer from Secrets'
      : 'Clinic AAT from Secrets',
    authReady ? null : 'load credentials first',
    operation.bodyKind === 'empty' ? 'body is {}' : null,
    needsClinicMaterial && !clinicDefaultsReady ? 'waiting for clinic defaults' : null,
  ]
    .filter(Boolean)
    .join(' · ')

  function updateParam(name: string, value: string) {
    setParams((current) => ({ ...current, [name]: value }))
  }

  function resetToClinicDefaults() {
    setParams(buildStage3DefaultParams(operation.id, clinicMaterial))
    onReloadClinicDefaults()
  }

  async function handleSend() {
    setSendError(null)
    setBusy(true)
    try {
      const result = await sendStage3Request(
        operation.id,
        operatorBearer,
        aat,
        params,
      )
      setExchange(result)
      setInspectorOpen(true)
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Send failed')
      setInspectorOpen(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <CommandPanel
      tone={stage3CommandTone(operation)}
      title={operation.title}
      method={operation.method}
      path={pathDisplay}
      summary={operation.summary}
      successNote={operation.successNote}
      failures={operation.failures}
      responseId={`cmd-responses-${operation.id}`}
      onClose={onClose}
      authLine={authLine}
      prefill={prefillNote}
      manifest={
        <CommandPanelFields>
          {operation.fields.map((field) => (
            <CommandPanelField
              key={field.name}
              name={field.name}
              scope={field.scope}
              hint={field.hint}
              wide={field.wide}
              value={params[field.name] ?? ''}
              placeholder={field.defaultValue || field.hint || ''}
              disabled={needsClinicMaterial && clinicMaterialLoading}
              onChange={(value) => updateParam(field.name, value)}
            />
          ))}
        </CommandPanelFields>
      }
      actions={
        <>
          {needsClinicMaterial ? (
            <button
              type="button"
              className="ghost-button ghost-button--compact"
              onClick={() => void resetToClinicDefaults()}
              disabled={clinicMaterialLoading}
            >
              Reload clinic defaults
            </button>
          ) : null}
          <button
            type="button"
            className={operation.destructive ? 'danger-button' : 'platform-button'}
            onClick={() => void handleSend()}
            disabled={busy || !authReady || !clinicDefaultsReady}
          >
            {busy ? 'Sending…' : 'Send request'}
          </button>
        </>
      }
      inspector={
        inspectorOpen ? (
          sendError ? (
            <p className="operation-card__error" role="alert">
              {sendError}
            </p>
          ) : exchange ? (
            <RequestInspector exchange={exchange} />
          ) : null
        ) : null
      }
    />
  )
}

export function stage3PathDisplay(operation: Stage3OperationDefinition): string {
  return operation.id === 'v1-request-probe'
    ? '/v1/requests'
    : `/control/installations/{installation_id}${operation.pathSuffix}`
}

export function stage3AuthLabel(operation: Stage3OperationDefinition): string {
  return operation.auth === 'operator' ? 'Operator bearer' : 'Clinic AAT'
}
