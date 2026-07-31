import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useCallback, useId } from 'react'
import { IconButton } from '@/components/actions/IconButton'
import { Select } from '@/components/ui/select/Select'
import { cn } from '@/lib/cn'

export type PaginationProps = {
  page: number
  pageSize: number
  total: number
  pageSizeOptions?: number[]
  onPageChange: (page: number) => void
  onPageSizeChange?: (size: number) => void
  className?: string
}

export function Pagination({
  page,
  pageSize,
  total,
  pageSizeOptions = [25, 50, 100],
  onPageChange,
  onPageSizeChange,
  className,
}: PaginationProps) {
  const labelId = useId()
  const totalPages = Math.max(1, Math.ceil(total / pageSize))
  const start = total === 0 ? 0 : (page - 1) * pageSize + 1
  const end = Math.min(page * pageSize, total)

  const goPrev = useCallback(() => {
    if (page > 1) onPageChange(page - 1)
  }, [page, onPageChange])

  const goNext = useCallback(() => {
    if (page < totalPages) onPageChange(page + 1)
  }, [page, totalPages, onPageChange])

  return (
    <nav
      aria-labelledby={labelId}
      className={cn('flex flex-wrap items-center justify-between gap-4', className)}
    >
      <p id={labelId} className="text-body-sm text-text-secondary tabular-nums">
        <span className="font-medium text-text-primary">
          {start.toLocaleString()}–{end.toLocaleString()}
        </span>{' '}
        of {total.toLocaleString()}
      </p>

      <div className="flex items-center gap-3">
        {onPageSizeChange ? (
          <div className="flex items-center gap-2">
            <label htmlFor={`${labelId}-size`} className="text-body-sm text-text-secondary">
              Rows
            </label>
            <Select
              id={`${labelId}-size`}
              size="sm"
              value={String(pageSize)}
              options={pageSizeOptions.map((n) => ({
                value: String(n),
                label: String(n),
              }))}
              onValueChange={(v) => onPageSizeChange(Number(v))}
              className="w-20"
            />
          </div>
        ) : null}

        <div className="flex items-center gap-1">
          <IconButton
            label="Previous page"
            size="sm"
            variant="ghost"
            disabled={page <= 1}
            onClick={goPrev}
            icon={
              <ChevronLeft size={16} strokeWidth={1.5} className="rtl:-scale-x-100" />
            }
          />
          <span className="min-w-[4rem] text-center text-body-sm tabular-nums text-text-primary">
            {page} / {totalPages}
          </span>
          <IconButton
            label="Next page"
            size="sm"
            variant="ghost"
            disabled={page >= totalPages}
            onClick={goNext}
            icon={
              <ChevronRight size={16} strokeWidth={1.5} className="rtl:-scale-x-100" />
            }
          />
        </div>
      </div>
    </nav>
  )
}
