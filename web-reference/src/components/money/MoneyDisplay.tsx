import { cn } from '@/lib/cn'

export type MoneyDisplayProps = {
  amount: number
  currency?: string
  emphasis?: boolean
  negative?: boolean
  className?: string
}

function formatAmount(amount: number): string {
  return Math.abs(amount).toLocaleString('en-EG', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

export function MoneyDisplay({
  amount,
  currency = 'EGP',
  emphasis = false,
  negative,
  className,
}: MoneyDisplayProps) {
  const isNegative = negative ?? amount < 0
  const formatted = formatAmount(amount)

  return (
    <span
      className={cn(
        'tabular-nums',
        emphasis ? 'font-semibold' : 'font-normal',
        isNegative ? 'text-status-danger-fg' : 'text-text-primary',
        className,
      )}
      dir="ltr"
    >
      {isNegative ? '−' : ''}
      {formatted}
      <span className="ms-1 text-text-tertiary">{currency}</span>
    </span>
  )
}
