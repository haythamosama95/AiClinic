import { cn } from '@/lib/cn'
import {
  componentSections,
  groupedComponentSections,
  showcaseGroups,
} from '@/showcase/components'

export function ComponentsPage() {
  return (
    <div className="space-y-16">
      <div>
        <p className="text-overline text-text-tertiary">Milestone 3</p>
        <h2 className="text-h2 text-text-primary">Components</h2>
        <p className="mt-2 max-w-2xl text-body-lg text-text-secondary">
          Shared primitives with full variant and state matrices. Toggle theme, direction, language,
          density, and AI mode in the header or the App shell demo.
        </p>
      </div>

      <nav aria-label="Component groups" className="flex flex-wrap gap-2 lg:hidden">
        {showcaseGroups.map((group) => {
          const count = groupedComponentSections[group.id].length
          if (count === 0) return null
          return (
            <a
              key={group.id}
              href={`#group-${group.id}`}
              className="focus-ring rounded-md px-3 py-1.5 text-body-sm text-text-link hover:bg-surface-hover"
            >
              {group.title}
            </a>
          )
        })}
      </nav>

      {showcaseGroups.map((group) => {
        const sections = groupedComponentSections[group.id]
        if (sections.length === 0) return null

        return (
          <div key={group.id} id={`group-${group.id}`} className="scroll-mt-24 space-y-10">
            <div className="border-b border-border-subtle pb-4">
              <h2 className="text-h2 text-text-primary">{group.title}</h2>
              <p className="mt-1 text-body text-text-secondary">{group.description}</p>
            </div>

            <div className="space-y-16">
              {sections.map((section) => {
                const Demo = section.component
                return (
                  <div
                    key={section.id}
                    className={cn(
                      section.status === 'placeholder' && 'opacity-80',
                    )}
                  >
                    <Demo />
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}
    </div>
  )
}

export function ComponentsSubNav() {
  return (
    <div>
      <p className="text-overline text-text-tertiary mb-2">Component groups</p>
      <ul className="space-y-3">
        {showcaseGroups.map((group) => {
          const sections = groupedComponentSections[group.id]
          if (sections.length === 0) return null
          const readyCount = sections.filter((s) => s.status === 'ready').length

          return (
            <li key={group.id}>
              <a
                href={`#group-${group.id}`}
                className="focus-ring block rounded-md px-2 py-1 text-body-sm text-text-link hover:bg-surface-hover"
              >
                {group.title}
                <span className="ms-1 text-caption text-text-tertiary">
                  ({readyCount}/{sections.length})
                </span>
              </a>
              {group.id === 'display' ||
              group.id === 'actions' ||
              group.id === 'inputs' ||
              group.id === 'navigation' ||
              group.id === 'layout' ? (
                <ul className="mt-1 space-y-0.5 border-s-2 border-border-subtle ps-3">
                  {sections.map((section) => (
                    <li key={section.id}>
                      <a
                        href={`#${section.id}`}
                        className={cn(
                          'focus-ring block rounded-sm py-0.5 text-caption hover:text-text-link',
                          section.status === 'ready'
                            ? 'text-text-secondary'
                            : 'text-text-tertiary italic',
                        )}
                      >
                        {section.title}
                      </a>
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          )
        })}
      </ul>
    </div>
  )
}

// Re-export for registry introspection
export { componentSections }
