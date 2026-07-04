import { Bell, Search } from 'lucide-react'
import { useEffect, useRef, type ReactNode } from 'react'
import { IconButton } from '@/components/actions/IconButton'
import { Badge } from '@/components/badge/Badge'
import { Kbd } from '@/components/kbd'
import { useCommandBar } from '@/providers/CommandBarProvider'
import { cn } from '@/lib/cn'
import { AiModeToggle } from './AiModeToggle'
import { BranchSwitcher } from './BranchSwitcher'
import { UserMenu, type UserMenuUser } from './UserMenu'
import type { Branch } from './nav-model'

export type AppTopBarProps = {
  pageContext?: ReactNode
  branches: Branch[]
  currentBranchId: string
  onBranchChange: (id: string) => void
  user: UserMenuUser
  notificationCount?: number
  onNotificationsClick?: () => void
  className?: string
  /** Slot for additional toolbar controls (e.g. showcase toggles) */
  toolbarSlot?: ReactNode
}

export function AppTopBar({
  pageContext,
  branches,
  currentBranchId,
  onBranchChange,
  user,
  notificationCount = 0,
  onNotificationsClick,
  className,
  toolbarSlot,
}: AppTopBarProps) {
  const { openCommandBar, registerTrigger } = useCommandBar()
  const triggerRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    registerTrigger(triggerRef.current)
    return () => registerTrigger(null)
  }, [registerTrigger])

  return (
    <header
      className={cn(
        'sticky top-0 z-[var(--z-sticky)] flex shrink-0 items-center gap-3 border-b border-border-subtle bg-surface-default/95 px-4 shadow-elevation-1 backdrop-blur-sm',
        'h-[var(--shell-topbar-height)]',
        className,
      )}
    >
      <div className="flex min-w-0 flex-1 items-center gap-3">
        {pageContext ? (
          <div className="hidden min-w-0 sm:block">{pageContext}</div>
        ) : null}

        <button
          ref={triggerRef}
          type="button"
          onClick={openCommandBar}
          className={cn(
            'focus-ring flex min-w-0 flex-1 items-center gap-2 rounded-md border border-border-default bg-surface-sunken px-3 py-1.5 text-start transition-colors hover:bg-surface-hover',
            'data-[density=compact]:py-1 data-[density=comfortable]:py-2',
            'max-w-md',
          )}
          aria-label="Open command bar"
        >
          <Search size={16} strokeWidth={1.5} className="shrink-0 text-icon-muted" />
          <span className="min-w-0 flex-1 truncate text-body-sm text-text-placeholder">
            Search or jump to…
          </span>
          <Kbd keys={['⌘', 'K']} className="hidden shrink-0 sm:inline-flex" />
        </button>
      </div>

      <div className="flex shrink-0 items-center gap-2">
        {toolbarSlot}

        <div className="hidden md:block">
          <BranchSwitcher
            branches={branches}
            currentBranchId={currentBranchId}
            onBranchChange={onBranchChange}
          />
        </div>

        <AiModeToggle className="hidden sm:inline-flex" />

        <div className="relative">
          <IconButton
            label={`Notifications${notificationCount > 0 ? `, ${notificationCount} unread` : ''}`}
            variant="ghost"
            size="md"
            onClick={onNotificationsClick}
            icon={<Bell size={20} strokeWidth={1.5} />}
          />
          {notificationCount > 0 ? (
            <span className="absolute end-1 top-1">
              <Badge variant="solid" color="danger" size="sm">
                {notificationCount > 9 ? '9+' : notificationCount}
              </Badge>
            </span>
          ) : null}
        </div>

        <UserMenu user={user} />
      </div>
    </header>
  )
}
