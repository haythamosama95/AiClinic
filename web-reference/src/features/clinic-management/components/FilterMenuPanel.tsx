import { Check } from 'lucide-react'
import { cn } from '@/lib/cn'

export type FilterMenuOption = {
  value: string
  label: string
}

export type FilterMenuSection = {
  id: string
  label: string
  value: string
  options: FilterMenuOption[]
  onChange: (value: string) => void
}

export type FilterMenuPanelProps = {
  sections: FilterMenuSection[]
  className?: string
}

export function FilterMenuPanel({ sections, className }: FilterMenuPanelProps) {
  return (
    <div className={cn('min-w-[14rem] p-2', className)}>
      {sections.map((section, index) => (
        <div key={section.id}>
          {index > 0 ? <div className="my-2 h-px bg-border-subtle" aria-hidden /> : null}
          <p className="px-2 py-1.5 text-overline text-text-tertiary">{section.label}</p>
          <ul role="listbox" aria-label={section.label}>
            {section.options.map((option) => {
              const selected = option.value === section.value
              return (
                <li key={option.value}>
                  <button
                    type="button"
                    role="option"
                    aria-selected={selected}
                    onClick={() => section.onChange(option.value)}
                    className={cn(
                      'focus-ring flex w-full items-center gap-2 rounded-md px-2 py-2 text-start text-body-sm transition-colors',
                      selected
                        ? 'bg-surface-selected font-medium text-text-primary'
                        : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary',
                    )}
                  >
                    <span className="flex size-4 shrink-0 items-center justify-center">
                      {selected ? (
                        <Check size={14} strokeWidth={2} className="text-action-primary" />
                      ) : null}
                    </span>
                    {option.label}
                  </button>
                </li>
              )
            })}
          </ul>
        </div>
      ))}
    </div>
  )
}
