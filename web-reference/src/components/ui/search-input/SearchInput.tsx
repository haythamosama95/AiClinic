import { Search } from 'lucide-react'
import {
  forwardRef,
  useCallback,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type InputHTMLAttributes,
} from 'react'
import { cn } from '@/lib/cn'
import { KbdKey } from '@/components/kbd'
import { bareInputClasses, inputWrapperClasses, type InputSize } from '../input-base/input-styles'
import { Spinner } from '../spinner/Spinner'

export type SearchInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'size' | 'onChange'> & {
  size?: InputSize
  invalid?: boolean
  loading?: boolean
  resultCount?: number
  showShortcutHint?: boolean
  debounceMs?: number
  onValueChange?: (value: string) => void
  onChange?: (event: ChangeEvent<HTMLInputElement>) => void
}

export const SearchInput = forwardRef<HTMLInputElement, SearchInputProps>(function SearchInput(
  {
    size = 'md',
    invalid,
    loading,
    resultCount,
    showShortcutHint = true,
    debounceMs = 300,
    onValueChange,
    onChange,
    disabled,
    readOnly,
    className,
    value: controlledValue,
    defaultValue,
    ...props
  },
  ref,
) {
  const [internal, setInternal] = useState(String(defaultValue ?? ''))
  const isControlled = controlledValue !== undefined
  const value = isControlled ? String(controlledValue) : internal
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const emit = useCallback(
    (next: string) => {
      if (!isControlled) setInternal(next)
      onValueChange?.(next)
    },
    [isControlled, onValueChange],
  )

  const handleChange = (e: ChangeEvent<HTMLInputElement>) => {
    const next = e.target.value
    if (!isControlled) setInternal(next)
    onChange?.(e)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => emit(next), debounceMs)
  }

  const clear = () => {
    emit('')
    if (!isControlled) setInternal('')
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && document.activeElement === (ref as React.RefObject<HTMLInputElement>)?.current) {
        clear()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  return (
    <div className={cn('flex flex-col gap-1', className)}>
      <div className={inputWrapperClasses({ size, invalid, disabled, readOnly })}>
        <Search className="size-4 shrink-0 text-icon-muted" aria-hidden />
        <input
          ref={ref}
          type="search"
          role="searchbox"
          disabled={disabled}
          readOnly={readOnly}
          value={value}
          onChange={handleChange}
          className={bareInputClasses()}
          {...props}
        />
        {loading ? <Spinner size="sm" /> : null}
        {value && !loading ? (
          <button
            type="button"
            onClick={clear}
            className="focus-ring shrink-0 rounded-sm px-1 text-caption text-text-link hover:bg-surface-hover"
            aria-label="Clear search"
          >
            Clear
          </button>
        ) : showShortcutHint && !value ? (
          <span className="hidden items-center gap-0.5 sm:flex" aria-hidden>
            <KbdKey>/</KbdKey>
          </span>
        ) : null}
      </div>
      {resultCount !== undefined ? (
        <p className="text-caption text-text-tertiary tabular-nums" aria-live="polite">
          {resultCount} {resultCount === 1 ? 'result' : 'results'}
        </p>
      ) : null}
    </div>
  )
})
