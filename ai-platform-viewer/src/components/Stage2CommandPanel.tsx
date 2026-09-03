import { useState } from 'react'
import type { Stage2OperationDefinition } from '@/catalog/stage-2-clinic-keypair'
import { RequestInspector } from '@/components/RequestInspector'
import {
  CommandPanel,
  CommandPanelField,
  CommandPanelFields,
} from '@/components/containers'
import { useSession } from '@/context/SessionContext'
import { sendStage2SupabaseRequest } from '@/lib/supabase-api'
import type { HttpExchange } from '@/types'

interface Stage2CommandPanelProps {
  operation: Stage2OperationDefinition
  onClose: () => void
}

export function Stage2CommandPanel({ operation, onClose }: Stage2CommandPanelProps) {
  const { supabaseAdminUsername, supabaseAdminPassword } = useSession()
  const usesParam = operation.paramName !== undefined
  const [paramValue, setParamValue] = useState('')
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [inspectorOpen, setInspectorOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  const authReady = Boolean(supabaseAdminUsername && supabaseAdminPassword)
  const sendDisabled = busy || !authReady || (usesParam && !paramValue.trim())

  const authLine = [
    operation.authHint,
    authReady ? null : 'load admin credentials in Secrets first',
  ]
    .filter(Boolean)
    .join(' — ')

  async function handleSend() {
    if (sendDisabled) {
      return
    }

    setSendError(null)
    setBusy(true)
    try {
      const result = await sendStage2SupabaseRequest(
        operation.id,
        {
          username: supabaseAdminUsername,
          password: supabaseAdminPassword,
        },
        usesParam ? { [operation.paramName!]: paramValue.trim() } : undefined,
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
      tone="lifecycle"
      title={operation.title}
      method="RPC"
      path={operation.path}
      summary={operation.summary}
      successNote={operation.successNote}
      failures={operation.failures}
      responseId={`cmd-responses-${operation.id}`}
      onClose={onClose}
      authLine={authLine}
      prefill={operation.paramHint}
      manifest={
        usesParam ? (
          <CommandPanelFields>
            <CommandPanelField
              name={operation.paramName!}
              scope="body"
              value={paramValue}
              onChange={setParamValue}
            />
          </CommandPanelFields>
        ) : undefined
      }
      actions={
        <button
          type="button"
          className="clinic-button"
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

export function stage2FieldCount(operation: Stage2OperationDefinition): number {
  return operation.paramName !== undefined ? 1 : 0
}
