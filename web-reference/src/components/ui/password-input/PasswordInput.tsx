import { Eye, EyeOff } from 'lucide-react'
import { forwardRef, useEffect, useState, type InputHTMLAttributes } from 'react'
import { bareInputClasses, inputWrapperClasses, type InputSize } from '../input-base/input-styles'

export type PasswordInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'size' | 'type'> & {
  size?: InputSize
  invalid?: boolean
}

export const PasswordInput = forwardRef<HTMLInputElement, PasswordInputProps>(
  function PasswordInput(
    { size = 'md', invalid, disabled, readOnly, className, ...props },
    ref,
  ) {
    const [visible, setVisible] = useState(false)
    const [capsLock, setCapsLock] = useState(false)

    useEffect(() => {
      const onKey = (e: KeyboardEvent) => {
        if (e.getModifierState) setCapsLock(e.getModifierState('CapsLock'))
      }
      window.addEventListener('keydown', onKey)
      window.addEventListener('keyup', onKey)
      return () => {
        window.removeEventListener('keydown', onKey)
        window.removeEventListener('keyup', onKey)
      }
    }, [])

    return (
      <div className="flex flex-col gap-1">
        <div className={inputWrapperClasses({ size, invalid, disabled, readOnly, className })}>
          <input
            ref={ref}
            type={visible ? 'text' : 'password'}
            disabled={disabled}
            readOnly={readOnly}
            className={bareInputClasses()}
            onKeyUp={(e) => setCapsLock(e.getModifierState('CapsLock'))}
            {...props}
          />
          <button
            type="button"
            disabled={disabled}
            onClick={() => setVisible((v) => !v)}
            className="focus-ring shrink-0 rounded-sm p-0.5 text-icon-muted hover:text-icon-default disabled:opacity-50"
            aria-label={visible ? 'Hide password' : 'Show password'}
            aria-pressed={visible}
          >
            {visible ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
          </button>
        </div>
        {capsLock ? (
          <p className="text-caption text-status-warning-fg" role="status">
            Caps Lock is on
          </p>
        ) : null}
      </div>
    )
  },
)
