import { useEffect, useState } from 'react'
import type { Stage3OperationDefinition } from '@/catalog/stage-3-platform-installation'
import { RequestInspector } from '@/components/RequestInspector'
import { clinicMaterialFingerprint } from '@/hooks/useClinicEnrollmentMaterial'
import { useSession } from '@/context/SessionContext'
import {
  buildStage3DefaultParams,
  sendStage3Request,
  stage3UsesClinicMaterial,
} from '@/lib/platform-installation-api'
import type { ClinicEnrollmentMaterial, HttpExchange } from '@/types'

interface PlatformOperationCardProps {
  operation: Stage3OperationDefinition
  clinicMaterial: ClinicEnrollmentMaterial | null
  clinicMaterialLoading: boolean
  clinicMaterialError: string | null
  onReloadClinicDefaults: () => void
}

function scopeLabel(scope: 'path' | 'body' | 'header'): string {
  switch (scope) {
    case 'path':
      return 'path'
    case 'header':
      return 'header'
    default:
      return 'body'
  }
}

export function PlatformOperationCard({
  operation,
  clinicMaterial,
  clinicMaterialLoading,
  clinicMaterialError,
  onReloadClinicDefaults,
}: PlatformOperationCardProps) {
  const { operatorBearer, aat } = useSession()
  const needsClinicMaterial = stage3UsesClinicMaterial(operation.id)
  const materialFingerprint = clinicMaterialFingerprint(clinicMaterial)
  const [params, setParams] = useState<Record<string, string>>(() =>
    buildStage3DefaultParams(operation.id, clinicMaterial),
  )
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  useEffect(() => {
    setParams(buildStage3DefaultParams(operation.id, clinicMaterial))
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
      setOpen(true)
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Send failed')
      setOpen(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <article
      className={`operation-card operation-card--platform${operation.destructive ? ' operation-card--destructive' : ''}`}
    >
      <div className="operation-card__head">
        <div className="operation-card__route">
          <span className="operation-card__method operation-card__method--platform">
            {operation.method}
          </span>
          <code className="operation-card__path">{pathDisplay}</code>
        </div>
        <h3>{operation.title}</h3>
        <p className="operation-card__summary">{operation.summary}</p>
      </div>

      <div className="operation-card__params">
        <p className="operation-card__params-label">Request parameters</p>
        <div className="operation-card__params-grid">
          {operation.fields.map((field) => (
            <label
              key={field.name}
              className={`operation-card__field${field.wide ? ' operation-card__field--wide' : ''}`}
            >
              <span className="operation-card__field-label">
                <code>{field.name}</code>
                <span className="operation-card__field-scope">
                  {scopeLabel(field.scope)}
                </span>
              </span>
              <input
                type="text"
                value={params[field.name] ?? ''}
                onChange={(event) => updateParam(field.name, event.target.value)}
                spellCheck={false}
                autoComplete="off"
                placeholder={field.defaultValue || field.hint || ''}
                disabled={needsClinicMaterial && clinicMaterialLoading}
              />
              {field.hint ? (
                <span className="operation-card__field-hint">{field.hint}</span>
              ) : null}
            </label>
          ))}
        </div>
      </div>

      <div className="operation-card__controls operation-card__controls--send">
        <p className="operation-card__auth-hint">
          {operation.auth === 'operator'
            ? 'Operator bearer from Secrets'
            : 'Clinic AAT from Secrets'}
          {authReady ? '' : ' — load credentials first'}
          {operation.bodyKind === 'empty' ? ' · body is {}' : ''}
          {needsClinicMaterial && !clinicDefaultsReady
            ? ' · waiting for clinic defaults'
            : ''}
        </p>
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
          {busy ? 'Sending…' : 'Send'}
        </button>
      </div>

      {prefillNote ? (
        <p className="operation-card__hint">{prefillNote}</p>
      ) : null}

      <p className="operation-card__hint">{operation.successNote}</p>

      <details className="operation-card__failures">
        <summary>Known response codes</summary>
        <ul>
          {operation.failures.map((failure) => (
            <li key={`${failure.status}-${failure.error}`}>
              <code>{failure.status}</code> {failure.error} — {failure.trigger}
            </li>
          ))}
        </ul>
      </details>

      {open ? (
        <div className="operation-card__inspector">
          {sendError ? (
            <p className="operation-card__error" role="alert">
              {sendError}
            </p>
          ) : exchange ? (
            <RequestInspector exchange={exchange} />
          ) : null}
        </div>
      ) : null}
    </article>
  )
}
