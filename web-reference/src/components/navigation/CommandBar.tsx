import {
  FileText,
  Plus,
  Sparkles,
  UserPlus,
} from 'lucide-react'
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import {
  useCallback,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent,
} from 'react'
import { createPortal } from 'react-dom'
import { Avatar } from '@/components/avatar/Avatar'
import { Kbd } from '@/components/kbd'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import { useAiMode } from '@/providers/AiModeProvider'
import { useCommandBar } from '@/providers/CommandBarProvider'
import { Signal } from '@/primitives/Signal'

export type CommandItem = {
  id: string
  group: string
  label: string
  meta?: string
  icon?: React.ReactNode
  shortcut?: string[]
  avatarName?: string
  onSelect: () => void
}

export type CommandBarProps = {
  items: CommandItem[]
  recentItems?: CommandItem[]
  placeholder?: string
}

const AI_ASK_ID = '__ask_ai__'

export function CommandBar({
  items,
  recentItems = [],
  placeholder = 'Search patients, pages, or actions…',
}: CommandBarProps) {
  const { open, closeCommandBar, focusTrigger } = useCommandBar()
  const { aiMode, setAiMode } = useAiMode()
  const prefersReducedMotion = useReducedMotion()
  const [query, setQuery] = useState('')
  const [highlightIndex, setHighlightIndex] = useState(0)
  const [aiEntry, setAiEntry] = useState(false)
  const [aiResponse, setAiResponse] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const dialogId = useId()
  const labelId = `${dialogId}-label`

  const askAiItem: CommandItem = useMemo(
    () => ({
      id: AI_ASK_ID,
      group: 'AI',
      label: 'Ask AI…',
      meta: 'Natural language assistant',
      icon: <Sparkles size={16} strokeWidth={1.5} className="text-text-ai" />,
      shortcut: ['↵'],
      onSelect: () => {
        setAiEntry(true)
        setAiMode(true)
      },
    }),
    [setAiMode],
  )

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    const base = q
      ? items.filter(
          (item) =>
            item.label.toLowerCase().includes(q) ||
            item.meta?.toLowerCase().includes(q) ||
            item.group.toLowerCase().includes(q),
        )
      : recentItems.length > 0
        ? recentItems
        : items

    if (!aiEntry && (q.length > 8 || q.includes('?'))) {
      return [...base, askAiItem]
    }
    return base
  }, [query, items, recentItems, askAiItem, aiEntry])

  const grouped = useMemo(() => {
    const map = new Map<string, CommandItem[]>()
    for (const item of filtered) {
      const list = map.get(item.group) ?? []
      list.push(item)
      map.set(item.group, list)
    }
    return map
  }, [filtered])

  const flatList = useMemo(() => filtered, [filtered])

  const reset = useCallback(() => {
    setQuery('')
    setHighlightIndex(0)
    setAiEntry(false)
    setAiResponse(null)
    setAiMode(false)
  }, [setAiMode])

  const handleClose = useCallback(() => {
    closeCommandBar()
    reset()
    focusTrigger()
  }, [closeCommandBar, reset, focusTrigger])

  useEffect(() => {
    if (open) {
      window.setTimeout(() => inputRef.current?.focus(), 50)
    } else {
      reset()
    }
  }, [open, reset])

  useEffect(() => {
    setHighlightIndex(0)
  }, [query])

  const activateItem = useCallback(
    (item: CommandItem) => {
      if (item.id === AI_ASK_ID) {
        setAiEntry(true)
        setAiMode(true)
        if (query.trim()) {
          setAiResponse(
            `Here's a suggested starting point for "${query.trim()}": review recent patient charts and schedule a follow-up.`,
          )
        }
        return
      }
      item.onSelect()
      handleClose()
    },
    [handleClose, query, setAiMode],
  )

  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      if (aiEntry) {
        setAiEntry(false)
        setAiMode(false)
        setAiResponse(null)
      } else {
        handleClose()
      }
      return
    }

    if (aiEntry) return

    if (event.key === 'ArrowDown') {
      event.preventDefault()
      setHighlightIndex((i) => (i + 1) % flatList.length)
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      setHighlightIndex((i) => (i - 1 + flatList.length) % flatList.length)
    } else if (event.key === 'Home') {
      event.preventDefault()
      setHighlightIndex(0)
    } else if (event.key === 'End') {
      event.preventDefault()
      setHighlightIndex(Math.max(0, flatList.length - 1))
    } else if (event.key === 'Enter' && flatList[highlightIndex]) {
      event.preventDefault()
      activateItem(flatList[highlightIndex])
    }
  }

  useEffect(() => {
    const el = listRef.current?.querySelector(`[data-cmd-index="${highlightIndex}"]`)
    el?.scrollIntoView({ block: 'nearest' })
  }, [highlightIndex])

  const showBlur =
    !prefersReducedMotion && !getReducedMotion() && !document.documentElement.dataset.reducedMotion

  const commandPreset = motionPresets.command

  if (!open) return null

  let flatOffset = 0

  return createPortal(
    <AnimatePresence>
      {open ? (
        <>
          <motion.button
            type="button"
            aria-label="Close command bar"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={resolveTransition(motionPresets.fade)}
            className={cn(
              'fixed inset-0 z-[var(--z-backdrop)] bg-surface-backdrop',
              showBlur && 'backdrop-blur-sm',
            )}
            onClick={handleClose}
          />

          <div className="fixed inset-0 z-[var(--z-command)] flex items-start justify-center px-4 pt-[12vh]">
            <motion.div
              role="dialog"
              aria-modal="true"
              aria-labelledby={labelId}
              initial="hidden"
              animate="visible"
              exit="hidden"
              variants={commandPreset.variants}
              transition={resolveTransition({
                duration: commandPreset.duration,
                ease: commandPreset.ease,
              })}
              className="w-full max-w-xl overflow-hidden rounded-xl border border-border-default bg-surface-raised shadow-elevation-3"
              onKeyDown={handleKeyDown}
            >
              <p id={labelId} className="sr-only">
                Command bar
              </p>

              <div className="relative border-b border-border-subtle px-4 pt-4 pb-3">
                <div className="relative">
                  <input
                    ref={inputRef}
                    type="text"
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder={aiEntry ? 'Ask AI anything about your clinic…' : placeholder}
                    aria-label={aiEntry ? 'Ask AI' : 'Command search'}
                    className={cn(
                      'focus-ring w-full rounded-md border bg-surface-default px-3 py-2.5 text-body outline-none transition-colors duration-[var(--duration-base)]',
                      aiEntry || aiMode
                        ? 'border-border-ai focus-ring-ai text-text-primary'
                        : 'border-border-default text-text-primary',
                    )}
                    autoComplete="off"
                    autoCorrect="off"
                    spellCheck={false}
                  />
                  <div className="pointer-events-none absolute inset-x-3 -bottom-px">
                    <Signal
                      variant={aiEntry || aiMode ? 'ai' : 'standard'}
                      orientation="horizontal"
                      size="hero"
                      thinking={aiEntry && !aiResponse}
                    />
                  </div>
                </div>
              </div>

              {aiEntry ? (
                <div className="border-b border-border-subtle bg-surface-ai px-4 py-4">
                  {aiResponse ? (
                    <p className="text-body text-text-primary">{aiResponse}</p>
                  ) : (
                    <p className="text-body text-text-ai">Thinking…</p>
                  )}
                  <p className="mt-2 text-caption text-text-secondary">
                    AI suggestions are human-gated. Review before acting.
                  </p>
                </div>
              ) : (
                <div
                  ref={listRef}
                  role="listbox"
                  aria-label="Command results"
                  className="max-h-80 overflow-y-auto p-2"
                >
                  {flatList.length === 0 ? (
                    <p className="px-3 py-6 text-center text-body-sm text-text-tertiary">
                      No results for &ldquo;{query}&rdquo;
                    </p>
                  ) : (
                    Array.from(grouped.entries()).map(([group, groupItems]) => (
                      <div key={group} className="mb-2 last:mb-0">
                        <p className="px-2 py-1 text-overline text-text-tertiary">{group}</p>
                        {groupItems.map((item) => {
                          const index = flatOffset
                          flatOffset += 1
                          const highlighted = index === highlightIndex

                          return (
                            <button
                              key={item.id}
                              type="button"
                              role="option"
                              aria-selected={highlighted}
                              data-cmd-index={index}
                              onClick={() => activateItem(item)}
                              onMouseEnter={() => setHighlightIndex(index)}
                              className={cn(
                                'focus-ring flex w-full items-center gap-3 rounded-md px-3 py-2 text-start transition-colors',
                                highlighted
                                  ? 'bg-surface-selected'
                                  : 'hover:bg-surface-hover',
                              )}
                            >
                              {item.avatarName ? (
                                <Avatar name={item.avatarName} size="sm" />
                              ) : item.icon ? (
                                <span className="flex size-8 shrink-0 items-center justify-center rounded-md bg-surface-muted text-icon-default">
                                  {item.icon}
                                </span>
                              ) : null}
                              <span className="min-w-0 flex-1">
                                <span className="block truncate text-body text-text-primary">
                                  {item.label}
                                </span>
                                {item.meta ? (
                                  <span className="block truncate text-caption text-text-secondary">
                                    {item.meta}
                                  </span>
                                ) : null}
                              </span>
                              {item.shortcut ? (
                                <Kbd keys={item.shortcut} className="shrink-0" />
                              ) : null}
                            </button>
                          )
                        })}
                      </div>
                    ))
                  )}
                </div>
              )}

              <div className="flex items-center justify-between border-t border-border-subtle px-4 py-2 text-caption text-text-tertiary">
                <span>
                  <Kbd keys={['↑', '↓']} /> navigate · <Kbd keys={['↵']} /> select ·{' '}
                  <Kbd keys={['Esc']} /> close
                </span>
              </div>
            </motion.div>
          </div>
        </>
      ) : null}
    </AnimatePresence>,
    document.body,
  )
}

