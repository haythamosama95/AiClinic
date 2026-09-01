import { copyText, formatTokenPreview } from '@/lib/tokens'

interface CredentialFieldProps {
  id: string
  label: string
  value: string
  revealed: boolean
  onToggleReveal: () => void
  hint?: string
  placeholder?: string
  rows?: number
}

export function CredentialField({
  id,
  label,
  value,
  revealed,
  onToggleReveal,
  hint,
  placeholder = 'Not loaded',
  rows = 2,
}: CredentialFieldProps) {
  const displayValue = value
    ? formatTokenPreview(value, revealed)
    : placeholder

  return (
    <div className="credential-field">
      <div className="credential-field__head">
        <div className="credential-field__meta">
          <label className="credential-field__label" htmlFor={id}>
            {label}
          </label>
          {hint ? <span className="credential-field__hint">{hint}</span> : null}
        </div>
        <div className="credential-field__actions">
          <button
            type="button"
            className="ghost-button ghost-button--compact"
            onClick={onToggleReveal}
            disabled={!value}
          >
            {revealed ? 'Hide' : 'Show'}
          </button>
          <button
            type="button"
            className="ghost-button ghost-button--compact"
            onClick={() => copyText(value)}
            disabled={!value}
          >
            Copy
          </button>
        </div>
      </div>
      <textarea
        id={id}
        className="credential-field__input"
        readOnly
        rows={rows}
        spellCheck={false}
        value={displayValue}
        aria-label={label}
      />
    </div>
  )
}
