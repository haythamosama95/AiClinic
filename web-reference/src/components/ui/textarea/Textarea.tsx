import {
  forwardRef,
  useCallback,
  useEffect,
  useRef,
  type TextareaHTMLAttributes,
} from 'react'
import { cn } from '@/lib/cn'
import { inputFieldClasses, type InputSize } from '../input-base/input-styles'

export type TextareaProps = Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'size'> & {
  size?: InputSize
  invalid?: boolean
  autoGrow?: boolean
  maxLength?: number
  showCounter?: boolean
}

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea(
  {
    size = 'md',
    invalid,
    autoGrow,
    maxLength,
    showCounter,
    disabled,
    readOnly,
    className,
    value,
    defaultValue,
    onChange,
    rows = 3,
    ...props
  },
  ref,
) {
  const innerRef = useRef<HTMLTextAreaElement | null>(null)

  const setRefs = useCallback(
    (node: HTMLTextAreaElement | null) => {
      innerRef.current = node
      if (typeof ref === 'function') ref(node)
      else if (ref) ref.current = node
    },
    [ref],
  )

  const resize = useCallback(() => {
    const el = innerRef.current
    if (!el || !autoGrow) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight}px`
  }, [autoGrow])

  useEffect(() => {
    resize()
  }, [resize, value, defaultValue])

  const currentLength = String(value ?? innerRef.current?.value ?? '').length

  return (
    <div className="relative">
      <textarea
        ref={setRefs}
        rows={rows}
        disabled={disabled}
        readOnly={readOnly}
        maxLength={maxLength}
        value={value}
        defaultValue={defaultValue}
        onChange={(e) => {
          onChange?.(e)
          resize()
        }}
        className={cn(
          inputFieldClasses({ size, invalid, disabled, readOnly }),
          'h-auto min-h-[calc(var(--space-8)*2)] resize-y py-2',
          autoGrow && 'resize-none overflow-hidden',
          showCounter && 'pb-7',
          className,
        )}
        {...props}
      />
      {showCounter && maxLength ? (
        <span
          className="absolute bottom-2 end-3 text-caption text-text-tertiary tabular-nums"
          aria-live="polite"
        >
          {currentLength}/{maxLength}
        </span>
      ) : null}
    </div>
  )
})
