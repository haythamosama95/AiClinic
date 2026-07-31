import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type TimelineEvent = {
  id: string
  timestamp: string
  title: string
  description?: ReactNode
  group?: string
}

export type TimelineProps = {
  events: TimelineEvent[]
  className?: string
}

export function Timeline({ events, className }: TimelineProps) {
  const groups = events.reduce<Map<string, TimelineEvent[]>>((acc, event) => {
    const key = event.group ?? ''
    const list = acc.get(key) ?? []
    list.push(event)
    acc.set(key, list)
    return acc
  }, new Map())

  const entries = groups.size > 1 ? Array.from(groups.entries()) : [['', events] as const]

  return (
    <div className={cn('space-y-8', className)} role="list" aria-label="Timeline">
      {entries.map(([group, groupEvents]) => (
        <div key={group || 'default'}>
          {group ? (
            <p className="mb-4 text-overline text-text-tertiary">{group}</p>
          ) : null}
          <ol className="relative space-y-0 border-s-2 border-border-subtle ps-6">
            {groupEvents.map((event, index) => (
              <li
                key={event.id}
                className={cn('relative pb-8 last:pb-0')}
                role="listitem"
              >
                <span
                  className="absolute -start-[calc(0.5rem+1px)] top-1.5 size-2.5 rounded-full border-2 border-surface-default bg-action-primary"
                  aria-hidden
                />
                <time
                  dateTime={event.timestamp}
                  className="text-caption tabular-nums text-text-tertiary"
                >
                  {event.timestamp}
                </time>
                <p className="mt-1 text-body-strong text-text-primary">{event.title}</p>
                {event.description ? (
                  <div className="mt-1 text-body-sm text-text-secondary">{event.description}</div>
                ) : null}
                {index < groupEvents.length - 1 ? null : null}
              </li>
            ))}
          </ol>
        </div>
      ))}
    </div>
  )
}
