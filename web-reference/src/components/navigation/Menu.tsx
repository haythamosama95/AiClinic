import * as ContextMenuPrimitive from '@radix-ui/react-context-menu'
import { Check } from 'lucide-react'
import { motion } from 'motion/react'
import type { ReactNode } from 'react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { Kbd } from '@/components/kbd'
import { Tooltip } from '@/components/tooltip/Tooltip'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition } from '@/lib/motion'

export type MenuItemDef = {
  id: string
  label: string
  icon?: ReactNode
  shortcut?: string[]
  checked?: boolean
  destructive?: boolean
  disabled?: boolean
  disabledReason?: string
  onSelect?: () => void
}

export type MenuSection = {
  type: 'section'
  label?: string
  items: MenuItemDef[]
}

export type MenuSeparator = { type: 'separator' }

export type MenuEntry = MenuItemDef | MenuSection | MenuSeparator

function isSection(entry: MenuEntry): entry is MenuSection {
  return 'type' in entry && entry.type === 'section'
}

function isSeparator(entry: MenuEntry): entry is MenuSeparator {
  return 'type' in entry && entry.type === 'separator'
}

function MenuItemContent({ item }: { item: MenuItemDef }) {
  const content = (
  <>
      {item.icon ? <span className="shrink-0 text-icon-default">{item.icon}</span> : null}
      <span className="flex-1">{item.label}</span>
      {item.checked ? (
        <Check size={16} strokeWidth={1.5} className="shrink-0 text-text-link" aria-hidden />
      ) : item.shortcut ? (
        <Kbd keys={item.shortcut} className="ms-auto shrink-0" />
      ) : null}
    </>
  )

  if (item.disabled && item.disabledReason) {
    return (
      <Tooltip content={item.disabledReason}>
        <span className="flex w-full items-center gap-2">{content}</span>
      </Tooltip>
    )
  }

  return <span className="flex w-full items-center gap-2">{content}</span>
}

function renderMenuEntries(entries: MenuEntry[]) {
  return entries.map((entry, index) => {
    if (isSeparator(entry)) {
      return <DropdownMenuSeparator key={`sep-${index}`} />
    }
    if (isSection(entry)) {
      return (
        <div key={entry.label ?? `section-${index}`}>
          {entry.label ? <DropdownMenuLabel>{entry.label}</DropdownMenuLabel> : null}
          {entry.items.map((item) => (
            <DropdownMenuItem
              key={item.id}
              icon={undefined}
              destructive={item.destructive}
              disabled={item.disabled}
              onSelect={item.onSelect}
              className="data-[density=compact]:py-1 data-[density=comfortable]:py-2"
            >
              <MenuItemContent item={item} />
            </DropdownMenuItem>
          ))}
        </div>
      )
    }
    return (
      <DropdownMenuItem
        key={entry.id}
        icon={undefined}
        destructive={entry.destructive}
        disabled={entry.disabled}
        onSelect={entry.onSelect}
        className="data-[density=compact]:py-1 data-[density=comfortable]:py-2"
      >
        <MenuItemContent item={entry} />
      </DropdownMenuItem>
    )
  })
}

export type MenuProps = {
  trigger: ReactNode
  entries: MenuEntry[]
  align?: 'start' | 'center' | 'end'
  open?: boolean
  onOpenChange?: (open: boolean) => void
}

export function Menu({ trigger, entries, align = 'start', open, onOpenChange }: MenuProps) {
  return (
    <DropdownMenu open={open} onOpenChange={onOpenChange}>
      <DropdownMenuTrigger asChild>{trigger}</DropdownMenuTrigger>
      <DropdownMenuContent align={align} className="min-w-[12rem]">
        {renderMenuEntries(entries)}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

const contextPreset = motionPresets['fade-scale']

function ContextMenuItemContent({ item }: { item: MenuItemDef }) {
  return (
    <ContextMenuPrimitive.Item
      disabled={item.disabled}
      onSelect={item.onSelect}
      className={cn(
        'focus-ring flex cursor-pointer select-none items-center gap-2 rounded-md px-2 py-1.5 text-body outline-none transition-colors',
        'data-[highlighted]:bg-surface-hover data-[disabled]:pointer-events-none data-[disabled]:text-text-disabled',
        item.destructive
          ? 'text-status-danger-fg data-[highlighted]:bg-status-danger-surface'
          : 'text-text-primary',
        'data-[density=compact]:py-1 data-[density=comfortable]:py-2',
      )}
    >
      <MenuItemContent item={item} />
    </ContextMenuPrimitive.Item>
  )
}

export type ContextMenuProps = {
  children: ReactNode
  entries: MenuEntry[]
}

export function ContextMenu({ children, entries }: ContextMenuProps) {
  return (
    <ContextMenuPrimitive.Root>
      <ContextMenuPrimitive.Trigger asChild>{children}</ContextMenuPrimitive.Trigger>
      <ContextMenuPrimitive.Portal>
        <ContextMenuPrimitive.Content
          asChild
          onCloseAutoFocus={(e) => e.preventDefault()}
        >
          <motion.div
            initial="hidden"
            animate="visible"
            exit="hidden"
            variants={contextPreset.variants}
            transition={resolveTransition({
              duration: contextPreset.duration,
              ease: contextPreset.ease,
            })}
            className="z-[var(--z-dropdown)] min-w-[12rem] overflow-hidden rounded-lg border border-border-default bg-surface-raised p-1 shadow-elevation-2"
          >
            {entries.map((entry, index) => {
              if (isSeparator(entry)) {
                return (
                  <ContextMenuPrimitive.Separator
                    key={`sep-${index}`}
                    className="my-1 h-px bg-border-subtle"
                  />
                )
              }
              if (isSection(entry)) {
                return (
                  <div key={entry.label ?? `section-${index}`}>
                    {entry.label ? (
                      <ContextMenuPrimitive.Label className="px-2 py-1.5 text-overline text-text-tertiary">
                        {entry.label}
                      </ContextMenuPrimitive.Label>
                    ) : null}
                    {entry.items.map((item) => (
                      <ContextMenuItemContent key={item.id} item={item} />
                    ))}
                  </div>
                )
              }
              return <ContextMenuItemContent key={entry.id} item={entry} />
            })}
          </motion.div>
        </ContextMenuPrimitive.Content>
      </ContextMenuPrimitive.Portal>
    </ContextMenuPrimitive.Root>
  )
}
