import { useState } from 'react'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { useSession } from '@/context/SessionContext'
import { pathForSection } from '@/lib/routes'

export function HeaderBar() {
  const {
    activeSection,
    setActiveSection,
    statusMessage,
    errorMessage,
    busyAction,
    resetAll,
    increaseTextSize,
    decreaseTextSize,
    canIncreaseTextSize,
    canDecreaseTextSize,
  } = useSession()
  const [resetOpen, setResetOpen] = useState(false)
  const onSecrets = activeSection === 'secrets'

  return (
    <>
      <header className="header-bar">
        <div className="header-bar__brand">
          <h1 className="header-bar__title">Platform Viewer</h1>
          <p className="header-bar__subtitle">Local ai-platform lab</p>
        </div>

        <div className="header-bar__actions">
          <div className="header-bar__font-controls">
            <button
              type="button"
              className="ghost-button ghost-button--compact"
              aria-label="Decrease text size"
              onClick={decreaseTextSize}
              disabled={!canDecreaseTextSize}
            >
              A−
            </button>
            <button
              type="button"
              className="ghost-button ghost-button--compact"
              aria-label="Increase text size"
              onClick={increaseTextSize}
              disabled={!canIncreaseTextSize}
            >
              A+
            </button>
          </div>
          <a
            href={pathForSection('secrets')}
            className={`ghost-button ghost-button--compact${onSecrets ? ' ghost-button--active' : ''}`}
            aria-current={onSecrets ? 'page' : undefined}
            onClick={(event) => {
              if (
                event.metaKey ||
                event.ctrlKey ||
                event.shiftKey ||
                event.altKey ||
                event.button !== 0
              ) {
                return
              }
              event.preventDefault()
              setActiveSection('secrets')
            }}
          >
            Secrets
          </a>
          <button
            type="button"
            className="danger-button danger-button--compact"
            onClick={() => setResetOpen(true)}
            disabled={busyAction !== null}
          >
            Reset
          </button>
        </div>
      </header>

      <div className="signal-rail" aria-hidden="true" />

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

      <ConfirmDialog
        open={resetOpen}
        title="Reset local ai-platform?"
        description="This clears local D1 rows, deletes local R2 objects, wipes Durable Object state, re-seeds token_contract ver=1, and resets Supabase ai_internal (installation_keys, ai_token_issuance, app_settings defaults including ai.aat.lifetime_minutes=5, ai.aat.ver=1, and ai.availability enrolled=false)."
        confirmLabel="Reset platform"
        busy={busyAction === 'reset'}
        onConfirm={() => {
          void resetAll().finally(() => setResetOpen(false))
        }}
        onCancel={() => setResetOpen(false)}
      />
    </>
  )
}
