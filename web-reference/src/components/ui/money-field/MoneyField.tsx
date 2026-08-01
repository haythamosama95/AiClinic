import {
  forwardRef,
  useState,
  type FocusEvent,
  type InputHTMLAttributes,
} from 'react'
import { cn } from '@/lib/cn'
import { useDirection } from '@/providers/DirectionProvider'
import {
  bareInputClasses,
  inputAffixClasses,
  inputWrapperClasses,
  type InputSize,
} from '../input-base/input-styles'

export type MoneyFieldProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'size' | 'type' | 'onChange'> & {
  size?: InputSize
  invalid?: boolean
  currency?: string
  value?: number | null
  defaultValue?: number
  onValueChange?: (value: number | null) => void
}

function formatMoney(value: number, locale: string): string {
  return new Intl.NumberFormat(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value)
}

function parseMoney(raw: string): number | null {
  const cleaned = raw.replace(/[^\d.-]/g, '')
  if (!cleaned || cleaned === '-' || cleaned === '.') return null
  const n = Number.parseFloat(cleaned)
  return Number.isFinite(n) ? n : null
}

export const MoneyField = forwardRef<HTMLInputElement, MoneyFieldProps>(function MoneyField(
  {
    size = 'md',
    invalid,
    currency = 'EGP',
    disabled,
    readOnly,
    className,
    value: controlled,
    defaultValue,
    onValueChange,
    min = 0,
    ...props
  },
  ref,
) {
  const { locale } = useDirection()
  const intlLocale = locale === 'ar' ? 'ar-EG' : 'en-EG'
  const [internal, setInternal] = useState<number | null>(defaultValue ?? null)
  const [display, setDisplay] = useState(() =>
    defaultValue !== undefined ? formatMoney(defaultValue, intlLocale) : '',
  )
  const [focused, setFocused] = useState(false)

  const numericValue = controlled !== undefined ? controlled : internal

  const handleFocus = () => {
    setFocused(true)
    if (numericValue !== null && numericValue !== undefined) {
      setDisplay(String(numericValue))
    }
  }

  const handleBlur = (e: FocusEvent<HTMLInputElement>) => {
    setFocused(false)
    const parsed = parseMoney(e.target.value)
    let next = parsed
    if (next !== null && typeof min === 'number' && next < min) next = min
    if (controlled === undefined) setInternal(next)
    onValueChange?.(next)
    setDisplay(next !== null ? formatMoney(next, intlLocale) : '')
    props.onBlur?.(e)
  }

  const handleChange = (raw: string) => {
    setDisplay(raw)
    const parsed = parseMoney(raw)
    if (controlled === undefined) setInternal(parsed)
    if (focused) onValueChange?.(parsed)
  }

  const affix = (
    <span className={inputAffixClasses(size)} aria-hidden>
      {currency}
    </span>
  )

  return (
    <div
      className={inputWrapperClasses({ size, invalid, disabled, readOnly, className })}
      dir="ltr"
    >
      {affix}
      <input
        ref={ref}
        type="text"
        inputMode="decimal"
        disabled={disabled}
        readOnly={readOnly}
        value={focused ? display : numericValue !== null && numericValue !== undefined ? formatMoney(numericValue, intlLocale) : display}
        onFocus={handleFocus}
        onBlur={handleBlur}
        onChange={(e) => handleChange(e.target.value)}
        className={cn(bareInputClasses(), 'text-end tabular-nums')}
        aria-valuemin={typeof min === 'number' ? min : undefined}
        {...props}
      />
    </div>
  )
})
