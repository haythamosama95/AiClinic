import { type ImgHTMLAttributes, useMemo } from 'react'
import { cn } from '@/lib/cn'

export type AvatarSize = 'xs' | 'sm' | 'md' | 'lg' | 'xl'
export type AvatarStatus = 'online' | 'offline' | 'busy' | 'away'

const sizeClasses: Record<AvatarSize, string> = {
  xs: 'size-5 text-[10px]',
  sm: 'size-6 text-caption',
  md: 'size-8 text-body-sm',
  lg: 'size-10 text-body',
  xl: 'size-12 text-title',
}

const statusSizeClasses: Record<AvatarSize, string> = {
  xs: 'size-1.5 border',
  sm: 'size-1.5 border',
  md: 'size-2 border-2',
  lg: 'size-2.5 border-2',
  xl: 'size-3 border-2',
}

const statusColorClasses: Record<AvatarStatus, string> = {
  online: 'bg-status-success-fg',
  offline: 'bg-icon-muted',
  busy: 'bg-status-danger-fg',
  away: 'bg-status-warning-fg',
}

const INITIALS_SURFACES = [
  'bg-surface-muted text-text-secondary',
  'bg-surface-selected text-text-link',
  'bg-status-info-surface text-status-info-fg',
  'bg-status-success-surface text-status-success-fg',
  'bg-status-warning-surface text-status-warning-fg',
] as const

function hashString(value: string): number {
  let hash = 0
  for (let i = 0; i < value.length; i += 1) {
    hash = (hash << 5) - hash + value.charCodeAt(i)
    hash |= 0
  }
  return Math.abs(hash)
}

function getInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase()
}

export type AvatarProps = Omit<ImgHTMLAttributes<HTMLImageElement>, 'size'> & {
  name: string
  size?: AvatarSize
  status?: AvatarStatus
  showStatus?: boolean
}

export function Avatar({
  name,
  src,
  alt,
  size = 'md',
  status = 'offline',
  showStatus = false,
  className,
  ...props
}: AvatarProps) {
  const initials = useMemo(() => getInitials(name), [name])
  const surfaceClass = useMemo(
    () => INITIALS_SURFACES[hashString(name) % INITIALS_SURFACES.length],
    [name],
  )

  return (
    <span className={cn('relative inline-flex shrink-0', className)}>
      {src ? (
        <img
          src={src}
          alt={alt ?? name}
          className={cn(
            'rounded-full object-cover ring-1 ring-border-subtle',
            sizeClasses[size],
          )}
          {...props}
        />
      ) : (
        <span
          role="img"
          aria-label={name}
          className={cn(
            'inline-flex items-center justify-center rounded-full font-medium ring-1 ring-border-subtle',
            sizeClasses[size],
            surfaceClass,
          )}
        >
          {initials}
        </span>
      )}

      {showStatus ? (
        <span
          className={cn(
            'absolute rounded-full border-surface-default',
            'end-0 bottom-0',
            statusSizeClasses[size],
            statusColorClasses[status],
          )}
          aria-label={`Status: ${status}`}
        />
      ) : null}
    </span>
  )
}
