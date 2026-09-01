import { useState } from 'react'
import type { Stage2OperationDefinition } from '@/catalog/stage-2-clinic-keypair'
import { RequestInspector } from '@/components/RequestInspector'
import { useSession } from '@/context/SessionContext'
import { sendStage2SupabaseRequest } from '@/lib/supabase-api'
import type { HttpExchange } from '@/types'

interface SupabaseOperationCardProps {
  operation: Stage2OperationDefinition
}

export function SupabaseOperationCard({ operation }: SupabaseOperationCardProps) {
  const { supabaseAdminUsername, supabaseAdminPassword } = useSession()
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  const authReady = Boolean(supabaseAdminUsername && supabaseAdminPassword)

  async function handleSend() {
    if (!authReady) {
      return
    }

    setSendError(null)
    setBusy(true)
    try {
      const result = await sendStage2SupabaseRequest(operation.id, {
        username: supabaseAdminUsername,
        password: supabaseAdminPassword,
      })
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
    <article className="operation-card operation-card--clinic">
      <div className="operation-card__head">
        <div className="operation-card__route">
          <span className="operation-card__method operation-card__method--clinic">
            RPC
          </span>
          <code className="operation-card__path">{operation.path}</code>
        </div>
        <h3>{operation.title}</h3>
        <p className="operation-card__summary">{operation.summary}</p>
      </div>

      <div className="operation-card__controls">
        <p className="operation-card__auth-hint">
          {operation.authHint}
          {authReady ? '' : ' — load admin credentials in Secrets first'}
        </p>
        <button
          type="button"
          className="clinic-button"
          onClick={() => void handleSend()}
          disabled={busy || !authReady}
        >
          {busy ? 'Sending…' : 'Send'}
        </button>
      </div>

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
