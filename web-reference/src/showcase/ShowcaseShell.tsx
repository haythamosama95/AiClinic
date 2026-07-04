import { type ReactNode } from 'react'
import { cn } from '@/lib/cn'
import { ShowcaseToolbar } from '@/components/showcase/ShowcaseToolbar'

export type ShowcaseArea = 'foundations' | 'components'

const AREAS: { id: ShowcaseArea; label: string }[] = [
  { id: 'foundations', label: 'Foundations' },
  { id: 'components', label: 'Components' },
]

export function ShowcaseShell({
  area,
  onAreaChange,
  children,
  subNav,
}: {
  area: ShowcaseArea
  onAreaChange: (area: ShowcaseArea) => void
  children: ReactNode
  subNav?: ReactNode
}) {
  return (
    <div className="min-h-dvh bg-surface-canvas">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:m-4 focus:rounded-md focus:bg-action-primary focus:px-4 focus:py-2 focus:text-action-primary-fg"
      >
        Skip to content
      </a>

      <header className="sticky top-0 z-sticky border-b border-border-subtle bg-surface-default/95 backdrop-blur-sm">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-6 py-4">
          <div>
            <p className="text-overline text-text-tertiary">Design System Showcase</p>
            <h1 className="text-h1 text-text-primary">AiClinic</h1>
          </div>
          <ShowcaseToolbar />
        </div>
      </header>

      <div className="mx-auto flex max-w-6xl gap-8 px-6 py-8">
        <aside className="hidden w-48 shrink-0 lg:block">
          <nav aria-label="Showcase areas" className="sticky top-24 space-y-6">
            <div>
              <p className="text-overline text-text-tertiary mb-2">Sections</p>
              <ul className="space-y-1">
                {AREAS.map((item) => (
                  <li key={item.id}>
                    <button
                      type="button"
                      onClick={() => onAreaChange(item.id)}
                      className={cn(
                        'focus-ring w-full rounded-md px-3 py-2 text-start text-body-sm transition-colors',
                        area === item.id
                          ? 'bg-surface-selected text-text-link font-medium'
                          : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary',
                      )}
                      aria-current={area === item.id ? 'page' : undefined}
                    >
                      {item.label}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
            {subNav}
          </nav>
        </aside>

        <main id="main" className="min-w-0 flex-1 pb-16">
          {children}
        </main>
      </div>

      <footer className="border-t border-border-subtle py-6 text-center text-caption text-text-tertiary">
        AiClinic Design System · web-reference · presentation only
      </footer>
    </div>
  )
}
