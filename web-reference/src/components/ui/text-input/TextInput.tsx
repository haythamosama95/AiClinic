import { X } from 'lucide-react'
import { forwardRef, type InputHTMLAttributes, type ReactNode } from 'react'
import {
  bareInputClasses,
  inputAffixClasses,
  inputFieldClasses,
  inputWrapperClasses,
  type InputSize,
} from '../input-base/input-styles'

export type TextInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> & {
  size?: InputSize
  invalid?: boolean
  leadingIcon?: ReactNode
  trailingIcon?: ReactNode
  prefix?: ReactNode
  suffix?: ReactNode
  onClear?: () => void
  showClear?: boolean
}

export const TextInput = forwardRef<HTMLInputElement, TextInputProps>(
  function TextInput(
    {
      size = 'md',
      invalid,
      leadingIcon,
      trailingIcon,
      prefix,
      suffix,
      onClear,
      showClear,
      disabled,
      readOnly,
      className,
      value,
      ...props
    },
    ref,
  ) {
    const hasAffix = prefix || suffix || leadingIcon || trailingIcon || showClear
    const canClear = showClear && !disabled && !readOnly && value

    if (!hasAffix) {
      return (
        <input
          ref={ref}
          disabled={disabled}
          readOnly={readOnly}
          value={value}
          className={inputFieldClasses({ size, invalid, disabled, readOnly, className })}
          {...props}
        />
      )
    }

    return (
      <div className={inputWrapperClasses({ size, invalid, disabled, readOnly, className })}>
        {leadingIcon ? (
          <span className="shrink-0 text-icon-muted" aria-hidden>
            {leadingIcon}
          </span>
        ) : null}
        {prefix ? <span className={inputAffixClasses(size)}>{prefix}</span> : null}
        <input
          ref={ref}
          disabled={disabled}
          readOnly={readOnly}
          value={value}
          className={bareInputClasses()}
          {...props}
        />
        {suffix ? <span className={inputAffixClasses(size)}>{suffix}</span> : null}
        {canClear ? (
          <button
            type="button"
            onClick={onClear}
            className="focus-ring shrink-0 rounded-sm p-0.5 text-icon-muted hover:text-icon-default"
            aria-label="Clear"
          >
            <X className="size-4" />
          </button>
        ) : trailingIcon ? (
          <span className="shrink-0 text-icon-muted" aria-hidden>
            {trailingIcon}
          </span>
        ) : null}
      </div>
    )
  },
)
