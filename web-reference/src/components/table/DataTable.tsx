import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  MoreHorizontal,
} from 'lucide-react'
import { motion } from 'motion/react'
import type { ReactNode } from 'react'
import { Checkbox } from '@/components/ui/checkbox/Checkbox'
import { IconButton } from '@/components/actions/IconButton'
import { ContextMenu, type MenuEntry } from '@/components/navigation/Menu'
import { Skeleton } from '@/components/skeleton/Skeleton'
import { cn } from '@/lib/cn'
import { useDensity } from '@/providers/DensityProvider'

export type TableDensity = 'compact' | 'default' | 'comfortable'
export type TableAlign = 'start' | 'end' | 'center'
export type SortDirection = 'asc' | 'desc' | null

export type TableColumn<T> = {
  id: string
  header: string
  accessor: (row: T) => ReactNode
  align?: TableAlign
  sortable?: boolean
  width?: string
}

export type DataTableProps<T> = {
  columns: TableColumn<T>[]
  data: T[]
  density?: TableDensity
  zebra?: boolean
  stickyFirstColumn?: boolean
  selectable?: boolean
  selectedIds?: Set<string>
  onSelectionChange?: (ids: Set<string>) => void
  getRowId: (row: T) => string
  sortColumn?: string
  sortDirection?: SortDirection
  onSort?: (columnId: string) => void
  loading?: boolean
  loadingRows?: number
  emptyState?: ReactNode
  errorState?: ReactNode
  footer?: ReactNode
  onRowClick?: (row: T) => void
  rowActions?: (row: T) => ReactNode
  rowContextMenu?: (row: T) => MenuEntry[]
  animateRows?: boolean
  className?: string
  'aria-label'?: string
}

const MotionTr = motion.tr

const densityRowHeight: Record<TableDensity, string> = {
  compact: 'h-9',
  default: 'h-10',
  comfortable: 'h-12',
}

const alignClass: Record<TableAlign, string> = {
  start: 'text-start',
  end: 'text-end',
  center: 'text-center',
}

