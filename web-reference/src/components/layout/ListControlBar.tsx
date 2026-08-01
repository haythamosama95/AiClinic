import type { ReactNode } from 'react'
import { ArrowUpDown, Check, SlidersHorizontal } from 'lucide-react'
import { motion, AnimatePresence } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { Chip } from '@/components/chip'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import { Popover } from '@/components/ui/popover/Popover'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { cn } from '@/lib/cn'
import { getReducedMotion } from '@/lib/motion'

export type SortOption = {
  value: string
  label: string
}

export type ActiveFilter = {
  id: string
  label: string
  onRemove: () => void
}

export type ListControlBarProps = {
  searchPlaceholder: string
  searchAriaLabel: string
  search: string
  onSearchChange: (value: string) => void
  sortValue: string
  defaultSortValue: string
  sortOptions: SortOption[]
  onSortChange: (value: string) => void
  sortAriaLabel: string
  filterMenu: ReactNode
  filterActiveCount?: number
  onClearFilters?: () => void
  activeFilters?: ActiveFilter[]
  onClearAll?: () => void
  className?: string
}

export function ListControlBar({
  searchPlaceholder,
  searchAriaLabel,
  search,
  onSearchChange,
  sortValue,
  defaultSortValue,
  sortOptions,
  onSortChange,
  sortAriaLabel,
  filterMenu,
  filterActiveCount = 0,
  onClearFilters,
  activeFilters = [],
  onClearAll,
  className,
}: ListControlBarProps) {
  const hasActiveFilters = activeFilters.length > 0 || search.length > 0
  const sortIsCustom = sortValue !== defaultSortValue

  return (
    <div
      className={cn(
        'overflow-hidden rounded-2xl border border-border-subtle',
        'bg-[linear-gradient(180deg,var(--surface-default)_0%,color-mix(in_srgb,var(--color-teal-50)_35%,var(--surface-default))_100%)]',
        'shadow-elevation-1',
        className,
      )}
    >
      <div className="flex flex-col gap-3 p-4 sm:p-5">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <SearchInput
            placeholder={searchPlaceholder}
            aria-label={searchAriaLabel}
            value={search}
            onValueChange={onSearchChange}
            className="min-w-0 flex-1"
            showShortcutHint={false}
          />

          <div className="flex shrink-0 items-center gap-2">
            <Popover
              align="end"
              contentClassName="w-[min(18rem,calc(100vw-2rem))]"
              trigger={
                <Button
                  type="button"
                  variant="secondary"
                  size="md"
                  leadingIcon={<SlidersHorizontal size={15} />}
                  className="relative"
                >
                  Filter
                  {filterActiveCount > 0 ? (
                    <span
                      aria-hidden
                      className="ms-1 inline-flex size-5 min-w-5 items-center justify-center rounded-full bg-action-primary px-1 text-[10px] font-semibold leading-none text-action-primary-fg"
                    >
                      {filterActiveCount}
                    </span>
                  ) : null}
                </Button>
              }
            >
              <div className="flex flex-col">
                {filterMenu}
                {filterActiveCount > 0 && onClearFilters ? (
                  <div className="border-t border-border-subtle p-2">
                    <Button
                      type="button"
                      variant="secondary"
                      size="sm"
                      className="w-full"
                      onClick={onClearFilters}
                    >
                      Clear filters
                    </Button>
                  </div>
                ) : null}
              </div>
            </Popover>

            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  type="button"
                  variant="secondary"
                  size="md"
                  leadingIcon={<ArrowUpDown size={15} />}
                  className="relative"
                  aria-label={sortAriaLabel}
                >
                  Sort
                  {sortIsCustom ? (
                    <span
                      aria-hidden
                      className="absolute end-1.5 top-1.5 size-1.5 rounded-full bg-action-primary"
                    />
                  ) : null}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-[11rem]">
                <DropdownMenuLabel>Sort by</DropdownMenuLabel>
                {sortOptions.map((option) => {
                  const selected = option.value === sortValue
                  return (
                    <DropdownMenuItem
                      key={option.value}
                      onSelect={() => onSortChange(option.value)}
                      icon={
                        selected ? (
                          <Check size={14} className="text-action-primary" />
                        ) : (
                          <span className="size-3.5" aria-hidden />
                        )
                      }
                    >
                      {option.label}
                    </DropdownMenuItem>
                  )
                })}
                {sortIsCustom ? (
                  <>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onSelect={() => onSortChange(defaultSortValue)}>
                      Clear sorting
                    </DropdownMenuItem>
                  </>
                ) : null}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </div>

      <AnimatePresence initial={false}>
        {activeFilters.length > 0 ? (
          <motion.div
            initial={getReducedMotion() ? false : { height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.18 }}
            className="overflow-hidden border-t border-border-subtle/80 bg-surface-sunken/40"
          >
            <div className="flex flex-wrap items-center gap-2 px-4 py-3 sm:px-5">
              <SlidersHorizontal
                size={13}
                strokeWidth={1.75}
                className="shrink-0 text-icon-muted"
                aria-hidden
              />
              <span className="text-caption font-medium text-text-tertiary">Filtered by</span>
              {activeFilters.map((filter) => (
                <Chip key={filter.id} removable onRemove={filter.onRemove}>
                  {filter.label}
                </Chip>
              ))}
              {hasActiveFilters && onClearAll ? (
                <button
                  type="button"
                  onClick={onClearAll}
                  className="focus-ring ms-auto rounded-md px-2 py-1 text-caption font-medium text-text-link transition-colors hover:bg-surface-hover"
                >
                  Clear all
                </button>
              ) : null}
            </div>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </div>
  )
}
