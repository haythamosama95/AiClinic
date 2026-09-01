import { useState } from 'react'
import type { Stage1OperationDefinition } from '@/catalog/stage-1-token-contract'
import { RequestInspector } from '@/components/RequestInspector'
import { sendCapabilitiesRequest, sendTokenContractRequest } from '@/lib/gateway-api'
import { useSession } from '@/context/SessionContext'
import type { HttpExchange } from '@/types'

interface OperationCardProps {
  operation: Stage1OperationDefinition
}

export function OperationCard({ operation }: OperationCardProps) {
  const { operatorBearer, aat } = useSession()
  const [ver, setVer] = useState(operation.defaultVer ?? '')
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  const usesVer = operation.defaultVer !== undefined
  const authReady = operation.auth === 'operator' ? Boolean(operatorBearer) : Boolean(aat)
  const sendDisabled =
    busy ||
    (usesVer && !ver.trim()) ||
    !authReady ||
    (operation.auth === 'aat' && !operatorBearer)

  async function handleSend() {
    setSendError(null)
    setBusy(true)
    try {
      const result =
        operation.id === 'get-capabilities'
          ? await sendCapabilitiesRequest(aat, operatorBearer)
          : await sendTokenContractRequest(
            operation.id === 'begin-rotation'
              ? '/control/token-contract/begin-rotation'
              : '/control/token-contract/retire',
            ver,
            operatorBearer,
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
    <article className="operation-card">
      <div className="operation-card__head">
        <div className="operation-card__route">
          <span className="operation-card__method">{operation.method}</span>
          <code className="operation-card__path">{operation.path}</code>
        </div>
        <h3>{operation.title}</h3>
        <p className="operation-card__summary">{operation.summary}</p>
      </div>

      <div className="operation-card__controls">
        {usesVer ? (
          <label className="operation-card__field">
            <span>ver</span>
            <input
              type="text"
              value={ver}
              onChange={(event) => setVer(event.target.value)}
              spellCheck={false}
              autoComplete="off"
            />
          </label>
        ) : (
          <p className="operation-card__auth-hint">
            Uses clinic AAT from Secrets
            {aat ? '' : ' — mint one first'}
            {operatorBearer ? '' : ' · operator bearer required for platform enroll sync'}
          </p>
        )}
        <button
          type="button"
          className="signal-button"
          onClick={() => void handleSend()}
          disabled={sendDisabled}
        >
          {busy ? 'Sending…' : 'Send'}
        </button>
      </div>

      {operation.verHint ? (
        <p className="operation-card__hint">{operation.verHint}</p>
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