export function DataTable<T>({
  columns,
  data,
  density: densityProp,
  zebra = false,
  stickyFirstColumn = false,
  selectable = false,
  selectedIds = new Set(),
  onSelectionChange,
  getRowId,
  sortColumn,
  sortDirection,
  onSort,
  loading = false,
  loadingRows = 5,
  emptyState,
  errorState,
  footer,
  onRowClick,
  rowActions,
  rowContextMenu,
  animateRows = false,
  className,
  'aria-label': ariaLabel = 'Data table',
}: DataTableProps<T>) {
  const { density: globalDensity } = useDensity()
  const density = densityProp ?? (globalDensity === 'compact' ? 'compact' : globalDensity === 'comfortable' ? 'comfortable' : 'default')

  const allSelected = data.length > 0 && data.every((row) => selectedIds.has(getRowId(row)))
  const someSelected = data.some((row) => selectedIds.has(getRowId(row)))

  const toggleAll = () => {
    if (!onSelectionChange) return
    if (allSelected) {
      onSelectionChange(new Set())
    } else {
      onSelectionChange(new Set(data.map(getRowId)))
    }
  }

  const toggleRow = (id: string) => {
    if (!onSelectionChange) return
    const next = new Set(selectedIds)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    onSelectionChange(next)
  }

  const SortIcon = ({ columnId }: { columnId: string }) => {
    if (sortColumn !== columnId) {
      return <ArrowUpDown size={14} className="text-icon-muted" aria-hidden />
    }
    return sortDirection === 'asc' ? (
      <ArrowUp size={14} className="text-text-link" aria-hidden />
    ) : (
      <ArrowDown size={14} className="text-text-link" aria-hidden />
    )
  }

  return (
    <div className={cn('overflow-hidden rounded-lg border border-border-default', className)}>
      <div className="overflow-x-auto">
        <table className="w-full min-w-max border-collapse text-body-sm" aria-label={ariaLabel}>
          <thead className="sticky top-0 z-10 bg-surface-muted">
            <tr className="border-b border-border-default">
              {selectable ? (
                <th scope="col" className="w-10 px-3 py-2">
                  <Checkbox
                    checked={
                      someSelected && !allSelected
                        ? 'indeterminate'
                        : allSelected
                    }
                    onCheckedChange={toggleAll}
                    aria-label="Select all rows"
                  />
                </th>
              ) : null}
              {columns.map((col, index) => (
                <th
                  key={col.id}
                  scope="col"
                  style={{ width: col.width }}
                  className={cn(
                    'px-3 py-2 text-overline text-text-tertiary',
                    alignClass[col.align ?? 'start'],
                    stickyFirstColumn && index === 0 && 'sticky start-0 z-20 bg-surface-muted',
                  )}
                >
                  {col.sortable ? (
                    <button
                      type="button"
                      onClick={() => onSort?.(col.id)}
                      className="focus-ring inline-flex items-center gap-1 rounded-sm hover:text-text-primary"
                      aria-sort={
                        sortColumn === col.id
                          ? sortDirection === 'asc'
                            ? 'ascending'
                            : 'descending'
                          : 'none'
                      }
                    >
                      {col.header}
                      <SortIcon columnId={col.id} />
                    </button>
                  ) : (
                    col.header
                  )}
                </th>
              ))}
              {rowActions ? <th scope="col" className="w-12 px-2 py-2"><span className="sr-only">Actions</span></th> : null}
            </tr>
          </thead>
          <tbody>
            {loading
              ? Array.from({ length: loadingRows }).map((_, i) => (
                <tr key={`skel-${i}`} className={cn('border-b border-border-subtle', densityRowHeight[density])}>
                  {selectable ? (
                    <td className="px-3 py-2">
                      <Skeleton className="size-4 rounded-sm" />
                    </td>
                  ) : null}
                  {columns.map((col) => (
                    <td key={col.id} className="px-3 py-2">
                      <Skeleton className="h-4 w-full max-w-[120px] rounded-sm" />
                    </td>
                  ))}
                  {rowActions ? <td /> : null}
                </tr>
              ))
              : null}

            {!loading && errorState ? (
              <tr>
                <td colSpan={columns.length + (selectable ? 1 : 0) + (rowActions ? 1 : 0)}>
                  {errorState}
                </td>
              </tr>
            ) : null}

            {!loading && !errorState && data.length === 0 && emptyState ? (
              <tr>
                <td colSpan={columns.length + (selectable ? 1 : 0) + (rowActions ? 1 : 0)}>
                  {emptyState}
                </td>
              </tr>
            ) : null}

            {!loading && !errorState
              ? data.map((rowData, rowIndex) => {
                const id = getRowId(rowData)
                const selected = selectedIds.has(id)

                const rowClassName = cn(
                  'border-b border-border-subtle transition-colors duration-[var(--duration-instant)]',
                  densityRowHeight[density],
                  zebra && rowIndex % 2 === 1 && 'bg-surface-muted',
                  selected && 'bg-surface-selected',
                  onRowClick && 'cursor-pointer hover:bg-surface-hover',
                )

                const rowInteractionProps = {
                  onClick: onRowClick ? () => onRowClick(rowData) : undefined,
                  onKeyDown: onRowClick
                    ? (e: React.KeyboardEvent<HTMLTableRowElement>) => {
                      if (e.key === 'Enter') onRowClick(rowData)
                    }
                    : undefined,
                  tabIndex: onRowClick ? 0 : undefined,
                  'aria-selected': selectable ? selected : undefined,
                }

                const rowCells = (
                  <>
                    {selectable ? (
                      <td className="px-3 py-2" onClick={(e) => e.stopPropagation()}>
                        <Checkbox
                          checked={selected}
                          onCheckedChange={() => toggleRow(id)}
                          aria-label={`Select row ${id}`}
                        />
                      </td>
                    ) : null}
                    {columns.map((col, colIndex) => (
                      <td
                        key={col.id}
                        className={cn(
                          'px-3 py-2 text-text-primary',
                          alignClass[col.align ?? 'start'],
                          col.align === 'end' && 'tabular-nums',
                          stickyFirstColumn && colIndex === 0 && 'sticky start-0 z-10 bg-surface-default',
                          selected && stickyFirstColumn && colIndex === 0 && 'bg-surface-selected',
                        )}
                      >
                        {col.accessor(rowData)}
                      </td>
                    ))}
                    {rowActions ? (
                      <td className="px-2 py-2" onClick={(e) => e.stopPropagation()}>
                        {rowActions(rowData) ?? (
                          <IconButton
                            icon={<MoreHorizontal size={16} />}
                            label="Row actions"
                            size="sm"
                          />
                        )}
                      </td>
                    ) : null}
                  </>
                )

                const rowElement = animateRows ? (
                  <MotionTr
                    key={id}
                    layout
                    initial={{ opacity: 0, x: -6 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{
                      duration: 0.2,
                      delay: Math.min(rowIndex * 0.025, 0.12),
                    }}
                    className={rowClassName}
                    {...rowInteractionProps}
                  >
                    {rowCells}
                  </MotionTr>
                ) : (
                  <tr key={id} className={rowClassName} {...rowInteractionProps}>
                    {rowCells}
                  </tr>
                )

                if (rowContextMenu) {
                  return (
                    <ContextMenu key={id} entries={rowContextMenu(rowData)}>
                      {rowElement}
                    </ContextMenu>
                  )
                }

                return rowElement
              })
              : null}
          </tbody>
          {footer ? (
            <tfoot className="border-t border-border-default bg-surface-muted">
              <tr>
                <td colSpan={columns.length + (selectable ? 1 : 0) + (rowActions ? 1 : 0)} className="px-3 py-2">
                  {footer}
                </td>
              </tr>
            </tfoot>
          ) : null}
        </table>
      </div>
    </div>
  )
}
