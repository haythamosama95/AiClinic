import { useEffect, useState } from 'react'
import type { JourneyOperationDefinition } from '@/catalog/journey-types'
import { RequestInspector } from '@/components/RequestInspector'
import { clinicMaterialFingerprint } from '@/hooks/useClinicEnrollmentMaterial'
import { useSession } from '@/context/SessionContext'
import {
  buildJourneyDefaultParams,
  journeyUsesClinicMaterial,
  sendJourneyRequest,
} from '@/lib/journey-api'
import type { ClinicEnrollmentMaterial, HttpExchange } from '@/types'

interface JourneyOperationCardProps {
  operation: JourneyOperationDefinition
  clinicMaterial: ClinicEnrollmentMaterial | null
  clinicMaterialLoading: boolean
  clinicMaterialError: string | null
  onReloadClinicDefaults: () => void
  accentClass: string
  cardClass: string
  buttonClass: string
}

function scopeLabel(scope: 'path' | 'body' | 'header' | 'query'): string {
  return scope
}

export function JourneyOperationCard({
  operation,
  clinicMaterial,
  clinicMaterialLoading,
  clinicMaterialError,
  onReloadClinicDefaults,
  accentClass,
  cardClass,
  buttonClass,
}: JourneyOperationCardProps) {
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
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  useEffect(() => {
    setParams(buildJourneyDefaultParams(operation.fields, clinicMaterial))
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
      setOpen(true)
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Send failed')
      setOpen(true)
    } finally {
      setBusy(false)
    }
  }

  const methodLabel = operation.method === 'RPC' ? 'RPC' : operation.method

  return (
    <article
      className={`operation-card ${cardClass}${operation.destructive ? ' operation-card--destructive' : ''}`}
      data-section={operation.section}
    >
      <div className="operation-card__head">
        <p className={`operation-card__section-label ${accentClass}`}>{operation.section}</p>
        <div className="operation-card__route">
          <span className={`operation-card__method ${accentClass}`}>{methodLabel}</span>
          <code className="operation-card__path">
            {operation.method === 'RPC' ? operation.rpcName ?? operation.path : operation.path}
          </code>
        </div>
        <h3>{operation.title}</h3>
        <p className="operation-card__summary">{operation.summary}</p>
      </div>

      {operation.fields.length > 0 ? (
        <div className="operation-card__params">
          <p className="operation-card__params-label">Request parameters</p>
          <div className="operation-card__params-grid">
            {operation.fields.map((field) => (
              <label
                key={field.name}
                className={`operation-card__field${field.wide ? ' operation-card__field--wide' : ''}${field.json ? ' operation-card__field--json' : ''}`}
              >
                <span className="operation-card__field-label">
                  <code>{field.name}</code>
                  <span className="operation-card__field-scope">{scopeLabel(field.scope)}</span>
                </span>
                {field.json ? (
                  <textarea
                    value={params[field.name] ?? ''}
                    onChange={(event) => updateParam(field.name, event.target.value)}
                    spellCheck={false}
                    rows={
                      field.jsonRows ??
                      (field.wide
                        ? Math.max(4, (params[field.name] ?? '').split('\n').length)
                        : 4)
                    }
                    disabled={needsClinicMaterial && clinicMaterialLoading}
                  />
                ) : (
                  <input
                    type="text"
                    value={params[field.name] ?? ''}
                    onChange={(event) => updateParam(field.name, event.target.value)}
                    spellCheck={false}
                    autoComplete="off"
                    placeholder={field.defaultValue || field.hint || ''}
                    disabled={needsClinicMaterial && clinicMaterialLoading}
                  />
                )}
                {field.hint ? (
                  <span className="operation-card__field-hint">{field.hint}</span>
                ) : null}
              </label>
            ))}
          </div>
        </div>
      ) : null}

      <div className="operation-card__controls operation-card__controls--send">
        <p className="operation-card__auth-hint">
          {operation.auth === 'operator'
            ? 'Operator bearer from Secrets'
            : operation.auth === 'aat'
              ? 'Clinic AAT from Secrets'
              : operation.auth === 'supabase-admin'
                ? 'Supabase admin session from Secrets'
                : 'No auth required'}
          {authReady ? '' : ' — load credentials first'}
          {operation.bodyKind === 'empty' ? ' · body is {}' : ''}
          {operation.bodyKind === 'sse' ? ' · SSE stream response' : ''}
          {needsClinicMaterial && !clinicDefaultsReady ? ' · waiting for clinic defaults' : ''}
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
          className={operation.destructive ? 'danger-button' : buttonClass}
          onClick={() => void handleSend()}
          disabled={busy || !authReady || !clinicDefaultsReady}
        >
          {busy ? 'Sending…' : 'Send'}
        </button>
      </div>

      {prefillNote ? <p className="operation-card__hint">{prefillNote}</p> : null}

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
