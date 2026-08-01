import { CircleHelp, AlertCircle } from 'lucide-react'
import { cn } from '@/lib/cn'
import { Tooltip } from '@/components/tooltip'

export type FormFieldProps = {
  id: string
  label: string
  required?: boolean
  hint?: string
  helperText?: string
  error?: string
  children: React.ReactNode
  className?: string
}

export function FormField({
  id,
  label,
  required,
  hint,
  helperText,
  error,
  children,
  className,
}: FormFieldProps) {
  const helperId = helperText ? `${id}-helper` : undefined
  const errorId = error ? `${id}-error` : undefined
  const describedBy = [helperId, errorId].filter(Boolean).join(' ') || undefined

  return (
    <div className={cn('flex flex-col gap-1.5', className)}>
      <div className="flex items-center gap-1.5">
        <label htmlFor={id} className="text-body-strong text-text-primary">
          {label}
          {required ? (
            <span className="ms-0.5 text-status-danger-fg" aria-hidden="true">
              *
            </span>
          ) : null}
          {required ? <span className="sr-only"> (required)</span> : null}
        </label>
        {hint ? (
          <Tooltip content={hint}>
            <button
              type="button"
              className="focus-ring inline-flex size-5 items-center justify-center rounded-sm text-icon-muted hover:text-icon-default"
              aria-label={`More about ${label}`}
            >
              <CircleHelp className="size-4" aria-hidden />
            </button>
          </Tooltip>
        ) : null}
      </div>

      <div
        aria-describedby={describedBy}
        aria-invalid={error ? true : undefined}
      >
        {children}
      </div>

      {error ? (
        <p id={errorId} className="flex items-start gap-1.5 text-caption text-status-danger-fg" role="alert">
          <AlertCircle className="mt-px size-4 shrink-0" aria-hidden />
          <span>{error}</span>
        </p>
      ) : helperText ? (
        <p id={helperId} className="text-caption text-text-tertiary">
          {helperText}
        </p>
      ) : null}
    </div>
  )
}

/** Clone control props for form field association */
export function fieldControlProps(
  id: string,
  {
    invalid,
    describedBy,
  }: {
    invalid?: boolean
    describedBy?: string
  } = {},
) {
  return {
    id,
    'aria-invalid': invalid || undefined,
    'aria-describedby': describedBy,
  }
}
