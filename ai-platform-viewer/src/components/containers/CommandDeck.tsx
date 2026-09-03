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

      <div className="cmd-deck__grid">{children}</div>

      {panel}
    </section>
  )
}

interface CommandDeckSectionProps {
  title: string
}

export function CommandDeckSection({ title }: CommandDeckSectionProps) {
  return <p className="cmd-deck__section">{title}</p>
}
