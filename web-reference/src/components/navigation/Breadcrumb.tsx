import { ChevronRight } from 'lucide-react'
import { cn } from '@/lib/cn'

export type BreadcrumbItem = {
  label: string
  href?: string
  onClick?: () => void
}

export type BreadcrumbProps = {
  items: BreadcrumbItem[]
  className?: string
}

export function Breadcrumb({ items, className }: BreadcrumbProps) {
  if (items.length === 0) return null

  return (
    <nav aria-label="Breadcrumb" className={cn('min-w-0', className)}>
      <ol className="flex min-w-0 items-center gap-1 text-body-sm">
        {items.map((item, index) => {
          const isLast = index === items.length - 1
          const isMiddle = index > 0 && index < items.length - 1 && items.length > 3

          return (
            <li
              key={`${item.label}-${index}`}
              className={cn(
                'flex min-w-0 items-center gap-1',
                isMiddle && index === 1 && items.length > 3 && 'max-sm:hidden',
                isMiddle && index === items.length - 2 && items.length > 3 && 'max-sm:hidden',
              )}
            >
              {index > 0 ? (
                <ChevronRight
                  size={14}
                  strokeWidth={1.5}
                  className="shrink-0 text-icon-muted rtl:-scale-x-100"
                  aria-hidden
                />
              ) : null}
              {index === 1 && items.length > 3 ? (
                <span className="hidden px-1 text-text-tertiary sm:inline" aria-hidden>
                  …
                </span>
              ) : null}
              {isLast ? (
                <span
                  className="truncate font-medium text-text-primary"
                  aria-current="page"
                >
                  {item.label}
                </span>
              ) : item.href || item.onClick ? (
                <a
                  href={item.href ?? '#'}
                  onClick={(e) => {
                    if (item.onClick) {
                      e.preventDefault()
                      item.onClick()
                    }
                  }}
                  className="focus-ring truncate rounded-sm text-text-secondary hover:text-text-link"
                >
                  {item.label}
                </a>
              ) : (
                <span className="truncate text-text-secondary">{item.label}</span>
              )}
            </li>
          )
        })}
      </ol>
    </nav>
  )
}
