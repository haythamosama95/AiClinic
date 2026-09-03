import type { CommandTone } from '@/components/containers/command-tone'
import { cardToneClass } from '@/components/containers/command-tone'

interface CommandCardProps {
  method: string
  title: string
  path: string
  authLabel: string
  fieldCount: number
  tone: CommandTone
  selected: boolean
  destructive?: boolean
  onSelect: () => void
}

export function CommandCard({
  method,
  title,
  path,
  authLabel,
  fieldCount,
  tone,
  selected,
  destructive,
  onSelect,
}: CommandCardProps) {
  return (
    <button
      type="button"
      className={`cmd-card__trigger ${cardToneClass(tone)}${selected ? ' cmd-card__trigger--selected' : ''}`}
      aria-pressed={selected}
      onClick={onSelect}
    >
      <span className="cmd-card__stamp" aria-hidden="true">
        {method}
      </span>
      <span className="cmd-card__trigger-body">
        <span className="cmd-card__trigger-top">
          <span className="cmd-card__title">{title}</span>
        </span>
        <code className="cmd-card__path">{path}</code>
        <span className="cmd-card__meta">
          <span className="cmd-card__chip">{authLabel}</span>
          <span className="cmd-card__chip">
            {fieldCount} field{fieldCount === 1 ? '' : 's'}
          </span>
          {destructive ? (
            <span className="cmd-card__chip cmd-card__chip--warn">Irreversible</span>
          ) : null}
        </span>
      </span>
    </button>
  )
}
