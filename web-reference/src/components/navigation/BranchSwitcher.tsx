import { Building2, Check, ChevronDown } from 'lucide-react'
import { useMemo, useState } from 'react'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { cn } from '@/lib/cn'
import type { Branch } from './nav-model'

export type BranchSwitcherProps = {
  branches: Branch[]
  currentBranchId: string
  onBranchChange: (branchId: string) => void
  className?: string
}

export function BranchSwitcher({
  branches,
  currentBranchId,
  onBranchChange,
  className,
}: BranchSwitcherProps) {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [feedback, setFeedback] = useState<string | null>(null)

  const current = branches.find((b) => b.id === currentBranchId) ?? branches[0]

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return branches
    return branches.filter(
      (b) => b.name.toLowerCase().includes(q) || b.org.toLowerCase().includes(q),
    )
  }, [branches, query])

  const handleSelect = (branchId: string) => {
    const branch = branches.find((b) => b.id === branchId)
    if (!branch || branchId === currentBranchId) {
      setOpen(false)
      return
    }
    onBranchChange(branchId)
    setFeedback(`Switched to ${branch.name}`)
    setOpen(false)
    setQuery('')
    window.setTimeout(() => setFeedback(null), 2500)
  }

  return (
    <div className={cn('relative', className)}>
      <DropdownMenu open={open} onOpenChange={setOpen}>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className={cn(
              'focus-ring inline-flex max-w-[12rem] items-center gap-2 rounded-md border border-border-default bg-surface-default px-3 py-1.5 text-start transition-colors hover:bg-surface-hover',
              'data-[density=compact]:py-1 data-[density=comfortable]:py-2',
            )}
            aria-label={`Current branch: ${current?.name ?? 'Unknown'}`}
          >
            <Building2 size={16} strokeWidth={1.5} className="shrink-0 text-icon-default" />
            <span className="min-w-0 flex-1 truncate text-body-sm font-medium text-text-primary">
              {current?.name}
            </span>
            <ChevronDown size={16} strokeWidth={1.5} className="shrink-0 text-icon-muted" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-72 p-0">
          <div className="border-b border-border-subtle p-2">
            <DropdownMenuLabel>{current?.org}</DropdownMenuLabel>
            {branches.length > 4 ? (
              <SearchInput
                size="sm"
                placeholder="Search branches…"
                value={query}
                onValueChange={setQuery}
                showShortcutHint={false}
                aria-label="Search branches"
              />
            ) : null}
          </div>
          <div className="max-h-60 overflow-y-auto p-1">
            {filtered.map((branch) => {
              const selected = branch.id === currentBranchId
              return (
                <DropdownMenuItem
                  key={branch.id}
                  onSelect={() => handleSelect(branch.id)}
                  className="justify-between"
                >
                  <span className="truncate">{branch.name}</span>
                  {selected ? (
                    <Check size={16} strokeWidth={1.5} className="shrink-0 text-text-link" />
                  ) : null}
                </DropdownMenuItem>
              )
            })}
            {filtered.length === 0 ? (
              <p className="px-2 py-3 text-center text-body-sm text-text-tertiary">
                No branches found
              </p>
            ) : null}
          </div>
        </DropdownMenuContent>
      </DropdownMenu>
      {feedback ? (
        <div
          role="status"
          className="absolute end-0 top-full z-[var(--z-toast)] mt-1 whitespace-nowrap rounded-md border border-border-default bg-surface-raised px-3 py-1.5 text-body-sm text-text-primary shadow-elevation-2"
        >
          {feedback}
        </div>
      ) : null}
    </div>
  )
}
