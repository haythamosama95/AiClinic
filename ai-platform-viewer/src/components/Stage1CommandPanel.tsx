import { useState } from 'react'
import type { Stage1OperationDefinition } from '@/catalog/stage-1-token-contract'
import { RequestInspector } from '@/components/RequestInspector'
import {
  CommandPanel,
  CommandPanelField,
  CommandPanelFields,
  stage1CommandTone,
} from '@/components/containers'
import { sendCapabilitiesRequest, sendTokenContractRequest } from '@/lib/gateway-api'
import { useSession } from '@/context/SessionContext'
import type { HttpExchange } from '@/types'

interface Stage1CommandPanelProps {
  operation: Stage1OperationDefinition
  onClose: () => void
}

export function Stage1CommandPanel({ operation, onClose }: Stage1CommandPanelProps) {
  const { operatorBearer, aat } = useSession()
  const usesVer = operation.defaultVer !== undefined
  const [ver, setVer] = useState(operation.defaultVer ?? '')
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [inspectorOpen, setInspectorOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  const authReady = operation.auth === 'operator' ? Boolean(operatorBearer) : Boolean(aat)
  const sendDisabled =
    busy ||
    (usesVer && !ver.trim()) ||
    !authReady ||
    (operation.auth === 'aat' && !operatorBearer)

  const authLine = (() => {
    if (usesVer) {
      return authReady
        ? 'Operator bearer from Secrets'
        : 'Operator bearer from Secrets — load credentials first'
    }
    return [
      'Uses clinic AAT from Secrets',
      aat ? null : 'mint one first',
      operatorBearer ? null : 'operator bearer required for platform enroll sync',
    ]
      .filter(Boolean)
      .join(' · ')
  })()

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
      tone={stage1CommandTone(operation)}
      title={operation.title}
      method={operation.method}
      path={operation.path}
      summary={operation.summary}
      successNote={operation.successNote}
      failures={operation.failures}
      responseId={`cmd-responses-${operation.id}`}
      onClose={onClose}
      authLine={authLine}
      prefill={operation.verHint}
      manifest={
        usesVer ? (
          <CommandPanelFields>
            <CommandPanelField
              name="ver"
              scope="body"
              value={ver}
              onChange={setVer}
            />
          </CommandPanelFields>
        ) : undefined
      }
      actions={
        <button
          type="button"
          className="signal-button"
          onClick={() => void handleSend()}
          disabled={sendDisabled}
        >
          {busy ? 'Sending…' : 'Send request'}
        </button>
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

export function stage1FieldCount(operation: Stage1OperationDefinition): number {
  return operation.defaultVer !== undefined ? 1 : 0
}

export function stage1AuthLabel(operation: Stage1OperationDefinition): string {
  return operation.auth === 'operator' ? 'Operator bearer' : 'Clinic AAT'
}
