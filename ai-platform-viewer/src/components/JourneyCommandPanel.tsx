import { useEffect, useState } from 'react'
import type { JourneyOperationDefinition } from '@/catalog/journey-types'
import { RequestInspector } from '@/components/RequestInspector'
import {
  CommandPanel,
  CommandPanelField,
  CommandPanelFields,
  journeyAuthLine,
  journeyCommandTone,
} from '@/components/containers'
import { clinicMaterialFingerprint } from '@/hooks/useClinicEnrollmentMaterial'
import { useSession } from '@/context/SessionContext'
import {
  buildJourneyDefaultParams,
  journeyUsesClinicMaterial,
  sendJourneyRequest,
} from '@/lib/journey-api'
import type { ClinicEnrollmentMaterial, HttpExchange } from '@/types'

interface JourneyCommandPanelProps {
  operation: JourneyOperationDefinition
  clinicMaterial: ClinicEnrollmentMaterial | null
  clinicMaterialLoading: boolean
  clinicMaterialError: string | null
  onReloadClinicDefaults: () => void
  onClose: () => void
  buttonClass: string
}

export function JourneyCommandPanel({
  operation,
  clinicMaterial,
  clinicMaterialLoading,
  clinicMaterialError,
  onReloadClinicDefaults,
  onClose,
  buttonClass,
}: JourneyCommandPanelProps) {
  const {
    operatorBearer,
    aat,
    supabaseAdminUsername,
    supabaseAdminPassword,
    storeClinicAat,
  } = useSession()
  const needsClinicMaterial = journeyUsesClinicMaterial(operation.fields)
  const materialFingerprint = clinicMaterialFingerprint(clinicMaterial)
  const [params, setParams] = useState<Record<string, string>>(() =>
    buildJourneyDefaultParams(operation.fields, clinicMaterial),
  )
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [inspectorOpen, setInspectorOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  useEffect(() => {
    setParams(buildJourneyDefaultParams(operation.fields, clinicMaterial))
    setExchange(null)
    setInspectorOpen(false)
    setSendError(null)
  }, [operation.id, clinicMaterial, materialFingerprint])

  const authReady = (() => {
    switch (operation.auth) {
      case 'operator':
        return Boolean(operatorBearer)
      case 'aat':
        return Boolean(aat)
      case 'supabase-admin':
        return Boolean(supabaseAdminUsername && supabaseAdminPassword)
      default:
        return true
    }
  })()

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
    return `Defaults synced from clinic Postgres (installation_id ${clinicMaterial.installation_id}).`
  })()

  const pathDisplay =
    operation.method === 'RPC'
      ? (operation.rpcName ?? operation.path)
      : operation.path

  const authLine = [
    journeyAuthLine(operation.auth, authReady),
    operation.bodyKind === 'empty' ? 'body is {}' : null,
    operation.bodyKind === 'sse' ? 'SSE stream response' : null,
    needsClinicMaterial && !clinicDefaultsReady ? 'waiting for clinic defaults' : null,
  ]
    .filter(Boolean)
    .join(' · ')

  function updateParam(name: string, value: string) {
    setParams((current) => ({ ...current, [name]: value }))
  }

  function resetToClinicDefaults() {
    setParams(buildJourneyDefaultParams(operation.fields, clinicMaterial))
    onReloadClinicDefaults()
  }

  async function handleSend() {
    setSendError(null)
    setBusy(true)
    try {
      const result = await sendJourneyRequest(operation, params, {
        operatorBearer,
        aat,
        supabaseAdmin:
          supabaseAdminUsername && supabaseAdminPassword
            ? { username: supabaseAdminUsername, password: supabaseAdminPassword }
            : undefined,
      })
      if (
        operation.rpcName === 'issue_ai_token' &&
        result.response.status === 200
      ) {
        const tokenRow = result.response.body.find((row) => row.name === 'token')
        if (tokenRow?.value) {
          storeClinicAat(tokenRow.value)
        }
      }
      setExchange(result)
      setInspectorOpen(true)
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Send failed')
      setInspectorOpen(true)
    } finally {
      setBusy(false)
    }
  }

  const methodLabel = operation.method === 'RPC' ? 'RPC' : operation.method

  return (
    <CommandPanel
      tone={journeyCommandTone(operation)}
      title={operation.title}
      method={methodLabel}
      path={pathDisplay}
      summary={operation.summary}
      successNote={operation.successNote}
      failures={operation.failures}
      responseId={`cmd-responses-${operation.id}`}
      onClose={onClose}
      authLine={authLine}
      prefill={prefillNote}
      manifest={
        operation.fields.length > 0 ? (
          <CommandPanelFields>
            {operation.fields.map((field) => (
              <CommandPanelField
                key={field.name}
                name={field.name}
                scope={field.scope}
                hint={field.hint}
                wide={field.wide}
                json={field.json}
                value={params[field.name] ?? ''}
                placeholder={field.defaultValue || field.hint || ''}
                disabled={needsClinicMaterial && clinicMaterialLoading}
                onChange={(value) => updateParam(field.name, value)}
              />
            ))}
          </CommandPanelFields>
        ) : undefined
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
            className={operation.destructive ? 'danger-button' : buttonClass}
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

export function journeyCommandPath(operation: JourneyOperationDefinition): string {
  return operation.method === 'RPC'
    ? (operation.rpcName ?? operation.path)
    : operation.path
}

export function journeyCommandFieldCount(operation: JourneyOperationDefinition): number {
  return operation.fields.length
}
