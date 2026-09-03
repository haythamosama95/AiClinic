import type { ReactNode } from 'react'

interface CommandDeckProps {
  eyebrow: string
  lede?: string
  ariaLabel: string
  children: ReactNode
  panel?: ReactNode
}

export function CommandDeck({
  eyebrow,
  lede,
  ariaLabel,
  children,
  panel,
}: CommandDeckProps) {
  return (
    <section className="cmd-deck" aria-label={ariaLabel}>
      <header className="cmd-deck__head">
        <p className="cmd-deck__eyebrow">{eyebrow}</p>
        {lede ? <p className="cmd-deck__lede">{lede}</p> : null}
      </header>

      <div className="cmd-deck__layout">
        <aside className="cmd-deck__rail" aria-label="Command list">
          {children}
        </aside>
        <div className="cmd-deck__detail">
          {panel ?? (
            <p className="cmd-deck__detail-empty">Select a command to open its request panel.</p>
          )}
        </div>
      </div>
    </section>
  )
}

interface CommandDeckSectionProps {
  title: string
}

export function CommandDeckSection({ title }: CommandDeckSectionProps) {
  return <p className="cmd-deck__section">{title}</p>
}
