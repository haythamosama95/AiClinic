import { DevSectionLink } from '@/components/showcase/DevSectionLink'
import { patternSections } from '@/showcase/patterns'

export function PatternsPage() {
  return (
    <div className="space-y-16">
      <div>
        <p className="text-overline text-text-tertiary">Milestone 5</p>
        <h2 className="text-h2 text-text-primary">Patterns</h2>
        <p className="mt-2 max-w-2xl text-body-lg text-text-secondary">
          Composed demos from 05 — realistic mocked compositions built from shared components.
        </p>
      </div>

      <nav aria-label="Pattern sections" className="flex flex-wrap gap-2 lg:hidden">
        {patternSections.map((section) => (
          <DevSectionLink
            key={section.id}
            sectionId={section.id}
            className="focus-ring rounded-md px-3 py-1.5 text-body-sm text-text-link hover:bg-surface-hover"
          >
            {section.title}
          </DevSectionLink>
        ))}
      </nav>

      {patternSections.map((section) => {
        const Demo = section.component
        return <Demo key={section.id} />
      })}
    </div>
  )
}

export function PatternsSubNav() {
  return (
    <div>
      <p className="text-overline text-text-tertiary mb-2">Patterns</p>
      <ul className="space-y-0.5">
        {patternSections.map((section) => (
          <li key={section.id}>
            <DevSectionLink
              sectionId={section.id}
              className="focus-ring block rounded-sm py-0.5 text-caption text-text-secondary hover:text-text-link"
            >
              {section.title}
            </DevSectionLink>
          </li>
        ))}
      </ul>
    </div>
  )
}
