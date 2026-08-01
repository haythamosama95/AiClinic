import { forwardRef, useState, type InputHTMLAttributes } from 'react'
import { cn } from '@/lib/cn'
import { bareInputClasses, inputWrapperClasses, type InputSize } from '../input-base/input-styles'

const DEFAULT_COUNTRY = '+20'

export type PhoneInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'size' | 'type'> & {
  size?: InputSize
  invalid?: boolean
  countryCode?: string
  onValueChange?: (value: string) => void
}

function formatPhoneDigits(digits: string): string {
  const d = digits.replace(/\D/g, '').slice(0, 10)
  if (d.length <= 3) return d
  if (d.length <= 6) return `${d.slice(0, 3)} ${d.slice(3)}`
  return `${d.slice(0, 3)} ${d.slice(3, 6)} ${d.slice(6)}`
}

export const PhoneInput = forwardRef<HTMLInputElement, PhoneInputProps>(function PhoneInput(
  {
    size = 'md',
    invalid,
    countryCode = DEFAULT_COUNTRY,
    disabled,
    readOnly,
    className,
    value,
    defaultValue,
    onChange,
    onValueChange,
    ...props
  },
  ref,
) {
  const [internal, setInternal] = useState(String(defaultValue ?? ''))

  const display = value !== undefined ? formatPhoneDigits(String(value)) : formatPhoneDigits(internal)

  const handleChange = (raw: string) => {
    const digits = raw.replace(/\D/g, '').slice(0, 10)
    const formatted = formatPhoneDigits(digits)
    if (value === undefined) setInternal(formatted)
    onValueChange?.(digits)
    onChange?.({
      target: { value: digits },
    } as React.ChangeEvent<HTMLInputElement>)
  }

  return (
    <div
      className={inputWrapperClasses({ size, invalid, disabled, readOnly, className })}
      dir="ltr"
    >
      <span className="shrink-0 text-body text-text-secondary tabular-nums" aria-hidden>
        {countryCode}
      </span>
      <span className="h-4 w-px shrink-0 bg-border-default" aria-hidden />
      <input
        ref={ref}
        type="tel"
        inputMode="numeric"
        autoComplete="tel-national"
        disabled={disabled}
        readOnly={readOnly}
        value={display}
        onChange={(e) => handleChange(e.target.value)}
        placeholder="10x xxx xxxx"
        className={cn(bareInputClasses(), 'tabular-nums')}
        {...props}
      />
    </div>
  )
})
