import { Bell, Moon, Search, Sun } from 'lucide-react'
import { useEffect, useRef, type ReactNode } from 'react'
import { IconButton } from '@/components/actions/IconButton'
import { Kbd } from '@/components/kbd'
import { useCommandBar } from '@/providers/CommandBarProvider'
import { useTheme } from '@/providers/ThemeProvider'
import { cn } from '@/lib/cn'
import { BranchSwitcher } from './BranchSwitcher'
import { UserMenu, type UserMenuUser } from './UserMenu'
import type { Branch } from './nav-model'

const TOPBAR_ICON_CLASS = '[&_span]:[--icon-btn-size:24px]'

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
  const { theme, toggleTheme } = useTheme()
  const triggerRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    registerTrigger(triggerRef.current)
    return () => registerTrigger(null)
  }, [registerTrigger])

  return (
    <header
      className={cn(
        'sticky top-0 z-[var(--z-sticky)] flex shrink-0 items-center gap-3 border-b border-border-subtle bg-surface-default px-4',
        'h-[var(--shell-topbar-height)]',
        className,
      )}
    >
      <div className="flex min-w-0 flex-1 items-center gap-3">
        {pageContext ? (
          <div className="hidden min-w-0 sm:block">{pageContext}</div>
        ) : null}
      </div>

      <div className="flex shrink-0 justify-center px-2">
        <button
          ref={triggerRef}
          type="button"
          onClick={openCommandBar}
          className={cn(
            'focus-ring flex w-[min(28rem,42vw)] items-center gap-2 rounded-md border border-border-default bg-surface-sunken px-3 py-1.5 text-start transition-colors hover:bg-surface-hover',
            'data-[density=compact]:py-1 data-[density=comfortable]:py-2',
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

      <div className="flex min-w-0 flex-1 items-center justify-end gap-2">
        {toolbarSlot}

        <div className="hidden md:block">
          <BranchSwitcher
            branches={branches}
            currentBranchId={currentBranchId}
            onBranchChange={onBranchChange}
          />
        </div>

        <div className="relative">
          <IconButton
            label={`Notifications${notificationCount > 0 ? `, ${notificationCount} unread` : ''}`}
            variant="ghost"
            size="lg"
            className={TOPBAR_ICON_CLASS}
            onClick={onNotificationsClick}
            icon={<Bell size={24} strokeWidth={1.5} />}
          />
          {notificationCount > 0 ? (
            <span
              aria-hidden
              className="pointer-events-none absolute end-1.5 top-1.5 flex size-4 min-w-4 items-center justify-center rounded-full bg-status-danger-fg px-0.5 text-[10px] font-semibold leading-none text-text-inverse"
            >
              {notificationCount > 9 ? '9+' : notificationCount}
            </span>
          ) : null}
        </div>

        <IconButton
          label={theme === 'light' ? 'Switch to dark theme' : 'Switch to light theme'}
          variant="ghost"
          size="lg"
          className={TOPBAR_ICON_CLASS}
          onClick={toggleTheme}
          icon={
            theme === 'light' ? (
              <Moon size={24} strokeWidth={1.5} />
            ) : (
              <Sun size={24} strokeWidth={1.5} />
            )
          }
        />

        <UserMenu user={user} />
      </div>
    </header>
  )
}