/** Default mock command items for showcase */
export function buildDefaultCommandItems(onNavigate?: (id: string) => void): CommandItem[] {
  const nav = (id: string, label: string) => ({
    id,
    group: 'Navigate',
    label,
    onSelect: () => onNavigate?.(id),
  })

  return [
    nav('patients', 'Patients'),
    nav('appointments', 'Appointments'),
    nav('billing', 'Billing'),
    nav('reports', 'Reports'),
    {
      id: 'patient-1',
      group: 'Patients',
      label: 'Layla Hassan',
      meta: 'MRN · 10482 · Last visit 2 days ago',
      avatarName: 'Layla Hassan',
      onSelect: () => onNavigate?.('patients'),
    },
    {
      id: 'patient-2',
      group: 'Patients',
      label: 'Omar Farouk',
      meta: 'MRN · 11029 · Appointment today',
      avatarName: 'Omar Farouk',
      onSelect: () => onNavigate?.('patients'),
    },
    {
      id: 'patient-3',
      group: 'Patients',
      label: 'Nadia El-Sayed',
      meta: 'MRN · 9876 · Follow-up due',
      avatarName: 'Nadia El-Sayed',
      onSelect: () => onNavigate?.('patients'),
    },
    {
      id: 'new-patient',
      group: 'Actions',
      label: 'New patient',
      icon: <UserPlus size={16} strokeWidth={1.5} />,
      shortcut: ['⌘', 'N'],
      onSelect: () => undefined,
    },
    {
      id: 'new-invoice',
      group: 'Actions',
      label: 'New invoice',
      icon: <FileText size={16} strokeWidth={1.5} />,
      shortcut: ['⌘', 'I'],
      onSelect: () => undefined,
    },
    {
      id: 'new-appointment',
      group: 'Actions',
      label: 'New appointment',
      icon: <Plus size={16} strokeWidth={1.5} />,
      onSelect: () => undefined,
    },
  ]
}
