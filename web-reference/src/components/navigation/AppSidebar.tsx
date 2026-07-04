import { PanelLeftClose, PanelLeftOpen } from 'lucide-react'
import { LayoutGroup, motion } from 'motion/react'
import { useCallback, useRef, type KeyboardEvent } from 'react'
import { IconButton } from '@/components/actions/IconButton'
import { Badge } from '@/components/badge/Badge'
import { Tooltip } from '@/components/tooltip/Tooltip'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition } from '@/lib/motion'
import { Signal } from '@/primitives/Signal'
import type { NavGroup, NavItem } from './nav-model'

export type AppSidebarProps = {
  items: NavGroup[]
  footerItems?: NavItem[]
  activeId: string
  onNavigate: (id: string) => void
  collapsed: boolean
  onToggleCollapsed: () => void
  org: string
  branch: string
  className?: string
}

const SIGNAL_LAYOUT_ID = 'sidebar-active-signal'

export function AppSidebar({
  items,
  footerItems = [],
  activeId,
  onNavigate,
  collapsed,
  onToggleCollapsed,
  org,
  branch,
  className,
}: AppSidebarProps) {
  const navRef = useRef<HTMLElement>(null)

  const handleKeyDown = useCallback(
    (event: KeyboardEvent<HTMLElement>) => {
      const buttons = Array.from(
        navRef.current?.querySelectorAll<HTMLButtonElement>('[data-nav-item]') ?? [],
      ).filter((b) => !b.disabled)
      const currentIndex = buttons.findIndex((b) => b === document.activeElement)
      if (currentIndex < 0) return

      let nextIndex = currentIndex
      if (event.key === 'ArrowDown') {
        event.preventDefault()
        nextIndex = (currentIndex + 1) % buttons.length
      } else if (event.key === 'ArrowUp') {
        event.preventDefault()
        nextIndex = (currentIndex - 1 + buttons.length) % buttons.length
      } else if (event.key === 'Home') {
        event.preventDefault()
        nextIndex = 0
      } else if (event.key === 'End') {
        event.preventDefault()
        nextIndex = buttons.length - 1
      } else {
        return
      }

      buttons[nextIndex]?.focus()
      const id = buttons[nextIndex]?.dataset.navId
      if (id) onNavigate(id)
    },
    [onNavigate],
  )

  return (
    <aside
      className={cn(
        'flex h-full shrink-0 flex-col border-e border-border-subtle bg-surface-default transition-[width] duration-[var(--duration-base)]',
        collapsed ? 'w-14' : 'w-[248px]',
        className,
      )}
      aria-label="Main navigation"
    >
      <div
        className={cn(
          'flex items-center gap-2 border-b border-border-subtle px-3 py-3',
          'data-[density=compact]:py-2 data-[density=comfortable]:py-4',
          collapsed && 'justify-center px-2',
        )}
      >
        {!collapsed ? (
          <div className="min-w-0 flex-1">
            <p className="truncate text-overline text-text-tertiary">{org}</p>
            <p className="truncate text-body-strong text-text-primary">{branch}</p>
          </div>
        ) : null}
        <IconButton
          label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          size="sm"
          variant="ghost"
          onClick={onToggleCollapsed}
          icon={
            collapsed ? (
              <PanelLeftOpen size={16} strokeWidth={1.5} className="rtl:-scale-x-100" />
            ) : (
              <PanelLeftClose size={16} strokeWidth={1.5} className="rtl:-scale-x-100" />
            )
          }
        />
      </div>

      <nav
        ref={navRef}
        className="flex-1 overflow-y-auto px-2 py-3"
        onKeyDown={handleKeyDown}
      >
        <LayoutGroup>
          {items.map((group) => (
            <div key={group.id} className="mb-4 last:mb-0">
              {group.label && !collapsed ? (
                <p className="mb-1 px-2 text-overline text-text-tertiary">{group.label}</p>
              ) : null}
              <ul className="space-y-0.5">
                {group.items.map((item) => (
                  <li key={item.id}>
                    <NavItemButton
                      item={item}
                      active={activeId === item.id}
                      collapsed={collapsed}
                      onNavigate={onNavigate}
                    />
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </LayoutGroup>
      </nav>

      {footerItems.length > 0 ? (
        <div className="border-t border-border-subtle px-2 py-3">
          <ul className="space-y-0.5">
            {footerItems.map((item) => (
              <li key={item.id}>
                <NavItemButton
                  item={item}
                  active={activeId === item.id}
                  collapsed={collapsed}
                  onNavigate={onNavigate}
                />
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </aside>
  )
}

function NavItemButton({
  item,
  active,
  collapsed,
  onNavigate,
}: {
  item: NavItem
  active: boolean
  collapsed: boolean
  onNavigate: (id: string) => void
}) {
  const Icon = item.icon

  const button = (
    <button
      type="button"
      data-nav-item
      data-nav-id={item.id}
      onClick={() => onNavigate(item.id)}
      aria-current={active ? 'page' : undefined}
      className={cn(
        'focus-ring relative flex w-full items-center gap-3 rounded-md px-2 text-start transition-colors',
        'h-[var(--shell-nav-item-height)]',
        collapsed && 'justify-center px-0',
        active
          ? 'bg-surface-selected text-text-primary'
          : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary',
      )}
    >
      {active ? (
        <motion.span
          layoutId={SIGNAL_LAYOUT_ID}
          className="absolute inset-y-1 start-0 flex w-0.5 items-stretch"
          transition={resolveTransition(motionPresets.nav)}
        >
          <Signal orientation="vertical" className="h-full" />
        </motion.span>
      ) : null}
      <Icon size={20} strokeWidth={1.5} className="shrink-0" aria-hidden />
      {!collapsed ? (
        <>
          <span className="min-w-0 flex-1 truncate text-body">{item.label}</span>
          {item.count !== undefined ? (
            <Badge size="sm" color="neutral" variant="soft">
              {item.count}
            </Badge>
          ) : null}
        </>
      ) : null}
    </button>
  )

  if (collapsed) {
    return <Tooltip content={item.label} side="right">{button}</Tooltip>
  }

  return button
}
