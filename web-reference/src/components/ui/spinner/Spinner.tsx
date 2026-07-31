import { Loader2 } from 'lucide-react'
import { cn } from '@/lib/cn'

export type SpinnerSize = 'sm' | 'md'

const sizeMap: Record<SpinnerSize, string> = {
  sm: 'size-4',
  md: 'size-5',
}

export function Spinner({
  size = 'sm',
  className,
  label = 'Loading',
}: {
  size?: SpinnerSize
  className?: string
  label?: string
}) {
  return (
    <Loader2
      className={cn('animate-spin text-icon-muted', sizeMap[size], className)}
      aria-label={label}
      role="status"
    />
  )
}
