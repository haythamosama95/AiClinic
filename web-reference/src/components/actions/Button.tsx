import { Slot } from '@radix-ui/react-slot'
import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { forwardRef, useRef, useEffect } from 'react'
import { Spinner } from '@/components/ui/spinner/Spinner'
import { cn } from '@/lib/cn'
import {
  getButtonClassNames,
  iconSizeForButton,
  type ButtonSize,
  type ButtonVariant,
} from './button-variants'

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant
  size?: ButtonSize
  loading?: boolean
  error?: boolean
  leadingIcon?: ReactNode
  trailingIcon?: ReactNode
  asChild?: boolean
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = 'primary',
    size = 'md',
    loading = false,
    error = false,
    disabled,
    leadingIcon,
    trailingIcon,
    asChild = false,
    className,
    children,
    type = 'button',
    ...props
  },
  ref,
) {
  const innerRef = useRef<HTMLButtonElement>(null)
  const isDisabled = disabled || loading
  const iconSize = iconSizeForButton(size)

  useEffect(() => {
    if (!loading || !innerRef.current) return
    const width = innerRef.current.offsetWidth
    innerRef.current.style.minWidth = `${width}px`
  }, [loading])

  const classNames = getButtonClassNames({
    variant,
    size,
    disabled: isDisabled,
    loading,
    error,
    className: cn(
      !isDisabled && 'active:scale-[0.98] motion-reduce:active:scale-100',
      className,
    ),
  })

  const content = (
    <>
      {loading ? (
        <Spinner size={size === 'lg' ? 'md' : 'sm'} className="shrink-0" />
      ) : leadingIcon ? (
        <span
          className="inline-flex shrink-0 [&>svg]:size-[var(--btn-icon-size)]"
          style={{ '--btn-icon-size': `${iconSize}px` } as React.CSSProperties}
        >
          {leadingIcon}
        </span>
      ) : null}
      <span>{children}</span>
      {!loading && trailingIcon ? (
        <span
          className="inline-flex shrink-0 [&>svg]:size-[var(--btn-icon-size)]"
          style={{ '--btn-icon-size': `${iconSize}px` } as React.CSSProperties}
        >
          {trailingIcon}
        </span>
      ) : null}
    </>
  )

  if (asChild) {
    return (
      <Slot
        ref={ref}
        className={classNames}
        aria-busy={loading || undefined}
        aria-disabled={isDisabled || undefined}
        {...props}
      >
        {children}
      </Slot>
    )
  }

  return (
    <button
      ref={(node) => {
        innerRef.current = node
        if (typeof ref === 'function') ref(node)
        else if (ref) ref.current = node
      }}
      type={type}
      disabled={isDisabled}
      aria-busy={loading || undefined}
      aria-invalid={error || undefined}
      className={classNames}
      {...props}
    >
      {content}
    </button>
  )
})
