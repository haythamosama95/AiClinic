import { useEffect, useState, type ReactNode } from 'react'
import type { CommandFailure, CommandTone } from '@/components/containers/command-tone'
import { panelToneClass } from '@/components/containers/command-tone'

interface CommandPanelProps {
  tone: CommandTone
  title: string
  method: string
  path: string
  summary: string
  successNote: string
  failures: CommandFailure[]
  responseId: string
  onClose: () => void
  authLine: string
  prefill?: string | null
  actions: ReactNode
  manifest?: ReactNode
  inspector?: ReactNode
}

export function CommandPanel({
  tone,
  title,
  method,
  path,
  summary,
  successNote,
  failures,
  responseId,
  onClose,
  authLine,
  prefill,
  actions,
  manifest,
  inspector,
}: CommandPanelProps) {
  const hasInspector = Boolean(inspector)
  const hasManifest = Boolean(manifest)
  const showViewToggle = hasInspector && hasManifest
  const [bodyView, setBodyView] = useState<'inputs' | 'response'>('inputs')

  useEffect(() => {
    if (hasInspector) {
      setBodyView('response')
    } else {
      setBodyView('inputs')
    }
  }, [hasInspector, title])

  const showBody = hasManifest || hasInspector

  return (
    <article className={`cmd-panel ${panelToneClass(tone)}`} aria-label={title}>
      <header className="cmd-panel__head">
        <div className="cmd-panel__head-main">
          <span className="cmd-panel__stamp">{method}</span>
          <div className="cmd-panel__head-copy">
            <h3 className="cmd-panel__title">{title}</h3>
            <code className="cmd-panel__path">{path}</code>
          </div>
        </div>
        <div className="cmd-panel__head-actions">
          {showViewToggle ? (
            <div className="cmd-panel__view-toggle" role="tablist" aria-label="Panel view">
              <button
                type="button"
                role="tab"
                className="cmd-panel__view-btn"
                aria-selected={bodyView === 'inputs'}
                onClick={() => setBodyView('inputs')}
              >
                Inputs
              </button>
              <button
                type="button"
                role="tab"
                className="cmd-panel__view-btn"
                aria-selected={bodyView === 'response'}
                onClick={() => setBodyView('response')}
              >
                Request / response
              </button>
            </div>
          ) : null}
          <CommandPanelResponses failures={failures} responseId={responseId} />
          <div className="cmd-panel__action-buttons">{actions}</div>
          <button
            type="button"
            className="ghost-button ghost-button--compact cmd-panel__close"
            onClick={onClose}
          >
            Close
          </button>
        </div>
      </header>

      <div className="cmd-panel__intro">
        <p className="cmd-panel__summary">{summary}</p>
        <p className="cmd-panel__success-note">{successNote}</p>
      </div>

      <p className="cmd-panel__auth-line">{authLine}</p>

      {showBody ? (
        <div className="cmd-panel__body">
          {bodyView === 'inputs' && hasManifest ? (
            <div className="cmd-panel__manifest">
              <p className="cmd-panel__section-label">Request manifest</p>
              {manifest}
            </div>
          ) : null}

          {bodyView === 'response' && hasInspector ? (
            <div className="cmd-panel__inspector">{inspector}</div>
          ) : null}
        </div>
      ) : null}

      {prefill ? <p className="cmd-panel__prefill">{prefill}</p> : null}
    </article>
  )
}

interface CommandPanelResponsesProps {
  failures: CommandFailure[]
  responseId: string
}

function CommandPanelResponses({ failures, responseId }: CommandPanelResponsesProps) {
  return (
    <div className="cmd-panel__responses-anchor">
      <button
        type="button"
        className="cmd-panel__responses-btn"
        aria-label={`Known responses (${failures.length})`}
        aria-describedby={responseId}
      >
        <svg
          className="cmd-panel__responses-icon"
          viewBox="0 0 20 20"
          fill="none"
          aria-hidden="true"
        >
          <path
            d="M5 4.5h10M5 8h10M5 11.5h6"
            stroke="currentColor"
            strokeWidth="1.4"
            strokeLinecap="round"
          />
          <rect
            x="3.25"
            y="2.75"
            width="13.5"
            height="14.5"
            rx="2"
            stroke="currentColor"
            strokeWidth="1.4"
          />
          <circle cx="14.25" cy="11.5" r="2.1" fill="currentColor" />
        </svg>
        <span className="cmd-panel__responses-count">{failures.length}</span>
      </button>
      <div
        id={responseId}
        className="cmd-panel__responses-popover"
        role="region"
        aria-label="Known responses"
      >
        <p className="cmd-panel__responses-popover-label">Known responses</p>
        <ul className="cmd-panel__response-list">
          {failures.map((failure) => (
            <li key={`${failure.status}-${failure.error}`}>
              <span className="cmd-panel__status">{failure.status}</span>
              <span className="cmd-panel__error-code">{failure.error}</span>
              <span className="cmd-panel__trigger-text">{failure.trigger}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}

interface CommandPanelFieldsProps {
  children: ReactNode
}

export function CommandPanelFields({ children }: CommandPanelFieldsProps) {
  return <div className="cmd-panel__fields">{children}</div>
}

interface CommandPanelFieldProps {
  name: string
  scope: string
  hint?: string
  wide?: boolean
  json?: boolean
  jsonRows?: number
  value: string
  placeholder?: string
  disabled?: boolean
  onChange: (value: string) => void
}

export function CommandPanelField({
  name,
  scope,
  hint,
  wide,
  json,
  jsonRows,
  value,
  placeholder,
  disabled,
  onChange,
}: CommandPanelFieldProps) {
  return (
    <label
      className={`cmd-panel__field${wide ? ' cmd-panel__field--wide' : ''}${json ? ' cmd-panel__field--json' : ''}`}
    >
      <span className="cmd-panel__field-head">
        <code>{name}</code>
        <span className="cmd-panel__scope">{scope}</span>
      </span>
      {json ? (
        <textarea
          value={value}
          onChange={(event) => onChange(event.target.value)}
          spellCheck={false}
          rows={
            jsonRows ??
            (wide ? Math.max(4, value.split('\n').length) : 4)
          }
          disabled={disabled}
        />
      ) : (
        <input
          type="text"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          spellCheck={false}
          autoComplete="off"
          placeholder={placeholder}
          disabled={disabled}
        />
      )}
      {hint ? <span className="cmd-panel__field-hint">{hint}</span> : null}
    </label>
  )
}
